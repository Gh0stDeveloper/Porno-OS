# Política de seguridad

No publiques tokens, Chat IDs privados, contraseñas, claves TLS, archivos de respaldo ni reportes sin sanitizar.

Las credenciales antiguas que aparecieron en el historial deben revocarse. La arquitectura actual carga secretos desde `/etc/hextunnel/secrets.env`, exige permisos `600` o `400` y genera credenciales únicas cuando están vacías.

Las actualizaciones requieren firma OpenSSL del manifiesto y SHA-256 por artefacto. Los binarios heredados sin digest se rechazan salvo autorización explícita mediante configuración.

Reporta vulnerabilidades mediante un canal privado del propietario, incluyendo versión, sistema operativo, pasos de reproducción e impacto sin adjuntar secretos reales.
