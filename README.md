# Nonimo Gateway: installation and examples

[Español](README.es.md)

Nonimo Gateway runs on **your own server**, between your applications and your AI provider. It masks personal data before a request leaves your network and puts the real values back in the response. Your applications change two things: the base URL and the API key.

> **This repository is not the Gateway's source code.** Nonimo Gateway is closed-source, commercial software, distributed as a private Docker image. This repository only holds the installer, a Docker Compose example, client examples and installation notes. You need a licence to download the image.

Product page: <https://nonimo.ai/gateway/> · Contact: <hello@nonimo.ai>

## What you need

- A Linux `amd64` or `arm64` server with Docker and Docker Compose v2 (`docker compose`).
- Root, or a user with `sudo`.
- Outbound HTTPS to your AI provider and to Nonimo's licence service.
- The install code from your trial or licence email (`XXXX-XXXX-XXXX`). It works once and lasts 48 hours.

## Install in one line

```bash
curl -fsSL https://nonimo.ai/gateway/install.sh | sh -s -- --code XXXX-XXXX-XXXX
```

The installer:

1. checks the server (Linux, Docker, Compose v2, curl, root or sudo);
2. redeems the code for your licence, image and version, and logs in to the registry;
3. creates the access key for your applications and the dashboard key in `/opt/nonimo-gateway`;
4. writes `docker-compose.yml`, starts the Gateway and waits until it is `healthy`;
5. prints the access key, the dashboard key and how to open the dashboard.

It doesn't ask for your AI provider key: you add it in the dashboard. It doesn't set up TLS either (see [Reach it from other machines](#reach-it-from-other-machines)).

Running it again with a new code updates the licence and the version, and keeps your keys.

### Download, review and run

If your security policy doesn't allow `curl | sh`, download the script, check it and run it. It is the same file as [`install.sh`](install.sh) in this repository.

```bash
curl -fsSLo install.sh https://nonimo.ai/gateway/install.sh
sha256sum install.sh   # compare with the value in your licence email
less install.sh
sh install.sh --code XXXX-XXXX-XXXX
```

| Option | Default | What it does |
|---|---|---|
| `--code` | | One-time install code (required) |
| `--dir` | `/opt/nonimo-gateway` | Install folder |
| `--port` | `8080` | API port, on `127.0.0.1` |
| `--dashboard-port` | `8081` | Dashboard port, on `127.0.0.1` |
| `--dry-run` | | Dry run: prints what it would do, changes nothing and doesn't use up the code |

The older names still work: `https://nonimo.ai/gateway/instalar.sh`, `--codigo`, `--puerto`, `--puerto-dashboard` and `--ensayo`.
Running the installer on an older install renames `licencia.nli`, `clave_entrada.txt` and `clave_panel.txt` to the names above
and keeps each old name as a link to the new file.

## Open the dashboard

The dashboard only listens on the server itself. From your computer, open an SSH tunnel:

```bash
ssh -L 8081:127.0.0.1:8081 you@your-server
```

Then go to <http://localhost:8081> and sign in with the dashboard key (`dashboard_key.txt`).

The first step in the dashboard is to add your AI provider key: OpenAI, Claude or both. The dashboard also shows your licence, the requests that went through and the personal data the Gateway masked.

## Point your application at the Gateway

The Gateway is compatible with the OpenAI and Anthropic APIs. Your applications use the **Gateway access key** (`access_key.txt`) as their API key, not your provider key. The provider key stays inside the Gateway.

| | Base URL | API key |
|---|---|---|
| OpenAI SDKs and compatible clients | `https://gateway.your-company.com/v1` | Gateway access key |
| Anthropic SDKs | `https://gateway.your-company.com` | Gateway access key |

Python, with the OpenAI SDK:

```python
from openai import OpenAI

# Two changes: the Gateway's address and its access key.
client = OpenAI(
    base_url="https://gateway.your-company.com/v1",
    api_key="your-gateway-access-key",
)
response = client.chat.completions.create(
    model="gpt-6.1-terra",
    messages=[{"role": "user", "content": "Write a short reply to Jane Citizen (jane.citizen@example.com)."}],
)
print(response.choices[0].message.content)
```

Python, with the Anthropic SDK:

```python
import anthropic

client = anthropic.Anthropic(
    base_url="https://gateway.your-company.com",
    api_key="your-gateway-access-key",
)
message = client.messages.create(
    model="claude-sonnet-5-5",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Summarise the file of Jane Citizen."}],
)
print(message.content[0].text)
```

curl:

```bash
curl https://gateway.your-company.com/v1/chat/completions \
  -H "Authorization: Bearer $NONIMO_GATEWAY_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-6.1-terra", "messages": [{"role": "user", "content": "Hello, I am Jane Citizen."}]}'
```

Runnable examples: [Python](examples/python/main.py) · [Node](examples/node/index.mjs).

Requests without the access key get a `401` and nothing is sent.

## Reach it from other machines

The Gateway's ports only open on the server itself (`127.0.0.1`). To reach it from other machines, put a TLS proxy (nginx, Caddy, Traefik…) in front of `127.0.0.1:8080`, so the original text doesn't cross your network unencrypted. Expose only the API routes your applications use, and keep the dashboard behind the SSH tunnel.

## Manual installation

If you prefer to do each step yourself, you need your licence file, `licence.nli`, and your licence email, which has the registry login command, the image name and the version.

Put [`docker-compose.yml`](docker-compose.yml) and `licence.nli` in the same folder, and make the licence readable by the container:

```bash
chmod 644 licence.nli
```

Log in to the registry with the command from your licence email. It reads the licence from a pipe, so nothing goes into your shell history:

```bash
base64 -w0 licence.nli | docker login nonimo.ai -u nonimo --password-stdin
```

Generate the access key for your applications and the dashboard key:

```bash
(umask 077; openssl rand -hex 32 > access_key.txt; openssl rand -hex 32 > dashboard_key.txt)
```

The Gateway runs as user 65532, so both files must belong to that user and nobody else:

```bash
sudo chown 65532:65532 access_key.txt dashboard_key.txt && sudo chmod 400 access_key.txt dashboard_key.txt
```

In `docker-compose.yml`, replace `<image>` and `<version>` with the image name and version from your licence email. Then start the Gateway:

```bash
docker compose up -d
```

Check that it is running. In less than a minute, the status column shows `healthy`:

```bash
docker compose ps
```

Then [open the dashboard](#open-the-dashboard), add your provider key and [put a TLS proxy in front](#reach-it-from-other-machines).

## Providers

The usual place for your provider key is the dashboard. If you prefer to keep it in a file, `docker-compose.yml` has two commented blocks: `NONIMO_CLAVE_DESTINO_FICHERO` for OpenAI or a compatible provider, and `NONIMO_CLAVE_ANTHROPIC_FICHERO` for Claude. Uncomment the one you need, with its secret, and create the file with the key on one line, owned by `65532:65532` with mode `400`.

| Variable | Default | What it is |
|---|---|---|
| `NONIMO_DESTINO_URL` | `https://api.openai.com/v1` | OpenAI or compatible provider |
| `NONIMO_DESTINO_ANTHROPIC_URL` | `https://api.anthropic.com/v1` | Provider for Anthropic requests |

The full guide arrives with your licence, including the other settings, image signature checks and updates.

## Licence

The files in this repository are under the [MIT licence](LICENSE). That licence does not cover Nonimo Gateway or its Docker image, which are proprietary.

## Contributing

This repository is read-only and doesn't accept contributions. For questions or security reports, email <hello@nonimo.ai>.
