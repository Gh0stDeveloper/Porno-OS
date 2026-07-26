#!/usr/bin/env bash

udp_custom_ports() { printf '%s\n' 'udp 36717'; }
udp_custom_dependencies() { printf '%s\n' ssh; }

udp_custom_default_asset() {
  case "${HEXTUNNEL_ARCH:-$(normalize_architecture)}" in
    amd64) printf '%s' 'https://raw.githubusercontent.com/mahpud896/UDP-Custom/main/bin/udp-custom-linux-amd64' ;;
    *) return 1 ;;
  esac
}

udp_custom_install_binary() {
  local url="${HEXTUNNEL_UDP_CUSTOM_BINARY_URL:-}" expected="${HEXTUNNEL_UDP_CUSTOM_SHA256:-}" tmp actual
  if [[ -z "$url" ]]; then
    url="$(udp_custom_default_asset)" || die "UDP Custom no publica un binario predeterminado para $HEXTUNNEL_ARCH; configura URL y SHA-256."
  fi
  tmp="$(mktemp /tmp/hextunnel-udp-custom.XXXXXX)"
  run_cmd curl -fL --retry 3 -o "$tmp" "$url"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && { rm -f "$tmp"; return 0; }
  actual="$(sha256sum "$tmp" | awk '{print tolower($1)}')"
  if [[ -n "$expected" ]]; then
    [[ "$actual" == "${expected,,}" ]] || { rm -f "$tmp"; die "El SHA-256 de UDP Custom no coincide."; }
  elif [[ "${HEXTUNNEL_ALLOW_UNVERIFIED_DOWNLOADS:-0}" != 1 ]]; then
    rm -f "$tmp"
    die "Define HEXTUNNEL_UDP_CUSTOM_SHA256 antes de instalar UDP Custom."
  else
    log_warn "UDP Custom se instalará sin checksum configurado: $actual"
  fi
  backup_path /usr/local/bin/udp-custom
  install -m 755 "$tmp" /usr/local/bin/udp-custom
  rm -f "$tmp"
}

udp_custom_install_badvpn() {
  local ref="${HEXTUNNEL_BADVPN_REF:-1.999.130}"
  local url="${HEXTUNNEL_BADVPN_SOURCE_URL:-https://codeload.github.com/ambrop72/badvpn/tar.gz/refs/tags/$ref}"
  local expected="${HEXTUNNEL_BADVPN_SHA256:-}" work archive actual source build
  [[ -n "$expected" || "${HEXTUNNEL_ALLOW_UNVERIFIED_DOWNLOADS:-0}" == 1 ]] \
    || die "Define HEXTUNNEL_BADVPN_SHA256 para compilar badvpn-udpgw."
  work="$(mktemp -d /tmp/hextunnel-badvpn.XXXXXX)"
  archive="$work/source.tar.gz"
  run_cmd curl -fL --retry 3 -o "$archive" "$url"
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]]; then
    rm -rf "$work"
    return 0
  fi
  actual="$(sha256sum "$archive" | awk '{print tolower($1)}')"
  if [[ -n "$expected" ]]; then
    [[ "$actual" == "${expected,,}" ]] || { rm -rf "$work"; die "El SHA-256 del código fuente de BadVPN no coincide."; }
  else
    log_warn "BadVPN se compilará sin checksum configurado: $actual"
  fi
  tar -xzf "$archive" -C "$work"
  source="$(find "$work" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  [[ -n "$source" && -f "$source/CMakeLists.txt" ]] || { rm -rf "$work"; die "El archivo de BadVPN no contiene CMakeLists.txt."; }
  build="$work/build"
  cmake -S "$source" -B "$build" \
    -DBUILD_NOTHING_BY_DEFAULT=1 \
    -DBUILD_UDPGW=1 \
    -DCMAKE_BUILD_TYPE=Release
  cmake --build "$build" --target badvpn-udpgw --parallel "$(nproc)"
  [[ -x "$build/udpgw/badvpn-udpgw" ]] || { rm -rf "$work"; die "No se generó badvpn-udpgw."; }
  backup_path /usr/local/libexec/hextunnel-badvpn-udpgw
  install -D -m 755 "$build/udpgw/badvpn-udpgw" /usr/local/libexec/hextunnel-badvpn-udpgw
  rm -rf "$work"
}

udp_custom_install() {
  run_cmd apt-get update
  run_cmd apt-get install -y curl jq ca-certificates cmake make gcc libc6-dev tar
  ensure_system_user hextunnel-udp
  ensure_dir 750 /etc/udp-custom
  udp_custom_install_binary
  udp_custom_install_badvpn
  backup_paths /etc/udp-custom/config.json /etc/systemd/system/hextunnel-badvpn.service /etc/systemd/system/udp-custom.service
  write_file /etc/udp-custom/config.json 640 <<'EOF'
{
  "listen": ":36717",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "auth": {
    "mode": "passwords"
  }
}
EOF
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || chown root:hextunnel-udp /etc/udp-custom/config.json
  install_systemd_unit hextunnel-badvpn.service 644 <<'EOF'
[Unit]
Description=Hex Tunnel BadVPN UDP gateway
After=network-online.target
Wants=network-online.target
Before=udp-custom.service

[Service]
Type=simple
User=hextunnel-udp
Group=hextunnel-udp
ExecStart=/usr/local/libexec/hextunnel-badvpn-udpgw --loglevel none --listen-addr 127.0.0.1:7300 --max-clients 1000 --max-connections-for-client 10
Restart=on-failure
RestartSec=2s
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6

[Install]
WantedBy=multi-user.target
EOF
  install_systemd_unit udp-custom.service 644 <<'EOF'
[Unit]
Description=Hex Tunnel UDP Custom Proxy
After=network-online.target hextunnel-badvpn.service
Wants=network-online.target hextunnel-badvpn.service

[Service]
Type=simple
User=hextunnel-udp
Group=hextunnel-udp
WorkingDirectory=/etc/udp-custom
ExecStart=/usr/local/bin/udp-custom server -c /etc/udp-custom/config.json
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
ReadOnlyPaths=/etc/udp-custom

[Install]
WantedBy=multi-user.target
EOF
  safe_restart_service hextunnel-badvpn "test -x /usr/local/libexec/hextunnel-badvpn-udpgw"
  safe_restart_service udp-custom "jq empty /etc/udp-custom/config.json && runuser -u hextunnel-udp -- test -r /etc/udp-custom/config.json"
}

udp_custom_uninstall() {
  safe_stop_disable_service udp-custom
  safe_stop_disable_service hextunnel-badvpn
  backup_paths /etc/udp-custom /etc/systemd/system/udp-custom.service /etc/systemd/system/hextunnel-badvpn.service /usr/local/bin/udp-custom /usr/local/libexec/hextunnel-badvpn-udpgw
  run_cmd rm -rf /etc/udp-custom
  run_cmd rm -f /etc/systemd/system/udp-custom.service /etc/systemd/system/hextunnel-badvpn.service /usr/local/bin/udp-custom /usr/local/libexec/hextunnel-badvpn-udpgw
  systemd_reload
  remove_managed_system_user hextunnel-udp
  firewall_close_port udp 36717
}

udp_custom_validate() {
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  [[ -x /usr/local/bin/udp-custom && -x /usr/local/libexec/hextunnel-badvpn-udpgw && -s /etc/udp-custom/config.json ]]
  jq empty /etc/udp-custom/config.json
  runuser -u hextunnel-udp -- test -r /etc/udp-custom/config.json
  systemctl is-active --quiet udp-custom
  systemctl is-active --quiet hextunnel-badvpn
}

udp_custom_doctor() {
  local failed=0
  printf 'service=%s badvpn=%s port=' "$(systemctl is-active udp-custom 2>/dev/null || true)" "$(systemctl is-active hextunnel-badvpn 2>/dev/null || true)"
  systemctl is-active --quiet udp-custom || failed=1
  systemctl is-active --quiet hextunnel-badvpn || failed=1
  if port_is_listening udp 36717; then printf open; else printf closed; failed=1; fi
  printf ' badvpn7300='
  if port_is_listening tcp 7300 any; then printf open; else printf closed; failed=1; fi
  printf ' config='
  if jq empty /etc/udp-custom/config.json >/dev/null 2>&1; then printf valid; else printf invalid; failed=1; fi
  printf '\n'
  return "$failed"
}
