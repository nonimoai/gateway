# Nonimo Gateway: installation and examples

[Español](README.es.md)

Nonimo Gateway runs on **your own server**, between your applications and your AI provider. It masks personal data before a request leaves your network and puts the real values back in the response. To use it, you change your application's `base_url`.

> **This repository is not the Gateway's source code.** Nonimo Gateway is closed-source, commercial software, distributed as a private Docker image. This repository only holds a Docker Compose example, client examples and installation notes. You need a licence to download the image.

Product page: <https://nonimo.ai/gateway/> · Contact: <gateway@nonimo.ai>

## What you need

- A Linux `amd64` or `arm64` server with Docker.
- Outbound HTTPS to your AI provider and to Nonimo's licence service (except on the offline plan).
- Your licence file, `licencia.nli`, and your licence email, which has the registry login command, the image name and the version.

## Install with Docker Compose

Put `licencia.nli` next to `docker-compose.yml` and make it readable by the container:

```bash
chmod 644 licencia.nli
```

Log in to the registry with the command from your licence email.

Create the file for your provider key:

```bash
install -m 600 /dev/null clave_proveedor.txt
```

Open `clave_proveedor.txt` in your editor and paste your provider key on one line, so it stays out of your shell history.

Generate the access key that your applications will use:

```bash
(umask 077; openssl rand -hex 32 > clave_entrada.txt)
```

The Gateway runs as user 65532, so both files must belong to that user and nobody else:

```bash
sudo chown 65532:65532 clave_proveedor.txt clave_entrada.txt && sudo chmod 400 clave_proveedor.txt clave_entrada.txt
```

In `docker-compose.yml`, replace the image placeholder with the image name and version from your licence email. Then start the Gateway:

```bash
docker compose up -d
```

Check that it is running. In less than a minute, the status column shows `healthy`:

```bash
docker compose ps
```

The port only opens on the server itself. To reach the Gateway from other machines, put a TLS proxy in front of `127.0.0.1:8080`, so the original text doesn't cross your network unencrypted. Expose only the API routes your applications use.

## Point your application at the Gateway

The Gateway is compatible with the OpenAI and Anthropic APIs. Change the base URL and use the access key from `clave_entrada.txt` as the API key:

| | Base URL | API key |
|---|---|---|
| OpenAI SDKs and compatible clients | `https://gateway.your-company.com/v1` | access key |
| Anthropic SDKs | `https://gateway.your-company.com` | access key |

Runnable examples: [Python](examples/python/main.py) · [Node](examples/node/index.mjs).

Requests without the access key get a `401` and nothing is sent.

## Providers

The Compose example stores one OpenAI-compatible provider key. For Anthropic, add `NONIMO_CLAVE_ANTHROPIC_FICHERO` and a third secret in the same way.

| Variable | Default | What it is |
|---|---|---|
| `NONIMO_DESTINO_URL` | `https://api.openai.com/v1` | OpenAI or compatible provider |
| `NONIMO_DESTINO_ANTHROPIC_URL` | `https://api.anthropic.com/v1` | Provider for Anthropic requests |

The full guide arrives with your licence, including the other settings, image signature checks and updates.

## Licence

The files in this repository are under the [MIT licence](LICENSE). That licence does not cover Nonimo Gateway or its Docker image, which are proprietary.

## Contributing

This repository is read-only and doesn't accept contributions. For questions or security reports, email <gateway@nonimo.ai>.
