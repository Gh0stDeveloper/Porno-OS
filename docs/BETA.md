# Hex Tunnel 1.0.0-rc.9 — prueba privada

Esta prueba valida en VPS reales la instalación comercial, activación permanente firmada, reseller, renovación, actualización privada y compatibilidad AMD64/ARM64 antes de declarar estable la distribución.

## Plataformas

- Debian 12.
- Ubuntu 22.04 LTS.
- Ubuntu 24.04 LTS.
- `amd64`/`x86_64`.
- `arm64`/`aarch64`.

El perfil ARM64 instala SSH/TLS, Xray, Hysteria v1, Hysteria 2, ZiVPN, Webmin, menú nativo y runtime de autorización. Por seguridad, UDP Custom, SlowDNS heredado, SlipStream y `legacy-all` continúan limitados a AMD64 hasta disponer de artefactos ARM64 oficiales y verificables.

## Separación de canales

- El instalador comercial se publica en `https://ghostdeveloper.duckdns.org/install.sh`.
- La primera autorización valida key, IP, nonce, fechas, reseller, firma RSA y SHA-256 del paquete.
- La key solo puede utilizarse una vez y su vencimiento solo aplica antes de activarla.
- La descarga privada es temporal y de un solo uso.
- `hextunnel-license` muestra activación permanente, reseller y lease firmado.
- `hextunnel-upgrade` utiliza el token de activación local; no requiere ni conserva la key original.
- Desde `1.0.0-rc.4`, el vencimiento informativo de la key no detiene una instalación activada.
- Desde `1.0.0-rc.5`, ZiVPN usa URL y SHA-256 fijados por arquitectura para AMD64 y ARM64.
- Desde `1.0.0-rc.6`, los servicios confinados pueden leer `/etc/hextunnel` sin intentar modificar permisos sobre un filesystem de solo lectura.
- Desde `1.0.0-rc.7`, APT y DPKG esperan de forma segura a que terminen `unattended-upgrades` u otras operaciones del gestor de paquetes.
- Desde `1.0.0-rc.8`, la espera APT muestra un latido periódico con PID, tiempo transcurrido y tiempo restante; cada módulo muestra fase, porcentaje y duración.
- Desde `1.0.0-rc.9`, Xray, Sing-box, Hysteria 2 y ZiVPN se descargan anticipadamente en paralelo y solo se reutilizan si superan SHA-256.
- Desde `1.0.0-rc.9`, IPv6 queda deshabilitado por defecto después de fijar los listeners administrados a IPv4. Si la sesión SSH actual usa IPv6, la política se omite para no cortar el acceso.
- El instalador nunca borra archivos lock ni termina procesos de APT/DPKG para forzar el acceso.
- El rollback elimina estados `failed/not-found` de unidades systemd creadas temporalmente, cancela descargas anticipadas y restaura el estado runtime de IPv6.
- Una instalación fallida puede reanudarse desde el mismo VPS mediante `/etc/hextunnel/activation.token`.
- La actualización renueva correctamente el menú AMD64 o ARM64.
- `beta-install.sh` queda reservado para pruebas por commit exacto.

## Preparación

1. Crear un snapshot del VPS.
2. Usar una VPS limpia y dedicada, separada del bot y la API.
3. Confirmar Debian 12 o Ubuntu 22.04/24.04.
4. Confirmar `uname -m` como `x86_64` o `aarch64`.
5. Mantener acceso a la consola del proveedor.
6. Confirmar que los puertos requeridos estén permitidos en el firewall externo.

## Instalación comercial

Con una key emitida por TeleBotGen:

```bash
sudo bash -c 'command -v curl >/dev/null 2>&1 || { apt-get update -y && apt-get install -y curl ca-certificates; }; curl -fsSL https://ghostdeveloper.duckdns.org/install.sh -o /tmp/hextunnel-install.sh && chmod 700 /tmp/hextunnel-install.sh && exec /tmp/hextunnel-install.sh install'
```

Durante la instalación deben aparecer estados similares a:

```text
Descarga anticipada iniciada: xray-v26.3.27-Xray-linux-arm64-v8a.zip (pid=...)
Descarga anticipada iniciada: hysteria2-app-v2.9.3-hysteria-linux-arm64 (pid=...)
[FASE 1/6 | 0%] Iniciando SSH + TLS.
[FASE 1/6 | 16%] SSH + TLS completado en 42s.
APT/DPKG ocupado; esperando sin interrumpirlo. Transcurrido=30s restante<=1170s proceso=pid=...
Artefacto reutilizado desde caché verificada: xray-v26.3.27-Xray-linux-arm64-v8a.zip
```

Al final de la instalación debe aparecer:

```text
IPv6 deshabilitado; los listeners administrados quedaron fijados a IPv4.
```

Si la conexión SSH activa usa IPv6, debe aparecer una advertencia y no se debe modificar IPv6 durante esa transacción.

Después:

```bash
sudo hextunnel version
sudo hextunnel status
sudo hextunnel-license status
sudo hextunnel-license reseller
sudo systemctl status hextunnel-license-renew.timer --no-pager
sudo menu
```

Comprobar que el menú muestre:

```text
Activación: permanente
Reseller: <nombre firmado>
```

El archivo `/etc/hextunnel/license.key` no debe existir después de una activación correcta.

## Recuperación de una instalación fallida

Si una transacción falla después de activar la key, no debe emitirse una key nueva ni eliminarse el token local. Descarga otra vez el instalador público y ejecuta `install`; el bootstrap debe detectar `/etc/hextunnel/activation.token`, solicitar autorización mediante el token y reanudar la instalación en la misma IP.

```bash
sudo test -s /etc/hextunnel/activation.token
sudo curl -fsSL https://ghostdeveloper.duckdns.org/install.sh -o /tmp/hextunnel-install.sh
sudo chmod 700 /tmp/hextunnel-install.sh
sudo /tmp/hextunnel-install.sh install
```

Si APT está ocupado por `unattended-upgrades`, el instalador debe mostrar actualizaciones periódicas y continuar automáticamente cuando el gestor quede libre. No se deben borrar `/var/lib/dpkg/lock*`, `/var/lib/apt/lists/lock` ni `/var/cache/apt/archives/lock`.

Los artefactos correctamente verificados permanecen en `/var/cache/hextunnel/artifacts` durante siete días por defecto y pueden reutilizarse después de un rollback. Un archivo corrupto o con SHA-256 diferente debe eliminarse y descargarse nuevamente.

## Actualización comercial

Cuando `1.0.0-rc.9` sea la release activa:

```bash
sudo hextunnel-upgrade
sudo hextunnel version
sudo hextunnel-license status
sudo hextunnel doctor
sudo menu
```

La actualización debe utilizar `/etc/hextunnel/activation.token`, conservar cuentas, configuraciones, listeners, NAT, firewall y servicios instalados. En ARM64, `menu` debe seguir mostrando el panel ARM64 actualizado; en AMD64 debe conservar el menú heredado detrás del encabezado de Hex Tunnel.

## Prueba del vencimiento de key

En un entorno de prueba controlado:

1. activar una key válida;
2. confirmar que el estado sea permanente;
3. simular o esperar que la fecha original de la key quede en el pasado;
4. ejecutar `sudo hextunnel-license renew`;
5. ejecutar `sudo hextunnel-upgrade`;
6. confirmar que ambas acciones funcionen;
7. revocar administrativamente la instalación y confirmar que la siguiente renovación sea rechazada.

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
sudo sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6
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
- Los listeners públicos administrados usan IPv4 cuando `HEXTUNNEL_DISABLE_IPV6=1`.
- UDP Custom, SlowDNS y SlipStream solamente en AMD64.
- Stunnel, SSLH, Fail2ban y HAProxy activos cuando correspondan.
- Creación, suspensión, renovación y eliminación de cuentas.
- Renovación del lease sin cambiar la IP vinculada.
- Actualización privada sin pérdida de configuración.
- Menú y reseller correctos después de una actualización.
- Respaldo creado y verificable.

## Reinicio

```bash
sudo reboot
```

Después:

```bash
sudo systemctl --failed
sudo sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6
sudo hextunnel status
sudo hextunnel doctor
sudo hextunnel-license status
sudo systemctl status hextunnel-license-renew.timer --no-pager
sudo menu
```

No se acepta una VPS si pierde SSH, puertos, NAT, firewall, activación, reseller, menú o servicios después del reinicio.

## Datos sensibles

El canal comercial conserva con permisos `600`:

```text
/etc/hextunnel/activation.token
/etc/hextunnel/license-state.env
/etc/hextunnel/license-public.pem
```

La key original no debe conservarse en el cliente. Nunca deben compartirse tokens de activación, contraseñas, claves privadas TLS ni respaldos sin cifrar.

## Criterio de aceptación

Se requiere como mínimo una instalación limpia AMD64 y una ARM64, además de pruebas de instalación, conexiones reales, activación permanente, reseller, actualización posterior al vencimiento de la key, renovación, revocación, reinicio, respaldo y rollback.

Desarrolladores: `@Gh0stDeveloper` y `@Jotchua_DevzZ`.
