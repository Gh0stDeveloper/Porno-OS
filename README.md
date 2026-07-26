# Instructivo: Hex Tunnel Script (VPS AutoScript)

Script desarrollado y mantenido por JotchuaDevz. Instala y configura un servidor multiprotocolo completo (SSH, Xray, Hysteria, ZiVPN, UDP Custom, SlowDNS, SlipStream) sobre un VPS limpio, con panel de administración por menú.

Repositorio: https://github.com/JotchuaDevz/Porno-OS

---

## 1. Requisitos previos

### 1.1 Servidor

- VPS limpio con acceso root.
- Al menos 1 GiB de espacio libre recomendado.
- Sistema operativo soportado:
  - Debian 12 (recomendado)
  - Debian 11 (soporte legado)
  - Ubuntu 24.04 (soportado)
  - Ubuntu 22.04 (recomendado)
  - Ubuntu 20.04 (soporte legado)

Cualquier otro sistema operativo o versión no es compatible y el instalador se detendrá al detectarlo.

### 1.2 Dominio para Xray (opcional pero recomendado)

Se necesita un registro DNS tipo A apuntando la IP de tu VPS. Ejemplo:

```text
vpn.tudominio.com    A    123.45.67.89
```

Si no cuentas con un dominio, puedes dejar el campo vacío durante la instalación y el script usará la IP pública del servidor directamente. En ese caso se generará un certificado autofirmado en lugar de uno de Let's Encrypt, y los clientes deberán activar la opción `allowInsecure` en la configuración TLS.

### 1.3 Subdominio NS para SlowDNS

SlowDNS no funciona con un registro A normal. Requiere que un subdominio esté delegado como nameserver hacia tu servidor. Esto se configura con dos registros DNS:

```text
ns.tudominio.com          NS    ns-server.tudominio.com
ns-server.tudominio.com   A     123.45.67.89
```

El valor que se ingresa cuando el script solicita el nameserver de SlowDNS es el registro delegado, por ejemplo `ns.tudominio.com`.

Si no se configura este registro correctamente, SlowDNS no recibirá tráfico aunque el servicio esté instalado y ejecutándose.

### 1.4 Subdominio NS para SlipStream (opcional)

SlipStream es un túnel DNS adicional. Si se activa durante la instalación, requiere su propio subdominio con delegación NS, siguiendo el mismo esquema del punto 1.3, pero con un nombre distinto al usado para SlowDNS. Ejemplo:

```text
ss.tudominio.com          NS    ss-server.tudominio.com
ss-server.tudominio.com   A     123.45.67.89
```

El script no permite usar el mismo dominio para SlowDNS y SlipStream, ya que el enrutador interno `dnsdist` distribuye el tráfico según el dominio de destino. Si ambos coinciden, uno de los dos túneles se queda sin tráfico.

### 1.5 Credenciales de notificación de Telegram (opcional)

El token del bot y el Chat ID no se almacenan dentro de `install.sh`. En el VPS pueden configurarse en `/etc/hextunnel/secrets.env`:

```bash
install -d -m 700 /etc/hextunnel
cat > /etc/hextunnel/secrets.env <<'EOF'
HEXTUNNEL_TELEGRAM_CHAT_ID='TU_CHAT_ID'
HEXTUNNEL_TELEGRAM_BOT_TOKEN='TU_TOKEN'
EOF
chmod 600 /etc/hextunnel/secrets.env
```

También se pueden proporcionar mediante variables de entorno o indicar otro archivo con `HEXTUNNEL_SECRETS_FILE`.

---

## 2. Instalación

Existen cuatro métodos equivalentes para ejecutar el instalador. Se recomienda el método 4 porque conserva el archivo en el servidor y permite revisarlo antes de ejecutarlo.

### Opción 1

```bash
wget -qO- https://raw.githubusercontent.com/JotchuaDevz/Porno-OS/refs/heads/main/install.sh | bash
```

### Opción 2

```bash
wget -qO xfc.sh https://raw.githubusercontent.com/JotchuaDevz/Porno-OS/refs/heads/main/install.sh && bash xfc.sh
```

### Opción 3

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/JotchuaDevz/Porno-OS/refs/heads/main/install.sh)
```

### Opción 4 (recomendada)

```bash
wget -qO install.sh https://raw.githubusercontent.com/JotchuaDevz/Porno-OS/refs/heads/main/install.sh
chmod +x install.sh
./install.sh
```

Para probar la instalación sin reinicio automático al finalizar:

```bash
./install.sh --no-reboot
```

También puede usarse:

```bash
HEXTUNNEL_NO_REBOOT=1 ./install.sh
```

---

## 3. Flujo de instalación

1. Comprueba que se ejecute como root, que exista systemd y que el sistema sea compatible.
2. Advierte cuando hay menos de 1 GiB libre en la partición raíz.
3. Solicita el dominio o subdominio para Xray. Se puede dejar en blanco para usar la IP del servidor.
4. Si se ingresó un dominio, verifica que resuelva correctamente a la IP del servidor antes de continuar.
5. Emite un certificado Let's Encrypt cuando existe un dominio válido o genera uno autofirmado cuando se usa una IP.
6. Solicita el nameserver para SlowDNS.
7. Pregunta si se desea instalar SlipStream y solicita un subdominio NS diferente.
8. Solicita el valor de ofuscación y la contraseña inicial de los servicios UDP.
9. Instala y configura automáticamente:
   - SSH, Stunnel y SSLH
   - Xray-core con VLESS, VMess y Trojan
   - HAProxy para enrutamiento TLS y HTTP/2
   - Hysteria v1 y v2
   - ZiVPN
   - UDP Custom
   - SlowDNS y, si se activó, SlipStream
   - Cronjobs de expiración de cuentas
   - Verificador de servicios y limitador de sesiones SSH
10. Al finalizar reinicia el servidor, salvo que se haya utilizado `--no-reboot` o `HEXTUNNEL_NO_REBOOT=1`.

---

## 4. Protocolos y puertos instalados

| Servicio | Puerto(s) |
|---|---|
| SSH directo | 22 |
| SSH interno secundario | 299 |
| Stunnel (SSL sobre SSH) | 4443 |
| SSLH (multiplexor interno) | 666 |
| WebSocket Proxy | 10080, 25, 2082, 2086 |
| Xray VLESS/VMess/Trojan TLS | 443 |
| Xray sin TLS | 80, 8080, 8880 |
| Hysteria v1 | 36712/udp |
| Hysteria 2 | 36713/udp |
| UDP Custom | 36717/udp |
| ZiVPN | 5667 |
| Panel interno Nginx | 85 |

Xray incluye variantes sobre TCP, WebSocket, gRPC, XHTTP y HTTPUpgrade, con y sin TLS, enrutadas mediante HAProxy según el path o el ALPN de la conexión.

---

## 5. Uso posterior a la instalación

Una vez reiniciado el servidor, se administra mediante:

```bash
menu
```

Desde el menú se pueden realizar, entre otras, las siguientes acciones:

- Crear, editar y eliminar usuarios de cada protocolo.
- Obtener enlaces `vmess://`, `vless://` y `trojan://` listos para importar.
- Cambiar el dominio o IP del servidor.
- Cambiar el nameserver de SlowDNS.
- Instalar o cambiar el dominio de SlipStream.
- Iniciar, detener o reiniciar servicios individuales.
- Acceder a herramientas de configuración avanzada.

---

## 6. Desarrollo y validación

La fuente mantenible está en `src/modules/`. El archivo raíz `install.sh` se genera mediante:

```bash
python3 tools/build.py
```

Para verificar que el bundle corresponde exactamente con los módulos:

```bash
python3 tools/build.py --check
```

Antes de enviar cambios se recomienda ejecutar:

```bash
bash -n install.sh
python3 -m unittest discover -s tests -v
python3 tools/secret_scan.py
```

Consulta `docs/ARCHITECTURE.md`, `docs/MIGRATION.md`, `CONTRIBUTING.md` y `SECURITY.md` para información adicional.

---

## 7. Notas y advertencias

- El script incluye un aviso de derechos reservados de Hex Applications. La contribución y redistribución deben contar con autorización del propietario.
- Las credenciales antiguas expuestas en el historial deben rotarse; moverlas fuera de `install.sh` no invalida copias anteriores.
- Si se cambia el dominio o nameserver después de compartir enlaces, esos enlaces pueden dejar de funcionar.
- Verifica que los registros DNS A y NS estén propagados antes de solicitar certificados o activar túneles DNS.
- Prueba cambios estructurales primero en un VPS desechable, nunca directamente en un servidor de producción.

---

## 8. Soporte

Canal de Telegram: https://t.me/RequestLab_X_Canal
