# Distribución privada y licencia previa

El archivo público `install.sh` no descarga el panel ni los módulos antes de validar la licencia. Cuando se ejecuta sin el árbol local (`lib/common.sh` ausente), actúa únicamente como bootstrap.

## Flujo

1. Instala dependencias mínimas (`curl`, `jq`, `openssl`, `tar` y `coreutils`).
2. Lee la key sin mostrarla en la terminal.
3. Obtiene la IP pública del VPS.
4. Envía key, IP, nonce y timestamp al endpoint HTTPS configurado.
5. Verifica la firma de la autorización con una clave pública fijada.
6. Solo entonces descarga el paquete privado mediante una URL HTTPS temporal.
7. Verifica el SHA-256 autorizado y rechaza rutas inseguras en el TAR.
8. Ejecuta `bin/hextunnel-private-install`.
9. El wrapper ejecuta automáticamente `legacy/install-all.sh`, omite la validación HTTP antigua ya reemplazada por la autorización firmada y abre `/usr/local/bin/menu` al finalizar.

El modo modular se mantiene para desarrollo, reparación y CI cuando el repositorio completo está presente localmente. El cliente que descarga únicamente `install.sh` no ve el selector modular.

## Configuración del bootstrap público

El servidor o el comando generado por el bot debe establecer:

```bash
HEXTUNNEL_DISTRIBUTION_ENDPOINT="https://panel.example.com/api/v1/install/authorize"
HEXTUNNEL_LICENSE_PUBLIC_KEY_URL="https://panel.example.com/.well-known/hextunnel-license-public.pem"
HEXTUNNEL_LICENSE_PUBLIC_KEY_SHA256="<sha256-de-64-caracteres>"
```

También se admite una clave pública local mediante `HEXTUNNEL_LICENSE_PUBLIC_KEY` o un PEM ya fijado mediante `HEXTUNNEL_LICENSE_PUBLIC_KEY_PEM`.

La key del cliente no debe incluirse en el mensaje del bot. El bootstrap la solicita mediante lectura silenciosa.

## Solicitud de autorización

`POST HEXTUNNEL_DISTRIBUTION_ENDPOINT`

```json
{
  "key": "KEY-DEL-CLIENTE",
  "ip": "203.0.113.10",
  "nonce": "48-caracteres-hex",
  "timestamp": 1785080000,
  "product": "hextunnel",
  "action": "install"
}
```

El servidor debe comprobar como mínimo:

- key existente, activa y no expirada;
- producto y acción permitidos;
- timestamp dentro de una ventana corta;
- política de activación por VPS/IP;
- límite de activaciones y revocaciones;
- que el paquete solicitado sea una versión publicada.

## Respuesta firmada

```json
{
  "status": "valid",
  "expires_at": "2027-07-26T00:00:00Z",
  "download_expires_at": "2026-07-26T18:10:00Z",
  "nonce": "MISMO-NONCE-DE-LA-SOLICITUD",
  "subject": "203.0.113.10",
  "version": "1.0.0",
  "download_url": "https://panel.example.com/api/v1/releases/download/TOKEN-DE-UN-SOLO-USO",
  "package_sha256": "SHA256-DEL-TAR-GZ",
  "entrypoint": "bin/hextunnel-private-install",
  "signature": "FIRMA-RSA-EN-BASE64"
}
```

La firma se calcula sobre este contenido canónico exacto:

```text
status=<status>
expires_at=<expires_at>
download_expires_at=<download_expires_at>
nonce=<nonce>
subject=<subject>
version=<version>
download_url=<download_url>
package_sha256=<package_sha256-en-minúsculas>
entrypoint=<entrypoint>
```

La firma recomendada es RSA/SHA-256 compatible con:

```bash
openssl dgst -sha256 -sign license-private.pem authorization.payload
```

La clave privada permanece únicamente en el servidor. El instalador distribuye o fija solamente la clave pública.

## Paquete privado

El TAR.GZ debe contener al menos:

```text
bin/hextunnel-private-install
legacy/install-all.sh
```

Puede incluir el resto del panel, menús, módulos, plantillas y configuraciones privadas. La URL de descarga debe ser temporal, de un solo uso y estar vinculada a la autorización emitida.

## Comando del bot

Cuando existan el dominio y el SHA-256 reales:

```bash
sudo apt-get update -y && sudo apt-get install -y curl ca-certificates && curl -fsSL "https://panel.example.com/install.sh" -o /tmp/hextunnel-install.sh && chmod 700 /tmp/hextunnel-install.sh && sudo HEXTUNNEL_DISTRIBUTION_ENDPOINT="https://panel.example.com/api/v1/install/authorize" HEXTUNNEL_LICENSE_PUBLIC_KEY_URL="https://panel.example.com/.well-known/hextunnel-license-public.pem" HEXTUNNEL_LICENSE_PUBLIC_KEY_SHA256="<SHA256>" /tmp/hextunnel-install.sh
```

No se debe usar `apt upgrade -y` en el comando de instalación.
