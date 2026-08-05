# Changelog

## 1.0.0-rc.16 — 2026-08-04

- El preflight AMD64 reconoce como válidos los listeners TCP 22 y 299 administrados por `sshd` o `systemd`, conservando el acceso SSH durante la instalación.
- Los procesos ajenos a OpenSSH continúan bloqueando la instalación y el error muestra la línea completa del listener responsable.
- El instalador comercial adopta una interfaz decorativa con colores, estados `[•]`, `[✓]`, `[!]` y `[✗]`, y fases numeradas.
- La revisión muestra cada puerto requerido como disponible, conservado o en conflicto.
- La salida extensa de APT, DPKG, servicios y componentes se guarda en `/var/log/hextunnel_install.log` para mantener limpia la terminal.
- APT, systemd, Git y las reglas de firewall muestran avances resumidos, incluyendo `Abriendo puerto <puerto>`.
- Cuando una fase falla, el instalador imprime el error completo y el contenido íntegro del registro técnico.
- Se añade una prueba de regresión para listeners OpenSSH en TCP 22/299 y rechazos por propietario, puerto o protocolo incorrectos.
- Se elimina un falso positivo de Gitleaks en una credencial ficticia utilizada únicamente por las pruebas.

## 1.0.0-rc.15 — 2026-08-04

- Las credenciales dejan de usar la IPv4 privada de la VPC como host público.
- La detección prioriza `HEXTUNNEL_PUBLIC_IPV4`, la IP pública firmada en la licencia y servicios externos IPv4; se rechazan rangos privados, loopback, link-local, CGNAT y documentación.
- Al crear una cuenta SSH desde el menú, el administrador introduce y confirma una contraseña visible en lugar de recibir una contraseña aleatoria obligatoria.
- Las contraseñas SSH interactivas se validan antes de modificar usuarios y no se pasan como argumentos del proceso.
- La entrega de credenciales adopta un bloque más legible con IPv4 pública, puertos, estado y conexiones compactas `HOST:PUERTO@USUARIO:CONTRASEÑA`.
- La creación SSH comprueba y abre las reglas locales administradas para SSH, TLS y WebSocket dentro de la transacción.
- Las operaciones transaccionales de cuentas incluyen snapshot del firewall para restaurarlo si la creación falla.
- El plan de prueba documenta que las Security Lists o NSG del proveedor deben permitir los puertos además del firewall local.

## 1.0.0-rc.14 — 2026-08-04

- La actualización privada distingue entre un archivo ausente y un archivo presente sin bit ejecutable.
- `hextunnel-private-install` exige que el actualizador sea un archivo regular legible, restaura su modo `0700` y lo ejecuta mediante Bash.
- Se añade una prueba funcional que reproduce un actualizador empaquetado como `0600` y confirma su ejecución y reparación a `0700`.
- El publicador de GhostDeveloperLicenseServer normaliza los modos del staging comercial y verifica los permisos ejecutables dentro del TAR.GZ antes de registrar la release.
- `rc.13` permanece funcional para instalaciones nuevas, pero su paquete comercial no puede actualizar instalaciones existentes debido al modo perdido de `bin/hextunnel-private-upgrade`.

## 1.0.0-rc.13 — 2026-08-04

- El menú ARM64 adopta la estructura visual y funcional de `hex-auto-optimizado.sh`.
- Se añaden submenús para SSH, VLESS, VMESS, Trojan, Hysteria v1, Hysteria 2 y ZiVPN.
- Las cuentas pueden crearse, renovarse, eliminarse, listarse, suspenderse, reactivarse y consultarse sin abandonar el panel.
- El panel incluye conexiones activas, control de servicios, respaldos, utilidades, configuración avanzada, licencia y actualización.
- `hextunnel-account show` muestra credenciales y genera enlaces de cliente para los protocolos compatibles.
- Las operaciones de cuentas Xray validan archivos temporales con sufijo `.json`, evitando el error de detección de formato de Xray.
- El gate de producción comprueba la presencia del menú, sus submenús, el comando `show` y las guardas de cuentas Xray.

## 1.0.0-rc.12 — 2026-08-04

- La política IPv4-only valida Xray usando un archivo temporal con sufijo `.json`, permitiendo que Xray detecte correctamente el formato.
- Hysteria v1 y ZiVPN también generan temporales JSON con extensión explícita para conservar el formato durante validaciones y reemplazos atómicos.
- Las rutas de configuración y binarios de la política de red pueden sobrescribirse en pruebas sin alterar los valores de producción.
- Se añade una prueba funcional con un Xray simulado que devuelve código `23` cuando el archivo temporal no termina en `.json`.
- El rollback de `rc.11` se conserva y continúa deteniendo servicios antes de restaurar sus unidades.

## 1.0.0-rc.11 — 2026-08-04

- El rollback detiene primero los servicios creados durante la transacción antes de restaurar o eliminar sus unidades systemd.
- Los servicios se apagan en orden inverso de registro para terminar dependientes antes que servicios auxiliares.
- Si una unidad queda `LoadState=not-found` pero mantiene procesos activos, el rollback intenta `stop`, `TERM` y finalmente `KILL` de forma limitada a esa unidad administrada.
- Antes del preflight, una nueva instalación limpia servicios residuales registrados en la última transacción `ROLLED_BACK`.
- Se añade una prueba de regresión que impide detener servicios preexistentes activos como SSH y valida el orden `quiesce -> archivos -> IPv6 -> firewall -> servicios -> usuarios`.

## 1.0.0-rc.10 — 2026-08-04

- La espera de APT/DPKG ahora consulta los locks reales mediante `fuser` o `lslocks`.
- El daemon permanente `unattended-upgrade-shutdown --wait-for-signal` deja de bloquear falsamente la instalación.
- El diagnóstico muestra únicamente procesos que poseen un lock del gestor de paquetes; ya no incluye el propio proceso `awk` usado para construir el mensaje.
- La caché verificada deja de aplicar permisos `0700` sobre directorios compartidos existentes como `/tmp`.
- Antes de ejecutar APT o DPKG se comprueba y, si es necesario, se restaura `/tmp` como `root:root` con modo `1777`.
- Se añaden pruebas de regresión para el vigilante sin lock, la descarga de ZiVPN a un archivo directo en un directorio compartido y la reparación de permisos temporales.
- Los timeouts internos de APT permanecen como protección contra carreras entre la comprobación y la ejecución.

## 1.0.0-rc.9 — 2026-08-03

- IPv6 se deshabilita por defecto al completar la instalación, después de fijar los listeners públicos administrados a IPv4.
- La política IPv4-only se omite si la sesión SSH actual usa IPv6, evitando cortar el acceso administrativo.
- El rollback restaura el archivo `sysctl`, el estado runtime previo de IPv6 y las configuraciones de listeners.
- Xray, Sing-box, Hysteria 2 y ZiVPN se descargan anticipadamente en paralelo mientras se instalan los primeros módulos.
- La caché persistente solo reutiliza artefactos que vuelven a superar el SHA-256 oficial o fijado por el `component-lock`.
- Las descargas paralelas se cancelan limpiamente cuando una transacción falla o finaliza.
- Se añade una prueba de regresión para la detección de sesiones SSH IPv6, caché verificada, materialización por URL y rechazo de artefactos corruptos.
- La implementación toma como referencia funcional `hex-auto-optimizado.sh`, manteniendo la arquitectura Bash modular y transaccional.

## 1.0.0-rc.8 — 2026-08-03

- La espera de APT/DPKG muestra cada 15 segundos el proceso detectado, PID, estado, tiempo transcurrido y límite restante.
- La instalación muestra fase, porcentaje y duración para cada módulo resuelto.
- El runtime visible se mantiene separado del núcleo común para no alterar servicios que cargan configuración en modo de solo lectura.
- Se amplía la prueba de regresión del gestor de paquetes para cubrir el diagnóstico del proceso y la salida de progreso.
- La mejora toma como referencia la interfaz del fuente `hex-auto-optimizado.sh`.

## 1.0.0-rc.7 — 2026-08-03

- Todas las operaciones `apt`, `apt-get` y `dpkg` del framework esperan de forma acotada a que finalicen `unattended-upgrades` u otras operaciones del gestor de paquetes.
- APT recibe `DPkg::Lock::Timeout` y `APT::Update::Lock::Timeout` como segunda protección contra carreras entre la comprobación y la ejecución.
- El instalador no elimina archivos lock ni termina procesos del sistema para forzar el acceso al gestor de paquetes.
- Se añade una prueba de regresión con APT, DPKG y `unattended-upgr` simulados.
- Las comprobaciones de release dejan de estar acopladas a un número `rc` escrito manualmente.

## 1.0.0-rc.6 — 2026-08-03

- `load_runtime_config` ya no intenta recrear ni cambiar permisos de `/etc/hextunnel` cuando el directorio existe.
- Los servicios systemd con `ProtectSystem=full` o `ProtectSystem=strict` pueden cargar configuración sin fallar por filesystem de solo lectura.
- Se añade una prueba de regresión específica para carga de configuración en runtime confinado.
- El rollback omite unidades eliminadas, limpia estados `failed/not-found` y evita advertencias falsas de restauración.

## 1.0.0-rc.5 — 2026-08-03

- La publicación fija por separado las URLs y los SHA-256 de ZiVPN para AMD64 y ARM64.
- El instalador ARM64 usa el checksum incluido en la release y ya no depende de que GitHub publique el campo `digest`.
- El gate de producción exige artefactos ZiVPN verificables para ambas arquitecturas.
- Se añade una prueba de regresión para impedir que el checksum AMD64 se elimine sin sustituirse por el checksum ARM64.

## 1.0.0-rc.4 — 2026-08-03

- La expiración de la key se considera únicamente el límite para realizar la primera activación.
- Una instalación activada continúa operativa y renovando leases después del vencimiento de la key, hasta una revocación administrativa.
- Las actualizaciones utilizan `activation.token`; la key original ya no se conserva ni se reutiliza.
- El estado local registra activación permanente, fecha de activación y reseller firmado.
- Los menús AMD64 y ARM64 muestran `Activación: permanente` y el reseller correspondiente.
- `hextunnel-license status` distingue el vencimiento informativo de la key del estado permanente de la instalación.
- Las pruebas ejercitan una renovación real después de vencer artificialmente la key.

## 1.0.0-rc.3 — 2026-08-01

- El runtime de actualización renueva el panel ARM64 desde el paquete instalado.
- El wrapper del menú AMD64 se reconstruye de forma segura sin sobrescribir el menú original.
- El bootstrap de actualización valida sintaxis Bash antes de ejecutarse.
- Las pruebas de licencia exigen que la actualización conserve y refresque el menú correspondiente a la arquitectura.
- La publicación comercial ejecuta el gate completo de producción antes de registrar el paquete.

## 1.0.0-rc.2 — 2026-08-01

- Distribución comercial protegida mediante key, autorización por IP, nonce y timestamp.
- Descarga privada temporal, de un solo uso y verificada mediante firma RSA y SHA-256.
- Runtime de licencia con `status`, `renew`, `remaining` y renovación periódica mediante systemd.
- Actualización privada transaccional mediante `hextunnel-upgrade`.
- Soporte de producción para `arm64/aarch64` en Debian 12 y Ubuntu 22.04/24.04.
- Instalación ARM64 mediante perfil modular nativo en lugar del instalador heredado AMD64.
- Perfil ARM64 con SSH/TLS, Xray, Hysteria v1, Hysteria 2, ZiVPN y Webmin.
- Sing-box y ZiVPN seleccionan el artefacto ARM64 y verifican el digest SHA-256 publicado por GitHub.
- Panel `menu` específico para ARM64 con estado, diagnóstico, cuentas, licencia y actualización.
- Validación de compatibilidad de cada módulo antes de modificar el VPS.
- UDP Custom, SlowDNS heredado, SlipStream dependiente de SlowDNS y `legacy-all` permanecen bloqueados en ARM64 hasta disponer de artefactos oficiales, reproducibles y verificables.

## 1.0.0-rc.1 — 2026-07-26

- Arquitectura Bash manual y modular; sin generadores Python.
- Instalador transaccional con respaldo, validación y rollback.
- Bloqueo global con `flock` para impedir instalaciones, desinstalaciones, actualizaciones o rollbacks simultáneos.
- Preflight de root, plataforma, arquitectura, systemd, reloj, RAM, disco, red y puertos.
- Soporte de producción delimitado a Debian 12, Ubuntu 22.04 LTS y Ubuntu 24.04 LTS sobre amd64.
- Firewall reversible compatible con UFW, nftables e iptables.
- Módulos SSH/TLS, Xray, Hysteria v1, Hysteria 2, UDP Custom, SlowDNS, SlipStream, ZiVPN y Webmin.
- SSLH aislado de los defaults incompatibles de Debian/Ubuntu mediante una unidad y configuración propias.
- Compatibilidad con SSLH 1.20 usando la forma estricta `-F/ruta` y con SSLH 1.22 en Ubuntu 24.04.
- Generación TLS compatible con hostnames largos y validación OpenSSH portable.
- HAProxy gRPC con PID dentro de su `RuntimeDirectory` de systemd.
- Hysteria 2 con usuario dedicado, TLS privado, validación temporal controlada y permisos de cuenta conservados.
- Centro `hextunnel doctor`, `hextunnel preflight`, versionado central y monitor periódico sanitizado.
- Gestión centralizada de cuentas, expiración, suspensión, reanudación y auditoría.
- Respaldo verificable, cifrado opcional con age, listado y restauración protegida por hostname.
- Respaldo preventivo automático antes de restaurar.
- Actualizador por canales con manifiesto firmado y SHA-256.
- Empaquetado reproducible con manifiesto SHA-256 interno, inventario y checksum externo.
- Runbooks de operación, recuperación y distribución privada.
- Canal beta privado fijado a commits inmutables para pruebas de VPS.
- Instalador heredado sanitizado como modo de compatibilidad.

## Unreleased

- Ampliación formal de la matriz a Debian 11/Ubuntu 20.04 y arquitecturas ARM32/i386 pendiente de pruebas reales.
- Validación integral pendiente en VPS AMD64 y ARM64 limpias antes de declarar la release estable.
