# Política de seguridad

## Versiones soportadas

La rama `main` y la última versión publicada reciben correcciones de seguridad. Las ramas de contribución son de evaluación y no deben desplegarse en producción sin revisión del mantenedor.

## Reportar una vulnerabilidad

No abras un issue público cuando el reporte incluya credenciales, bypass de autenticación, ejecución remota, exposición de usuarios, claves privadas o instrucciones que permitan comprometer un VPS.

Usa, en este orden:

1. **Private vulnerability reporting** de GitHub, mediante **Security → Report a vulnerability**, cuando esté habilitado.
2. El canal privado de Telegram acordado con el mantenedor. El canal público indicado en el README debe utilizarse únicamente para solicitar un contacto privado, sin publicar los detalles técnicos.

Incluye la versión o commit afectado, sistema operativo, pasos mínimos de reproducción, impacto estimado y una corrección propuesta cuando sea posible. Sanitiza IP, dominios, usuarios, tokens y claves.

El equipo intentará confirmar la recepción dentro de 72 horas. La publicación coordinada se realizará después de disponer de una corrección y de que los operadores tengan tiempo razonable para actualizar.

## Gestión de secretos

- No se aceptan credenciales reales en commits, issues, logs, artefactos ni pull requests.
- Los secretos locales se guardan en `config/secrets.env` o `/etc/hextunnel/secrets.env`, con permisos `600`.
- En CI se utilizan GitHub Actions Secrets.
- Una credencial expuesta debe revocarse y rotarse; eliminarla del último commit no elimina su historial.

## Alcance de endurecimiento

Los cambios de SSH, firewall, certificados, DNS, systemd y servicios de túnel deben incluir validación previa y procedimiento de reversión. Un cambio que pueda cortar la sesión SSH debe probarse primero en un VPS desechable.
