# Hex Tunnel 1.0.0-rc.2 — prueba privada

Esta prueba permite validar en VPS reales la instalación, la licencia firmada, la renovación periódica y la actualización privada antes de declarar estable la distribución.

## Alcance

El código local se trata como release candidate con criterios de producción. La distribución directa mediante GitHub sigue siendo un canal de laboratorio; la instalación comercial utiliza `https://ghostdeveloper.duckdns.org/install.sh`, autorización RSA y paquetes privados temporales.

Plataformas soportadas:

- Debian 12.
- Ubuntu 22.04 LTS.
- Ubuntu 24.04 LTS.
- Arquitectura `x86_64`/`amd64`.

## Separación de canales

- `install.sh` implementa el flujo de producción: licencia HTTPS firmada y descarga privada.
- El instalador público fija la clave RSA mediante SHA-256 y conserva la key, el token de activación y el estado con permisos `600`.
- `hextunnel-license` muestra el tiempo restante y renueva el lease firmado.
- `hextunnel-upgrade` vuelve a autorizar la VPS y actualiza el framework sin reinstalar todos los servicios de red.
- `beta-install.sh` continúa como canal de pruebas separado que descarga un commit exacto desde GitHub.
- No se aceptan nombres de rama en `HEXTUNNEL_BETA_REF`; se exige el SHA completo de 40 caracteres.
- El usuario debe aceptar explícitamente el riesgo mediante `HEXTUNNEL_BETA_ACK=ACEPTO_BETA_PRIVADA`.
- La versión instalada se toma del archivo `VERSION` del paquete.

## Preparación del VPS

1. Crear un snapshot desde el panel del proveedor.
2. Usar una VPS limpia y dedicada, sin el bot, la API, Nginx, paneles, VPN ni proxies preinstalados.
3. Confirmar que la arquitectura sea amd64/x86_64.
4. Confirmar acceso root por consola del proveedor además de SSH.
5. Mantener abierta la sesión SSH actual.
6. Comprobar que los puertos necesarios no estén bloqueados externamente.

## Instalación comercial de prueba

Con una licencia emitida por TeleBotGen:

```bash
sudo bash -c 'command -v curl >/dev/null 2>&1 || { apt-get update -y && apt-get install -y curl ca-certificates; }; curl -fsSL https://ghostdeveloper.duckdns.org/install.sh -o /tmp/hextunnel-install.sh && chmod 700 /tmp/hextunnel-install.sh && exec /tmp/hextunnel-install.sh install'
```

Después:

```bash
sudo hextunnel-license status
sudo systemctl status hextunnel-license-renew.timer --no-pager
sudo menu
```

## Actualización comercial de prueba

Cuando `1.0.0-rc.2` sea la release activa:

```bash
sudo hextunnel-upgrade
sudo hextunnel version
sudo hextunnel-license status
sudo hextunnel doctor
```

La actualización debe conservar cuentas, configuraciones, listeners y servicios previamente instalados.

## Canal beta por commit

Reemplaza `<COMMIT_SHA_RC>` por el commit exacto anunciado:

```bash
BETA_SHA="<COMMIT_SHA_RC>"
curl -fsSL "https://raw.githubusercontent.com/Gh0stDeveloper/Porno-OS/${BETA_SHA}/beta-install.sh" -o /tmp/hextunnel-beta-install.sh
chmod 700 /tmp/hextunnel-beta-install.sh
sudo HEXTUNNEL_BETA_ACK="ACEPTO_BETA_PRIVADA" \
  HEXTUNNEL_BETA_REF="$BETA_SHA" \
  /tmp/hextunnel-beta-install.sh
```

No uses `main` ni `feat/transactional-architecture` en `HEXTUNNEL_BETA_REF`.

## Verificación no destructiva del canal beta

```bash
sudo HEXTUNNEL_BETA_ACK="ACEPTO_BETA_PRIVADA" \
  HEXTUNNEL_BETA_REF="$BETA_SHA" \
  HEXTUNNEL_BETA_VERIFY_ONLY=1 \
  /tmp/hextunnel-beta-install.sh
```

## Verificación posterior

```bash
sudo hextunnel version
sudo hextunnel preflight
sudo systemctl --failed
sudo ss -lntup
sudo hextunnel status
sudo hextunnel doctor
sudo hextunnel backup create
sudo hextunnel-license status
sudo systemctl list-timers | grep hextunnel-license
sudo menu
```

Debe comprobarse:

- SSH accesible en 22 y 299.
- Xray escuchando en sus puertos configurados.
- Hysteria, Hysteria 2, UDP Custom y ZiVPN activos.
- SlowDNS, SlipStream y DNSdist sin conflictos.
- Stunnel, SSLH, Fail2ban, HAProxy y Dante activos cuando corresponda.
- Creación, renovación, suspensión y eliminación de una cuenta de prueba.
- Menú con ambos desarrolladores y tiempo restante de licencia.
- Renovación de lease válida.
- Actualización privada sin pérdida de configuración.
- Respaldo creado y validado.

## Prueba de reinicio

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

No se acepta un VPS si pierde SSH, puertos, NAT, firewall, licencia o servicios después del reinicio.

## Estado instalado

El canal beta crea `/etc/hextunnel/beta-state.env`. El canal comercial mantiene:

```text
/etc/hextunnel/license.key
/etc/hextunnel/activation.token
/etc/hextunnel/license-state.env
```

Los archivos utilizan permisos `600`.

## Reporte de errores

Registrar proveedor, sistema operativo, versión, commit o release, comando ejecutado, paso que falló, salida de `systemctl --failed`, reporte de `hextunnel doctor` y comportamiento antes/después del reinicio.

Nunca deben compartirse keys de licencia, tokens de activación, contraseñas, claves privadas TLS ni respaldos sin cifrar.

## Salida de la prueba privada

Se requieren como mínimo tres VPS limpias y dedicadas:

- Debian 12;
- Ubuntu 22.04;
- Ubuntu 24.04.

Cada VPS debe completar instalación, licencia, conexiones reales, actualización, reinicio, persistencia, respaldo, restauración controlada y desinstalación o restauración del snapshot.

Desarrolladores: `@Gh0stDeveloper` y `@Jotchua_DevzZ`.
