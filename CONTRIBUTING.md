# Contribuir a Hex Tunnel

## Flujo de ramas

No realices commits directamente en `main`. Crea una rama con un alcance único:

- `contrib/<tema>` para contribuciones amplias.
- `fix/<problema>` para correcciones.
- `feat/<funcion>` para nuevas funciones.
- `security/<tema>` para endurecimiento coordinado.

Los pull requests deben ser pequeños, revisables y reversibles. Los cambios que afecten varios protocolos deben dividirse cuando sea posible.

## Arquitectura del instalador

`src/modules/*.sh` es la fuente editable. `install.sh` es un artefacto generado y se mantiene para conservar los métodos de instalación mediante `curl` o `wget`.

Después de modificar un módulo:

```bash
python3 tools/build.py
python3 tools/build.py --check
bash -n install.sh
python3 -m unittest discover -s tests -v
python3 tools/secret_scan.py
```

No edites manualmente el archivo generado `install.sh`, porque CI rechazará diferencias con `src/manifest.txt`.

## Secretos

Copia `config/secrets.env.example` como `config/secrets.env`. Este último está ignorado por Git y debe tener permisos `600`.

Nunca publiques tokens de Telegram, contraseñas UDP, claves privadas, credenciales de panel, datos de usuarios ni enlaces de acceso activos.

## Requisitos para un pull request

- Explicar el problema, causa y solución.
- Indicar sistemas operativos y arquitecturas probadas.
- Incluir procedimiento de reversión.
- Evitar cambios de formato no relacionados.
- Añadir o actualizar pruebas.
- No desactivar verificaciones de seguridad para hacer pasar CI.
