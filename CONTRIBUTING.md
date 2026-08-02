# Contribución

Trabaja en una rama del fork y conserva el aviso de copyright. La licencia del propietario requiere autorización para modificar o redistribuir.

La fuente mantenible es Bash en `lib/`, `modules/`, `bin/` y `templates/`. No añadas generadores Python para construir el instalador.

Antes de enviar cambios:

```bash
bash tests/integration/test-syntax.sh
bash tests/unit/test-core.sh
bash tests/unit/test-module-contract.sh
bash tests/security/test-current-tree.sh
find . -type f -name '*.sh' -not -path './legacy/*' -print0 | xargs -0 shellcheck --severity=error
```

Los cambios de configuración deben usar respaldo, validación previa al reinicio y rollback. No desinstales el firewall ni incrustes credenciales.
