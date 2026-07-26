# Arquitectura modular

## Objetivo

Separar el mantenimiento del instalador sin romper el archivo autónomo utilizado por los comandos de instalación existentes.

## Flujo

```text
src/modules/*.sh
        │
        ├── src/manifest.txt define el orden
        │
        ▼
 tools/build.py
        │
        ▼
 install.sh (artefacto autónomo generado)
```

Los módulos se concatenan sin alterar su contenido ni el orden de ejecución. Esto conserva el comportamiento del instalador monolítico, pero permite revisar cada sección por separado.

## Migración inicial

`tools/bootstrap_modularize.py` realiza una migración conservadora:

1. Valida el `install.sh` original con `bash -n`.
2. Guarda una copia local en `.migration-backup/install.sh` con permisos `600`.
3. Extrae el Chat ID y token de Telegram hacia `config/secrets.env`, ignorado por Git.
4. Sustituye las asignaciones incrustadas por carga desde variables de entorno o archivo local.
5. Añade comprobaciones previas de root, `/etc/os-release`, systemd y espacio disponible.
6. Añade el control `--no-reboot`/`HEXTUNNEL_NO_REBOOT=1` para evitar reinicios automáticos.
7. Busca límites de fragmento que sean sintácticamente válidos para Bash.
8. Genera `src/modules/` y `src/manifest.txt`.
9. Reconstruye `install.sh` y verifica que coincida exactamente con los módulos.
10. Ejecuta el escaneo local de secretos.

## Secretos

Orden de carga:

1. Variables `HEXTUNNEL_TELEGRAM_CHAT_ID` y `HEXTUNNEL_TELEGRAM_BOT_TOKEN` ya exportadas.
2. Archivo indicado por `HEXTUNNEL_SECRETS_FILE`.
3. `/etc/hextunnel/secrets.env`.
4. `config/secrets.env` cuando el instalador se ejecuta desde un clon local.

El archivo `config/secrets.env` no debe subirse al repositorio.

## Compatibilidad

El archivo raíz continúa siendo ejecutable como script autónomo. La modularidad se aplica al desarrollo y revisión; el usuario final recibe el bundle generado.
