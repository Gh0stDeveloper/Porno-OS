# Aplicar la migración modular

Ejecuta este proceso únicamente en una rama separada y con el árbol de trabajo limpio.

```bash
git switch -c contrib/modular-foundation
python3 tools/bootstrap_modularize.py
python3 tools/build.py --check
bash -n install.sh
python3 -m unittest discover -s tests -v
python3 tools/secret_scan.py
git status --short
```

Revisa `config/secrets.env` localmente. El archivo conserva los valores encontrados durante la migración, tiene permisos `600` y no debe aparecer en `git status`.

Para instalar sin que el script reinicie automáticamente el VPS:

```bash
bash install.sh --no-reboot
```

También puede utilizarse:

```bash
HEXTUNNEL_NO_REBOOT=1 bash install.sh
```

Antes de publicar el pull request, revoca cualquier token que haya estado visible en el historial público. Posteriormente configura los valores en `/etc/hextunnel/secrets.env` o como GitHub Actions Secrets.
