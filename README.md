# Hex Tunnel

Instalador transaccional y modular para administrar SSH/TLS, Xray, Hysteria v1, Hysteria 2, UDP Custom, SlowDNS, SlipStream, ZiVPN y Webmin en Debian y Ubuntu.

## Estado

- Versión: `1.0.0-rc.1`.
- Estado del componente local: release candidate con criterios de producción.
- Uso inmediato: pruebas controladas en VPS reales.
- Plataformas soportadas: Debian 12, Ubuntu 22.04 LTS y Ubuntu 24.04 LTS sobre amd64.
- Fuera de este alcance: bot de Telegram, API de licencias y servidor privado de distribución.

La ausencia temporal del bot y del servidor no impide validar el instalador, los módulos, las cuentas, el menú, el rollback, los respaldos ni la persistencia tras reinicio.

## Capacidades

- Instalación, validación y desinstalación por módulo.
- Transacciones con respaldo y rollback automático.
- Bloqueo contra operaciones administrativas simultáneas.
- Firewall y NAT reversibles.
- Gestión de cuentas y expiraciones.
- Diagnóstico sanitizado y auditoría periódica mediante systemd.
- Respaldo, verificación, cifrado opcional y restauración.
- Actualizaciones mediante manifiestos firmados y SHA-256.
- Paquetes de release reproducibles con manifiesto interno.
- Instalador original completo conservado en `legacy/install-all.sh`.

## Comandos instalados

```bash
sudo hextunnel version
sudo hextunnel preflight
sudo hextunnel status
sudo hextunnel doctor
sudo hextunnel account --help
sudo hextunnel backup --help
sudo hextunnel update check
sudo hextunnel rollback <ID>
sudo menu
```

## Prueba privada

El bootstrap de prueba exige un SHA completo de commit, aceptación explícita y un VPS limpio con snapshot. Consulta [`docs/BETA.md`](docs/BETA.md).

## Operación y recuperación

- [`docs/OPERATIONS.md`](docs/OPERATIONS.md)
- [`docs/RECOVERY.md`](docs/RECOVERY.md)
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`SECURITY.md`](SECURITY.md)

## Distribución futura

`install.sh`, cuando se usa como bootstrap público aislado, está preparado para validar una licencia HTTPS firmada y descargar después un paquete privado autorizado. El contrato se documenta en [`docs/PRIVATE_DISTRIBUTION.md`](docs/PRIVATE_DISTRIBUTION.md). Esa integración se activará cuando se desarrollen el bot y el servidor.

## Desarrollo local

```bash
sudo ./install.sh
sudo ./install.sh install ssh xray hysteria2 --no-reboot
sudo ./install.sh uninstall xray
sudo ./install.sh doctor
sudo ./install.sh rollback
sudo ./install.sh legacy
bash scripts/production-readiness.sh
bash scripts/build-release.sh dist
```

Cada operación modular crea una transacción en `/var/lib/hextunnel/transactions`, respalda archivos, firewall y estados de systemd, valida configuraciones y revierte los cambios cuando falla un paso.
