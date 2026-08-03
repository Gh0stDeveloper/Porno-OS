# Changelog

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

- Validación integral pendiente en VPS AMD64 y ARM64 limpias antes de declarar la release estable.
