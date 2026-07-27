# Hex Tunnel 1.0.0-beta.1

Esta beta permite probar el instalador original completo antes de desplegar el bot, la API de licencias y el servidor de distribución privada.

## Alcance

La beta está destinada exclusivamente a VPS de prueba administrados por el propietario del proyecto. No debe entregarse todavía como edición comercial ni instalarse en servidores con datos o servicios importantes.

Sistemas objetivo:

- Debian 12.
- Ubuntu 22.04 LTS.
- Ubuntu 24.04 LTS.
- Arquitectura `x86_64`/`amd64`.

## Separación respecto de producción

- `install.sh` conserva el flujo de producción: licencia HTTPS firmada y descarga privada.
- `beta-install.sh` es un bootstrap separado que descarga un commit exacto desde GitHub.
- La beta no acepta nombres de rama; exige el SHA completo de 40 caracteres.
- El usuario debe aceptar explícitamente el riesgo mediante `HEXTUNNEL_BETA_ACK=ACEPTO_BETA_PRIVADA`.
- El instalador original se ejecuta automáticamente y abre `/usr/local/bin/menu` al terminar.
- La consulta HTTP de licencia heredada se omite únicamente dentro del wrapper beta temporal.

## Preparación del VPS

Antes de instalar:

1. Crear un snapshot desde el panel del proveedor.
2. Usar un VPS limpio sin paneles web, Apache, Nginx, VPN ni proxies preinstalados.
3. Confirmar acceso root por consola del proveedor además de SSH.
4. Comprobar que los puertos necesarios no estén bloqueados por un firewall externo.

## Instalación

Reemplaza `<COMMIT_SHA_BETA>` por el commit exacto anunciado para la beta:

```bash
BETA_SHA="<COMMIT_SHA_BETA>"
curl -fsSL "https://raw.githubusercontent.com/Gh0stDeveloper/Porno-OS/${BETA_SHA}/beta-install.sh" -o /tmp/hextunnel-beta-install.sh
chmod 700 /tmp/hextunnel-beta-install.sh
sudo HEXTUNNEL_BETA_ACK="ACEPTO_BETA_PRIVADA" \
  HEXTUNNEL_BETA_REF="$BETA_SHA" \
  /tmp/hextunnel-beta-install.sh
```

No uses una rama como `main` o `feat/transactional-architecture` en `HEXTUNNEL_BETA_REF`. El bootstrap la rechazará.

## Verificación posterior

Después de instalar y antes de crear usuarios:

```bash
sudo systemctl --failed
sudo ss -lntup
sudo hextunnel doctor
sudo menu
```

También debe verificarse:

- SSH accesible en 22 y 299.
- Xray escuchando en sus puertos configurados.
- Hysteria, Hysteria 2, UDP Custom y ZiVPN activos.
- SlowDNS, SlipStream y DNSdist sin conflictos.
- Stunnel, SSLH, Fail2ban, HAProxy y Dante activos cuando corresponda.
- El menú permite crear, renovar, suspender y eliminar una cuenta de prueba.

## Prueba de reinicio

```bash
sudo reboot
```

Después del reinicio:

```bash
sudo systemctl --failed
sudo hextunnel doctor
sudo menu
```

No se debe considerar válido un VPS beta si pierde SSH, puertos, reglas NAT o servicios después de reiniciar.

## Estado instalado

El wrapper crea:

```text
/etc/hextunnel/beta-state.env
```

Contiene el canal, versión beta, commit exacto e instante de instalación. El archivo utiliza permisos `600`.

## Reporte de errores

Para cada incidencia se debe registrar:

- proveedor del VPS;
- sistema operativo y versión;
- commit beta;
- comando ejecutado;
- paso exacto que falló;
- salida de `systemctl --failed`;
- reporte generado por `sudo hextunnel doctor`;
- si el fallo ocurre antes o después de reiniciar.

Nunca deben compartirse keys privadas, contraseñas de usuarios, tokens de Telegram ni archivos de claves TLS.

## Salida de la beta

La beta termina cuando estén validados, como mínimo, tres VPS limpios:

- uno con Debian 12;
- uno con Ubuntu 22.04;
- uno con Ubuntu 24.04.

Cada VPS debe completar instalación, creación de cuentas, conexiones reales, reinicio, persistencia, actualización y desinstalación o restauración del snapshot.
