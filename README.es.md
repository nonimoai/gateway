# Nonimo Gateway: instalación y ejemplos

[English](README.md)

Nonimo Gateway corre en **tu propio servidor**, entre tus aplicaciones y tu proveedor de IA. Tapa los datos personales antes de que la petición salga de tu red y devuelve los valores reales en la respuesta. En tus aplicaciones cambian dos cosas: la dirección base y la clave de API.

> **Este repositorio no es el código fuente del Gateway.** Nonimo Gateway es software comercial de código cerrado y se distribuye como imagen privada de Docker. Aquí solo están el instalador, un ejemplo de Docker Compose, ejemplos de cliente y notas de instalación. Para descargar la imagen hace falta una licencia.

Página del producto: <https://nonimo.ai/es/gateway/> · Contacto: <hello@nonimo.ai>

## Qué necesitas

- Un servidor Linux `amd64` o `arm64` con Docker y Docker Compose v2 (`docker compose`).
- Ser root, o un usuario con `sudo`.
- Salida HTTPS hacia tu proveedor de IA y hacia el servicio de licencias de Nonimo.
- El código de instalación del correo de tu prueba o de tu licencia (`XXXX-XXXX-XXXX`). Sirve una vez y dura 48 horas.

## Instalación en una línea

```bash
curl -fsSL https://nonimo.ai/gateway/install.sh | sh -s -- --code XXXX-XXXX-XXXX
```

El instalador:

1. comprueba el servidor (Linux, Docker, Compose v2, curl, root o sudo);
2. canjea el código por tu licencia, la imagen y la versión, y entra en el registro;
3. crea la clave de acceso de tus aplicaciones y la clave del panel en `/opt/nonimo-gateway`;
4. escribe `docker-compose.yml`, arranca el Gateway y espera a que esté `healthy`;
5. te enseña la clave de acceso, la clave del panel y cómo entrar en el panel.

No te pide la clave de tu proveedor de IA: la pones en el panel. Tampoco monta el TLS (ver [Llegar desde otros equipos](#llegar-desde-otros-equipos)).

Si lo vuelves a ejecutar con un código nuevo, actualiza la licencia y la versión y conserva tus claves.

### Descarga, revisa y ejecuta

Si tu política de seguridad no permite `curl | sh`, descarga el script, revísalo y ejecútalo. Es el mismo fichero que [`install.sh`](install.sh) de este repositorio.

```bash
curl -fsSLo install.sh https://nonimo.ai/gateway/install.sh
sha256sum install.sh   # compáralo con el valor del correo de tu licencia
less install.sh
sh install.sh --code XXXX-XXXX-XXXX
```

| Opción | Valor de serie | Qué hace |
|---|---|---|
| `--code` | | Código de instalación de un solo uso (obligatorio) |
| `--dir` | `/opt/nonimo-gateway` | Carpeta de la instalación |
| `--port` | `8080` | Puerto de la API, en `127.0.0.1` |
| `--dashboard-port` | `8081` | Puerto del panel, en `127.0.0.1` |
| `--dry-run` | | Ensayo: enseña lo que haría, no cambia nada y no gasta el código |

Los nombres de antes siguen valiendo: `https://nonimo.ai/gateway/instalar.sh`, `--codigo`, `--puerto`, `--puerto-panel` y `--ensayo`.
Si lo ejecutas sobre una instalación anterior, renombra `licencia.nli`, `clave_entrada.txt` y `clave_panel.txt` a los nombres de
arriba y deja cada nombre antiguo como enlace al fichero nuevo.

## Entra en el panel

El panel solo escucha en el propio servidor. Desde tu ordenador, abre un túnel SSH:

```bash
ssh -L 8081:127.0.0.1:8081 tu-usuario@tu-servidor
```

Después abre <http://localhost:8081> y entra con la clave del panel (`dashboard_key.txt`).

Lo primero en el panel es poner la clave de tu proveedor de IA: OpenAI, Claude o los dos. El panel enseña también tu licencia, las peticiones que han pasado y los datos personales que ha tapado el Gateway.

## Apunta tu aplicación al Gateway

El Gateway es compatible con las API de OpenAI y Anthropic. Tus aplicaciones usan como clave de API la **clave de acceso del Gateway** (`access_key.txt`), no la de tu proveedor. La clave del proveedor se queda dentro del Gateway.

| | Dirección base | Clave de API |
|---|---|---|
| SDK de OpenAI y clientes compatibles | `https://gateway.tu-empresa.es/v1` | clave de acceso del Gateway |
| SDK de Anthropic | `https://gateway.tu-empresa.es` | clave de acceso del Gateway |

Python, con el SDK de OpenAI:

```python
from openai import OpenAI

# Cambian dos cosas: la dirección del Gateway y su clave de acceso.
client = OpenAI(
    base_url="https://gateway.tu-empresa.es/v1",
    api_key="la-clave-de-acceso-del-gateway",
)
response = client.chat.completions.create(
    model="gpt-6.1-terra",
    messages=[{"role": "user", "content": "Escribe una respuesta breve a María López (maria.lopez@example.com)."}],
)
print(response.choices[0].message.content)
```

Python, con el SDK de Anthropic:

```python
import anthropic

client = anthropic.Anthropic(
    base_url="https://gateway.tu-empresa.es",
    api_key="la-clave-de-acceso-del-gateway",
)
message = client.messages.create(
    model="claude-sonnet-5-5",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Resume el expediente de María López."}],
)
print(message.content[0].text)
```

curl:

```bash
curl https://gateway.tu-empresa.es/v1/chat/completions \
  -H "Authorization: Bearer $NONIMO_GATEWAY_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-6.1-terra", "messages": [{"role": "user", "content": "Hola, soy María López."}]}'
```

Ejemplos que se pueden ejecutar: [Python](examples/python/main.py) · [Node](examples/node/index.mjs).

Sin la clave de acceso, la petición recibe un `401` y no se envía nada.

## Llegar desde otros equipos

Los puertos del Gateway solo se abren en el propio servidor (`127.0.0.1`). Para llegar desde otros equipos, pon un proxy con TLS (nginx, Caddy, Traefik…) delante de `127.0.0.1:8080`, y así el texto original no cruza tu red sin cifrar. Publica solo las rutas de la API que usen tus aplicaciones y deja el panel detrás del túnel SSH.

## Instalación manual

Si prefieres hacer cada paso tú, necesitas tu fichero de licencia, `licence.nli`, y el correo de tu licencia, que trae la orden para entrar en el registro, el nombre de la imagen y la versión.

Deja [`docker-compose.yml`](docker-compose.yml) y `licence.nli` en la misma carpeta, y haz la licencia legible para el contenedor:

```bash
chmod 644 licence.nli
```

Entra en el registro con la orden del correo de tu licencia. Lee la licencia por una tubería, así que no queda nada en el historial de la terminal:

```bash
base64 -w0 licence.nli | docker login nonimo.ai -u nonimo --password-stdin
```

Genera la clave de acceso de tus aplicaciones y la clave del panel:

```bash
(umask 077; openssl rand -hex 32 > access_key.txt; openssl rand -hex 32 > dashboard_key.txt)
```

El Gateway corre con el usuario 65532, así que los dos ficheros tienen que ser de ese usuario y de nadie más:

```bash
sudo chown 65532:65532 access_key.txt dashboard_key.txt && sudo chmod 400 access_key.txt dashboard_key.txt
```

En `docker-compose.yml`, cambia `<image>` y `<version>` por el nombre de la imagen y la versión del correo de tu licencia. Después arranca el Gateway:

```bash
docker compose up -d
```

Comprueba que funciona. En menos de un minuto, la columna de estado muestra `healthy`:

```bash
docker compose ps
```

Después [entra en el panel](#entra-en-el-panel), pon la clave de tu proveedor y [pon un proxy con TLS delante](#llegar-desde-otros-equipos).

## Proveedores

Lo normal es poner la clave de tu proveedor en el panel. Si prefieres tenerla en un fichero, `docker-compose.yml` trae dos bloques comentados: `NONIMO_CLAVE_DESTINO_FICHERO` para OpenAI o un proveedor compatible, y `NONIMO_CLAVE_ANTHROPIC_FICHERO` para Claude. Quita el comentario del que necesites, con su secreto, y crea el fichero con la clave en una línea, del usuario `65532:65532` y con permisos `400`.

| Variable | Valor de serie | Qué es |
|---|---|---|
| `NONIMO_DESTINO_URL` | `https://api.openai.com/v1` | OpenAI o proveedor compatible |
| `NONIMO_DESTINO_ANTHROPIC_URL` | `https://api.anthropic.com/v1` | Proveedor para las peticiones de Anthropic |

La guía completa llega con tu licencia, con los demás ajustes, la comprobación de la firma de la imagen y las actualizaciones.

## Licencia

Los ficheros de este repositorio están bajo la [licencia MIT](LICENSE). Esa licencia no cubre Nonimo Gateway ni su imagen de Docker, que son software propietario.

## Contribuciones

Este repositorio es de solo lectura y no acepta contribuciones. Para dudas o avisos de seguridad, escribe a <hello@nonimo.ai>.
