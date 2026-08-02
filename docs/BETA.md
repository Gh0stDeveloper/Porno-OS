# Hex Tunnel 1.0.0-rc.3 — prueba privada

Esta prueba valida en VPS reales la instalación comercial, licencia firmada, renovación, actualización privada y compatibilidad AMD64/ARM64 antes de declarar estable la distribución.

## Plataformas

- Debian 12.
- Ubuntu 22.04 LTS.
- Ubuntu 24.04 LTS.
- `amd64`/`x86_64`.
- `arm64`/`aarch64`.

El perfil ARM64 instala SSH/TLS, Xray, Hysteria v1, Hysteria 2, ZiVPN, Webmin, menú nativo y runtime de licencia. Por seguridad, UDP Custom, SlowDNS heredado, SlipStream y `legacy-all` continúan limitados a AMD64 hasta disponer de artefactos ARM64 oficiales y verificables.

## Separación de canales

- El instalador comercial se publica en `https://ghostdeveloper.duckdns.org/install.sh`.
- La autorización valida key, IP, nonce, fechas, firma RSA y SHA-256 del paquete.
- La descarga privada es temporal y de un solo uso.
- `hextunnel-license` muestra y renueva el lease firmado.
- `hextunnel-upgrade` vuelve a autorizar la VPS y actualiza el framework sin reinstalar los servicios de red.
- Desde `1.0.0-rc.3`, la actualización también renueva correctamente el menú AMD64 o ARM64.
- `beta-install.sh` queda reservado para pruebas por commit exacto.

## Preparación

1. Crear un snapshot del VPS.
2. Usar una VPS limpia y dedicada, separada del bot y la API.
3. Confirmar Debian 12 o Ubuntu 22.04/24.04.
4. Confirmar `uname -m` como `x86_64` o `aarch64`.
5. Mantener acceso a la consola del proveedor.
6. Confirmar que los puertos requeridos estén permitidos en el firewall externo.

## Instalación comercial

Con una licencia emitida por TeleBotGen:

```bash
sudo bash -c 'command -v curl >/dev/null 2>&1 || { apt-get update -y && apt-get install -y curl ca-certificates; }; curl -fsSL https://ghostdeveloper.duckdns.org/install.sh -o /tmp/hextunnel-install.sh && chmod 700 /tmp/hextunnel-install.sh && exec /tmp/hextunnel-install.sh install'
```

Después:

```bash
sudo hextunnel version
sudo hextunnel status
sudo hextunnel-license status
sudo systemctl status hextunnel-license-renew.timer --no-pager
sudo menu
```

## Actualización comercial

Cuando `1.0.0-rc.3` sea la release activa:

```bash
sudo hextunnel-upgrade
sudo hextunnel version
sudo hextunnel-license status
sudo hextunnel doctor
sudo menu
```

La actualización debe conservar cuentas, configuraciones, listeners, NAT, firewall y servicios instalados. En ARM64, `menu` debe seguir mostrando el panel ARM64 actualizado; en AMD64 debe conservar el menú heredado detrás del encabezado de Hex Tunnel.

## Canal beta por commit

```bash
BETA_SHA="<COMMIT_SHA_RC>"
curl -fsSL "https://raw.githubusercontent.com/Gh0stDeveloper/Porno-OS/${BETA_SHA}/beta-install.sh" -o /tmp/hextunnel-beta-install.sh
chmod 700 /tmp/hextunnel-beta-install.sh
sudo HEXTUNNEL_BETA_ACK="ACEPTO_BETA_PRIVADA" \
  HEXTUNNEL_BETA_REF="$BETA_SHA" \
  /tmp/hextunnel-beta-install.sh
```

No deben utilizarse nombres de rama en `HEXTUNNEL_BETA_REF`.

## Verificación posterior

```bash
sudo systemctl --failed
sudo ss -lntup
sudo hextunnel status
sudo hextunnel doctor
sudo hextunnel backup create
sudo hextunnel-license status
sudo systemctl list-timers | grep hextunnel-license
sudo menu
```

Comprobar:

- SSH accesible en 22 y 299.
- Xray y sus transportes activos.
- Hysteria/Hysteria 2 y ZiVPN operativos.
- UDP Custom, SlowDNS y SlipStream solamente en AMD64.
- Stunnel, SSLH, Fail2ban y HAProxy activos cuando correspondan.
- Creación, suspensión, renovación y eliminación de cuentas.
- Renovación del lease sin cambiar la IP vinculada.
- Actualización privada sin pérdida de configuración.
- Menú correcto después de una actualización.
- Respaldo creado y verificable.

## Reinicio

```bash
sudo reboot
```

Después:

```bash
sudo systemctl --failed
sudo hextunnel status
sudo hextunnel doctor
sudo hextunnel-license status
sudo systemctl status hextunnel-license-renew.timer --no-pager
sudo menu
```

No se acepta una VPS si pierde SSH, puertos, NAT, firewall, licencia, menú o servicios después del reinicio.

## Datos sensibles

El canal comercial conserva con permisos `600`:

```text
/etc/hextunnel/license.key
/etc/hextunnel/activation.token
/etc/hextunnel/license-state.env
```

Nunca deben compartirse keys, tokens de activación, contraseñas, claves privadas TLS ni respaldos sin cifrar.

## Criterio de aceptación

Se requiere como mínimo una instalación limpia AMD64 y una ARM64, además de pruebas de instalación, conexiones reales, actualización, renovación, reinicio, respaldo y rollback.

Desarrolladores: `@Gh0stDeveloper` y `@Jotchua_DevzZ`.
