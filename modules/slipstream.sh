#!/usr/bin/env bash

slipstream_ports() { printf '%s\n' 'udp 53 0.0.0.0/0 public'; }
slipstream_dependencies() { printf '%s\n' slowdns; }

slipstream_install() {
  local domain="${HEXTUNNEL_SLIPSTREAM_DOMAIN:-}"
  local slowdns_ns="${HEXTUNNEL_SLOWDNS_NS:-}"
  local install_dir="${HEXTUNNEL_SLIPSTREAM_DIR:-/opt/slipstream-rust}"
  local commit="${HEXTUNNEL_SLIPSTREAM_COMMIT:-bc772dd07d9a136dbd7553b0da575526de207847}"
  local external_ip
  if [[ -z "$domain" && "${HEXTUNNEL_NON_INTERACTIVE:-0}" != 1 ]]; then
    read -r -p "Dominio delegado para SlipStream: " domain
  fi
  [[ -n "$domain" && "$domain" =~ ^[A-Za-z0-9.-]+$ ]] || die "HEXTUNNEL_SLIPSTREAM_DOMAIN es obligatorio."
  [[ "$domain" != "$slowdns_ns" ]] || die "SlowDNS y SlipStream deben usar dominios diferentes."
  external_ip="$(primary_ipv4)"
  [[ -n "$external_ip" ]] || die "No se pudo determinar la IP pública para DNSdist."

  run_cmd apt-get update
  run_cmd apt-get install -y git cargo rustc pkg-config libssl-dev dante-server dnsdist openssl ca-certificates
  ensure_system_user hextunnel-slipstream
  backup_paths "$install_dir" /etc/danted.conf /etc/dnsdist/dnsdist.conf /etc/systemd/system/slipstream.service /etc/slipstream

  if [[ "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]]; then
    if [[ -d "$install_dir/.git" ]]; then
      git -C "$install_dir" fetch --tags --force origin
    else
      rm -rf "$install_dir"
      git clone https://github.com/Mygod/slipstream-rust.git "$install_dir"
    fi
    git -C "$install_dir" checkout --detach "$commit"
    [[ "$(git -C "$install_dir" rev-parse HEAD)" == "$commit" ]] || die "No se pudo fijar el commit de SlipStream."
    git -C "$install_dir" submodule update --init --recursive
    cargo build --release -p slipstream-server --manifest-path "$install_dir/Cargo.toml"
    [[ -x "$install_dir/target/release/slipstream-server" ]] || die "No se generó slipstream-server."
  fi

  ensure_dir 750 /etc/slipstream
  if [[ ! -s /etc/slipstream/cert.pem || ! -s /etc/slipstream/key.pem ]]; then
    run_cmd openssl req -x509 -nodes -newkey rsa:3072 -days 825 \
      -keyout /etc/slipstream/key.pem -out /etc/slipstream/cert.pem \
      -subj "/CN=$domain/O=HexTunnel"
  fi
  if [[ ! -s /etc/slipstream/reset-seed ]]; then
    [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || openssl rand 32 > /etc/slipstream/reset-seed
  fi
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]]; then
    chown root:hextunnel-slipstream /etc/slipstream /etc/slipstream/cert.pem /etc/slipstream/key.pem /etc/slipstream/reset-seed
    chmod 750 /etc/slipstream
    chmod 644 /etc/slipstream/cert.pem
    chmod 640 /etc/slipstream/key.pem /etc/slipstream/reset-seed
  fi

  write_file /etc/danted.conf 600 <<EOF
logoutput: syslog
internal: 127.0.0.1 port = 1080
external: $external_ip
socksmethod: none
clientmethod: none
client pass {
  from: 127.0.0.1/32 to: 0.0.0.0/0
  log: connect disconnect error
}
socks pass {
  from: 127.0.0.1/32 to: 0.0.0.0/0
  protocol: tcp udp
  log: connect disconnect error
}
EOF

  install_systemd_unit slipstream.service 644 <<EOF
[Unit]
Description=Hex Tunnel SlipStream DNS tunnel
After=network-online.target danted.service
Wants=network-online.target

[Service]
Type=simple
User=hextunnel-slipstream
Group=hextunnel-slipstream
WorkingDirectory=/etc/slipstream
ExecStart=$install_dir/target/release/slipstream-server --dns-listen-port 5300 --target-address 127.0.0.1:1080 --domain $domain --cert /etc/slipstream/cert.pem --key /etc/slipstream/key.pem --reset-seed /etc/slipstream/reset-seed
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ReadOnlyPaths=$install_dir /etc/slipstream
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

  slowdns_set_listener 127.0.0.1 5301
  write_file /etc/dnsdist/dnsdist.conf 600 <<EOF
setLocal('$external_ip:53')
setACL({'0.0.0.0/0', '::/0'})
newServer({address='127.0.0.1:5301', name='slowdns', pool='slowdns'})
newServer({address='127.0.0.1:5300', name='slipstream', pool='slipstream'})
addAction(QNameSuffixRule('$slowdns_ns'), PoolAction('slowdns'))
addAction(QNameSuffixRule('$domain'), PoolAction('slipstream'))
addAction(AllRule(), PoolAction('slowdns'))
EOF

  safe_restart_service danted "danted -V -f /etc/danted.conf >/dev/null 2>&1 || test -s /etc/danted.conf"
  safe_restart_service slipstream "test -x $install_dir/target/release/slipstream-server && runuser -u hextunnel-slipstream -- test -r /etc/slipstream/key.pem && openssl x509 -in /etc/slipstream/cert.pem -noout"
  safe_restart_service dnsdist "dnsdist --check-config -C /etc/dnsdist/dnsdist.conf >/dev/null 2>&1 || dnsdist --check-config >/dev/null 2>&1"
}

slipstream_uninstall() {
  local external_ip
  external_ip="$(primary_ipv4)"
  safe_stop_disable_service dnsdist
  safe_stop_disable_service slipstream
  safe_stop_disable_service danted
  backup_paths /etc/dnsdist/dnsdist.conf /etc/danted.conf /etc/systemd/system/slipstream.service /etc/slipstream
  run_cmd rm -f /etc/dnsdist/dnsdist.conf /etc/danted.conf /etc/systemd/system/slipstream.service
  run_cmd rm -rf /etc/slipstream
  systemd_reload
  slowdns_set_listener "$external_ip" 53
  remove_managed_system_user hextunnel-slipstream
  firewall_close_port udp 53
}

slipstream_validate() {
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  local install_dir="${HEXTUNNEL_SLIPSTREAM_DIR:-/opt/slipstream-rust}"
  [[ -x "$install_dir/target/release/slipstream-server" && -s /etc/dnsdist/dnsdist.conf && -s /etc/slipstream/key.pem ]]
  runuser -u hextunnel-slipstream -- test -r /etc/slipstream/key.pem
  dnsdist --check-config -C /etc/dnsdist/dnsdist.conf >/dev/null 2>&1 || dnsdist --check-config >/dev/null 2>&1
}

slipstream_doctor() {
  local failed=0
  printf 'slipstream=%s dnsdist=%s udp53=' "$(systemctl is-active slipstream 2>/dev/null || true)" "$(systemctl is-active dnsdist 2>/dev/null || true)"
  systemctl is-active --quiet slipstream || failed=1
  systemctl is-active --quiet dnsdist || failed=1
  if port_is_listening udp 53 public; then printf open; else printf closed; failed=1; fi
  printf ' udp5300='
  if port_is_listening udp 5300 any; then printf open; else printf closed; failed=1; fi
  printf '\n'
  return "$failed"
}
