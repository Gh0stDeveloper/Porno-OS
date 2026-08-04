#!/usr/bin/env bash
[[ -n "${HEXTUNNEL_ACCOUNT_DISPLAY_LOADED:-}" ]] && return 0
HEXTUNNEL_ACCOUNT_DISPLAY_LOADED=1

account_public_host() {
  local value="${HEXTUNNEL_DOMAIN:-}"
  [[ -n "$value" ]] || value="$(cat /etc/deekayvpn/domain.txt 2>/dev/null || true)"
  [[ -n "$value" ]] || value="$(primary_ipv4 2>/dev/null || true)"
  [[ -n "$value" ]] || value="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [[ -n "$value" ]] || die "No se pudo determinar el host público. Define HEXTUNNEL_DOMAIN."
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

account_show() {
  local protocol="$1" username="$2" row expires status max_sessions quota speed host secret encoded obfs
  require_root
  accounts_init
  account_validate_protocol "$protocol"
  account_validate_username "$username"
  row="$(account_get_row "$protocol" "$username")"
  [[ -n "$row" ]] || die "Cuenta no registrada."
  IFS=$'\t' read -r _ _ expires status max_sessions quota speed <<< "$row"
  account_load_credential "$protocol" "$username"
  secret="$ACCOUNT_SECRET"
  host="$(account_public_host)"
  encoded="$(account_uri_encode "$secret")"

  printf 'Usuario: %s\nProtocolo: %s\nEstado: %s\nExpira: %s\nHost: %s\n' \
    "$username" "$protocol" "$status" "$expires" "$host"

  case "$protocol" in
    ssh)
      printf 'Contraseña: %s\nPuertos SSH: 22, 299\nTLS/SSL: 443, 4443\nWebSocket: 25, 2082, 2086, 10080\nMáximo de sesiones: %s\n' \
        "$secret" "$max_sessions"
      ;;
    vless)
      printf '\nVLESS TLS WebSocket:\n'
      printf 'vless://%s@%s:443?encryption=none&security=tls&sni=%s&allowInsecure=1&type=ws&host=%s&path=%%2Fvless#%s-VLESS-WS\n' "$secret" "$host" "$host" "$host" "$username"
      printf '\nVLESS TLS XHTTP:\n'
      printf 'vless://%s@%s:443?encryption=none&security=tls&sni=%s&allowInsecure=1&type=xhttp&host=%s&path=%%2Fxhttp&mode=auto#%s-VLESS-XHTTP\n' "$secret" "$host" "$host" "$host" "$username"
      printf '\nVLESS TLS HTTPUpgrade:\n'
      printf 'vless://%s@%s:443?encryption=none&security=tls&sni=%s&allowInsecure=1&type=httpupgrade&host=%s&path=%%2Fhttpupgrade#%s-VLESS-HUP\n' "$secret" "$host" "$host" "$host" "$username"
      printf '\nVLESS TLS gRPC:\n'
      printf 'vless://%s@%s:443?encryption=none&security=tls&sni=%s&allowInsecure=1&type=grpc&serviceName=grpc-svc&alpn=h2#%s-VLESS-GRPC\n' "$secret" "$host" "$host" "$username"
      printf '\nVLESS sin TLS WebSocket:\n'
      printf 'vless://%s@%s:80?encryption=none&security=none&type=ws&host=%s&path=%%2Fvless#%s-VLESS-NTLS\n' "$secret" "$host" "$host" "$username"
      ;;
    vmess)
      printf '\nVMESS TLS WebSocket:\n'
      account_vmess_link "$username-VMESS-WS" "$host" "$secret" ws /vmess
      printf '\n\nVMESS TLS gRPC:\n'
      account_vmess_link "$username-VMESS-GRPC" "$host" "$secret" grpc '' vmess-grpc-svc
      printf '\n'
      ;;
    trojan)
      printf '\nTROJAN TLS WebSocket:\n'
      printf 'trojan://%s@%s:443?security=tls&sni=%s&allowInsecure=1&type=ws&host=%s&path=%%2Ftrojan#%s-TROJAN-WS\n' "$encoded" "$host" "$host" "$host" "$username"
      ;;
    hysteria)
      obfs="$(jq -r '.inbounds[]? | select(.tag=="hy1-inbound") | .obfs // empty' /etc/hysteria1/config.json 2>/dev/null | head -n1)"
      printf 'Auth: %s\nObfs: %s\nPuerto principal: 36712/UDP\nRango NAT: 20000-50000/UDP\n' "$secret" "${obfs:-no-configurado}"
      ;;
    hysteria2)
      obfs="$(awk '/^[[:space:]]*password:/ {gsub(/^[[:space:]]*password:[[:space:]]*|[\"\047]/,""); print; exit}' /etc/hysteria2/config.yaml 2>/dev/null)"
      printf 'Token: %s\nPuerto: 36713/UDP\n\nEnlace Hysteria 2:\n' "$secret"
      printf 'hysteria2://%s@%s:36713?insecure=1&sni=%s&obfs=salamander&obfs-password=%s#%s-HY2\n' \
        "$encoded" "$host" "$host" "$(account_uri_encode "${obfs:-}")" "$username"
      ;;
    zivpn)
      obfs="$(jq -r '.obfs // .obfuscation // "zivpn"' /etc/zivpn/config.json 2>/dev/null || printf zivpn)"
      printf 'Contraseña: %s\nObfs: %s\nPuerto interno: 5667/UDP\nRango público: 6000-19999/UDP\n' "$secret" "$obfs"
      ;;
  esac
}
