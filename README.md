# Hex Tunnel Script

Arquitectura transaccional y modular para instalar y administrar SSH, Xray, Hysteria, Hysteria 2, UDP Custom, SlowDNS, SlipStream, ZiVPN y Webmin en Debian/Ubuntu.

El instalador original completo se conserva en `legacy/install-all.sh`. El nuevo sistema no depende de scripts Python: `install.sh` carga bibliotecas y módulos Bash mantenidos manualmente.

## Estado

- Canal actual: `1.0.0-beta.1`.
- Objetivo: beta privada en VPS limpios administrados por el propietario.
- Sistemas validados por CI: Debian 12, Ubuntu 22.04 LTS y Ubuntu 24.04 LTS.
- Producción: pendiente del bot, API de licencias y servidor privado de distribución.

## Beta privada

La beta usa un bootstrap separado, exige un commit exacto y ejecuta automáticamente el instalador original completo. No modifica ni debilita el flujo protegido de `install.sh`.

Consulta [`docs/BETA.md`](docs/BETA.md) antes de instalar. Debe utilizarse únicamente en VPS de prueba con snapshot y acceso a la consola del proveedor.

## Distribución de producción

Cuando se ejecuta como archivo público aislado, `install.sh` valida primero la licencia mediante HTTPS y firma criptográfica. Solo después de autorizar descarga el paquete privado y ejecuta el instalador completo. Este flujo requiere que el servidor de licencias y distribución esté desplegado.

Consulta [`docs/PRIVATE_DISTRIBUTION.md`](docs/PRIVATE_DISTRIBUTION.md).

## Uso del árbol completo

```bash
sudo ./install.sh
sudo ./install.sh install ssh xray hysteria2 --no-reboot
sudo ./install.sh uninstall xray
sudo ./install.sh doctor
sudo ./install.sh rollback
sudo ./install.sh legacy
```

Las credenciales de Telegram se cargan desde `/etc/hextunnel/secrets.env` o mediante `HEXTUNNEL_TELEGRAM_CHAT_ID` y `HEXTUNNEL_TELEGRAM_BOT_TOKEN`. Las variables siguen disponibles para todas las funciones del sistema, pero los valores reales no se publican.

Cada operación modular crea una transacción en `/var/lib/hextunnel/transactions`, respalda archivos, firewall y estados de systemd, valida configuraciones y revierte los cambios cuando falla un paso.
