# Arquitectura manual de Hex Tunnel

```text
Porno-OS/
├── install.sh
├── bin/
│   ├── hextunnel
│   ├── hextunnel-account
│   ├── hextunnel-doctor
│   ├── hextunnel-health
│   └── hextunnel-update
├── lib/
│   ├── accounts.sh
│   ├── backup.sh
│   ├── common.sh
│   ├── firewall.sh
│   ├── framework.sh
│   ├── logging.sh
│   ├── modules.sh
│   ├── rollback.sh
│   ├── secrets.sh
│   ├── systemd.sh
│   ├── update.sh
│   └── validation.sh
├── modules/
│   ├── ssh.sh
│   ├── xray.sh
│   ├── hysteria2.sh
│   ├── slowdns.sh
│   ├── slipstream.sh
│   ├── zivpn.sh
│   ├── webmin.sh
│   └── legacy-all.sh
├── templates/
│   └── xray/config.json
├── legacy/install-all.sh
└── tests/
```

## Contrato de módulos

Cada módulo define `ports`, `dependencies`, `install`, `uninstall`, `validate` y `doctor`. Las dependencias se resuelven recursivamente. Un módulo se registra como instalado solo después de completar validación y firewall.

## Transacciones

Antes de cambiar un archivo se invoca `backup_path`. Antes de reiniciar un servicio se registra su estado y se ejecuta un validador. Los cambios de firewall se capturan antes de abrir puertos. Cualquier error restaura archivos, reglas y servicios.

## Compatibilidad

`legacy/install-all.sh` conserva el flujo monolítico sanitizado para funciones aún no migradas. No es la fuente de los módulos nuevos y no requiere ejecutar herramientas Python.
