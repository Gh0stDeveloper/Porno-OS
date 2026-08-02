# Hex Tunnel

Hex Tunnel es una plataforma Bash modular y transaccional para desplegar, operar y actualizar servicios de túnel en VPS dedicadas.

## Estado

- Versión: `1.0.0-rc.2`.
- Estado: release candidate privada.
- Plataformas de producción: Debian 12, Ubuntu 22.04 LTS y Ubuntu 24.04 LTS.
- Arquitecturas: `amd64/x86_64` y `arm64/aarch64`.
- Distribución: bootstrap público con licencia, autorización firmada y descarga privada temporal.

## Perfil AMD64

La instalación comercial AMD64 conserva el instalador completo heredado saneado y después integra el framework modular, la licencia renovable, el diagnóstico, los respaldos y la actualización privada.

## Perfil ARM64

La instalación comercial detecta ARM64 automáticamente y utiliza el framework modular nativo. Incluye:

- SSH, TLS, SSLH y proxy WebSocket.
- Xray.
- Hysteria v1 mediante Sing-box ARM64.
- Hysteria 2.
- ZiVPN ARM64.
- Webmin con TLS.
- Panel `menu` específico para ARM64.
- Licencia renovable y actualización privada.

Por seguridad, UDP Custom, SlowDNS heredado, SlipStream dependiente de ese SlowDNS y `legacy-all` no se habilitan en ARM64 hasta disponer de artefactos oficiales, reproducibles y verificables. El preflight rechaza esos módulos antes de modificar el VPS.

## Capacidades

- Instalación, validación y desinstalación por módulo.
- Transacciones con respaldo y rollback automático.
- Bloqueo contra operaciones administrativas simultáneas.
- Firewall y NAT reversibles.
- Gestión de cuentas y expiraciones.
- Diagnóstico sanitizado y auditoría periódica mediante systemd.
- Respaldo, verificación, cifrado opcional y restauración.
- Actualizaciones privadas mediante autorización y paquete verificado.
- Paquetes reproducibles con manifiesto SHA-256 interno.

## Instalación comercial

El bootstrap público solicita la key, consulta la API de licencias y, cuando la autorización es válida, recibe un enlace privado temporal. La respuesta se verifica mediante RSA y el paquete mediante SHA-256 antes de ejecutar el entrypoint.

```bash
curl -fsSL https://ghostdeveloper.duckdns.org/install.sh -o /tmp/hextunnel-install.sh
sudo bash /tmp/hextunnel-install.sh install
```

## Comandos instalados

```bash
sudo menu
sudo hextunnel version
sudo hextunnel preflight
sudo hextunnel status
sudo hextunnel doctor
sudo hextunnel account --help
sudo hextunnel backup --help
sudo hextunnel rollback <ID>
sudo hextunnel-license status
sudo hextunnel-upgrade
```

## Operación y recuperación

- [`docs/OPERATIONS.md`](docs/OPERATIONS.md)
- [`docs/RECOVERY.md`](docs/RECOVERY.md)
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`docs/PRIVATE_DISTRIBUTION.md`](docs/PRIVATE_DISTRIBUTION.md)
- [`SECURITY.md`](SECURITY.md)

## Desarrollo y validación

```bash
sudo ./install.sh install ssh xray hysteria2 --no-reboot
sudo ./install.sh uninstall xray
sudo ./install.sh doctor
sudo ./install.sh rollback
bash scripts/production-readiness.sh
bash scripts/build-release.sh dist
```

Cada operación modular crea una transacción en `/var/lib/hextunnel/transactions`, respalda archivos, firewall y estados de systemd, valida configuraciones y revierte los cambios cuando falla un paso.
