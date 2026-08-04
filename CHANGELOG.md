# Changelog

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
- APT recibe `DPkg::Lock::Timeout` y `APT::Update::Lock::Timeout` como segunda protección contra carreras entre procesos.
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

- El runtime de actualización renueva el panel ARM64 desde la release nueva.
- AMD64 reconstruye el wrapper sin sobrescribir `menu-original`.
- El bootstrap descargado por `hextunnel-upgrade` pasa `bash -n` antes de ejecutarse.
- La actualización respalda framework, menú, runtime y unidades de licencia dentro de la misma transacción.
- Antes del commit valida todos los módulos instalados, el estado de licencia y el timer de renovación.
- Cualquier fallo ejecuta rollback en vez de dejar una actualización parcial.
- La renovación de lease usa `flock`, evitando carreras entre el timer y una renovación manual.
- `license-state.env` se reemplaza atómicamente en vez de modificarse con `sed + append`.
- La clave pública verificada queda almacenada localmente y se reutiliza; solo se descarga si falta o no coincide con el SHA-256 fijado.
- El token de activación se envía a `curl` mediante un archivo JSON modo `600`, no como argumento del proceso.

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
