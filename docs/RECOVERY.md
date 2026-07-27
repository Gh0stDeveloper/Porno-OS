# Recuperación y continuidad

## Orden de recuperación

1. Usar la consola del proveedor si SSH no responde.
2. Revisar el estado de servicios y puertos.
3. Aplicar rollback de la última transacción fallida.
4. Restaurar un respaldo verificado cuando el estado local no sea recuperable.
5. Restaurar el snapshot del proveedor ante pérdida de red, sistema de archivos o acceso root.

## Rollback transaccional

Listar transacciones recientes:

```bash
sudo ls -1 /var/lib/hextunnel/transactions
```

Restaurar una transacción fallida o no confirmada:

```bash
sudo hextunnel rollback <ID>
```

Una transacción confirmada requiere una decisión explícita:

```bash
sudo hextunnel rollback <ID> --force
```

## Crear respaldo

```bash
sudo hextunnel-backup create
```

Con cifrado age:

```bash
sudo hextunnel-backup create --age-recipient '<RECIPIENT>'
```

## Verificar respaldo

```bash
sudo hextunnel-backup verify /ruta/respaldo.tar.gz
```

Para un archivo cifrado:

```bash
sudo hextunnel-backup verify /ruta/respaldo.tar.gz.age --identity /ruta/identity.txt
```

## Restaurar respaldo

La restauración requiere el hostname actual para evitar ejecuciones accidentales:

```bash
sudo hextunnel-backup restore /ruta/respaldo.tar.gz \
  --confirm-host "$(hostname)"
```

Para un respaldo cifrado:

```bash
sudo hextunnel-backup restore /ruta/respaldo.tar.gz.age \
  --identity /ruta/identity.txt \
  --confirm-host "$(hostname)"
```

Antes de extraer, la herramienta crea un respaldo preventivo del estado actual. La restauración valida rutas, bloquea ejecuciones simultáneas y reinicia únicamente servicios conocidos.

## Comprobación posterior

```bash
sudo systemctl daemon-reload
sudo systemctl --failed
sudo ss -lntup
sudo hextunnel status
sudo hextunnel doctor
```

Después debe realizarse un reinicio completo y repetir las comprobaciones.

## Datos que no deben compartirse

- `/etc/hextunnel/license.key`.
- `/etc/hextunnel/secrets.env`.
- claves privadas TLS.
- contraseñas o credenciales de cuentas.
- tokens de Telegram.
- respaldos sin cifrar.
