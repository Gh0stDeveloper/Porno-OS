# Hex Tunnel 1.0.0-rc.1 — prueba privada

Esta prueba permite validar en VPS reales el componente local completo antes de desplegar el bot, la API de licencias y el servidor privado.

## Alcance

El código local se trata como release candidate con criterios de producción. La distribución mediante GitHub sigue siendo temporal y debe utilizarse únicamente en VPS de prueba administrados por el propietario.

Plataformas soportadas:

- Debian 12.
- Ubuntu 22.04 LTS.
- Ubuntu 24.04 LTS.
- Arquitectura `x86_64`/`amd64`.

## Separación respecto de la distribución final

- `install.sh` conserva el flujo futuro de producción: licencia HTTPS firmada y descarga privada.
- `beta-install.sh` es un canal de pruebas separado que descarga un commit exacto desde GitHub.
- No se aceptan nombres de rama; se exige el SHA completo de 40 caracteres.
- El usuario debe aceptar explícitamente el riesgo mediante `HEXTUNNEL_BETA_ACK=ACEPTO_BETA_PRIVADA`.
- El instalador original se ejecuta automáticamente y abre `/usr/local/bin/menu` al terminar.
- La consulta HTTP de licencia heredada se omite únicamente dentro del wrapper temporal.
- La versión instalada se toma del archivo `VERSION` del paquete.

## Preparación del VPS

1. Crear un snapshot desde el panel del proveedor.
2. Usar un VPS limpio sin Apache, Nginx, paneles, VPN ni proxies preinstalados.
3. Confirmar acceso root por consola del proveedor además de SSH.
4. Mantener abierta la sesión SSH actual.
5. Comprobar que los puertos necesarios no estén bloqueados externamente.

## Instalación

Reemplaza `<COMMIT_SHA_RC>` por el commit exacto anunciado:

```bash
BETA_SHA="<COMMIT_SHA_RC>"
curl -fsSL "https://raw.githubusercontent.com/Gh0stDeveloper/Porno-OS/${BETA_SHA}/beta-install.sh" -o /tmp/hextunnel-beta-install.sh
chmod 700 /tmp/hextunnel-beta-install.sh
sudo HEXTUNNEL_BETA_ACK="ACEPTO_BETA_PRIVADA" \
  HEXTUNNEL_BETA_REF="$BETA_SHA" \
  /tmp/hextunnel-beta-install.sh
```

No uses `main` ni `feat/transactional-architecture` en `HEXTUNNEL_BETA_REF`.

## Verificación no destructiva

```bash
sudo HEXTUNNEL_BETA_ACK="ACEPTO_BETA_PRIVADA" \
  HEXTUNNEL_BETA_REF="$BETA_SHA" \
  HEXTUNNEL_BETA_VERIFY_ONLY=1 \
  /tmp/hextunnel-beta-install.sh
```

Este modo descarga, inspecciona y elimina el paquete temporal sin modificar servicios.

## Verificación posterior

```bash
sudo hextunnel version
sudo hextunnel preflight
sudo systemctl --failed
sudo ss -lntup
sudo hextunnel status
sudo hextunnel doctor
sudo hextunnel backup create
sudo menu
```

Debe comprobarse:

- SSH accesible en 22 y 299.
- Xray escuchando en sus puertos configurados.
- Hysteria, Hysteria 2, UDP Custom y ZiVPN activos.
- SlowDNS, SlipStream y DNSdist sin conflictos.
- Stunnel, SSLH, Fail2ban, HAProxy y Dante activos cuando corresponda.
- Creación, renovación, suspensión y eliminación de una cuenta de prueba.
- Respaldo creado y validado.

## Prueba de reinicio

```bash
sudo reboot
```

Después:

```bash
sudo systemctl --failed
sudo hextunnel status
sudo hextunnel doctor
sudo menu
```

No se acepta un VPS si pierde SSH, puertos, NAT, firewall o servicios después del reinicio.

## Estado instalado

El wrapper crea `/etc/hextunnel/beta-state.env` con canal `release-candidate`, versión, commit exacto e instante de instalación. El archivo utiliza permisos `600`.

## Reporte de errores

Registrar:

- proveedor del VPS;
- sistema operativo y versión;
- commit exacto;
- comando ejecutado;
- paso que falló;
- salida de `systemctl --failed`;
- reporte de `sudo hextunnel doctor`;
- comportamiento antes y después del reinicio.

Nunca deben compartirse contraseñas, tokens, claves privadas TLS ni respaldos sin cifrar.

## Salida de la prueba privada

Se requieren como mínimo tres VPS limpios:

- Debian 12;
- Ubuntu 22.04;
- Ubuntu 24.04.

Cada VPS debe completar instalación, cuentas, conexiones reales, reinicio, persistencia, respaldo, restauración controlada y desinstalación o restauración del snapshot.
