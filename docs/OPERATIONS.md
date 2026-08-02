# Operación de Hex Tunnel

Este documento cubre únicamente el instalador, los módulos VPN, el menú y las herramientas locales. El bot, la API de licencias y el servidor privado se integrarán en una fase posterior.

## Sistemas soportados

- Debian 12.
- Ubuntu 22.04 LTS.
- Ubuntu 24.04 LTS.
- Arquitectura amd64/x86_64.
- systemd obligatorio.

## Requisitos mínimos

- 1 GiB de RAM recomendado; 512 MiB es el mínimo técnico.
- 2 GiB libres recomendados en `/`.
- Acceso root.
- Consola de emergencia del proveedor.
- VPS limpio sin paneles, proxies o VPN preexistentes.

## Antes de instalar

1. Crear un snapshot del VPS.
2. Confirmar acceso por consola web.
3. Mantener abierta la sesión SSH actual.
4. Registrar puertos abiertos por el firewall del proveedor.
5. Ejecutar la verificación no destructiva del paquete beta o release candidate.

## Comandos operativos

```bash
sudo hextunnel version
sudo hextunnel preflight
sudo hextunnel status
sudo hextunnel doctor
sudo hextunnel account --help
sudo hextunnel update check
sudo hextunnel-backup create
```

## Rutina diaria

```bash
sudo systemctl --failed
sudo systemctl status hextunnel-health.timer --no-pager
sudo hextunnel status
```

## Rutina semanal

```bash
sudo hextunnel doctor
sudo hextunnel-backup create
sudo find /var/backups/hextunnel -type f -mtime +30 -delete
```

Los respaldos deben copiarse fuera del VPS. Un respaldo almacenado únicamente en el mismo servidor no protege ante pérdida del VPS.

## Actualizaciones

Las actualizaciones de producción utilizan manifiestos firmados y SHA-256. Hasta que el servidor privado esté disponible, no configure URLs de actualización públicas ficticias.

Antes de aplicar una actualización:

```bash
sudo hextunnel-backup create
sudo hextunnel update check
```

Después:

```bash
sudo systemctl --failed
sudo hextunnel doctor
```

## Reinicio controlado

```bash
sudo systemctl reboot
```

Tras volver a conectar:

```bash
sudo systemctl --failed
sudo ss -lntup
sudo hextunnel status
sudo hextunnel doctor
```

## Incidentes

1. No cerrar la consola del proveedor.
2. Guardar la salida de `sudo hextunnel doctor`.
3. Revisar `/var/log/hextunnel`.
4. Revisar `journalctl -u <servicio> --since -30min`.
5. Usar rollback solo con el ID correcto de la transacción.
6. Restaurar el snapshot si se perdió acceso o el sistema quedó inconsistente.

## Criterio de aceptación de un VPS

El VPS queda aceptado cuando completa:

- instalación sin errores;
- creación y eliminación de cuentas de prueba;
- conexiones reales desde clientes;
- reinicio completo;
- persistencia de servicios, firewall y NAT;
- `systemctl --failed` sin fallos relacionados;
- `hextunnel doctor` sin fallos;
- respaldo verificado.
