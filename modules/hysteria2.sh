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
  [[ -n "$expected" && "$actual" == "$expected" ]] || {
    rm -rf "$tmp"
    die "La verificación SHA-256 de Hysteria 2 falló."
  }
  backup_path /usr/local/bin/hysteria2
  install -m 755 "$tmp/$asset" /usr/local/bin/hysteria2.new
  mv -f /usr/local/bin/hysteria2.new /usr/local/bin/hysteria2
  rm -rf "$tmp"
}

hysteria2_install_auth_helper() {
  write_file /usr/local/libexec/hextunnel-hysteria2-auth 750 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
user_db=/etc/hysteria2/users.txt
auth="${2:-}"
[[ -n "$auth" && -r "$user_db" ]] || exit 1
awk -v token="$auth" '$2 == token {print $1; found=1; exit} END {exit !found}' "$user_db"
EOF
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || chown root:hextunnel-hysteria2 /usr/local/libexec/hextunnel-hysteria2-auth
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
install -m 640 -o root -g hextunnel-hysteria2 "$work" "$user_db"
EOF
  write_file /etc/cron.d/hextunnel-hysteria2-expiry 644 <<'EOF'
11 0 * * * root /usr/local/sbin/hextunnel-hysteria2-expire >/dev/null 2>&1
EOF
}

hysteria2_validate_config() {
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  local work result
  work="$(mktemp -d /tmp/hextunnel-hysteria2-check.XXXXXX)"
  trap 'rm -rf "$work"' RETURN
  sed -E 's|^listen:.*|listen: 127.0.0.1:0|' /etc/hysteria2/config.yaml > "$work/config.yaml"
  chown hextunnel-hysteria2:hextunnel-hysteria2 "$work" "$work/config.yaml"
  chmod 700 "$work"
  chmod 600 "$work/config.yaml"
  set +e
  timeout --signal=TERM 2s runuser -u hextunnel-hysteria2 -- \
    /usr/local/bin/hysteria2 server --config "$work/config.yaml" \
    >"$work/output.log" 2>&1
  result=$?
  set -e
  [[ "$result" -eq 124 || "$result" -eq 143 ]] || {
    sanitize_text < "$work/output.log" >&2
    die "La configuración Hysteria 2 no pudo iniciar en el puerto temporal."
  }
}

hysteria2_install() {
  run_cmd apt-get update
  run_cmd apt-get install -y curl ca-certificates jq util-linux openssl
  ensure_system_user hextunnel-hysteria2
  ensure_dir 750 /etc/hysteria2
  ensure_dir 755 /usr/local/libexec
  hysteria2_install_binary
  hysteria2_install_auth_helper

  local initial_token obfs
  initial_token="$(secret_get_or_create HEXTUNNEL_HYSTERIA2_PASSWORD 32)"
  obfs="${HEXTUNNEL_HYSTERIA2_OBFS:-$(secret_get_or_create HEXTUNNEL_HYSTERIA2_OBFS 24)}"

  backup_paths \
    /etc/hysteria2/config.yaml \
    /etc/hysteria2/users.txt \
    /etc/hysteria2/server.crt \
    /etc/hysteria2/server.key \
    /etc/systemd/system/hysteria2.service

  if [[ "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]]; then
    install -m 644 -o root -g hextunnel-hysteria2 /etc/xray/xray.crt /etc/hysteria2/server.crt
    install -m 640 -o root -g hextunnel-hysteria2 /etc/xray/xray.key /etc/hysteria2/server.key
  fi

  if [[ ! -s /etc/hysteria2/users.txt ]]; then
    [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || \
      printf 'default %s %s\n' "$initial_token" "$(date -d '+365 days' +%Y-%m-%d)" > /etc/hysteria2/users.txt
  fi
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]]; then
    chown root:hextunnel-hysteria2 /etc/hysteria2/users.txt
    chmod 640 /etc/hysteria2/users.txt
  fi

  write_file /etc/hysteria2/config.yaml 640 <<EOF
listen: :36713
tls:
  cert: /etc/hysteria2/server.crt
  key: /etc/hysteria2/server.key
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
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || {
    chown root:hextunnel-hysteria2 /etc/hysteria2 /etc/hysteria2/config.yaml
    chmod 750 /etc/hysteria2
  }

  install_systemd_unit hysteria2.service 644 <<'EOF'
[Unit]
Description=Hex Tunnel Hysteria 2
After=network-online.target xray.service
Wants=network-online.target

[Service]
Type=simple
User=hextunnel-hysteria2
Group=hextunnel-hysteria2
ExecStart=/usr/local/bin/hysteria2 server --config /etc/hysteria2/config.yaml
Restart=on-failure
RestartSec=2s
LimitNOFILE=1048576
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ReadOnlyPaths=/etc/hysteria2
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

  hysteria2_install_expiry
  hysteria2_validate_config
  safe_restart_service hysteria2
}

hysteria2_uninstall() {
  safe_stop_disable_service hysteria2
  backup_paths \
    /etc/hysteria2 \
    /etc/systemd/system/hysteria2.service \
    /usr/local/bin/hysteria2 \
    /usr/local/libexec/hextunnel-hysteria2-auth \
    /usr/local/sbin/hextunnel-hysteria2-expire \
    /etc/cron.d/hextunnel-hysteria2-expiry
  run_cmd rm -rf /etc/hysteria2
  run_cmd rm -f \
    /etc/systemd/system/hysteria2.service \
    /usr/local/bin/hysteria2 \
    /usr/local/libexec/hextunnel-hysteria2-auth \
    /usr/local/sbin/hextunnel-hysteria2-expire \
    /etc/cron.d/hextunnel-hysteria2-expiry
  systemd_reload
  remove_managed_system_user hextunnel-hysteria2
  firewall_close_port udp 36713
}

hysteria2_validate() {
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  [[ -x /usr/local/bin/hysteria2 ]]
  [[ -s /etc/hysteria2/config.yaml && -s /etc/hysteria2/users.txt ]]
  [[ -s /etc/hysteria2/server.crt && -s /etc/hysteria2/server.key ]]
  runuser -u hextunnel-hysteria2 -- test -r /etc/hysteria2/config.yaml
  runuser -u hextunnel-hysteria2 -- test -r /etc/hysteria2/users.txt
  runuser -u hextunnel-hysteria2 -- test -r /etc/hysteria2/server.key
  openssl x509 -in /etc/hysteria2/server.crt -noout >/dev/null
}

hysteria2_doctor() {
  local failed=0
  printf 'service=%s port=' "$(systemctl is-active hysteria2 2>/dev/null || true)"
  systemctl is-active --quiet hysteria2 || failed=1
  if port_is_listening udp 36713; then printf open; else printf closed; failed=1; fi
  printf ' users=%s tls=' "$(wc -l < /etc/hysteria2/users.txt 2>/dev/null || printf 0)"
  if openssl x509 -in /etc/hysteria2/server.crt -noout >/dev/null 2>&1; then printf valid; else printf invalid; failed=1; fi
  printf '\n'
  return "$failed"
}
