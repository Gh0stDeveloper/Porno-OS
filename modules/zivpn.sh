#!/usr/bin/env bash

zivpn_ports() { printf '%s\n' 'udp 5667'; }
zivpn_dependencies() { printf '%s\n' xray; }

zivpn_asset_name() {
  case "${HEXTUNNEL_ARCH:-$(normalize_architecture)}" in
    amd64) printf udp-zivpn-linux-amd64 ;;
    arm64) printf udp-zivpn-linux-arm64 ;;
    arm) printf udp-zivpn-linux-arm ;;
    386) printf udp-zivpn-linux-386 ;;
    *) return 1 ;;
  esac
}

zivpn_install_binary() {
  local tag="${HEXTUNNEL_ZIVPN_VERSION:-udp-zivpn_1.4.9}" asset api metadata url digest expected actual tmp
  asset="${HEXTUNNEL_ZIVPN_ASSET:-$(zivpn_asset_name)}" || die "Arquitectura ZiVPN no soportada."
  api="https://api.github.com/repos/zahidbd2/udp-zivpn/releases/tags/$tag"
  metadata="$(curl -fsSL --retry 3 "$api")" || die "No se pudo consultar la versión ZiVPN."
  url="$(jq -r --arg asset "$asset" '.assets[] | select(.name == $asset) | .browser_download_url' <<< "$metadata" | head -n1)"
  digest="$(jq -r --arg asset "$asset" '.assets[] | select(.name == $asset) | (.digest // empty)' <<< "$metadata" | head -n1)"
  [[ -n "$url" && "$url" != null ]] || {
    url="${HEXTUNNEL_ZIVPN_BINARY_URL:-}"
    [[ -n "$url" ]] || die "La versión ZiVPN no contiene el activo $asset; configura HEXTUNNEL_ZIVPN_BINARY_URL."
  }
  tmp="$(mktemp /tmp/hextunnel-zivpn.XXXXXX)"
  run_cmd curl -fL --retry 3 -o "$tmp" "$url"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && { rm -f "$tmp"; return 0; }
  actual="$(sha256sum "$tmp" | awk '{print tolower($1)}')"
  expected="${HEXTUNNEL_ZIVPN_SHA256:-}"
  [[ -z "$expected" && "$digest" == sha256:* ]] && expected="${digest#sha256:}"
  if [[ -n "$expected" ]]; then
    [[ "$actual" == "${expected,,}" ]] || { rm -f "$tmp"; die "El SHA-256 de ZiVPN no coincide."; }
  elif [[ "${HEXTUNNEL_ALLOW_UNVERIFIED_DOWNLOADS:-0}" != 1 ]]; then
    rm -f "$tmp"
    die "El release ZiVPN no publica digest. Define HEXTUNNEL_ZIVPN_SHA256."
  else
    log_warn "ZiVPN se instalará sin checksum configurado: $actual"
  fi
  backup_path /usr/local/bin/zivpn
  install -m 755 "$tmp" /usr/local/bin/zivpn
  rm -f "$tmp"
}

zivpn_rebuild_config_passwords() {
  local config="${1:-/etc/zivpn/config.json}" users="${2:-/etc/zivpn/users.txt}" tmp passwords
  [[ -s "$config" && -f "$users" ]] || return 0
  tmp="$(mktemp /tmp/hextunnel-zivpn-config.XXXXXX)"
  passwords="$(awk 'NF >= 3 {print $2}' "$users" | jq -R . | jq -s .)"
  jq --argjson passwords "$passwords" '.auth.config=$passwords' "$config" > "$tmp"
  jq empty "$tmp"
  install -m 600 "$tmp" "$config"
  rm -f "$tmp"
}

zivpn_install_expiry() {
  write_file /usr/local/sbin/hextunnel-zivpn-expire 700 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
users=/etc/zivpn/users.txt
config=/etc/zivpn/config.json
[[ -s "$users" && -s "$config" ]] || exit 0
exec 9>/run/lock/hextunnel-zivpn.lock
flock -w 30 9
work="$(mktemp -d /tmp/hextunnel-zivpn-expire.XXXXXX)"
trap 'rm -rf "$work"' EXIT
awk -v today="$(date +%Y-%m-%d)" 'NF >= 3 && $3 >= today {print}' "$users" > "$work/users.txt"
passwords="$(awk 'NF >= 3 {print $2}' "$work/users.txt" | jq -R . | jq -s .)"
jq --argjson passwords "$passwords" '.auth.config=$passwords' "$config" > "$work/config.json"
jq empty "$work/config.json"
cp -p "$config" "$work/config.backup"
cp -p "$users" "$work/users.backup"
install -m 600 "$work/config.json" "$config"
install -m 600 "$work/users.txt" "$users"
if ! systemctl restart zivpn; then
  install -m 600 "$work/config.backup" "$config"
  install -m 600 "$work/users.backup" "$users"
  systemctl restart zivpn || true
  exit 1
fi
EOF
  write_file /etc/cron.d/hextunnel-zivpn-expiry 644 <<'EOF'
13 0 * * * root /usr/local/sbin/hextunnel-zivpn-expire >/dev/null 2>&1
EOF
}

zivpn_install_nat() {
  install_systemd_unit hextunnel-zivpn-nat.service 644 <<'EOF'
[Unit]
Description=Hex Tunnel ZiVPN UDP range NAT
After=network-online.target
Wants=network-online.target
Before=zivpn.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hextunnel-nat apply zivpn
ExecStop=/usr/local/bin/hextunnel-nat remove zivpn
RemainAfterExit=yes
NoNewPrivileges=true
ProtectHome=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF
  safe_restart_service hextunnel-zivpn-nat
}

zivpn_install() {
  run_cmd apt-get update
  run_cmd apt-get install -y curl jq ca-certificates util-linux iptables nftables
  ensure_dir 700 /etc/zivpn
  zivpn_install_binary
  local password obfs
  password="$(secret_get_or_create HEXTUNNEL_ZIVPN_PASSWORD 32)"
  obfs="$(secret_get_or_create HEXTUNNEL_ZIVPN_OBFS 16)"
  backup_paths /etc/zivpn/config.json /etc/zivpn/users.txt /etc/zivpn/zivpn.crt /etc/zivpn/zivpn.key /etc/systemd/system/zivpn.service
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || {
    install -m 644 /etc/xray/xray.crt /etc/zivpn/zivpn.crt
    install -m 600 /etc/xray/xray.key /etc/zivpn/zivpn.key
  }
  write_file /etc/zivpn/config.json 600 <<EOF
{
  "listen": ":5667",
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "$obfs",
  "auth": {
    "mode": "passwords",
    "config": ["$password"]
  }
}
EOF
  if [[ ! -s /etc/zivpn/users.txt ]]; then
    [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || printf 'default %s %s\n' "$password" "$(date -d '+365 days' +%Y-%m-%d)" > /etc/zivpn/users.txt
  fi
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || {
    chmod 600 /etc/zivpn/users.txt
    zivpn_rebuild_config_passwords
  }
  zivpn_install_nat
  install_systemd_unit zivpn.service 644 <<'EOF'
[Unit]
Description=Hex Tunnel ZiVPN server
After=network-online.target hextunnel-zivpn-nat.service
Wants=network-online.target hextunnel-zivpn-nat.service

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=on-failure
RestartSec=3s
LimitNOFILE=1048576
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=full
ReadOnlyPaths=/etc/zivpn
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW

[Install]
WantedBy=multi-user.target
EOF
  zivpn_install_expiry
  safe_restart_service zivpn "jq empty /etc/zivpn/config.json && openssl x509 -in /etc/zivpn/zivpn.crt -noout"
}

zivpn_uninstall() {
  safe_stop_disable_service zivpn
  safe_stop_disable_service hextunnel-zivpn-nat
  nat_remove zivpn
  backup_paths /etc/zivpn /etc/systemd/system/zivpn.service /etc/systemd/system/hextunnel-zivpn-nat.service /usr/local/bin/zivpn /usr/local/sbin/hextunnel-zivpn-expire /etc/cron.d/hextunnel-zivpn-expiry
  run_cmd rm -rf /etc/zivpn
  run_cmd rm -f /etc/systemd/system/zivpn.service /etc/systemd/system/hextunnel-zivpn-nat.service /usr/local/bin/zivpn /usr/local/sbin/hextunnel-zivpn-expire /etc/cron.d/hextunnel-zivpn-expiry
  systemd_reload
  firewall_close_port udp 5667
}

zivpn_validate() {
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  [[ -x /usr/local/bin/zivpn && -s /etc/zivpn/config.json && -s /etc/zivpn/zivpn.key && -s /etc/zivpn/users.txt ]]
  jq empty /etc/zivpn/config.json
  awk 'NF != 3 {exit 1}' /etc/zivpn/users.txt
  nat_is_present zivpn
}

zivpn_doctor() {
  local failed=0
  printf 'service=%s port=' "$(systemctl is-active zivpn 2>/dev/null || true)"
  systemctl is-active --quiet zivpn || failed=1
  if port_is_listening udp 5667; then printf open; else printf closed; failed=1; fi
  printf ' nat='
  if nat_is_present zivpn; then printf active; else printf missing; failed=1; fi
  printf ' users=%s config=' "$(wc -l < /etc/zivpn/users.txt 2>/dev/null || printf 0)"
  if jq empty /etc/zivpn/config.json >/dev/null 2>&1; then printf valid; else printf invalid; failed=1; fi
  printf '\n'
  return "$failed"
}
