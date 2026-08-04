#!/usr/bin/env bash
[[ -n "${HEXTUNNEL_ACCOUNT_DISPLAY_LOADED:-}" ]] && return 0
HEXTUNNEL_ACCOUNT_DISPLAY_LOADED=1

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  ACCOUNT_CYAN=$'\033[1;36m'
  ACCOUNT_GREEN=$'\033[1;32m'
  ACCOUNT_YELLOW=$'\033[1;33m'
  ACCOUNT_WHITE=$'\033[1;37m'
  ACCOUNT_GRAY=$'\033[38;5;245m'
  ACCOUNT_RESET=$'\033[0m'
else
  ACCOUNT_CYAN=''
  ACCOUNT_GREEN=''
  ACCOUNT_YELLOW=''
  ACCOUNT_WHITE=''
  ACCOUNT_GRAY=''
  ACCOUNT_RESET=''
fi

account_is_public_ipv4() {
  local value="$1" a b c d
  [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r a b c d <<< "$value"
  ((10#$a <= 255 && 10#$b <= 255 && 10#$c <= 255 && 10#$d <= 255)) || return 1

  ((10#$a == 0 || 10#$a == 10 || 10#$a == 127 || 10#$a >= 224)) && return 1
  ((10#$a == 100 && 10#$b >= 64 && 10#$b <= 127)) && return 1
  ((10#$a == 169 && 10#$b == 254)) && return 1
  ((10#$a == 172 && 10#$b >= 16 && 10#$b <= 31)) && return 1
  ((10#$a == 192 && 10#$b == 168)) && return 1
  return 0
}

account_license_public_ipv4() {
  local value=''
  if [[ -r /etc/hextunnel/license-state.env ]]; then
    value="$(awk -F= '$1=="HEXTUNNEL_LICENSE_SUBJECT" {sub(/^[^=]*=/,""); gsub(/^[\047\042]|[\047\042]$/,""); print; exit}' /etc/hextunnel/license-state.env 2>/dev/null)"
  fi
  account_is_public_ipv4 "$value" && printf '%s' "$value"
}

account_public_ipv4() {
  local value endpoint

  value="${HEXTUNNEL_PUBLIC_IPV4:-}"
  account_is_public_ipv4 "$value" && { printf '%s' "$value"; return 0; }

  value="$(account_license_public_ipv4 2>/dev/null || true)"
  account_is_public_ipv4 "$value" && { printf '%s' "$value"; return 0; }

  for endpoint in \
    https://api.ipify.org \
    https://ifconfig.me/ip \
    https://icanhazip.com; do
    value="$(curl -4fsS --connect-timeout 3 --max-time 5 "$endpoint" 2>/dev/null | tr -d '\r\n[:space:]' || true)"
    account_is_public_ipv4 "$value" && { printf '%s' "$value"; return 0; }
  done

  die "No se pudo determinar una IPv4 pública. Define HEXTUNNEL_PUBLIC_IPV4 en /etc/hextunnel/hextunnel.env."
}

account_configured_domain() {
  local value="${HEXTUNNEL_DOMAIN:-}"
  [[ -n "$value" ]] || value="$(awk -F= '$1=="HEXTUNNEL_DOMAIN" {sub(/^[^=]*=/,""); gsub(/^[\047\042]|[\047\042]$/,""); print; exit}' /etc/hextunnel/hextunnel.env 2>/dev/null)"
  [[ -n "$value" ]] || value="$(cat /etc/deekayvpn/domain.txt 2>/dev/null || true)"
  printf '%s' "$value"
}

account_public_host() {
  local value
  value="$(account_configured_domain)"
  [[ -n "$value" ]] || value="$(account_public_ipv4)"
  printf '%s' "$value"
}

account_uri_encode() {
  jq -rn --arg value "$1" '$value|@uri'
}

account_base64_compact() {
  if base64 --help 2>&1 | grep -q -- '-w'; then
    base64 -w0
  else
    base64 | tr -d '\n'
  fi
}

account_vmess_link() {
  local name="$1" host="$2" id="$3" network="$4" path="$5" service_name="${6:-}"
  jq -cn \
    --arg ps "$name" --arg add "$host" --arg id "$id" --arg net "$network" \
    --arg path "$path" --arg service "$service_name" '
      {
        v:"2",ps:$ps,add:$add,port:"443",id:$id,aid:"0",scy:"auto",
        net:$net,type:"none",host:$add,path:(if $net=="grpc" then $service else $path end),
        tls:"tls",sni:$add,alpn:(if $net=="grpc" then "h2" else "" end)
      }
    ' | account_base64_compact | sed 's/^/vmess:\/\//'
}

account_display_header() {
  local protocol="$1"
  printf '\n%s╔══════════════════════════════════════════════════════════════╗%s\n' "$ACCOUNT_CYAN" "$ACCOUNT_RESET"
  printf '%s║%s %sCREDENCIAL %s CREADA / CONSULTADA%s\n' \
    "$ACCOUNT_CYAN" "$ACCOUNT_RESET" "$ACCOUNT_WHITE" "${protocol^^}" "$ACCOUNT_RESET"
  printf '%s╚══════════════════════════════════════════════════════════════╝%s\n' "$ACCOUNT_CYAN" "$ACCOUNT_RESET"
}

account_display_section() {
  printf '\n%s── %s ─────────────────────────────────────────────────────%s\n' \
    "$ACCOUNT_CYAN" "$1" "$ACCOUNT_RESET"
}

account_display_field() {
  printf '%s%-20s%s %s\n' "$ACCOUNT_GRAY" "$1:" "$ACCOUNT_RESET" "$2"
}

account_display_compact() {
  printf '%s%-20s%s %s%s%s\n' \
    "$ACCOUNT_YELLOW" "$1:" "$ACCOUNT_RESET" "$ACCOUNT_GREEN" "$2" "$ACCOUNT_RESET"
}

account_show() {
  local protocol="$1" username="$2" row expires status max_sessions quota speed
  local host public_ip secret encoded obfs
  require_root
  accounts_init
  account_validate_protocol "$protocol"
  account_validate_username "$username"
  row="$(account_get_row "$protocol" "$username")"
  [[ -n "$row" ]] || die "Cuenta no registrada."
  IFS=$'\t' read -r _ _ expires status max_sessions quota speed <<< "$row"
  account_load_credential "$protocol" "$username"
  secret="$ACCOUNT_SECRET"
  public_ip="$(account_public_ipv4)"
  host="$(account_public_host)"
  encoded="$(account_uri_encode "$secret")"

  account_display_header "$protocol"
  account_display_section 'DATOS DE LA CUENTA'
  account_display_field 'Usuario' "$username"
  account_display_field 'Protocolo' "$protocol"
  account_display_field 'Estado' "$status"
  account_display_field 'Expira' "$expires"
  account_display_field 'IPv4 pública' "$public_ip"
  if [[ "$host" != "$public_ip" ]]; then
    account_display_field 'Host/SNI' "$host"
  fi

  case "$protocol" in
    ssh)
      account_display_field 'Contraseña' "$secret"
      account_display_field 'Puertos SSH' '22, 299'
      account_display_field 'TLS/SSL' '443, 4443'
      account_display_field 'WebSocket' '25, 2082, 2086, 10080'
      account_display_field 'Máximo de sesiones' "$max_sessions"
      account_display_field 'Firewall local' 'reglas TCP administradas habilitadas'

      account_display_section 'CONEXIONES RÁPIDAS'
      account_display_compact 'SSH' "$public_ip:22@$username:$secret"
      account_display_compact 'SSH alternativo' "$public_ip:299@$username:$secret"
      account_display_compact 'SSH + SSL' "$public_ip:443@$username:$secret"
      account_display_compact 'SSH + SSL alt.' "$public_ip:4443@$username:$secret"
      account_display_compact 'WebSocket 25' "$public_ip:25@$username:$secret"
      account_display_compact 'WebSocket 2082' "$public_ip:2082@$username:$secret"
      account_display_compact 'WebSocket 2086' "$public_ip:2086@$username:$secret"
      account_display_compact 'WebSocket 10080' "$public_ip:10080@$username:$secret"
      ;;
    vless)
      account_display_section 'VLESS TLS WEBSOCKET'
      printf 'vless://%s@%s:443?encryption=none&security=tls&sni=%s&allowInsecure=1&type=ws&host=%s&path=%%2Fvless#%s-VLESS-WS\n' "$secret" "$host" "$host" "$host" "$username"
      account_display_section 'VLESS TLS XHTTP'
      printf 'vless://%s@%s:443?encryption=none&security=tls&sni=%s&allowInsecure=1&type=xhttp&host=%s&path=%%2Fxhttp&mode=auto#%s-VLESS-XHTTP\n' "$secret" "$host" "$host" "$host" "$username"
      account_display_section 'VLESS TLS HTTPUPGRADE'
      printf 'vless://%s@%s:443?encryption=none&security=tls&sni=%s&allowInsecure=1&type=httpupgrade&host=%s&path=%%2Fhttpupgrade#%s-VLESS-HUP\n' "$secret" "$host" "$host" "$host" "$username"
      account_display_section 'VLESS TLS GRPC'
      printf 'vless://%s@%s:443?encryption=none&security=tls&sni=%s&allowInsecure=1&type=grpc&serviceName=grpc-svc&alpn=h2#%s-VLESS-GRPC\n' "$secret" "$host" "$host" "$username"
      account_display_section 'VLESS SIN TLS WEBSOCKET'
      printf 'vless://%s@%s:80?encryption=none&security=none&type=ws&host=%s&path=%%2Fvless#%s-VLESS-NTLS\n' "$secret" "$public_ip" "$host" "$username"
      ;;
    vmess)
      account_display_section 'VMESS TLS WEBSOCKET'
      account_vmess_link "$username-VMESS-WS" "$host" "$secret" ws /vmess
      printf '\n'
      account_display_section 'VMESS TLS GRPC'
      account_vmess_link "$username-VMESS-GRPC" "$host" "$secret" grpc '' vmess-grpc-svc
      printf '\n'
      ;;
    trojan)
      account_display_section 'TROJAN TLS WEBSOCKET'
      printf 'trojan://%s@%s:443?security=tls&sni=%s&allowInsecure=1&type=ws&host=%s&path=%%2Ftrojan#%s-TROJAN-WS\n' "$encoded" "$host" "$host" "$host" "$username"
      ;;
    hysteria)
      obfs="$(jq -r '.inbounds[]? | select(.tag=="hy1-inbound") | .obfs // empty' /etc/hysteria1/config.json 2>/dev/null | head -n1)"
      account_display_field 'Auth' "$secret"
      account_display_field 'Obfs' "${obfs:-no-configurado}"
      account_display_field 'Puerto principal' '36712/UDP'
      account_display_field 'Rango NAT' '20000-50000/UDP'
      ;;
    hysteria2)
      obfs="$(awk '/^[[:space:]]*password:/ {gsub(/^[[:space:]]*password:[[:space:]]*|[\"\047]/,""); print; exit}' /etc/hysteria2/config.yaml 2>/dev/null)"
      account_display_field 'Token' "$secret"
      account_display_field 'Puerto' '36713/UDP'
      account_display_section 'ENLACE HYSTERIA 2'
      printf 'hysteria2://%s@%s:36713?insecure=1&sni=%s&obfs=salamander&obfs-password=%s#%s-HY2\n' \
        "$encoded" "$host" "$host" "$(account_uri_encode "${obfs:-}")" "$username"
      ;;
    zivpn)
      obfs="$(jq -r '.obfs // .obfuscation // "zivpn"' /etc/zivpn/config.json 2>/dev/null || printf zivpn)"
      account_display_field 'Contraseña' "$secret"
      account_display_field 'Obfs' "$obfs"
      account_display_field 'Puerto interno' '5667/UDP'
      account_display_field 'Rango público' '6000-19999/UDP'
      ;;
  esac

  printf '\n%sImportante:%s en Oracle Cloud también debes permitir estos puertos en la Security List o NSG de la VCN.\n' \
    "$ACCOUNT_YELLOW" "$ACCOUNT_RESET"
}
