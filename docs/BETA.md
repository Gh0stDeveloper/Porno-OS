# Hex Tunnel 1.0.0-rc.12 — prueba privada

Esta prueba valida instalación comercial, activación permanente, reseller, renovación, actualización privada y compatibilidad AMD64/ARM64 antes de declarar estable la distribución.

## Plataformas validadas

- Debian 12.
- Ubuntu 22.04 LTS.
- Ubuntu 24.04 LTS.
- `amd64`/`x86_64`.
- `arm64`/`aarch64`.

El perfil ARM64 instala SSH/TLS, Xray, Hysteria v1, Hysteria 2, ZiVPN, Webmin, menú nativo y runtime de autorización. UDP Custom, SlowDNS heredado, SlipStream y `legacy-all` continúan limitados a AMD64 hasta disponer de artefactos ARM64 verificables.

## Cambios acumulados relevantes

- `rc.4`: activación permanente y actualizaciones mediante `activation.token`.
- `rc.5`: ZiVPN con URL y SHA-256 fijados para AMD64 y ARM64.
- `rc.6`: servicios confinados leen `/etc/hextunnel` sin intentar modificarlo.
- `rc.7`: APT/DPKG espera de manera acotada cuando sus locks reales están ocupados.
- `rc.8`: progreso por fases y latido visible durante esperas del gestor de paquetes.
- `rc.9`: descargas anticipadas paralelas verificadas, caché persistente e IPv4-only por defecto.
- `rc.10`: detección real de locks APT/DPKG, preservación de `/tmp` y reparación automática de su modo `1777`.
- `rc.11`: el rollback apaga servicios creados durante una transacción antes de retirar sus unidades; el siguiente preflight limpia residuos de la última transacción revertida.
- `rc.12`: Xray, Hysteria v1 y ZiVPN conservan una extensión JSON explícita durante la validación temporal de la política IPv4-only.

El instalador nunca elimina archivos lock ni termina procesos de APT/DPKG para forzar acceso. El rollback cancela descargas anticipadas, apaga servicios nuevos, restaura firewall, archivos administrados, estados originales y el estado runtime previo de IPv6.

## Instalación comercial

```bash
sudo bash -c 'command -v curl >/dev/null 2>&1 || { apt-get update -y && apt-get install -y curl ca-certificates; }; curl -fsSL https://ghostdeveloper.duckdns.org/install.sh -o /tmp/hextunnel-install.sh && chmod 700 /tmp/hextunnel-install.sh && exec /tmp/hextunnel-install.sh install'
```

Durante una instalación real deben aparecer mensajes similares a:

```text
Descarga anticipada iniciada: xray-v26.3.27-Xray-linux-arm64-v8a.zip (pid=...)
Descarga anticipada iniciada: hysteria2-app-v2.9.3-hysteria-linux-arm64 (pid=...)
[FASE 1/6 | 0%] Iniciando SSH + TLS.
Artefacto reutilizado desde caché verificada: xray-v26.3.27-Xray-linux-arm64-v8a.zip
```

Solo debe aparecer una espera APT cuando un proceso posea realmente uno de estos locks:

```text
/var/lib/dpkg/lock-frontend
/var/lib/dpkg/lock
/var/lib/apt/lists/lock
/var/cache/apt/archives/lock
/var/lib/apt/daily_lock
```

El daemon permanente `unattended-upgrade-shutdown --wait-for-signal` no debe detener la instalación si no posee uno de esos locks.

Al finalizar mediante una sesión SSH IPv4 debe aparecer:

```text
IPv6 deshabilitado; los listeners administrados quedaron fijados a IPv4.
```

Antes de reemplazar `/etc/xray/config.json`, Xray debe aceptar una ruta temporal que termine en `.json`. No debe aparecer:

```text
Failed to get format of /tmp/hextunnel-xray-ipv4.*
```

Si la sesión SSH activa usa IPv6, la política se omite para no cortar el acceso.

## Recuperación

Una instalación fallida puede reanudarse desde la misma VPS sin emitir otra key:

```bash
sudo test -s /etc/hextunnel/activation.token
sudo curl -fsSL https://ghostdeveloper.duckdns.org/install.sh -o /tmp/hextunnel-install.sh
sudo chmod 700 /tmp/hextunnel-install.sh
sudo /tmp/hextunnel-install.sh install
```

Antes de validar los puertos, el instalador revisa la última transacción `ROLLED_BACK` y detiene únicamente servicios que estaban inactivos antes de esa transacción. No debe detener SSH ni otro servicio que ya estuviera activo.

Los artefactos verificados permanecen en `/var/cache/hextunnel/artifacts` durante siete días por defecto. Un archivo corrupto o con SHA-256 diferente se rechaza y vuelve a descargarse.

## Actualización comercial

Cuando `1.0.0-rc.12` sea la release activa:

```bash
sudo hextunnel-upgrade
sudo hextunnel version
sudo hextunnel-license status
sudo hextunnel doctor
sudo menu
```

La actualización debe conservar cuentas, listeners, NAT, firewall, configuraciones, activación, reseller y menú.

## Verificación posterior

```bash
sudo systemctl --failed
sudo ss -lntup
sudo sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6
sudo hextunnel version
sudo hextunnel status
sudo hextunnel doctor
sudo hextunnel-license status
sudo hextunnel-license reseller
sudo systemctl status hextunnel-license-renew.timer --no-pager
sudo menu
```

Comprobar:

- SSH accesible en 22 y 299.
- Xray y sus transportes activos.
- Hysteria v1, Hysteria 2 y ZiVPN operativos.
- Listeners públicos en IPv4 cuando `HEXTUNNEL_DISABLE_IPV6=1`.
- Stunnel, SSLH, Fail2ban y HAProxy activos cuando correspondan.
- Cuentas con creación, suspensión, renovación, expiración y eliminación.
- Renovación del lease y actualización sin perder configuración.

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
sudo menu
```

No se acepta una VPS si pierde SSH, protocolos, NAT, firewall, activación, reseller o menú después del reinicio.

## Datos sensibles

Se conservan con permisos restrictivos:

```text
/etc/hextunnel/activation.token
/etc/hextunnel/license-state.env
/etc/hextunnel/license-public.pem
```

La key original no debe conservarse en el cliente.

Desarrolladores: `@Gh0stDeveloper` y `@Jotchua_DevzZ`.
