#!/usr/bin/env bash

slowdns_ports() {
  local address="${HEXTUNNEL_SLOWDNS_LISTEN_ADDRESS:-}" port="${HEXTUNNEL_SLOWDNS_LISTEN_PORT:-53}"
  [[ "$address" == 127.* || "$address" == ::1 ]] && return 0
  printf 'udp %s 0.0.0.0/0 public\n' "$port"
}
slowdns_dependencies() { printf '%s\n' ssh; }

slowdns_download_binary() {
  local ref="${HEXTUNNEL_SLOWDNS_REF:-b667b0d15be0589cd89cd2f997873296ceb07ce2}"
  local default_url="https://raw.githubusercontent.com/fisabiliyusri/SLDNS/${ref}/slowdns/sldns-server"
  local url="${HEXTUNNEL_SLOWDNS_BINARY_URL:-$default_url}"
  local expected="${HEXTUNNEL_SLOWDNS_SHA256:-}" tmp actual
  [[ "$ref" =~ ^[0-9a-fA-F]{40}$ ]] || die "HEXTUNNEL_SLOWDNS_REF debe ser un commit completo."
  [[ "$url" == https://* ]] || die "SlowDNS solo puede descargarse mediante HTTPS."
  tmp="$(mktemp /tmp/hextunnel-slowdns.XXXXXX)"
  run_cmd curl -fL --retry 3 -o "$tmp" "$url"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && { rm -f "$tmp"; return 0; }
  actual="$(sha256sum "$tmp" | awk '{print tolower($1)}')"
  if [[ -n "$expected" ]]; then
    [[ "$actual" == "${expected,,}" ]] || { rm -f "$tmp"; die "El SHA-256 de SlowDNS no coincide."; }
  elif [[ "${HEXTUNNEL_ALLOW_UNVERIFIED_DOWNLOADS:-0}" != 1 ]]; then
    rm -f "$tmp"
    die "El paquete no contiene el SHA-256 bloqueado de SlowDNS."
  else
    log_warn "SlowDNS se instalará sin checksum configurado: $actual"
  fi
  backup_path /usr/local/bin/sldns-server
  install -m 755 "$tmp" /usr/local/bin/sldns-server
  rm -f "$tmp"
}

slowdns_generate_keys() {
  ensure_dir 750 /etc/slowdns
  if [[ ! -s /etc/slowdns/server.key || ! -s /etc/slowdns/server.pub ]]; then
    backup_paths /etc/slowdns/server.key /etc/slowdns/server.pub
    if [[ "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]]; then
      if /usr/local/bin/sldns-server -gen-key -privkey-file /etc/slowdns/server.key /etc/slowdns/server.pub >/dev/null 2>&1; then
        :
      elif /usr/local/bin/sldns-server --gen-key --privkey-file /etc/slowdns/server.key --pubkey-file /etc/slowdns/server.pub >/dev/null 2>&1; then
        :
      else
        die "El binario SlowDNS no pudo generar un par de claves."
      fi
    fi
  fi
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]]; then
    chown root:hextunnel-slowdns /etc/slowdns /etc/slowdns/server.key /etc/slowdns/server.pub
    chmod 750 /etc/slowdns
    chmod 640 /etc/slowdns/server.key
    chmod 644 /etc/slowdns/server.pub
  fi
}

slowdns_write_environment() {
  local ns="${HEXTUNNEL_SLOWDNS_NS:-}"
  local port="${HEXTUNNEL_SLOWDNS_LISTEN_PORT:-53}"
  local address="${HEXTUNNEL_SLOWDNS_LISTEN_ADDRESS:-$(primary_ipv4)}"
  if [[ -z "$ns" && "${HEXTUNNEL_NON_INTERACTIVE:-0}" != 1 ]]; then
    read -r -p "Nameserver delegado para SlowDNS: " ns
  fi
  [[ -n "$ns" ]] || die "HEXTUNNEL_SLOWDNS_NS es obligatorio."
  [[ "$ns" =~ ^[A-Za-z0-9.-]+$ ]] || die "Nameserver SlowDNS inválido."
  [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]] || die "Puerto SlowDNS inválido: $port"
  [[ -n "$address" ]] || die "No se pudo determinar la IP de escucha para SlowDNS."
  write_file /etc/default/hextunnel-slowdns 600 <<EOF
SLOWDNS_NS=$ns
SLOWDNS_LISTEN_ADDRESS=$address
SLOWDNS_LISTEN_PORT=$port
SLOWDNS_TARGET_HOST=127.0.0.1
SLOWDNS_TARGET_PORT=299
EOF
}

slowdns_install() {
  run_cmd apt-get update
  run_cmd apt-get install -y curl ca-certificates
  ensure_system_user hextunnel-slowdns
  slowdns_download_binary
  slowdns_generate_keys
  slowdns_write_environment
  install_systemd_unit server-sldns.service 644 <<'EOF'
[Unit]
Description=Hex Tunnel SlowDNS server
After=network-online.target ssh.service
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/default/hextunnel-slowdns
ExecStart=/usr/local/bin/sldns-server -udp ${SLOWDNS_LISTEN_ADDRESS}:${SLOWDNS_LISTEN_PORT} -privkey-file /etc/slowdns/server.key ${SLOWDNS_NS} ${SLOWDNS_TARGET_HOST}:${SLOWDNS_TARGET_PORT}
Restart=on-failure
RestartSec=3s
User=hextunnel-slowdns
Group=hextunnel-slowdns
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ReadOnlyPaths=/etc/slowdns /etc/default/hextunnel-slowdns
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
  safe_restart_service server-sldns "runuser -u hextunnel-slowdns -- test -r /etc/slowdns/server.key && test -s /etc/slowdns/server.pub && test -s /etc/default/hextunnel-slowdns"
}

slowdns_set_listener() {
  local address="$1" port="$2"
  [[ -f /etc/default/hextunnel-slowdns ]] || return 0
  [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]] || die "Puerto SlowDNS inválido: $port"
  backup_path /etc/default/hextunnel-slowdns
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]]; then
    sed -i -E "s/^SLOWDNS_LISTEN_ADDRESS=.*/SLOWDNS_LISTEN_ADDRESS=$address/" /etc/default/hextunnel-slowdns
    sed -i -E "s/^SLOWDNS_LISTEN_PORT=.*/SLOWDNS_LISTEN_PORT=$port/" /etc/default/hextunnel-slowdns
  fi
  safe_restart_service server-sldns "test -s /etc/default/hextunnel-slowdns"
}

slowdns_uninstall() {
  safe_stop_disable_service server-sldns
  backup_paths /etc/slowdns /etc/default/hextunnel-slowdns /etc/systemd/system/server-sldns.service /usr/local/bin/sldns-server
  run_cmd rm -rf /etc/slowdns
  run_cmd rm -f /etc/default/hextunnel-slowdns /etc/systemd/system/server-sldns.service /usr/local/bin/sldns-server
  systemd_reload
  remove_managed_system_user hextunnel-slowdns
  firewall_close_port udp "${HEXTUNNEL_SLOWDNS_LISTEN_PORT:-53}"
}

slowdns_validate() {
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  [[ -x /usr/local/bin/sldns-server && -s /etc/slowdns/server.key && -s /etc/slowdns/server.pub && -s /etc/default/hextunnel-slowdns ]]
  runuser -u hextunnel-slowdns -- test -r /etc/slowdns/server.key
}

slowdns_doctor() {
  local address="" port=53 failed=0 scope=public
  if [[ -r /etc/default/hextunnel-slowdns ]]; then
    # shellcheck disable=SC1091
    source /etc/default/hextunnel-slowdns
    address="$SLOWDNS_LISTEN_ADDRESS"
    port="$SLOWDNS_LISTEN_PORT"
  fi
  [[ "$address" == 127.* || "$address" == ::1 ]] && scope=any
  printf 'service=%s listener=%s:%s:' "$(systemctl is-active server-sldns 2>/dev/null || true)" "${address:-unknown}" "$port"
  systemctl is-active --quiet server-sldns || failed=1
  if port_is_listening udp "$port" "$scope"; then printf open; else printf closed; failed=1; fi
  printf ' public-key=%s\n' "$(head -c 16 /etc/slowdns/server.pub 2>/dev/null || printf missing)"
  [[ -s /etc/slowdns/server.pub ]] || failed=1
  return "$failed"
}
