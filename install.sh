#!/bin/sh
# Nonimo Gateway installer for Linux (amd64 and arm64).
#
#   curl -fsSL https://nonimo.ai/gateway/install.sh | sh -s -- --code XXXX-XXXX-XXXX
#
# Or download it, read it, check its sha256 and run it:
#
#   curl -fsSLo install.sh https://nonimo.ai/gateway/install.sh
#   sha256sum install.sh
#   sh install.sh --code XXXX-XXXX-XXXX
#
# The older names still work: https://nonimo.ai/gateway/instalar.sh, --codigo,
# --puerto, --puerto-panel and --ensayo.
#
# What it does: checks the server, redeems your one-time install code for the
# licence, logs in to the image registry, creates the access key and the
# dashboard key, writes docker-compose.yml, starts the Gateway and waits until
# it is healthy. It does not ask for your AI provider key: you add it in the
# dashboard.
# It does not set up TLS either.
#
# Running it again with a new code updates the licence and the version. It
# never overwrites existing keys. Files from older versions (licencia.nli,
# clave_entrada.txt, clave_panel.txt...) are renamed to the current names and
# the old name is kept as a link, so nothing that points to them breaks.
#
# Source and licence: https://nonimo.ai/gateway/ (installer under the MIT licence).

set -eu

DIR=/opt/nonimo-gateway
# NONIMO_API points the installer at another licence service (the test one, for example).
API=${NONIMO_API:-https://api.nonimo.ai}
CODIGO=
ENSAYO=0
PUERTO=8080
PUERTO_PANEL=8081
REGISTRO_POR_DEFECTO=nonimo.ai
USUARIO_GW=65532
ESPERA_MAX=90

say() { printf '%s\n' "$*"; }
err() { printf 'nonimo: %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

usage() {
	cat <<'EOF'
Nonimo Gateway installer (Linux, amd64/arm64)

Usage: sh install.sh --code XXXX-XXXX-XXXX [options]

  --code CODE           one-time install code from your licence email (required)
  --dir PATH            install folder (default /opt/nonimo-gateway)
  --port PORT           API port on 127.0.0.1 (default 8080)
  --dashboard-port PORT dashboard port on 127.0.0.1 (default 8081)
  --api URL             licence service (default https://api.nonimo.ai)
  --dry-run             print what it would do, change nothing and don't
                        redeem the code
  -h, --help            this help

The older option names still work: --codigo, --puerto, --puerto-panel, --ensayo.
EOF
}

# In a dry run, print the command instead of running it.
run() {
	if [ "$ENSAYO" = 1 ]; then
		printf '  + %s\n' "$*"
	else
		"$@"
	fi
}

# 64 hex characters from the kernel's random source (no openssl needed).
nueva_clave() {
	od -An -tx1 -N32 /dev/urandom | tr -d ' \n'
}

# Value of a flat string field in a JSON file, without jq. Handles spaces and
# escaped slashes; anything else that is escaped is rejected by the callers.
json_texto() {
	tr -d '\r\n' <"$2" |
		sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"\\]*\(\\.[^"\\]*\)*\)".*/\1/p' |
		sed 's#\\/#/#g'
}

es_puerto() {
	case $1 in '' | *[!0-9]*) return 1 ;; esac
	[ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

compose_yml() {
	# $1 image, $2 version, $3 API port, $4 panel port
	cat <<EOF
# Nonimo Gateway with Docker Compose.
# install.sh writes this file with your image and version. For a manual
# install, replace <image> and <version> with the ones in your licence email.
services:
  nonimo-gateway:
    image: "$1:$2"
    restart: unless-stopped
    read_only: true
    cap_drop: [ALL]
    security_opt: ["no-new-privileges:true"]
    ulimits:
      core: 0
    # Both ports are published on 127.0.0.1 only: nothing outside this server
    # reaches them. Put a TLS proxy in front of the API port for your
    # applications, and open the panel through an SSH tunnel.
    ports:
      - "127.0.0.1:$3:8080" # API for your applications
      - "127.0.0.1:$4:8081" # dashboard
    environment:
      NONIMO_LICENCIA: /run/secrets/licence
      NONIMO_CLAVE_ENTRADA_FICHERO: /run/secrets/access_key
      NONIMO_CLAVE_PANEL_FICHERO: /run/secrets/dashboard_key
      NONIMO_PANEL: "1"
      # Inside the container the dashboard listens on 0.0.0.0, or Docker's port
      # mapping can't reach it, and the Gateway only allows that with
      # NONIMO_PANEL_ABRIR_A_LA_RED. It is still private: "ports" above
      # publishes it on 127.0.0.1 only.
      NONIMO_PANEL_ESCUCHAR: 0.0.0.0
      NONIMO_PANEL_ABRIR_A_LA_RED: "1"
      # Your AI provider key goes in the dashboard. If you prefer a file instead,
      # uncomment a block here and the matching lines under both "secrets".
      # OpenAI or a compatible provider:
      # NONIMO_CLAVE_DESTINO_FICHERO: /run/secrets/openai_key
      # Claude (Anthropic):
      # NONIMO_CLAVE_ANTHROPIC_FICHERO: /run/secrets/anthropic_key
    volumes:
      - nonimo-datos:/var/lib/nonimo
    secrets:
      - licence
      - access_key
      - dashboard_key
      # - openai_key
      # - anthropic_key

volumes:
  nonimo-datos:

secrets:
  licence:
    file: ./licence.nli
  access_key:
    file: ./access_key.txt
  dashboard_key:
    file: ./dashboard_key.txt
  # Key files: one line, owned by 65532:65532, mode 400.
  # openai_key:
  #   file: ./openai_key.txt
  # anthropic_key:
  #   file: ./anthropic_key.txt
EOF
}

main() {
	# ── Options ──────────────────────────────────────────────────────────────
	while [ $# -gt 0 ]; do
		case $1 in
		--code | --codigo | --dir | --api | --port | --puerto | --dashboard-port | --puerto-panel)
			[ $# -ge 2 ] || die "$1 needs a value (see --help)"
			case $1 in
			--code | --codigo) CODIGO=$2 ;;
			--dir) DIR=$2 ;;
			--api) API=$2 ;;
			--port | --puerto) PUERTO=$2 ;;
			--dashboard-port | --puerto-panel) PUERTO_PANEL=$2 ;;
			esac
			shift 2
			;;
		--code=* | --codigo=*) CODIGO=${1#*=}; shift ;;
		--dir=*) DIR=${1#*=}; shift ;;
		--api=*) API=${1#*=}; shift ;;
		--port=* | --puerto=*) PUERTO=${1#*=}; shift ;;
		--dashboard-port=* | --puerto-panel=*) PUERTO_PANEL=${1#*=}; shift ;;
		--dry-run | --ensayo) ENSAYO=1; shift ;;
		-h | --help) usage; exit 0 ;;
		*) die "unknown option: $1 (see --help)" ;;
		esac
	done

	# The code is Crockford base32 in capitals: accept it typed in lower case too.
	CODIGO=$(printf '%s' "$CODIGO" | tr 'abcdefghijklmnopqrstuvwxyz' 'ABCDEFGHIJKLMNOPQRSTUVWXYZ')
	case $CODIGO in
	'') die "missing --code: use the install code from your licence email" ;;
	*[!A-Za-z0-9-]*) die "--code has unexpected characters: copy it from your licence email" ;;
	esac
	case $DIR in
	/ | *[!A-Za-z0-9._/-]*) die "--dir must be a plain absolute path, like /opt/nonimo-gateway" ;;
	/*) DIR=${DIR%/} ;;
	*) die "--dir must be an absolute path, like /opt/nonimo-gateway" ;;
	esac
	API=${API%/}
	case $API in
	*[!A-Za-z0-9.:/_-]*) die "--api has unexpected characters" ;;
	https://* | http://localhost* | http://127.0.0.1*) ;;
	*) die "--api must start with https://" ;;
	esac
	es_puerto "$PUERTO" || die "--port must be a number from 1 to 65535"
	es_puerto "$PUERTO_PANEL" || die "--dashboard-port must be a number from 1 to 65535"
	[ "$PUERTO" != "$PUERTO_PANEL" ] || die "--port and --dashboard-port must be different"

	[ "$ENSAYO" = 1 ] && say "Dry run: nothing is changed and the code is not redeemed."

	# ── Checks ───────────────────────────────────────────────────────────────
	FALTA=
	falta() { FALTA="$FALTA
  - $*"; }

	SO=$(uname -s 2>/dev/null || echo unknown)
	[ "$SO" = Linux ] || falta "Linux only (this is $SO)"
	ARQ=$(uname -m 2>/dev/null || echo unknown)
	case $ARQ in
	x86_64 | amd64 | aarch64 | arm64) ;;
	*) falta "amd64 or arm64 only (this is $ARQ)" ;;
	esac

	SUDO=
	if [ "$(id -u)" -ne 0 ]; then
		if command -v sudo >/dev/null 2>&1; then
			SUDO=sudo
		else
			falta "run as root, or install sudo"
			SUDO=sudo
		fi
	fi

	for herramienta in curl base64 od; do
		command -v "$herramienta" >/dev/null 2>&1 || falta "$herramienta is not installed"
	done
	if ! command -v docker >/dev/null 2>&1; then
		falta "Docker is not installed: https://docs.docker.com/engine/install/"
	else
		VERSION_COMPOSE=$(docker compose version --short 2>/dev/null </dev/null || true)
		case $VERSION_COMPOSE in
		'') falta "Docker Compose v2 is missing (the 'docker compose' plugin): https://docs.docker.com/compose/install/linux/" ;;
		v1.* | 1.* | v0.* | 0.*) falta "Docker Compose v2 is needed (found $VERSION_COMPOSE)" ;;
		esac
	fi

	if [ -n "$FALTA" ]; then
		if [ "$ENSAYO" = 1 ]; then
			say "Would stop here on a real run:$FALTA"
		else
			die "can't install yet:$FALTA"
		fi
	fi

	# Ask for the sudo password once, up front.
	if [ -n "$SUDO" ] && [ "$ENSAYO" = 0 ]; then
		sudo -v || die "sudo failed: run as root or as a user with sudo"
	fi
	if command -v docker >/dev/null 2>&1; then
		if [ "$ENSAYO" = 1 ]; then
			[ -n "$SUDO" ] && PRUEBA_DOCKER="sudo -n docker" || PRUEBA_DOCKER=docker
		else
			PRUEBA_DOCKER="$SUDO docker"
		fi
		if ! $PRUEBA_DOCKER info >/dev/null 2>&1 </dev/null; then
			if [ "$ENSAYO" = 1 ]; then
				say "Couldn't check that Docker is running (a real run checks it as root)."
			else
				die "Docker is installed but not running: start it (systemctl start docker) and try again"
			fi
		fi
	fi

	umask 077
	TMP=$(mktemp -d 2>/dev/null || mktemp -d -t nonimo)
	trap 'rm -rf "$TMP"' EXIT
	trap 'exit 130' INT TERM

	# ── Redeem the install code ──────────────────────────────────────────────
	CADUCA=
	if [ "$ENSAYO" = 1 ]; then
		say "Would redeem the code (skipped: it works only once):"
		say "  + curl -X POST $API/v1/gwlicencia {\"accion\":\"instalar\",\"codigo\":\"$CODIGO\"}"
		IMAGEN='<image>'
		VERSION='<version>'
		REGISTRO=$REGISTRO_POR_DEFECTO
		NUEVA_LICENCIA=0
	else
		say "Redeeming the install code..."
		HTTP=$(curl -sS --max-time 30 -o "$TMP/respuesta" -w '%{http_code}' \
			-H 'Content-Type: application/json' -H 'Accept: application/json' \
			--data "{\"accion\":\"instalar\",\"codigo\":\"$CODIGO\"}" \
			"$API/v1/gwlicencia" </dev/null) ||
			die "can't reach $API: the server needs outbound HTTPS"
		MOTIVO=$(json_texto error "$TMP/respuesta" 2>/dev/null || true)
		[ "$HTTP" = 410 ] && die "this install code has expired or was already used. Ask for a new one at https://nonimo.ai"
		[ -n "$MOTIVO" ] || MOTIVO=$(json_texto motivo "$TMP/respuesta" 2>/dev/null || true)
		case $HTTP in
		200) ;;
		400 | 403 | 404 | 409 | 410 | 422)
			die "this install code is used, expired or wrong${MOTIVO:+ ($MOTIVO)}. Ask for a new one at https://nonimo.ai" ;;
		429) die "too many attempts. Wait a few minutes and try again" ;;
		*) die "the licence service answered HTTP $HTTP${MOTIVO:+ ($MOTIVO)}. Try again later or write to hello@nonimo.ai" ;;
		esac

		LICENCIA_B64=$(json_texto licencia "$TMP/respuesta" | tr -d ' \t')
		IMAGEN=$(json_texto imagen "$TMP/respuesta")
		VERSION=$(json_texto version "$TMP/respuesta")
		CADUCA=$(json_texto fin_prueba "$TMP/respuesta" 2>/dev/null || true)
		ES_PRUEBA=0
		if [ -n "$CADUCA" ]; then ES_PRUEBA=1; else CADUCA=$(json_texto caduca "$TMP/respuesta" 2>/dev/null || true); fi
		rm -f "$TMP/respuesta"

		case $LICENCIA_B64 in '' | *[!A-Za-z0-9+/=]*) die "the licence service sent an unexpected licence" ;; esac
		case $IMAGEN in '' | *[!a-z0-9./_:-]* | */ | /*) die "the licence service sent an unexpected image name" ;; esac
		case $IMAGEN in */*) ;; *) die "the licence service sent an unexpected image name" ;; esac
		case ${IMAGEN##*/} in *:*) die "the licence service sent an image name with a tag" ;; esac
		case $VERSION in '' | *[!A-Za-z0-9._-]*) die "the licence service sent an unexpected version" ;; esac
		case $CADUCA in *[!0-9-]*) CADUCA= ;; esac

		printf '%s' "$LICENCIA_B64" | base64 -d >"$TMP/licence.nli" 2>/dev/null ||
			die "the licence from the licence service doesn't decode"
		[ -s "$TMP/licence.nli" ] || die "the licence from the licence service is empty"
		LICENCIA_B64=

		# The registry is the image's host (nonimo.ai in production).
		REGISTRO=${IMAGEN%%/*}
		case $REGISTRO in
		*.* | *:* | localhost) ;;
		*) REGISTRO=$REGISTRO_POR_DEFECTO ;;
		esac
		NUEVA_LICENCIA=1
	fi
	say "Image: $IMAGEN:$VERSION"

	# ── Files ────────────────────────────────────────────────────────────────
	say "Preparing $DIR..."
	run $SUDO mkdir -p "$DIR"
	run $SUDO chmod 755 "$DIR"
	# Files from older versions of this installer had Spanish names: rename them
	# to the current ones and keep the old name as a link (scripts and backups
	# that point to it keep working).
	for par in clave_entrada.txt:access_key.txt clave_panel.txt:dashboard_key.txt \
		clave_openai.txt:openai_key.txt clave_anthropic.txt:anthropic_key.txt; do
		viejo=${par%%:*}
		nuevo=${par#*:}
		if [ -e "$DIR/$viejo" ] && [ ! -L "$DIR/$viejo" ] && [ ! -e "$DIR/$nuevo" ]; then
			say "Renaming $DIR/$viejo to $nuevo (the old name stays as a link)"
			run $SUDO mv "$DIR/$viejo" "$DIR/$nuevo"
			run $SUDO ln -s "$nuevo" "$DIR/$viejo"
		fi
	done
	if [ "$NUEVA_LICENCIA" = 1 ]; then
		run $SUDO install -m 644 "$TMP/licence.nli" "$DIR/licence.nli"
	else
		run $SUDO install -m 644 "<licence from the code>" "$DIR/licence.nli"
	fi
	if [ -e "$DIR/licencia.nli" ] && [ ! -L "$DIR/licencia.nli" ]; then
		say "Replacing the old $DIR/licencia.nli with a link to licence.nli"
		run $SUDO rm -f "$DIR/licencia.nli"
		run $SUDO ln -s licence.nli "$DIR/licencia.nli"
	fi

	NUEVA_ENTRADA=0
	NUEVA_PANEL=0
	for clave in access_key dashboard_key; do
		if [ -e "$DIR/$clave.txt" ]; then
			say "Keeping the existing $DIR/$clave.txt"
			continue
		fi
		nueva_clave >"$TMP/$clave.txt"
		[ "$(tr -d '\n' <"$TMP/$clave.txt" | wc -c | tr -d ' ')" = 64 ] ||
			die "couldn't create a random key from /dev/urandom"
		run $SUDO install -m 400 -o "$USUARIO_GW" -g "$USUARIO_GW" "$TMP/$clave.txt" "$DIR/$clave.txt"
		case $clave in
		access_key) NUEVA_ENTRADA=1 ;;
		dashboard_key) NUEVA_PANEL=1 ;;
		esac
	done

	compose_yml "$IMAGEN" "$VERSION" "$PUERTO" "$PUERTO_PANEL" >"$TMP/docker-compose.yml"
	if [ "$ENSAYO" = 1 ]; then
		say "Would write $DIR/docker-compose.yml:"
		sed 's/^/    | /' "$TMP/docker-compose.yml"
	elif [ -e "$DIR/docker-compose.yml" ] && ! cmp -s "$TMP/docker-compose.yml" "$DIR/docker-compose.yml"; then
		COPIA="$DIR/docker-compose.yml.bak-$(date +%Y%m%d%H%M%S)"
		say "Saving your current docker-compose.yml as $COPIA"
		$SUDO cp -p "$DIR/docker-compose.yml" "$COPIA"
	fi
	run $SUDO install -m 644 "$TMP/docker-compose.yml" "$DIR/docker-compose.yml"

	# ── Registry and start ───────────────────────────────────────────────────
	say "Logging in to $REGISTRO..."
	if [ "$ENSAYO" = 1 ]; then
		say "  + base64 licence.nli | $SUDO${SUDO:+ }docker login $REGISTRO -u nonimo --password-stdin"
	else
		base64 <"$TMP/licence.nli" | tr -d '\n' |
			$SUDO docker login "$REGISTRO" -u nonimo --password-stdin >/dev/null ||
			die "the registry refused the licence. Write to hello@nonimo.ai"
	fi
	rm -f "$TMP/licence.nli"

	COMPOSE="$SUDO${SUDO:+ }docker compose --project-directory $DIR -f $DIR/docker-compose.yml"
	say "Downloading and starting the Gateway..."
	run $COMPOSE pull --quiet </dev/null || die "couldn't download $IMAGEN:$VERSION"
	run $COMPOSE up -d --force-recreate </dev/null || die "docker compose couldn't start the Gateway"

	if [ "$ENSAYO" = 1 ]; then
		say "Would wait up to ${ESPERA_MAX}s for the status 'healthy'."
	else
		say "Waiting for the Gateway to be healthy (up to ${ESPERA_MAX}s)..."
		ESPERADO=0
		ESTADO=starting
		while :; do
			ID=$($COMPOSE ps -q nonimo-gateway </dev/null 2>/dev/null || true)
			if [ -n "$ID" ]; then
				ESTADO=$($SUDO docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$ID" </dev/null 2>/dev/null || echo missing)
			fi
			case $ESTADO in
			healthy) break ;;
			unhealthy | exited | dead) break ;;
			esac
			[ "$ESPERADO" -lt "$ESPERA_MAX" ] || break
			sleep 2
			ESPERADO=$((ESPERADO + 2))
		done
		if [ "$ESTADO" != healthy ]; then
			err "the Gateway is not healthy (status: $ESTADO). Last log lines:"
			$COMPOSE logs --tail 30 </dev/null >&2 || true
			die "fix the error above and run the installer again, or write to hello@nonimo.ai"
		fi
	fi

	# ── Next steps ───────────────────────────────────────────────────────────
	SERVIDOR=$(hostname 2>/dev/null || echo your-server)
	say ""
	if [ "$ENSAYO" = 1 ]; then
		say "Dry run finished. A real run would now print the keys and the next steps."
		return 0
	fi
	say "Nonimo Gateway $VERSION is running."
	if [ -n "$CADUCA" ] && [ "${ES_PRUEBA:-0}" = 1 ]; then
		say "Free trial: it ends on $CADUCA. Add payment in the dashboard before then and it keeps working."
	elif [ -n "$CADUCA" ]; then
		say "Licence valid until $CADUCA."
	fi
	say ""
	if [ "$NUEVA_ENTRADA" = 1 ]; then
		say "Access key for your applications (shown only now; it is also in"
		say "$DIR/access_key.txt, readable by root):"
		say "  $(cat "$TMP/access_key.txt")"
	else
		say "Access key for your applications: unchanged, in $DIR/access_key.txt"
	fi
	if [ "$NUEVA_PANEL" = 1 ]; then
		say "Dashboard key (shown only now; also in $DIR/dashboard_key.txt):"
		say "  $(cat "$TMP/dashboard_key.txt")"
	else
		say "Dashboard key: unchanged, in $DIR/dashboard_key.txt"
	fi
	say ""
	say "Three steps:"
	say ""
	say "  1. Open the dashboard. From your computer:"
	say "       ssh -L $PUERTO_PANEL:127.0.0.1:$PUERTO_PANEL <you>@$SERVIDOR"
	say "     then go to http://localhost:$PUERTO_PANEL and sign in with the dashboard key."
	say ""
	say "  2. In the dashboard, add your AI provider key (OpenAI, Claude or both)."
	say ""
	say "  3. Point your applications at the Gateway, with the access key as their API key:"
	say "       OpenAI SDKs:     base_url http://127.0.0.1:$PUERTO/v1"
	say "       Anthropic SDKs:  base_url http://127.0.0.1:$PUERTO"
	say "     From other machines, use your TLS proxy's address (see below)."
	say ""
	say "Copy for your AI coding assistant (works with an API key; not with a"
	say "Claude Pro/Max/Team login or a ChatGPT login):"
	say ""
	say "  Claude Code:"
	say "    export ANTHROPIC_BASE_URL=\"http://127.0.0.1:$PUERTO\""
	say "    export ANTHROPIC_API_KEY=\"<access key>\""
	say ""
	say "  Codex CLI (~/.codex/config.toml):"
	say "    model_provider = \"nonimo\""
	say "    [model_providers.nonimo]"
	say "    name = \"Nonimo Gateway\""
	say "    base_url = \"http://127.0.0.1:$PUERTO/v1\""
	say "    env_key = \"NONIMO_GATEWAY_KEY\""
	say "    wire_api = \"responses\""
	say "  and: export NONIMO_GATEWAY_KEY=\"<access key>\""
	say ""
	say "Still to do: the Gateway only listens on this server (127.0.0.1:$PUERTO)."
	say "To reach it from other machines, put a TLS proxy (nginx, Caddy, Traefik...)"
	say "in front of it, so the original text never crosses your network unencrypted."
}

main "$@"
