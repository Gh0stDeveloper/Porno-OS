## Objetivo

Describe el problema y el resultado esperado.

## Cambios

- [ ] El cambio está limitado a una rama de contribución.
- [ ] No se editaron secretos ni credenciales reales.
- [ ] Si se modificó `src/modules/`, se regeneró `install.sh` con `python3 tools/build.py`.

## Validación

- [ ] `python3 tools/build.py --check`
- [ ] `bash -n install.sh`
- [ ] `python3 -m unittest discover -s tests -v`
- [ ] `python3 tools/secret_scan.py`
- [ ] ShellCheck sin errores nuevos

## Riesgo y reversión

Explica qué servicios puede afectar y cómo se revierte el cambio.
