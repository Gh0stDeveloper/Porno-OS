#!/usr/bin/env bash

slipstream_ports() {
  local address="${HEXTUNNEL_SLIPSTREAM_DNS_ADDRESS:-}" port="${HEXTUNNEL_SLIPSTREAM_DNS_PORT:-53}"
  [[ "$address" == 127.* || "$address" == ::1 ]] && return 0
  printf 'udp %s 0.0.0.0/0 public\n' "$port"
}
slipstream_dependencies() { printf '%s\n' slowdns; }

slipstream_rust_target() {
  case "${HEXTUNNEL_ARCH:-$(normalize_architecture)}" in
    amd64) printf '%s' x86_64-unknown-linux-gnu ;;
    arm64) printf '%s' aarch64-unknown-linux-gnu ;;
    *) return 1 ;;
  esac
}

slipstream_install_rust_toolchain() {
  local root="${HEXTUNNEL_RUST_ROOT:-/opt/hextunnel-rust}"
  local toolchain="${HEXTUNNEL_RUST_TOOLCHAIN:-1.97.0}"
  local target url checksum_url expected actual work rustup_init rustc cargo
  target="$(slipstream_rust_target)" || die "SlipStream no tiene toolchain Rust configurado para ${HEXTUNNEL_ARCH:-$(normalize_architecture)}."
  url="${HEXTUNNEL_RUSTUP_INIT_URL:-https://static.rust-lang.org/rustup/dist/${target}/rustup-init}"
  checksum_url="${HEXTUNNEL_RUSTUP_INIT_SHA256_URL:-${url}.sha256}"
  expected="${HEXTUNNEL_RUSTUP_INIT_SHA256:-}"
  [[ "$toolchain" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Versión Rust inválida: $toolchain"

  if [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]]; then
    log_dry "instalar Rust $toolchain para $target en $root mediante rustup-init verificado"
    return 0
  fi

  work="$(mktemp -d /tmp/hextunnel-rustup.XXXXXX)"
  rustup_init="$work/rustup-init"
  curl -fL --retry 3 --connect-timeout 10 -o "$rustup_init" "$url"
  actual="$(sha256sum "$rustup_init" | awk '{print tolower($1)}')"
  if [[ -z "$expected" ]]; then
    [[ "$url" == https://static.rust-lang.org/* && "$checksum_url" == https://static.rust-lang.org/* ]] \
      || { rm -rf "$work"; die "Un rustup-init no oficial requiere HEXTUNNEL_RUSTUP_INIT_SHA256 explícito."; }
    curl -fL --retry 3 --connect-timeout 10 -o "$work/rustup-init.sha256" "$checksum_url"
    expected="$(awk 'NR==1 {print tolower($1)}' "$work/rustup-init.sha256")"
  fi
  [[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || { rm -rf "$work"; die "Checksum rustup-init inválido."; }
  [[ "$actual" == "${expected,,}" ]] || { rm -rf "$work"; die "El SHA-256 de rustup-init no coincide."; }
  chmod 700 "$rustup_init"

  backup_path "$root"
  rm -rf "$root"
  install -d -m 700 "$root/rustup" "$root/cargo"
  RUSTUP_HOME="$root/rustup" CARGO_HOME="$root/cargo" \
    "$rustup_init" -y --no-modify-path --profile minimal \
      --default-host "$target" --default-toolchain "$toolchain"
  rm -rf "$work"

  rustc="$root/cargo/bin/rustc"
  cargo="$root/cargo/bin/cargo"
  [[ -x "$rustc" && -x "$cargo" ]] || die "El toolchain Rust aislado no instaló rustc y cargo."
  RUSTUP_HOME="$root/rustup" CARGO_HOME="$root/cargo" "$rustc" --version \
    | grep -Fq "rustc $toolchain " \
    || die "El toolchain Rust instalado no corresponde a $toolchain."
}

slipstream_reset_seed_valid() {
  local seed="${1:-/etc/slipstream/reset-seed}"
  [[ -f "$seed" ]] || return 1
  grep -Eq '^[0-9a-f]{32}$' "$seed"
}

slipstream_install() {
  local domain="${HEXTUNNEL_SLIPSTREAM_DOMAIN:-}"
  local slowdns_ns="${HEXTUNNEL_SLOWDNS_NS:-}"
  local install_dir="${HEXTUNNEL_SLIPSTREAM_DIR:-/opt/slipstream-rust}"
  local rust_root="${HEXTUNNEL_RUST_ROOT:-/opt/hextunnel-rust}"
  local commit="${HEXTUNNEL_SLIPSTREAM_COMMIT:-bc772dd07d9a136dbd7553b0da575526de207847}"
  local external_ip dns_address dns_port common_name previous_address previous_port cargo
  if [[ -z "$domain" && "${HEXTUNNEL_NON_INTERACTIVE:-0}" != 1 ]]; then
    read -r -p "Dominio delegado para SlipStream: " domain
  fi
  [[ -n "$domain" && "$domain" =~ ^[A-Za-z0-9.-]+$ ]] || die "HEXTUNNEL_SLIPSTREAM_DOMAIN es obligatorio."
  [[ "$domain" != "$slowdns_ns" ]] || die "SlowDNS y SlipStream deben usar dominios diferentes."
  external_ip="$(primary_ipv4)"
  [[ -n "$external_ip" ]] || die "No se pudo determinar la IP pública para Dante."
  dns_address="${HEXTUNNEL_SLIPSTREAM_DNS_ADDRESS:-$external_ip}"
  dns_port="${HEXTUNNEL_SLIPSTREAM_DNS_PORT:-53}"
  [[ -n "$dns_address" ]] || die "HEXTUNNEL_SLIPSTREAM_DNS_ADDRESS no puede estar vacío."
  [[ "$dns_port" =~ ^[0-9]+$ && "$dns_port" -ge 1 && "$dns_port" -le 65535 ]] || die "Puerto DNSdist inválido: $dns_port"
  common_name="${domain:0:64}"

  run_cmd apt-get update
  run_cmd apt-get install -y git curl build-essential pkg-config libssl-dev dante-server dnsdist openssl ca-certificates
  ensure_system_user hextunnel-slipstream
  backup_paths "$install_dir" "$rust_root" /etc/danted.conf /etc/dnsdist/dnsdist.conf /etc/systemd/system/slipstream.service /etc/slipstream
  slipstream_install_rust_toolchain

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
    cargo="$rust_root/cargo/bin/cargo"
    RUSTUP_HOME="$rust_root/rustup" CARGO_HOME="$rust_root/cargo" \
      "$cargo" build --locked --release -p slipstream-server --manifest-path "$install_dir/Cargo.toml"
    [[ -x "$install_dir/target/release/slipstream-server" ]] || die "No se generó slipstream-server."
  fi

  ensure_dir 750 /etc/slipstream
  if [[ ! -s /etc/slipstream/cert.pem || ! -s /etc/slipstream/key.pem ]]; then
    run_cmd openssl req -x509 -nodes -newkey rsa:3072 -days 825 \
      -keyout /etc/slipstream/key.pem -out /etc/slipstream/cert.pem \
      -subj "/CN=$common_name/O=HexTunnel"
  fi
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]] && ! slipstream_reset_seed_valid; then
    backup_path /etc/slipstream/reset-seed
    openssl rand -hex 16 > /etc/slipstream/reset-seed
  fi
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]]; then
    slipstream_reset_seed_valid || die "SlipStream requiere un reset seed hexadecimal de 32 caracteres."
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

  previous_address="${HEXTUNNEL_SLOWDNS_LISTEN_ADDRESS:-$external_ip}"
  previous_port="${HEXTUNNEL_SLOWDNS_LISTEN_PORT:-53}"
  if [[ -r /etc/default/hextunnel-slowdns ]]; then
    # shellcheck disable=SC1091
    source /etc/default/hextunnel-slowdns
    previous_address="$SLOWDNS_LISTEN_ADDRESS"
    previous_port="$SLOWDNS_LISTEN_PORT"
  fi
  write_file /etc/slipstream/slowdns-listener.env 600 <<EOF
SLOWDNS_RESTORE_ADDRESS=$previous_address
SLOWDNS_RESTORE_PORT=$previous_port
EOF

  slowdns_set_listener 127.0.0.1 5301
  write_file /etc/dnsdist/dnsdist.conf 644 <<EOF
setLocal('$dns_address:$dns_port')
setACL({'0.0.0.0/0', '::/0'})
newServer({address='127.0.0.1:5301', name='slowdns', pool='slowdns'})
newServer({address='127.0.0.1:5300', name='slipstream', pool='slipstream'})
slowdnsSuffixes = newSuffixMatchNode()
slowdnsSuffixes:add(newDNSName('$slowdns_ns'))
slipstreamSuffixes = newSuffixMatchNode()
slipstreamSuffixes:add(newDNSName('$domain'))
addAction(SuffixMatchNodeRule(slowdnsSuffixes), PoolAction('slowdns'))
addAction(SuffixMatchNodeRule(slipstreamSuffixes), PoolAction('slipstream'))
addAction(AllRule(), PoolAction('slowdns'))
EOF

  safe_restart_service danted "danted -V -f /etc/danted.conf >/dev/null 2>&1 || test -s /etc/danted.conf"
  safe_restart_service slipstream "test -x $install_dir/target/release/slipstream-server && runuser -u hextunnel-slipstream -- test -r /etc/slipstream/key.pem && grep -Eq '^[0-9a-f]{32}$' /etc/slipstream/reset-seed && openssl x509 -in /etc/slipstream/cert.pem -noout"
  safe_restart_service dnsdist "dnsdist -C /etc/dnsdist/dnsdist.conf --check-config >/dev/null 2>&1"
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]]; then
    sleep 1
    systemctl is-active --quiet slipstream || die "SlipStream no permaneció activo después del reinicio."
    systemctl is-active --quiet dnsdist || die "DNSdist no permaneció activo después del reinicio."
  fi
}

slipstream_uninstall() {
  local restore_address="${HEXTUNNEL_SLOWDNS_LISTEN_ADDRESS:-$(primary_ipv4)}"
  local restore_port="${HEXTUNNEL_SLOWDNS_LISTEN_PORT:-53}"
  local install_dir="${HEXTUNNEL_SLIPSTREAM_DIR:-/opt/slipstream-rust}"
  local rust_root="${HEXTUNNEL_RUST_ROOT:-/opt/hextunnel-rust}"
  if [[ -r /etc/slipstream/slowdns-listener.env ]]; then
    # shellcheck disable=SC1091
    source /etc/slipstream/slowdns-listener.env
    restore_address="$SLOWDNS_RESTORE_ADDRESS"
    restore_port="$SLOWDNS_RESTORE_PORT"
  fi
  safe_stop_disable_service dnsdist
  safe_stop_disable_service slipstream
  safe_stop_disable_service danted
  backup_paths /etc/dnsdist/dnsdist.conf /etc/danted.conf /etc/systemd/system/slipstream.service /etc/slipstream "$install_dir" "$rust_root"
  run_cmd rm -f /etc/dnsdist/dnsdist.conf /etc/danted.conf /etc/systemd/system/slipstream.service
  run_cmd rm -rf /etc/slipstream "$install_dir" "$rust_root"
  systemd_reload
  slowdns_set_listener "$restore_address" "$restore_port"
  remove_managed_system_user hextunnel-slipstream
  firewall_close_port udp "${HEXTUNNEL_SLIPSTREAM_DNS_PORT:-53}"
}

slipstream_validate() {
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  local install_dir="${HEXTUNNEL_SLIPSTREAM_DIR:-/opt/slipstream-rust}"
  [[ -x "$install_dir/target/release/slipstream-server" && -s /etc/dnsdist/dnsdist.conf && -s /etc/slipstream/key.pem && -s /etc/slipstream/slowdns-listener.env ]]
  runuser -u hextunnel-slipstream -- test -r /etc/slipstream/key.pem
  slipstream_reset_seed_valid
  dnsdist -C /etc/dnsdist/dnsdist.conf --check-config >/dev/null 2>&1
  systemctl is-active --quiet slipstream
  systemctl is-active --quiet dnsdist
}

slipstream_doctor() {
  local failed=0 dns_address="${HEXTUNNEL_SLIPSTREAM_DNS_ADDRESS:-$(primary_ipv4)}" dns_port="${HEXTUNNEL_SLIPSTREAM_DNS_PORT:-53}" scope=public seed=invalid
  [[ "$dns_address" == 127.* || "$dns_address" == ::1 ]] && scope=any
  slipstream_reset_seed_valid && seed=valid || failed=1
  printf 'slipstream=%s dnsdist=%s dns=%s:%s:' "$(systemctl is-active slipstream 2>/dev/null || true)" "$(systemctl is-active dnsdist 2>/dev/null || true)" "$dns_address" "$dns_port"
  systemctl is-active --quiet slipstream || failed=1
  systemctl is-active --quiet dnsdist || failed=1
  if port_is_listening udp "$dns_port" "$scope"; then printf open; else printf closed; failed=1; fi
  printf ' udp5300='
  if port_is_listening udp 5300 any; then printf open; else printf closed; failed=1; fi
  printf ' seed=%s\n' "$seed"
  return "$failed"
}
