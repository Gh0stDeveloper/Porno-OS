#!/usr/bin/env bash

slowdns_ports() { printf '%s\n' 'udp 53'; }
slowdns_dependencies() { printf '%s\n' ssh; }

slowdns_download_binary() {
  local url="${HEXTUNNEL_SLOWDNS_BINARY_URL:-https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server}"
  local expected="${HEXTUNNEL_SLOWDNS_SHA256:-}" tmp actual
  tmp="$(mktemp /tmp/hextunnel-slowdns.XXXXXX)"
  run_cmd curl -fL --retry 3 -o "$tmp" "$url"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  actual="$(sha256sum "$tmp" | awk '{print tolower($1)}')"
  if [[ -n "$expected" ]]; then
    [[ "$actual" == "${expected,,}" ]] || { rm -f "$tmp"; die "El SHA-256 de SlowDNS no coincide."; }
  elif [[ "${HEXTUNNEL_ALLOW_UNVERIFIED_DOWNLOADS:-0}" != 1 ]]; then
    rm -f "$tmp"
    die "Define HEXTUNNEL_SLOWDNS_SHA256 o habilita conscientemente HEXTUNNEL_ALLOW_UNVERIFIED_DOWNLOADS=1."
  else
    log_warn "SlowDNS se instalará sin checksum configurado: $actual"
  fi
  backup_path /usr/local/bin/sldns-server
  install -m 755 "$tmp" /usr/local/bin/sldns-server
  rm -f "$tmp"
}

slowdns_generate_keys() {
  ensure_dir 700 /etc/slowdns
  if [[ -s /etc/slowdns/server.key && -s /etc/slowdns/server.pub ]]; then return 0; fi
  backup_paths /etc/slowdns/server.key /etc/slowdns/server.pub
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  if /usr/local/bin/sldns-server -gen-key -privkey-file /etc/slowdns/server.key /etc/slowdns/server.pub >/dev/null 2>&1; then
    :
  elif /usr/local/bin/sldns-server --gen-key --privkey-file /etc/slowdns/server.key --pubkey-file /etc/slowdns/server.pub >/dev/null 2>&1; then
    :
  else
    die "El binario SlowDNS no pudo generar un par de claves."
  fi
  chmod 600 /etc/slowdns/server.key
  chmod 644 /etc/slowdns/server.pub
}

slowdns_write_environment() {
  local ns="${HEXTUNNEL_SLOWDNS_NS:-}" port="${HEXTUNNEL_SLOWDNS_LISTEN_PORT:-53}"
  if [[ -z "$ns" && "${HEXTUNNEL_NON_INTERACTIVE:-0}" != 1 ]]; then
    read -r -p "Nameserver delegado para SlowDNS: " ns
  fi
  [[ -n "$ns" ]] || die "HEXTUNNEL_SLOWDNS_NS es obligatorio."
  [[ "$ns" =~ ^[A-Za-z0-9.-]+$ ]] || die "Nameserver SlowDNS inválido."
  write_file /etc/default/hextunnel-slowdns 600 <<EOF
SLOWDNS_NS=$ns
SLOWDNS_LISTEN_PORT=$port
SLOWDNS_TARGET_HOST=127.0.0.1
SLOWDNS_TARGET_PORT=299
EOF
}

slowdns_install() {
  run_cmd apt-get update
  run_cmd apt-get install -y curl ca-certificates
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
ExecStart=/usr/local/bin/sldns-server -udp :${SLOWDNS_LISTEN_PORT} -privkey-file /etc/slowdns/server.key ${SLOWDNS_NS} ${SLOWDNS_TARGET_HOST}:${SLOWDNS_TARGET_PORT}
Restart=on-failure
RestartSec=3s
User=nobody
Group=nogroup
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadOnlyPaths=/etc/slowdns /etc/default/hextunnel-slowdns
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
  safe_restart_service server-sldns "test -s /etc/slowdns/server.key && test -s /etc/slowdns/server.pub && test -s /etc/default/hextunnel-slowdns"
}

slowdns_set_listen_port() {
  local port="$1"
  [[ -f /etc/default/hextunnel-slowdns ]] || return 0
  backup_path /etc/default/hextunnel-slowdns
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || sed -i -E "s/^SLOWDNS_LISTEN_PORT=.*/SLOWDNS_LISTEN_PORT=$port/" /etc/default/hextunnel-slowdns
  safe_restart_service server-sldns "test -s /etc/default/hextunnel-slowdns"
}

slowdns_uninstall() {
  safe_stop_disable_service server-sldns
  backup_paths /etc/slowdns /etc/default/hextunnel-slowdns /etc/systemd/system/server-sldns.service /usr/local/bin/sldns-server
  run_cmd rm -rf /etc/slowdns
  run_cmd rm -f /etc/default/hextunnel-slowdns /etc/systemd/system/server-sldns.service /usr/local/bin/sldns-server
  systemd_reload
  firewall_close_port udp 53
}

slowdns_validate() {
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  [[ -x /usr/local/bin/sldns-server && -s /etc/slowdns/server.key && -s /etc/slowdns/server.pub && -s /etc/default/hextunnel-slowdns ]]
}

slowdns_doctor() {
  local port=53
  [[ -r /etc/default/hextunnel-slowdns ]] && port="$(. /etc/default/hextunnel-slowdns; printf '%s' "$SLOWDNS_LISTEN_PORT")"
  printf 'service=%s port=%s:' "$(systemctl is-active server-sldns 2>/dev/null || true)" "$port"
  port_is_listening udp "$port" && printf open || printf closed
  printf ' public-key=%s\n' "$(head -c 16 /etc/slowdns/server.pub 2>/dev/null || printf missing)"
}
