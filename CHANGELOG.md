# Changelog

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

- Integración futura con bot, API de licencias y servidor privado de distribución.
