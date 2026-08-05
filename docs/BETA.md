# Hex Tunnel 1.0.0-rc.19 — prueba privada

Esta prueba valida instalación comercial, activación permanente, reseller, renovación, actualización privada, menú administrativo y compatibilidad AMD64/ARM64 antes de declarar estable la distribución.

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
- `rc.13`: el menú ARM64 adopta la navegación de `hex-auto-optimizado.sh`, con submenús de cuentas, conexiones, servicios, respaldos, utilidades y configuración avanzada.
- `rc.13`: `hextunnel-account show` entrega credenciales y enlaces para SSH, VLESS, VMESS, Trojan, Hysteria, Hysteria 2 y ZiVPN.
- `rc.13`: crear o eliminar cuentas Xray valida siempre un temporal con sufijo `.json`.
- `rc.14`: la actualización privada recupera automáticamente el permiso ejecutable del actualizador empaquetado y el publicador comercial verifica los modos dentro del TAR.GZ.
- `rc.15`: las credenciales usan la IPv4 pública firmada o detectada y rechazan direcciones privadas de VPC como `10.0.0.0/8`.
- `rc.15`: el administrador puede introducir y confirmar una contraseña SSH visible al crear la cuenta.
- `rc.15`: la entrega SSH muestra un bloque legible y conexiones compactas `HOST:PUERTO@USUARIO:CONTRASEÑA`.
- `rc.15`: la creación SSH comprueba las reglas locales de los puertos administrados dentro de la misma transacción y restaura el firewall si falla.
- `rc.16`: el preflight AMD64 acepta que OpenSSH ya ocupe TCP 22 o 299 mediante `sshd` o `systemd`, sin desactivar ni mover el acceso administrativo.
- `rc.16`: los propietarios ajenos a OpenSSH continúan siendo conflictos estrictos y muestran la línea completa del listener.
- `rc.16`: la instalación comercial utiliza una interfaz por fases con colores y estados `[•]`, `[✓]`, `[!]` y `[✗]`.
- `rc.16`: la salida extensa se conserva en `/var/log/hextunnel_install.log`; cualquier fallo imprime el diagnóstico completo en la terminal.
- `rc.17`: el preflight acepta UDP 53 ocupado por `systemd-resolved` únicamente cuando todos sus listeners permanecen en `127.0.0.53/54`.
- `rc.17`: la validación analiza todas las líneas devueltas por `ss`, evitando ocultar un listener público ajeno detrás de uno local permitido.
- `rc.17`: SlowDNS y dnsdist escuchan en la IPv4 asignada a la interfaz del VPS, no en `0.0.0.0:53`, y pueden coexistir con el resolvedor local.
- `rc.17`: `systemd-resolved` y `/etc/resolv.conf` se conservan; no se interrumpe la resolución DNS del sistema durante la instalación.
- `rc.18`: el instalador elimina y respalda una fuente incompleta de Cloudflare WARP antes del primer `apt-get update` de una reanudación.
- `rc.18`: la clave OpenPGP de Cloudflare se descarga por HTTPS, se valida por fingerprint y se instala mediante un keyring dedicado con `signed-by`.
- `rc.18`: si el repositorio de Cloudflare no supera la verificación de APT, se retira automáticamente y no queda bloqueando Webmin ni futuras actualizaciones.
- `rc.18`: `warp-cli` solo se ejecuta después de instalar y validar `cloudflare-warp`; el proxy local debe quedar escuchando en `127.0.0.1:40000`.
- `rc.18`: el runtime heredado deja de escribir en el descriptor cerrado `3`, eliminando el error `Bad file descriptor` durante el progreso visual.
- `rc.19`: las descargas verificadas ya no reaplican modo `0700` sobre directorios existentes como `/tmp`.
- `rc.19`: `/tmp` se repara como `root:root 1777` antes de usar APT, DPKG o componentes temporales.
- `rc.19`: WARP, Sing-box y BadVPN utilizan un ejecutor único que espera locks reales y no termina `unattended-upgrades`.
- `rc.19`: DPKG reintenta únicamente una carrera confirmada de lock, conservando errores reales de instalación.

El instalador nunca elimina archivos lock ni termina procesos de APT/DPKG para forzar acceso. El rollback cancela descargas anticipadas, apaga servicios nuevos, restaura firewall, archivos administrados, estados originales y el estado runtime previo de IPv6.

## Instalación comercial

```bash
sudo bash -c 'command -v curl >/dev/null 2>&1 || { apt-get update -y && apt-get install -y curl ca-certificates; }; curl -fsSL https://ghostdeveloper.duckdns.org/install.sh -o /tmp/hextunnel-install.sh && chmod 700 /tmp/hextunnel-install.sh && exec /tmp/hextunnel-install.sh install'
```

Durante una instalación real AMD64 deben aparecer mensajes similares a:

```text
[•] Iniciando instalación
[•] Instalación parte [1/6] — Revisando sistema y puertos
[✓] Puerto tcp/22 conservado: listener compatible existente
[✓] Puerto tcp/299 disponible
[✓] Puerto udp/53 conservado: listener compatible existente
[•] Instalación parte [2/6] — Preparando componentes verificados
[•] Instalación parte [3/6] — Instalando servicios y configuraciones
[•] Procesando paquetes del sistema
[•] Configurando Cloudflare WARP como proxy local
[✓] Cloudflare WARP disponible en el proxy local 40000
[•] Configurando servicio ssh
[•] Abriendo puerto 443
[✓] Servicios y configuraciones instalados
```

Si una fase falla, debe aparecer `[✗]`, seguido de `Detalles completos del error:` y la salida íntegra de la fase o de `/var/log/hextunnel_install.log`.

## Convivencia DNS en Ubuntu

Ubuntu puede mantener estos stubs locales:

```text
127.0.0.53:53 systemd-resolved
127.0.0.54:53 systemd-resolved
```

Hex Tunnel no debe detener ese servicio. SlowDNS o dnsdist deben escuchar en la IPv4 asignada a la interfaz principal del VPS. En Oracle Cloud normalmente será la IPv4 privada de la VNIC porque la IPv4 pública se aplica mediante NAT.

Comprobar la dirección seleccionable:

```bash
ip -4 route get 1.1.1.1
ip -4 addr show
```

Después de instalar:

```bash
sudo ss -lunp 'sport = :53'
sudo systemctl is-active systemd-resolved
sudo resolvectl status
```

Se acepta que aparezcan los stubs `127.0.0.53/54:53` junto con SlowDNS o dnsdist en la IPv4 de la interfaz. No se acepta otro proceso en `0.0.0.0:53`, en la IP de la interfaz o en una dirección pública.

## Recuperación de Cloudflare WARP y APT

Una instalación `rc.17` interrumpida puede dejar esta fuente con una clave anterior o incompleta:

```text
/etc/apt/sources.list.d/cloudflare-client.list
```

`rc.18` la respalda antes de retirarla y vuelve a comprobar APT. El helper mantenido admite:

```bash
sudo /opt/hextunnel/bin/hextunnel-cloudflare-warp cleanup
sudo /opt/hextunnel/bin/hextunnel-cloudflare-warp repair
sudo /opt/hextunnel/bin/hextunnel-cloudflare-warp install
```

La instalación no debe utilizar `apt-key`, `trusted=yes` ni continuar después de un fallo de firma. Comprobaciones posteriores:

```bash
sudo apt-get update
sudo test -s /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
sudo grep -F 'signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg' \
  /etc/apt/sources.list.d/cloudflare-client.list
command -v warp-cli
sudo systemctl is-active warp-svc
sudo ss -lntp 'sport = :40000'
```

El fingerprint de la clave debe terminar en `6E2DD2174FA1C3BA`. Si la firma del repositorio no puede validarse, la fuente de Cloudflare debe desaparecer y `apt-get update` debe volver a funcionar con los repositorios restantes.

## Recuperación de `/tmp` y locks DPKG

Una instalación `rc.18` interrumpida puede haber dejado `/tmp` con modo `0700`. Antes de reanudar, el estado correcto es:

```bash
sudo chown root:root /tmp
sudo chmod 1777 /tmp
stat -c '%U:%G %a %n' /tmp
```

Salida esperada:

```text
root:root 1777 /tmp
```

`rc.19` vuelve a comprobar y reparar ese estado antes de cada operación protegida. Si `unattended-upgrades` posee un lock real, el instalador espera y muestra el PID; no elimina el lock ni termina el proceso.

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

## Menú administrativo

Después de actualizar, `sudo menu` debe mostrar como mínimo:

```text
01 Cuentas SSH
02 Cuentas Xray
03 Cuentas Hysteria
04 Cuentas Hysteria 2
05 Cuentas ZiVPN
06 Conexiones activas
07 Control de servicios
08 Backup y restaurar
09 Utilidades
10 Configuración avanzada
```

Cada protocolo debe incluir crear, renovar, eliminar, listar, mostrar credenciales/enlaces, suspender y reactivar. La opción de cuentas no debe imprimir solamente la ayuda de `hextunnel-account`.

Prueba mínima Xray:

```bash
sudo hextunnel-account create vless prueba-menu "$(date -d '+1 day' +%Y-%m-%d)"
sudo hextunnel-account show vless prueba-menu
sudo hextunnel-account delete vless prueba-menu
```

La creación y eliminación deben validar Xray con una ruta temporal terminada en `.json`.

## Prueba de cuenta SSH

Desde el menú, crear una cuenta SSH e introducir una contraseña visible dos veces. La entrega debe mostrar una IPv4 pública; no se aceptan direcciones privadas como `10.0.0.121`.

Formato mínimo esperado:

```text
Usuario:             test
Protocolo:           ssh
Estado:              active
IPv4 pública:        149.130.209.224
Contraseña:          contraseña-elegida
Puertos SSH:         22, 299
TLS/SSL:             443, 4443
WebSocket:           25, 2082, 2086, 10080
SSH:                 149.130.209.224:22@test:contraseña-elegida
SSH alternativo:     149.130.209.224:299@test:contraseña-elegida
```

Comprobar que los listeners existen localmente:

```bash
sudo ss -lntup | grep -E ':(22|299|443|4443|25|2082|2086|10080)\b'
```

En proveedores con firewall externo, como Oracle Cloud, también se deben permitir los puertos correspondientes en la Security List o NSG. Hex Tunnel solo administra el firewall del sistema operativo.

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

Cuando `1.0.0-rc.19` sea la release activa:

```bash
sudo hextunnel-upgrade
sudo hextunnel version
sudo hextunnel-license status
sudo hextunnel doctor
sudo menu
```

Durante la publicación, `ghostctl` debe comprobar que estos archivos son ejecutables tanto en staging como dentro del TAR.GZ:

```text
install.sh
bin/hextunnel-private-install
bin/hextunnel-private-upgrade
bin/hextunnel-license
bin/hextunnel-install-license-runtime
bin/hextunnel-package-manager
bin/hextunnel-cloudflare-warp
```

La actualización debe conservar cuentas, listeners, NAT, firewall, configuraciones, activación, reseller y menú. No debe aparecer:

```text
ERROR: El paquete no contiene el actualizador privado.
```

## Verificación posterior

```bash
sudo systemctl --failed
sudo ss -lntup
sudo ss -lunp 'sport = :53'
sudo ss -lntp 'sport = :40000'
sudo systemctl is-active systemd-resolved
sudo systemctl is-active warp-svc
sudo resolvectl status
sudo apt-get update
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
- UDP 53 del túnel enlazado a la IPv4 de la interfaz y `systemd-resolved` activo únicamente en loopback.
- Cloudflare WARP activo y con proxy local en TCP 40000 cuando Hysteria v1 lo utilice.
- APT sin repositorios rotos ni errores `NO_PUBKEY`.
- `/tmp` conserva propietario `root:root` y modo `1777`.
- No quedan locks huérfanos ni procesos de APT/DPKG terminados por el instalador.
- Listeners públicos en IPv4 cuando `HEXTUNNEL_DISABLE_IPV6=1`.
- Stunnel, SSLH, Fail2ban y HAProxy activos cuando correspondan.
- Cuentas con creación, suspensión, renovación, expiración y eliminación.
- Credenciales y enlaces disponibles mediante el menú y `hextunnel-account show`.
- Las credenciales muestran la IPv4 pública y nunca una IP privada de VPC.
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

No se acepta una VPS si pierde SSH, DNS del sistema, protocolos, NAT, firewall, activación, reseller o menú después del reinicio.

## Datos sensibles

Se conservan con permisos restrictivos:

```text
/etc/hextunnel/activation.token
/etc/hextunnel/license-state.env
/etc/hextunnel/license-public.pem
/var/lib/hextunnel/warp/state.env
```

La key original no debe conservarse en el cliente.

Desarrolladores: `@Gh0stDeveloper` y `@Jotchua_DevzZ`.
