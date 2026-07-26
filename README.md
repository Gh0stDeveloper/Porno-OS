# Hex Tunnel Script

Arquitectura transaccional y modular para instalar y administrar SSH, Xray, Hysteria 2, SlowDNS, SlipStream, ZiVPN y Webmin en Debian/Ubuntu.

El instalador original completo se conserva en `legacy/install-all.sh`. El nuevo sistema no depende de scripts Python: `install.sh` carga bibliotecas y módulos Bash mantenidos manualmente.

## Uso

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
