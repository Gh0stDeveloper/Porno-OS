# Changelog

## Unreleased

- Arquitectura Bash manual y modular; sin generadores Python.
- Instalador transaccional con respaldo, validación y rollback.
- Preflight de root, OS, arquitectura, RAM, disco, red y puertos.
- Firewall reversible compatible con UFW, nftables e iptables.
- Módulos SSH/TLS, Xray, Hysteria v1, Hysteria 2, UDP Custom, SlowDNS, SlipStream, ZiVPN y Webmin.
- SSLH aislado de los defaults incompatibles de Debian/Ubuntu mediante una unidad y configuración propias.
- Generación TLS compatible con hostnames largos y validación OpenSSH portable.
- HAProxy gRPC con PID dentro de su `RuntimeDirectory` de systemd.
- Hysteria 2 con usuario dedicado, TLS privado y permisos de cuenta conservados.
- Centro `hextunnel doctor` y monitor periódico sanitizado.
- Gestión centralizada de cuentas, expiración, suspensión, reanudación y auditoría.
- Actualizador por canales con manifiesto firmado y SHA-256.
- Instalador heredado sanitizado como modo de compatibilidad.
