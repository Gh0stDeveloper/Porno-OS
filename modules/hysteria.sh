#!/usr/bin/env bash

hysteria_ports() { printf '%s\n' 'udp 36712'; }
hysteria_dependencies() { printf '%s\n' xray; }

hysteria_singbox_asset() {
  local version="${HEXTUNNEL_SINGBOX_VERSION:-1.12.22}"
  case "${HEXTUNNEL_ARCH:-$(normalize_architecture)}" in
    amd64) printf 'sing-box_%s_linux_amd64.deb' "$version" ;;
    arm64) printf 'sing-box_%s_linux_arm64.deb' "$version" ;;
    arm) printf 'sing-box_%s_linux_armv7.deb' "$version" ;;
    386) printf 'sing-box_%s_linux_386.deb' "$version" ;;
    *) return 1 ;;
  esac
}

hysteria_install_singbox() {
  local version="${HEXTUNNEL_SINGBOX_VERSION:-1.12.22}" asset api metadata url digest expected actual tmp root binary
  asset="$(hysteria_singbox_asset)" || die "Arquitectura Sing-box no soportada."
  api="https://api.github.com/repos/SagerNet/sing-box/releases/tags/v${version}"
  metadata="$(curl -fsSL --retry 3 "$api")" || die "No se pudo consultar Sing-box v$version."
  url="$(jq -r --arg asset "$asset" '.assets[] | select(.name == $asset) | .browser_download_url' <<< "$metadata" | head -n1)"
  digest="$(jq -r --arg asset "$asset" '.assets[] | select(.name == $asset) | (.digest // empty)' <<< "$metadata" | head -n1)"
  [[ -n "$url" && "$url" != null ]] || die "El release Sing-box no contiene $asset."
  tmp="$(mktemp -d /tmp/hextunnel-singbox.XXXXXX)"
  run_cmd curl -fL --retry 3 -o "$tmp/sing-box.deb" "$url"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && { rm -rf "$tmp"; return 0; }
  actual="$(sha256sum "$tmp/sing-box.deb" | awk '{print tolower($1)}')"
  expected="${HEXTUNNEL_SINGBOX_SHA256:-}"
  [[ -z "$expected" && "$digest" == sha256:* ]] && expected="${digest#sha256:}"
  if [[ -n "$expected" ]]; then
    [[ "$actual" == "${expected,,}" ]] || { rm -rf "$tmp"; die "El SHA-256 de Sing-box no coincide."; }
  elif [[ "${HEXTUNNEL_ALLOW_UNVERIFIED_DOWNLOADS:-0}" != 1 ]]; then
    rm -rf "$tmp"
    die "El release Sing-box no publica digest. Define HEXTUNNEL_SINGBOX_SHA256."
  else
    log_warn "Sing-box se instalará sin checksum configurado: $actual"
  fi
  root="$tmp/root"
  mkdir -p "$root"
  dpkg-deb -x "$tmp/sing-box.deb" "$root"
  binary="$(find "$root" -type f -path '*/bin/sing-box' | head -n1)"
  [[ -n "$binary" && -f "$binary" ]] || { rm -rf "$tmp"; die "El paquete Sing-box no contiene el binario."; }
  backup_path /usr/local/bin/sing-box-hextunnel
  install -m 755 "$binary" /usr/local/bin/sing-box-hextunnel.new
  if [[ -s /etc/hysteria1/config.json ]]; then
    /usr/local/bin/sing-box-hextunnel.new check -c /etc/hysteria1/config.json \
      || { rm -f /usr/local/bin/sing-box-hextunnel.new; rm -rf "$tmp"; die "La versión Sing-box rechazó la configuración Hysteria v1."; }
  fi
  mv -f /usr/local/bin/sing-box-hextunnel.new /usr/local/bin/sing-box-hextunnel
  rm -rf "$tmp"
}

hysteria_rebuild_users() {
  local config="${1:-/etc/hysteria1/config.json}" users="${2:-/etc/hysteria1/users.txt}" tmp auth
  [[ -s "$config" && -f "$users" ]] || return 0
  tmp="$(mktemp /tmp/hextunnel-hysteria-users.XXXXXX)"
  auth="$(awk 'NF >= 3 {print $2}' "$users" | jq -R '{auth_str:.}' | jq -s .)"
  jq --argjson auth "$auth" '(.inbounds[] | select(.tag == "hy1-inbound") | .users)=$auth' "$config" > "$tmp"
  /usr/local/bin/sing-box-hextunnel check -c "$tmp"
  install -m 640 -o root -g hextunnel-hysteria "$tmp" "$config"
  rm -f "$tmp"
}

hysteria_install_expiry() {
  write_file /usr/local/sbin/hextunnel-hysteria-expire 700 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
users=/etc/hysteria1/users.txt
config=/etc/hysteria1/config.json
binary=/usr/local/bin/sing-box-hextunnel
[[ -s "$users" && -s "$config" && -x "$binary" ]] || exit 0
exec 9>/run/lock/hextunnel-hysteria.lock
flock -w 30 9
work="$(mktemp -d /tmp/hextunnel-hysteria-expire.XXXXXX)"
trap 'rm -rf "$work"' EXIT
awk -v today="$(date +%Y-%m-%d)" 'NF >= 3 && $3 >= today {print}' "$users" > "$work/users.txt"
auth="$(awk 'NF >= 3 {print $2}' "$work/users.txt" | jq -R '{auth_str:.}' | jq -s .)"
jq --argjson auth "$auth" '(.inbounds[] | select(.tag == "hy1-inbound") | .users)=$auth' "$config" > "$work/config.json"
"$binary" check -c "$work/config.json"
cp -p "$config" "$work/config.backup"
cp -p "$users" "$work/users.backup"
install -m 640 -o root -g hextunnel-hysteria "$work/config.json" "$config"
install -m 600 "$work/users.txt" "$users"
if ! systemctl restart hextunnel-hysteria; then
  install -m 640 -o root -g hextunnel-hysteria "$work/config.backup" "$config"
  install -m 600 "$work/users.backup" "$users"
  systemctl restart hextunnel-hysteria || true
  exit 1
fi
EOF
  write_file /etc/cron.d/hextunnel-hysteria-expiry 644 <<'EOF'
17 0 * * * root /usr/local/sbin/hextunnel-hysteria-expire >/dev/null 2>&1
EOF
}

hysteria_install_nat() {
  install_systemd_unit hextunnel-hysteria-nat.service 644 <<'EOF'
[Unit]
Description=Hex Tunnel Hysteria v1 UDP range NAT
After=network-online.target
Wants=network-online.target
Before=hextunnel-hysteria.service hysteria2.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hextunnel-nat apply hysteria1
ExecStop=/usr/local/bin/hextunnel-nat remove hysteria1
RemainAfterExit=yes
NoNewPrivileges=true
ProtectHome=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF
  safe_restart_service hextunnel-hysteria-nat
}

hysteria_install() {
  run_cmd apt-get update
  run_cmd apt-get install -y curl jq ca-certificates dpkg util-linux iptables nftables
  ensure_system_user hextunnel-hysteria
  ensure_dir 750 /etc/hysteria1
  hysteria_install_singbox
  local password obfs
  password="$(secret_get_or_create HEXTUNNEL_HYSTERIA_PASSWORD 32)"
  obfs="$(secret_get_or_create HEXTUNNEL_HYSTERIA_OBFS 24)"
  backup_paths /etc/hysteria1/config.json /etc/hysteria1/users.txt /etc/hysteria1/server.crt /etc/hysteria1/server.key /etc/systemd/system/hextunnel-hysteria.service
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || {
    install -m 644 -o root -g hextunnel-hysteria /etc/xray/xray.crt /etc/hysteria1/server.crt
    install -m 640 -o root -g hextunnel-hysteria /etc/xray/xray.key /etc/hysteria1/server.key
  }
  write_file /etc/hysteria1/config.json 640 <<EOF
{
  "log": {"level": "fatal"},
  "inbounds": [
    {
      "type": "hysteria",
      "tag": "hy1-inbound",
      "listen": "::",
      "listen_port": 36712,
      "up_mbps": 100,
      "down_mbps": 100,
      "obfs": "$obfs",
      "users": [{"auth_str": "$password"}],
      "tls": {
        "enabled": true,
        "certificate_path": "/etc/hysteria1/server.crt",
        "key_path": "/etc/hysteria1/server.key"
      }
    }
  ],
  "outbounds": [
    {"type": "direct", "tag": "direct"},
    {"type": "block", "tag": "block"}
  ],
  "route": {"auto_detect_interface": true}
}
EOF
  if [[ ! -s /etc/hysteria1/users.txt ]]; then
    [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || printf 'default %s %s\n' "$password" "$(date -d '+365 days' +%Y-%m-%d)" > /etc/hysteria1/users.txt
  fi
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]]; then
    chown root:hextunnel-hysteria /etc/hysteria1/config.json
    chmod 640 /etc/hysteria1/config.json
    chmod 600 /etc/hysteria1/users.txt
    hysteria_rebuild_users
  fi
  hysteria_install_nat
  install_systemd_unit hextunnel-hysteria.service 644 <<'EOF'
[Unit]
Description=Hex Tunnel Hysteria v1 via Sing-box
After=network-online.target hextunnel-hysteria-nat.service
Wants=network-online.target hextunnel-hysteria-nat.service

[Service]
Type=simple
User=hextunnel-hysteria
Group=hextunnel-hysteria
ExecStart=/usr/local/bin/sing-box-hextunnel run -c /etc/hysteria1/config.json
Restart=on-failure
RestartSec=3s
LimitNOFILE=1048576
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ReadOnlyPaths=/etc/hysteria1

[Install]
WantedBy=multi-user.target
EOF
  hysteria_install_expiry
  safe_restart_service hextunnel-hysteria "/usr/local/bin/sing-box-hextunnel check -c /etc/hysteria1/config.json"
}

hysteria_uninstall() {
  safe_stop_disable_service hextunnel-hysteria
  safe_stop_disable_service hextunnel-hysteria-nat
  nat_remove hysteria1
  backup_paths /etc/hysteria1 /etc/systemd/system/hextunnel-hysteria.service /etc/systemd/system/hextunnel-hysteria-nat.service /usr/local/bin/sing-box-hextunnel /usr/local/sbin/hextunnel-hysteria-expire /etc/cron.d/hextunnel-hysteria-expiry
  run_cmd rm -rf /etc/hysteria1
  run_cmd rm -f /etc/systemd/system/hextunnel-hysteria.service /etc/systemd/system/hextunnel-hysteria-nat.service /usr/local/bin/sing-box-hextunnel /usr/local/sbin/hextunnel-hysteria-expire /etc/cron.d/hextunnel-hysteria-expiry
  systemd_reload
  remove_managed_system_user hextunnel-hysteria
  firewall_close_port udp 36712
}

hysteria_validate() {
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  [[ -x /usr/local/bin/sing-box-hextunnel && -s /etc/hysteria1/config.json && -s /etc/hysteria1/users.txt ]]
  runuser -u hextunnel-hysteria -- test -r /etc/hysteria1/server.key
  /usr/local/bin/sing-box-hextunnel check -c /etc/hysteria1/config.json
  nat_is_present hysteria1
}

hysteria_doctor() {
  local failed=0
  printf 'service=%s port=' "$(systemctl is-active hextunnel-hysteria 2>/dev/null || true)"
  systemctl is-active --quiet hextunnel-hysteria || failed=1
  if port_is_listening udp 36712; then printf open; else printf closed; failed=1; fi
  printf ' nat='
  if nat_is_present hysteria1; then printf active; else printf missing; failed=1; fi
  printf ' users=%s config=' "$(wc -l < /etc/hysteria1/users.txt 2>/dev/null || printf 0)"
  if /usr/local/bin/sing-box-hextunnel check -c /etc/hysteria1/config.json >/dev/null 2>&1; then printf valid; else printf invalid; failed=1; fi
  printf '\n'
  return "$failed"
}
