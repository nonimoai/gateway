#!/bin/sh
# Nonimo Gateway installer for Linux (amd64 and arm64).
#
#   curl -fsSL https://nonimo.ai/gateway/instalar.sh | sh -s -- --codigo XXXX-XXXX
#
# Or download it, read it, check its sha256 and run it:
#
#   curl -fsSLo install.sh https://nonimo.ai/gateway/instalar.sh
#   sha256sum install.sh
#   sh install.sh --codigo XXXX-XXXX
#
# What it does: checks the server, redeems your one-time install code for the
# licence, logs in to the image registry, creates the access key and the panel
# key, writes docker-compose.yml, starts the Gateway and waits until it is
# healthy. It does not ask for your AI provider key: you add it in the panel.
# It does not set up TLS either.
#
# Running it again with a new code updates the licence and the version. It
# never overwrites existing keys.
#
# Source: https://github.com/nonimoai/gateway (MIT licence).

set -eu

DIR=/opt/nonimo-gateway
API=https://api.nonimo.ai
CODIGO=
ENSAYO=0
PUERTO=8080
PUERTO_PANEL=8081
REGISTRO_POR_DEFECTO=descargas.nonimo.ai
USUARIO_GW=65532
ESPERA_MAX=90

say() { printf '%s\n' "$*"; }
err() { printf 'nonimo: %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

usage() {
	cat <<'EOF'
Nonimo Gateway installer (Linux, amd64/arm64)

Usage: sh install.sh --codigo XXXX-XXXX [options]

  --codigo CODE       one-time install code from your licence email (required)
  --dir PATH          install folder (default /opt/nonimo-gateway)
  --puerto PORT       API port on 127.0.0.1 (default 8080)
  --puerto-panel PORT panel port on 127.0.0.1 (default 8081)
  --api URL           licence service (default https://api.nonimo.ai)
  --ensayo            dry run: print what it would do, change nothing and
                      don't redeem the code
  -h, --help          this help
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
      - "127.0.0.1:$4:8081" # admin panel
    environment:
      NONIMO_LICENCIA: /run/secrets/licencia
      NONIMO_CLAVE_ENTRADA_FICHERO: /run/secrets/clave_entrada
      NONIMO_CLAVE_PANEL_FICHERO: /run/secrets/clave_panel
      NONIMO_PANEL: "1"
      # Inside the container the panel listens on 0.0.0.0, or Docker's port
      # mapping can't reach it, and the Gateway only allows that with
      # NONIMO_PANEL_ABRIR_A_LA_RED. It is still private: "ports" above
      # publishes it on 127.0.0.1 only.
      NONIMO_PANEL_ESCUCHAR: 0.0.0.0
      NONIMO_PANEL_ABRIR_A_LA_RED: "1"
      # Your AI provider key goes in the panel. If you prefer a file instead,
      # uncomment a block here and the matching lines under both "secrets".
      # OpenAI or a compatible provider:
      # NONIMO_CLAVE_DESTINO_FICHERO: /run/secrets/clave_openai
      # Claude (Anthropic):
      # NONIMO_CLAVE_ANTHROPIC_FICHERO: /run/secrets/clave_anthropic
    volumes:
      - nonimo-datos:/var/lib/nonimo
    secrets:
      - licencia
      - clave_entrada
      - clave_panel
      # - clave_openai
      # - clave_anthropic

volumes:
  nonimo-datos:

secrets:
  licencia:
    file: ./licencia.nli
  clave_entrada:
    file: ./clave_entrada.txt
  clave_panel:
    file: ./clave_panel.txt
  # Key files: one line, owned by 65532:65532, mode 400.
  # clave_openai:
  #   file: ./clave_openai.txt
  # clave_anthropic:
  #   file: ./clave_anthropic.txt
EOF
}

main() {
	# ── Options ──────────────────────────────────────────────────────────────
	while [ $# -gt 0 ]; do
		case $1 in
		--codigo | --dir | --api | --puerto | --puerto-panel)
			[ $# -ge 2 ] || die "$1 needs a value (see --help)"
			case $1 in
			--codigo) CODIGO=$2 ;;
			--dir) DIR=$2 ;;
			--api) API=$2 ;;
			--puerto) PUERTO=$2 ;;
			--puerto-panel) PUERTO_PANEL=$2 ;;
			esac
			shift 2
			;;
		--codigo=*) CODIGO=${1#*=}; shift ;;
		--dir=*) DIR=${1#*=}; shift ;;
		--api=*) API=${1#*=}; shift ;;
		--puerto=*) PUERTO=${1#*=}; shift ;;
		--puerto-panel=*) PUERTO_PANEL=${1#*=}; shift ;;
		--ensayo) ENSAYO=1; shift ;;
		-h | --help) usage; exit 0 ;;
		*) die "unknown option: $1 (see --help)" ;;
		esac
	done

	case $CODIGO in
	'') die "missing --codigo: use the install code from your licence email" ;;
	*[!A-Za-z0-9-]*) die "--codigo has unexpected characters: copy it from your licence email" ;;
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
	es_puerto "$PUERTO" || die "--puerto must be a number from 1 to 65535"
	es_puerto "$PUERTO_PANEL" || die "--puerto-panel must be a number from 1 to 65535"
	[ "$PUERTO" != "$PUERTO_PANEL" ] || die "--puerto and --puerto-panel must be different"

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
		[ -n "$MOTIVO" ] || MOTIVO=$(json_texto motivo "$TMP/respuesta" 2>/dev/null || true)
		case $HTTP in
		200) ;;
		400 | 403 | 404 | 409 | 410 | 422)
			die "this install code is used, expired or wrong${MOTIVO:+ ($MOTIVO)}. Ask for a new one at https://nonimo.ai" ;;
		429) die "too many attempts. Wait a few minutes and try again" ;;
		*) die "the licence service answered HTTP $HTTP${MOTIVO:+ ($MOTIVO)}. Try again later or write to gateway@nonimo.ai" ;;
		esac

		LICENCIA_B64=$(json_texto licencia "$TMP/respuesta" | tr -d ' \t')
		IMAGEN=$(json_texto imagen "$TMP/respuesta")
		VERSION=$(json_texto version "$TMP/respuesta")
		CADUCA=$(json_texto caduca "$TMP/respuesta")
		rm -f "$TMP/respuesta"

		case $LICENCIA_B64 in '' | *[!A-Za-z0-9+/=]*) die "the licence service sent an unexpected licence" ;; esac
		case $IMAGEN in '' | *[!a-z0-9./_:-]* | */ | /*) die "the licence service sent an unexpected image name" ;; esac
		case $IMAGEN in */*) ;; *) die "the licence service sent an unexpected image name" ;; esac
		case ${IMAGEN##*/} in *:*) die "the licence service sent an image name with a tag" ;; esac
		case $VERSION in '' | *[!A-Za-z0-9._-]*) die "the licence service sent an unexpected version" ;; esac
		case $CADUCA in *[!0-9-]*) CADUCA= ;; esac

		printf '%s' "$LICENCIA_B64" | base64 -d >"$TMP/licencia.nli" 2>/dev/null ||
			die "the licence from the licence service doesn't decode"
		[ -s "$TMP/licencia.nli" ] || die "the licence from the licence service is empty"
		LICENCIA_B64=

		# The registry is the image's host (descargas.nonimo.ai in production).
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
	if [ "$NUEVA_LICENCIA" = 1 ]; then
		run $SUDO install -m 644 "$TMP/licencia.nli" "$DIR/licencia.nli"
	else
		run $SUDO install -m 644 "<licence from the code>" "$DIR/licencia.nli"
	fi

	NUEVA_ENTRADA=0
	NUEVA_PANEL=0
	for clave in clave_entrada clave_panel; do
		if [ -e "$DIR/$clave.txt" ]; then
			say "Keeping the existing $DIR/$clave.txt"
			continue
		fi
		nueva_clave >"$TMP/$clave.txt"
		[ "$(tr -d '\n' <"$TMP/$clave.txt" | wc -c | tr -d ' ')" = 64 ] ||
			die "couldn't create a random key from /dev/urandom"
		run $SUDO install -m 400 -o "$USUARIO_GW" -g "$USUARIO_GW" "$TMP/$clave.txt" "$DIR/$clave.txt"
		case $clave in
		clave_entrada) NUEVA_ENTRADA=1 ;;
		clave_panel) NUEVA_PANEL=1 ;;
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
		say "  + base64 licencia.nli | $SUDO${SUDO:+ }docker login $REGISTRO -u nonimo --password-stdin"
	else
		base64 <"$TMP/licencia.nli" | tr -d '\n' |
			$SUDO docker login "$REGISTRO" -u nonimo --password-stdin >/dev/null ||
			die "the registry refused the licence. Write to gateway@nonimo.ai"
	fi
	rm -f "$TMP/licencia.nli"

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
			die "fix the error above and run the installer again, or write to gateway@nonimo.ai"
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
	[ -n "$CADUCA" ] && say "Licence valid until $CADUCA."
	say ""
	if [ "$NUEVA_ENTRADA" = 1 ]; then
		say "Access key for your applications (shown only now; it is also in"
		say "$DIR/clave_entrada.txt, readable by root):"
		say ""
		say "  $(cat "$TMP/clave_entrada.txt")"
	else
		say "Access key for your applications: unchanged, in $DIR/clave_entrada.txt"
		say "(sudo cat $DIR/clave_entrada.txt)."
	fi
	say ""
	say "In your applications, use it as the API key, with the Gateway as base URL:"
	say "  base_url: https://gateway.your-company.com/v1   (OpenAI SDKs)"
	say "  base_url: https://gateway.your-company.com      (Anthropic SDKs)"
	say ""
	say "Open the panel. From your computer:"
	say "  ssh -L $PUERTO_PANEL:127.0.0.1:$PUERTO_PANEL <you>@$SERVIDOR"
	say "and then http://localhost:$PUERTO_PANEL"
	if [ "$NUEVA_PANEL" = 1 ]; then
		say "Panel key (also in $DIR/clave_panel.txt):"
		say ""
		say "  $(cat "$TMP/clave_panel.txt")"
	else
		say "Panel key: unchanged, in $DIR/clave_panel.txt"
	fi
	say ""
	say "First step in the panel: add your AI provider key (OpenAI, Claude or both)."
	say ""
	say "Still to do: the Gateway only listens on this server (127.0.0.1:$PUERTO)."
	say "To reach it from other machines, put a TLS proxy (nginx, Caddy, Traefik...)"
	say "in front of it, so the original text never crosses your network unencrypted."
}

main "$@"
