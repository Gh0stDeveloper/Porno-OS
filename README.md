# Hex Tunnel

### Modular tunnel-management tooling for Linux VPS

Hex Tunnel is a Bash-based platform for deploying, operating and updating a set of supported tunnel services on dedicated Linux servers.

## Overview

The project includes installation workflows, service configuration, diagnostics, backups, license integration and controlled updates. It supports architecture-specific profiles rather than assuming every component is compatible with every VPS.

## Technologies and services

- Bash and Linux service management.
- SSH and TLS-based networking services.
- Xray and supported proxy transports.
- Automated diagnostics, recovery and backup procedures.
- Signed authorization and private update workflows.
- Configuration profiles for supported AMD64 and ARM64 systems.

## Compatibility

The available installation profile depends on the distribution, CPU architecture, service binaries and verified dependencies. Legacy or unavailable components are disabled on platforms where they cannot be safely validated.

## Deployment

Review the repository's installer and configuration requirements before using a VPS. License validation, private binary delivery and third-party dependencies may require credentials or additional infrastructure.

## Related projects

- [Public website](https://github.com/Gh0stDeveloper/HexTunnelWeb)
- [License backend](https://github.com/Gh0stDeveloper/GhostDeveloperLicenseServer)
- [Telegram activation bot](https://github.com/Gh0stDeveloper/TeleBotGen)

---

**Hex Tunnel — modular operation and maintenance of supported tunnel services.**
