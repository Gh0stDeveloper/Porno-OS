#!/bin/bash
# GENERATED FILE: edit src/modules/*.sh and run python3 tools/build.py
# Runtime safety controls. These checks fail before the installer modifies the VPS.
HEXTUNNEL_NO_REBOOT="${HEXTUNNEL_NO_REBOOT:-0}"
for _hextunnel_arg in "$@"; do
  case "$_hextunnel_arg" in
    --no-reboot) HEXTUNNEL_NO_REBOOT=1 ;;
  esac
done
unset _hextunnel_arg

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "ERROR: Hex Tunnel debe ejecutarse como root." >&2
  exit 1
fi
if [[ ! -r /etc/os-release ]]; then
  echo "ERROR: No se pudo leer /etc/os-release." >&2
  exit 1
fi
if ! command -v systemctl >/dev/null 2>&1; then
  echo "ERROR: Este instalador requiere systemd/systemctl." >&2
  exit 1
fi

_hextunnel_free_kb="$(df -Pk / 2>/dev/null | awk 'NR==2 {print $4}')"
if [[ "$_hextunnel_free_kb" =~ ^[0-9]+$ ]] && (( _hextunnel_free_kb < 1048576 )); then
  echo "ADVERTENCIA: hay menos de 1 GiB libre en la partición raíz." >&2
fi
unset _hextunnel_free_kb
#
# Copyright (c) 2026 Hex Applications. Todos los derechos reservados.
# Uso permitido según LICENSE. Prohibida la copia, modificación o
# redistribución de este script sin autorización previa y por escrito
# de Hex Applications.
#
set -o pipefail
clear

export DEBIAN_FRONTEND=noninteractive
source /etc/os-release
LOG_FILE="/var/log/hextunnel_install.log"
: > "$LOG_FILE" 2>/dev/null || true

SUPPORT_LEVEL="unsupported"
case "$ID:$VERSION_ID" in
  ubuntu:20.04) SUPPORT_LEVEL="legacy" ;;
  ubuntu:22.04) SUPPORT_LEVEL="recommended" ;;
  ubuntu:24.04) SUPPORT_LEVEL="supported" ;;
  debian:11) SUPPORT_LEVEL="legacy" ;;
  debian:12) SUPPORT_LEVEL="supported" ;;
  *) SUPPORT_LEVEL="unsupported" ;;
esac

apt-get install figlet -y >> "$LOG_FILE" 2>&1
apt install lolcat -y >> "$LOG_FILE" 2>&1

echo "============================================================"
echo "              Instalador de Script SSH Hex Auto"
echo "        (AutoScript: SSH/Xray/Hysteria/ZiVPN/UDP Custom)"
echo "============================================================"
echo ""
echo "Sistemas Operativos Soportados:"
echo ""
echo "  ✔ Debian 12              (Recomendado)"
echo "  ✔ Debian 11              (Soporte Legado)"
echo "  ✔ Ubuntu 24.04           (Soportado)"
echo "  ✔ Ubuntu 22.04           (Recomendado)"
echo "  ✔ Ubuntu 20.04           (Soporte Legado)"
echo ""
echo "============================================================"
sleep 5

if [ "$SUPPORT_LEVEL" = "unsupported" ]; then
  echo "Este instalador solo soporta Ubuntu 20.04/22.04/24.04 y Debian 11/12."
  echo "Detectado: ${ID} ${VERSION_ID}"
  exit 1
fi

clear

ofus() {
    unset txtofus
    local str="$1" number=$(expr length "$1") c
    for ((i=1; i<=number; i++)); do
        c=$(echo "$str" | cut -b "$i")
        case "$c" in
            ".") c="*";; "*") c=".";;
            "1") c="@";; "@") c="1";;
            "2") c="?";; "?") c="2";;
            "4") c="%";; "%") c="4";;
            "-") c="K";; "K") c="-";;
        esac
        txtofus+="$c"
    done
    echo "$txtofus" | rev
}

validar_key_hextunnel() {
    local keyuser prefijo resto keyraw ip_port valuekey miip resp tmpfile
    local intentos=0 max_intentos=5
    miip="$(wget -qO- --timeout=5 ipv4.icanhazip.com)"
    [[ -z "$miip" ]] && miip="$(hostname -I | awk '{print $1}')"

    while true; do
        ((intentos++))
        [[ $intentos -gt $max_intentos ]] && {
            echo "Demasiados intentos fallidos. Instalación cancelada."
            exit 1
        }

        echo ""
        echo "============================================================"
        figlet HEX AUTO SCRIPT -c | lolcat
        echo "============================================================"
        read -r -p " KEY: " keyuser
        echo "============================================================"

        if [[ -z "$keyuser" ]]; then
            echo "No ingresaste ninguna key."
        else
            prefijo="${keyuser%%/*}"
            resto="${keyuser#*/}"

            if [[ "$prefijo" != "HexGen" || "$resto" == "$keyuser" || -z "$resto" ]]; then
                echo "Key con formato inválido."
            else
                keyraw="$(ofus "$resto")"
                ip_port="$(echo "$keyraw" | cut -d'/' -f1)" 
                valuekey="$(echo "$keyraw" | cut -d'/' -f2)"
                tmpfile="$(mktemp)"

                echo "Verificando key..."

                wget -q --timeout=10 --tries=1 -O "$tmpfile" \
                    "http://${ip_port}/${valuekey}/HexGen/${miip}"
                resp="$(tr -d '\r\n' < "$tmpfile" 2>/dev/null)"
                rm -f "$tmpfile"

                case "$resp" in
                    "HexGen")
                        echo "Key válida, continuando..."
                        sleep 4
                        break
                        ;;
                    "KEY INVALIDA!")
                        echo "Key expirada o inválida."
                        ;;
                    "KEY DE GENERADOR!"|"KEY DE HEXGEN!")
                        echo "Esta key no corresponde a este tipo de instalación."
                        ;;
                    *)
                        echo "No se pudo contactar al servidor de validación."
                        ;;
                esac
            fi
        fi

        read -r -p "¿Deseas intentar de nuevo? [s/n]: " reintentar
        [[ "$reintentar" != "s" && "$reintentar" != "S" ]] && {
            echo "Instalación cancelada."
            exit 1
        }
    done
}

validar_key_hextunnel
clear

read -p "Ingresa tu Dominio/Subdominio para Xray (o presiona enter para usar la IP): " -e -i "$(curl -4 -s --max-time 2 ipv4.icanhazip.com || hostname -I | awk '{print $1}')" DOMAIN
export DOMAIN
echo "Por Favor Espere...."

apt-get update -y >> "$LOG_FILE" 2>&1

command -v dig >> "$LOG_FILE" 2>&1 || apt-get install -y dnsutils >> "$LOG_FILE" 2>&1
command -v certbot >> "$LOG_FILE" 2>&1 || apt-get install -y certbot >> "$LOG_FILE" 2>&1

mkdir -p /etc/xray
if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    USE_LETSENCRYPT=false
    echo "Se usará un certificado autofirmado para la IP $DOMAIN."
    echo "Los clientes deberán activar 'allowInsecure' para el TLS en el puerto 443."
else
    USE_LETSENCRYPT=true
    echo "Verificando que el dominio $DOMAIN resuelva a la IP del servidor..."
    SERVER_IP=$(curl -4 -s --max-time 2 ipv4.icanhazip.com || hostname -I | awk '{print $1}')
    DOMAIN_IP=$(dig +short "$DOMAIN" @8.8.8.8 | tail -1)
    if [ "$DOMAIN_IP" != "$SERVER_IP" ]; then
        echo "ERROR: El dominio $DOMAIN no apunta a la IP $SERVER_IP."
        echo "       Crea un registro A en tu DNS y vuelve a ejecutar el script."
        exit 1
    fi
    echo "Dominio verificado. Solicitando certificado Let's Encrypt..."
    systemctl stop xray 2>/dev/null || true
    systemctl stop nginx 2>/dev/null || true
    if ! certbot certonly --standalone --non-interactive --agree-tos --email "admin@$DOMAIN" -d "$DOMAIN" >> "$LOG_FILE" 2>&1; then
        echo "ERROR: No se pudo emitir el certificado Let's Encrypt para $DOMAIN."
        exit 1
    fi
    CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    echo "letsencrypt" > /etc/xray/cert_type
fi

if [ "$USE_LETSENCRYPT" = false ]; then
    echo "Generando certificado autofirmado para la IP $DOMAIN..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout /etc/xray/xray.key \
      -out /etc/xray/xray.crt \
      -subj "/CN=${DOMAIN}/O=HexTunnel/C=US" >> "$LOG_FILE" 2>&1
    echo "selfsigned" > /etc/xray/cert_type
else
    cp "$CERT_PATH" /etc/xray/xray.crt
    cp "$KEY_PATH" /etc/xray/xray.key
fi
chmod 644 /etc/xray/xray.crt
chmod 600 /etc/xray/xray.key
mkdir -p /etc/stunnel
cat /etc/xray/xray.key /etc/xray/xray.crt > /etc/stunnel/stunnel.pem
chmod 600 /etc/stunnel/stunnel.pem
chown root:root /etc/stunnel/stunnel.pem

SSH_Port1='22'
SSH_Port2='299'

Stunnel_Port='127.0.0.1:4443'
Stunnel_Port_Num='4443' 

Squid_Port1='3128'
Squid_Port2='8000'

WsPorts=('10080' '25' '2082' '2086')  
WsPort='10080'  

MainPort='666' 

read -p "Ingresa el Nameserver de SlowDNS (o presiona enter para el predeterminado): " -e -i "ns-miami.hexapps.app" Nameserver
Serverkey='819d82813183e4be3ca1ad74387e47c0c993b81c601b2d1473a3f47731c404ae'
Serverpub='7fbd1f8aa0abfe15a7903e837f78aba39cf61d36f183bd604daa2fe4ef3b7b59'

SlowDNS_Internal_Port='5301'
read -p "¿Deseas instalar SlipStream (túnel DNS adicional)? [y/N]: " -e -i "N" _install_slipstream
if [[ "$_install_slipstream" =~ ^[Yy]$ ]]; then
    InstallSlipstream="y"
    read -p "Ingresa el dominio/nameserver para SlipStream (o presiona enter para el predeterminado): " -e -i "ns2-miami.hexapps.app" SlipstreamDomain
    while [ "$SlipstreamDomain" = "$Nameserver" ]; do
        echo -e "\n\e[1;31m✘ El dominio de Slipstream no puede ser igual al Nameserver de SlowDNS.\e[0m"
        echo -e "  dnsdist enruta por dominio; si son iguales, uno de los dos túneles queda sin tráfico."
        echo -e "  Usa un subdominio distinto (ej. ss.${Nameserver} en vez de ${Nameserver}).\n"
        read -p "Ingresa un dominio distinto para SlipStream: " -e -i "ss.$Nameserver" SlipstreamDomain
    done
else
    InstallSlipstream="n"
    SlipstreamDomain=""
    echo -e "  SlipStream omitido. Podrás instalarlo después desde el menú: Configuración Avanzada > Instalar SlipStream."
fi
SlipstreamPinnedCommit='bc772dd07d9a136dbd7553b0da575526de207847'
SlipstreamInstallDir='/opt/slipstream-rust'
Slipstream_Internal_Port='5300'
SlipstreamSocksPort='1080'
DnsdistConf='/etc/dnsdist/dnsdist.conf'

UDP_PORT=":36712"
HYST2_PORT="36713"
UDP_CUSTOM_PORT="36717"
ZIVPN_PORT="5667"
_default_obfs='HexTunnel'
_default_password='HexTunnel'

if [ -t 0 ]; then
  read -e -p "Ingresa Hysteria/ZiVPN Obfuscation (obfs) [${_default_obfs}]: " -i "${_default_obfs}" _input_obfs
  OBFS="${_input_obfs:-${_default_obfs}}"
  read -e -p "Ingresa la contraseña predeterminada para UDP [${_default_password}]: " -i "${_default_password}" _input_pass
  PASSWORD="${_input_pass:-${_default_password}}"
else
  OBFS="${OBFS:-${_default_obfs}}"
  PASSWORD="${PASSWORD:-${_default_password}}"
fi

export OBFS PASSWORD

clear
sleep 1.5
Nginx_Port='85' 
Dns_1='1.1.1.1' 
Dns_2='1.0.0.1'

MyVPS_Time='Africa/Accra'

# Telegram notification credentials are loaded from environment variables or
# a local secrets file. config/secrets.env is intentionally ignored by Git.
HEXTUNNEL_SECRETS_FILE="${HEXTUNNEL_SECRETS_FILE:-/etc/hextunnel/secrets.env}"
if [[ ! -f "$HEXTUNNEL_SECRETS_FILE" && -n "${BASH_SOURCE[0]:-}" ]]; then
  _hextunnel_source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P || true)"
  if [[ -n "$_hextunnel_source_dir" && -f "$_hextunnel_source_dir/config/secrets.env" ]]; then
    HEXTUNNEL_SECRETS_FILE="$_hextunnel_source_dir/config/secrets.env"
  fi
fi
if [[ -f "$HEXTUNNEL_SECRETS_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$HEXTUNNEL_SECRETS_FILE"
fi
My_Chat_ID="${HEXTUNNEL_TELEGRAM_CHAT_ID:-}"
My_Bot_Key="${HEXTUNNEL_TELEGRAM_BOT_TOKEN:-}"
unset _hextunnel_source_dir

function ip_address(){
  local IP="$( ip addr | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | egrep -v "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." | head -n 1 )"
  [ -z "${IP}" ] && IP="$( wget -qO- -t1 -T2 ipv4.icanhazip.com )"
  [ -z "${IP}" ] && IP="$( wget -qO- -t1 -T2 ipinfo.io/ip )"
  [ ! -z "${IP}" ] && echo "${IP}" || echo
} 
IPADDR="$(ip_address)"

red='\e[1;31m'; green='\e[0;32m'; NC='\e[0m'

echo "  -> Actualizando el sistema (apt upgrade)..."
apt-get update -y && apt-get upgrade -y --with-new-pkgs

systemctl stop systemd-resolved 2>/dev/null
systemctl disable systemd-resolved 2>/dev/null

SSH_SERVICE="ssh"; STUNNEL_SERVICE="stunnel4"; SQUID_SERVICE="squid"; SSLH_SERVICE="sslh"; NGINX_SERVICE="nginx"; SFTP_SUBSYSTEM="internal-sftp"

mkdir -p /etc/stunnel /etc/nginx/conf.d /etc/deekayvpn /var/run/sslh /etc/xray
echo "$DOMAIN" > /etc/deekayvpn/domain.txt
echo "$SlipstreamDomain" > /etc/deekayvpn/slipstream_domain.txt
ssh-keygen -A >/dev/null 2>&1 || true

command -v ss >/dev/null 2>&1 || apt-get install -y iproute2
command -v netfilter-persistent >/dev/null 2>&1 || apt-get install -y netfilter-persistent iptables-persistent
command -v jq >/dev/null 2>&1 || apt-get install -y jq
command -v curl >/dev/null 2>&1 || apt-get install -y curl

if ! systemctl list-unit-files | grep -q "^${STUNNEL_SERVICE}\.service"; then
  if systemctl list-unit-files | grep -q "^stunnel\.service"; then STUNNEL_SERVICE="stunnel"; fi
fi
if ! systemctl list-unit-files | grep -q "^${SQUID_SERVICE}\.service"; then
  if systemctl list-unit-files | grep -q "^squid3\.service"; then SQUID_SERVICE="squid3"; fi
fi

apt-get update -y

PACKAGE_LIST=(
  neofetch sslh dnsutils stunnel4 squid nano sudo wget unzip tar zip gzip
  iptables iptables-persistent netfilter-persistent bc cron dos2unix whois screen ruby
  apt-transport-https software-properties-common gnupg2 ca-certificates curl net-tools
  nginx haproxy certbot jq figlet git gcc make build-essential perl expect libdbi-perl vnstat socat
  libnet-ssleay-perl libauthen-pam-perl libio-pty-perl apt-show-versions openssh-server rsyslog lsof procps
  cmake pkg-config libssl-dev dante-server dnsdist
)

AVAILABLE_PACKAGES=()
UNAVAILABLE_PACKAGES=()
for pkg in "${PACKAGE_LIST[@]}"; do
  if apt-cache show "$pkg" >/dev/null 2>&1; then
    AVAILABLE_PACKAGES+=("$pkg")
  else
    UNAVAILABLE_PACKAGES+=("$pkg")
  fi
done

if [[ ${#UNAVAILABLE_PACKAGES[@]} -gt 0 ]]; then
  echo "⚠️  Paquetes no disponibles en este repo (no se instalaran): ${UNAVAILABLE_PACKAGES[*]}"
fi

SSH_CLIENT_IP="$(echo "${SSH_CONNECTION:-}" | awk '{print $1}')"
if [[ "$SSH_CLIENT_IP" == *:* ]]; then
    echo "Tu sesion SSH actual usa IPv6 ($SSH_CLIENT_IP) - se omite deshabilitar IPv6 para no cortar la conexion."
else
    echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 && sysctl -w net.ipv6.conf.default.disable_ipv6=1
fi
rm -f /etc/resolv.conf
printf 'nameserver %s\nnameserver %s\n' "$Dns_1" "$Dns_2" > /etc/resolv.conf
ln -fs /usr/share/zoneinfo/$MyVPS_Time /etc/localtime

