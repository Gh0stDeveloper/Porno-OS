#!/usr/bin/env bash

hysteria2_ports() { printf '%s\n' 'udp 36713'; }
hysteria2_dependencies() { printf '%s\n' xray; }

hysteria2_asset_name() {
  case "${HEXTUNNEL_ARCH:-$(normalize_architecture)}" in
    amd64) printf hysteria-linux-amd64 ;;
    386) printf hysteria-linux-386 ;;
    arm64) printf hysteria-linux-arm64 ;;
    arm) printf hysteria-linux-arm ;;
    *) return 1 ;;
  esac
}

hysteria2_install_binary() {
  local version="${HEXTUNNEL_HYSTERIA2_VERSION:-app/v2.9.3}" asset tmp base expected actual
  asset="$(hysteria2_asset_name)" || die "Arquitectura Hysteria 2 no soportada."
  tmp="$(mktemp -d /tmp/hextunnel-hysteria2.XXXXXX)"
  base="https://github.com/apernet/hysteria/releases/download/${version}"
  run_cmd curl -fL --retry 3 -o "$tmp/$asset" "$base/$asset"
  run_cmd curl -fL --retry 3 -o "$tmp/hashes.txt" "$base/hashes.txt"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && { rm -rf "$tmp"; return 0; }
  expected="$(awk -v asset="$asset" '$2 == asset || $2 == "build/" asset || $2 == "*" asset {print tolower($1); exit}' "$tmp/hashes.txt")"
  actual="$(sha256sum "$tmp/$asset" | awk '{print tolower($1)}')"
  [[ -n "$expected" && "$actual" == "$expected" ]] || { rm -rf "$tmp"; die "La verificación SHA-256 de Hysteria 2 falló."; }
  backup_path /usr/local/bin/hysteria2
  install -m 755 "$tmp/$asset" /usr/local/bin/hysteria2.new
  mv -f /usr/local/bin/hysteria2.new /usr/local/bin/hysteria2
  rm -rf "$tmp"
}

hysteria2_install_auth_helper() {
  write_file /usr/local/libexec/hextunnel-hysteria2-auth 700 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
user_db=/etc/hysteria2/users.txt
auth="${2:-}"
[[ -n "$auth" && -r "$user_db" ]] || exit 1
awk -v token="$auth" '$2 == token {print $1; found=1; exit} END {exit !found}' "$user_db"
EOF
}

hysteria2_install_expiry() {
  write_file /usr/local/sbin/hextunnel-hysteria2-expire 700 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
user_db=/etc/hysteria2/users.txt
[[ -f "$user_db" ]] || exit 0
exec 9>/run/lock/hextunnel-hysteria2.lock
flock -w 30 9
work="$(mktemp /tmp/hextunnel-hysteria2-users.XXXXXX)"
trap 'rm -f "$work"' EXIT
awk -v today="$(date +%Y-%m-%d)" '$3 >= today' "$user_db" > "$work"
install -m 600 "$work" "$user_db"
EOF
  write_file /etc/cron.d/hextunnel-hysteria2-expiry 644 <<'EOF'
11 0 * * * root /usr/local/sbin/hextunnel-hysteria2-expire >/dev/null 2>&1
EOF
}

hysteria2_install() {
  run_cmd apt-get update
  run_cmd apt-get install -y curl ca-certificates jq util-linux
  ensure_dir 700 /etc/hysteria2
  ensure_dir 755 /usr/local/libexec
  hysteria2_install_binary
  hysteria2_install_auth_helper
  local initial_token obfs
  initial_token="$(secret_get_or_create HEXTUNNEL_HYSTERIA2_PASSWORD 32)"
  obfs="${HEXTUNNEL_HYSTERIA2_OBFS:-$(secret_get_or_create HEXTUNNEL_HYSTERIA2_OBFS 24)}"
  backup_paths /etc/hysteria2/config.yaml /etc/hysteria2/users.txt /etc/systemd/system/hysteria2.service
  if [[ ! -s /etc/hysteria2/users.txt ]]; then
    [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || printf 'default %s %s\n' "$initial_token" "$(date -d '+365 days' +%Y-%m-%d)" > /etc/hysteria2/users.txt
  fi
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || chmod 600 /etc/hysteria2/users.txt
  write_file /etc/hysteria2/config.yaml 600 <<EOF
listen: :36713
tls:
  cert: /etc/xray/xray.crt
  key: /etc/xray/xray.key
auth:
  type: command
  command: /usr/local/libexec/hextunnel-hysteria2-auth
obfs:
  type: salamander
  salamander:
    password: "$obfs"
masquerade:
  type: proxy
  proxy:
    url: https://www.microsoft.com/
    rewriteHost: true
bandwidth:
  up: 1 gbps
  down: 1 gbps
EOF
  install_systemd_unit hysteria2.service 644 <<'EOF'
[Unit]
Description=Hex Tunnel Hysteria 2
After=network-online.target xray.service
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/hysteria2 server --config /etc/hysteria2/config.yaml
Restart=on-failure
RestartSec=2s
LimitNOFILE=1048576
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=full
ReadOnlyPaths=/etc/xray/xray.crt /etc/xray/xray.key
ReadWritePaths=/etc/hysteria2
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
  hysteria2_install_expiry
  safe_restart_service hysteria2 "/usr/local/bin/hysteria2 server --config /etc/hysteria2/config.yaml --check 2>/dev/null || /usr/local/bin/hysteria2 server --config /etc/hysteria2/config.yaml --test 2>/dev/null || test -s /etc/hysteria2/config.yaml"
}

hysteria2_uninstall() {
  safe_stop_disable_service hysteria2
  backup_paths /etc/hysteria2 /etc/systemd/system/hysteria2.service /usr/local/bin/hysteria2 /usr/local/libexec/hextunnel-hysteria2-auth /usr/local/sbin/hextunnel-hysteria2-expire /etc/cron.d/hextunnel-hysteria2-expiry
  run_cmd rm -rf /etc/hysteria2
  run_cmd rm -f /etc/systemd/system/hysteria2.service /usr/local/bin/hysteria2 /usr/local/libexec/hextunnel-hysteria2-auth /usr/local/sbin/hextunnel-hysteria2-expire /etc/cron.d/hextunnel-hysteria2-expiry
  systemd_reload
  firewall_close_port udp 36713
}

hysteria2_validate() {
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  [[ -x /usr/local/bin/hysteria2 && -s /etc/hysteria2/config.yaml && -s /etc/hysteria2/users.txt ]]
  openssl x509 -in /etc/xray/xray.crt -noout >/dev/null
}

hysteria2_doctor() {
  printf 'service=%s port=' "$(systemctl is-active hysteria2 2>/dev/null || true)"
  port_is_listening udp 36713 && printf open || printf closed
  printf ' users=%s\n' "$(wc -l < /etc/hysteria2/users.txt 2>/dev/null || printf 0)"
}
