# Nonimo Gateway: instalación y ejemplos

[English](README.md)

Nonimo Gateway corre en **tu propio servidor**, entre tus aplicaciones y tu proveedor de IA. Tapa los datos personales antes de que la petición salga de tu red y devuelve los valores reales en la respuesta. Para usarlo, cambias el `base_url` de tu aplicación.

> **Este repositorio no es el código fuente del Gateway.** Nonimo Gateway es software comercial de código cerrado y se distribuye como imagen privada de Docker. Aquí solo hay un ejemplo de Docker Compose, ejemplos de cliente y notas de instalación. Para descargar la imagen hace falta una licencia.

Página del producto: <https://nonimo.ai/es/gateway/> · Contacto: <gateway@nonimo.ai>

## Qué necesitas

- Un servidor Linux `amd64` o `arm64` con Docker.
- Salida HTTPS hacia tu proveedor de IA y hacia el servicio de licencias de Nonimo.
- Tu fichero de licencia, `licencia.nli`, y el correo de tu licencia, que trae la orden para entrar en el registro, el nombre de la imagen y la versión.

## Instalar con Docker Compose

Deja `licencia.nli` junto a `docker-compose.yml` y hazla legible para el contenedor:

```bash
chmod 644 licencia.nli
```

Entra en el registro con la orden del correo de tu licencia.

Crea el fichero para la clave de tu proveedor:

```bash
install -m 600 /dev/null clave_proveedor.txt
```

Abre `clave_proveedor.txt` con tu editor y pega la clave de tu proveedor en una línea, para que no quede en el historial de la terminal.

Genera la clave de acceso que usarán tus aplicaciones:

```bash
(umask 077; openssl rand -hex 32 > clave_entrada.txt)
```

El Gateway corre con el usuario 65532, así que los dos ficheros tienen que ser de ese usuario y de nadie más:

```bash
sudo chown 65532:65532 clave_proveedor.txt clave_entrada.txt && sudo chmod 400 clave_proveedor.txt clave_entrada.txt
```

En `docker-compose.yml`, cambia el texto de la imagen por el nombre y la versión del correo de tu licencia. Después arranca el Gateway:

```bash
docker compose up -d
```

Comprueba que funciona. En menos de un minuto, la columna de estado muestra `healthy`:

```bash
docker compose ps
```

El puerto solo se abre en el propio servidor. Para llegar desde otros equipos, pon un proxy con TLS delante de `127.0.0.1:8080`, y así el texto original no cruza tu red sin cifrar. Publica solo las rutas de la API que usen tus aplicaciones.

## Apunta tu aplicación al Gateway

El Gateway es compatible con las API de OpenAI y Anthropic. Cambia la dirección base y usa como clave de API la clave de acceso de `clave_entrada.txt`:

| | Dirección base | Clave de API |
|---|---|---|
| SDK de OpenAI y clientes compatibles | `https://gateway.tu-empresa.es/v1` | clave de acceso |
| SDK de Anthropic | `https://gateway.tu-empresa.es` | clave de acceso |

Ejemplos que se pueden ejecutar: [Python](examples/python/main.py) · [Node](examples/node/index.mjs).

Sin la clave de acceso, la petición recibe un `401` y no se envía nada.

## Proveedores

El ejemplo de Compose guarda una clave de un proveedor compatible con OpenAI. Para Anthropic, añade `NONIMO_CLAVE_ANTHROPIC_FICHERO` y un tercer secreto de la misma forma.

| Variable | Valor de serie | Qué es |
|---|---|---|
| `NONIMO_DESTINO_URL` | `https://api.openai.com/v1` | OpenAI o proveedor compatible |
| `NONIMO_DESTINO_ANTHROPIC_URL` | `https://api.anthropic.com/v1` | Proveedor para las peticiones de Anthropic |

La guía completa llega con tu licencia, con los demás ajustes, la comprobación de la firma de la imagen y las actualizaciones.

## Licencia

Los ficheros de este repositorio están bajo la [licencia MIT](LICENSE). Esa licencia no cubre Nonimo Gateway ni su imagen de Docker, que son software propietario.

## Contribuciones

Este repositorio es de solo lectura y no acepta contribuciones. Para dudas o avisos de seguridad, escribe a <gateway@nonimo.ai>.
