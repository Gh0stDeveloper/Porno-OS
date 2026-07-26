#!/usr/bin/env bash

xray_ports() {
  cat <<'EOF'
tcp 443
tcp 80
tcp 8080
tcp 8880
EOF
}
xray_dependencies() { printf '%s\n' ssh; }

xray_asset_name() {
  case "${HEXTUNNEL_ARCH:-$(normalize_architecture)}" in
    amd64) printf 'Xray-linux-64.zip' ;;
    386) printf 'Xray-linux-32.zip' ;;
    arm64) printf 'Xray-linux-arm64-v8a.zip' ;;
    arm) printf 'Xray-linux-arm32-v7a.zip' ;;
    *) return 1 ;;
  esac
}

xray_install_verified_binary() {
  local version="${HEXTUNNEL_XRAY_VERSION:-v26.3.27}" asset tmp base expected actual
  asset="$(xray_asset_name)" || die "Arquitectura Xray no soportada."
  tmp="$(mktemp -d /tmp/hextunnel-xray.XXXXXX)"
  base="https://github.com/XTLS/Xray-core/releases/download/${version}/${asset}"
  run_cmd curl -fL --retry 3 -o "$tmp/xray.zip" "$base"
  run_cmd curl -fL --retry 3 -o "$tmp/xray.zip.dgst" "$base.dgst"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && { rm -rf "$tmp"; return 0; }
  expected="$(awk -F'= *' 'toupper($1) == "SHA2-256" {print tolower($2); exit}' "$tmp/xray.zip.dgst")"
  actual="$(sha256sum "$tmp/xray.zip" | awk '{print tolower($1)}')"
  [[ -n "$expected" && "$actual" == "$expected" ]] || { rm -rf "$tmp"; die "La verificación SHA-256 de Xray falló."; }
  unzip -q "$tmp/xray.zip" -d "$tmp/unpacked"
  [[ -f "$tmp/unpacked/xray" ]] || { rm -rf "$tmp"; die "El archivo Xray no contiene el binario."; }
  backup_paths /usr/local/bin/xray /usr/local/share/xray/geoip.dat /usr/local/share/xray/geosite.dat
  install -d -m 755 /usr/local/share/xray
  install -m 755 "$tmp/unpacked/xray" /usr/local/bin/xray.new
  [[ -f "$tmp/unpacked/geoip.dat" ]] && install -m 644 "$tmp/unpacked/geoip.dat" /usr/local/share/xray/geoip.dat
  [[ -f "$tmp/unpacked/geosite.dat" ]] && install -m 644 "$tmp/unpacked/geosite.dat" /usr/local/share/xray/geosite.dat
  if [[ -s /etc/xray/config.json ]]; then
    /usr/local/bin/xray.new run -test -config /etc/xray/config.json \
      || { rm -f /usr/local/bin/xray.new; rm -rf "$tmp"; die "La versión descargada rechazó la configuración Xray actual."; }
  fi
  mv -f /usr/local/bin/xray.new /usr/local/bin/xray
  rm -rf "$tmp"
}

xray_install_grpc_router() {
  run_cmd apt-get install -y haproxy
  backup_paths /etc/hextunnel/haproxy-xray.cfg /etc/systemd/system/hextunnel-haproxy.service
  write_file /etc/hextunnel/haproxy-xray.cfg 644 <<'EOF'
global
  log /dev/log local0
  maxconn 4096
  user haproxy
  group haproxy

  ssl-default-bind-options ssl-min-ver TLSv1.2

defaults
  log global
  mode http
  option httplog
  timeout connect 5s
  timeout client 1h
  timeout server 1h

frontend xray-grpc-router
  bind 127.0.0.1:10444 accept-proxy proto h2
  acl is_vless_grpc path_beg /grpc-svc
  acl is_vmess_grpc path_beg /vmess-grpc-svc
  use_backend vless-grpc if is_vless_grpc
  use_backend vmess-grpc if is_vmess_grpc
  http-request deny deny_status 404

backend vless-grpc
  mode http
  server vless 127.0.0.1:10006 proto h2 send-proxy-v2 check

backend vmess-grpc
  mode http
  server vmess 127.0.0.1:10012 proto h2 send-proxy-v2 check
EOF
  install_systemd_unit hextunnel-haproxy.service 644 <<'EOF'
[Unit]
Description=Hex Tunnel internal Xray gRPC router
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/sbin/haproxy -Ws -f /etc/hextunnel/haproxy-xray.cfg -p /run/hextunnel-haproxy.pid
ExecReload=/usr/sbin/haproxy -Ws -f /etc/hextunnel/haproxy-xray.cfg -p /run/hextunnel-haproxy.pid -sf $MAINPID
Restart=on-failure
RestartSec=2s
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadOnlyPaths=/etc/hextunnel/haproxy-xray.cfg
RuntimeDirectory=hextunnel-haproxy
RuntimeDirectoryMode=0750

[Install]
WantedBy=multi-user.target
EOF
  safe_restart_service hextunnel-haproxy "haproxy -c -f /etc/hextunnel/haproxy-xray.cfg"
}

xray_install_expiry_job() {
  write_file /usr/local/sbin/hextunnel-xray-expire 700 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
now="$(date +%Y-%m-%d)"
config=/etc/xray/config.json
[[ -s "$config" ]] || exit 0
exec 9>/run/lock/hextunnel-xray.lock
flock -w 30 9
work="$(mktemp -d /tmp/hextunnel-xray-expire.XXXXXX)"
trap 'rm -rf "$work"' EXIT
mapfile -t expired < <(for protocol in vless vmess trojan; do file="/etc/xray/${protocol}.txt"; [[ -f "$file" ]] && awk -v today="$now" '$3 < today {print $1}' "$file"; done | sort -u)
((${#expired[@]} > 0)) || exit 0
expired_json="$(printf '%s\n' "${expired[@]}" | jq -R . | jq -s .)"
jq --argjson expired "$expired_json" '
  (.inbounds[] | select(((.settings.clients? // null) | type) == "array") | .settings.clients) |= map(. as $client | select(($expired | index($client.email)) == null)) |
  (.inbounds[] | select(((.settings.users? // null) | type) == "array") | .settings.users) |= map(. as $user | select(($expired | index($user.email)) == null))
' "$config" > "$work/config.json"
/usr/local/bin/xray run -test -config "$work/config.json"
cp -p "$config" "$work/config.backup"
install -m 600 "$work/config.json" "$config"
if ! systemctl restart xray; then
  install -m 600 "$work/config.backup" "$config"
  systemctl restart xray || true
  exit 1
fi
for protocol in vless vmess trojan; do
  file="/etc/xray/${protocol}.txt"
  [[ -f "$file" ]] || continue
  awk -v today="$now" '$3 >= today' "$file" > "$work/${protocol}.txt"
  install -m 600 "$work/${protocol}.txt" "$file"
done
EOF
  write_file /etc/cron.d/hextunnel-xray-expiry 644 <<'EOF'
7 0 * * * root /usr/local/sbin/hextunnel-xray-expire >/dev/null 2>&1
EOF
}

xray_install() {
  run_cmd apt-get update
  run_cmd apt-get install -y curl unzip jq ca-certificates util-linux
  ensure_dir 700 /etc/xray
  ensure_dir 750 /var/log/xray
  xray_install_verified_binary
  backup_paths /etc/xray/config.json /etc/systemd/system/xray.service /etc/xray/vless.txt /etc/xray/vmess.txt /etc/xray/trojan.txt
  if [[ ! -s /etc/xray/config.json || "${HEXTUNNEL_FORCE:-0}" == 1 ]]; then
    [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || install -m 600 "$HEXTUNNEL_ROOT/templates/xray/config.json" /etc/xray/config.json
  fi
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || {
    touch /etc/xray/vless.txt /etc/xray/vmess.txt /etc/xray/trojan.txt
    chmod 600 /etc/xray/vless.txt /etc/xray/vmess.txt /etc/xray/trojan.txt
  }
  xray_install_grpc_router
  install_systemd_unit xray.service 644 <<'EOF'
[Unit]
Description=Hex Tunnel Xray Core
After=network-online.target hextunnel-haproxy.service
Wants=network-online.target hextunnel-haproxy.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartSec=2s
LimitNOFILE=1048576
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=full
ReadWritePaths=/etc/xray /var/log/xray
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
  xray_install_expiry_job
  safe_restart_service xray "/usr/local/bin/xray run -test -config /etc/xray/config.json"
}

xray_uninstall() {
  safe_stop_disable_service xray
  safe_stop_disable_service hextunnel-haproxy
  backup_paths /etc/systemd/system/xray.service /etc/systemd/system/hextunnel-haproxy.service /etc/hextunnel/haproxy-xray.cfg /etc/cron.d/hextunnel-xray-expiry /usr/local/sbin/hextunnel-xray-expire /usr/local/bin/xray /etc/xray
  run_cmd rm -f /etc/systemd/system/xray.service /etc/systemd/system/hextunnel-haproxy.service /etc/hextunnel/haproxy-xray.cfg /etc/cron.d/hextunnel-xray-expiry /usr/local/sbin/hextunnel-xray-expire /usr/local/bin/xray
  run_cmd rm -rf /etc/xray
  systemd_reload
  local port
  for port in 443 80 8080 8880; do firewall_close_port tcp "$port"; done
}

xray_validate() {
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  [[ -x /usr/local/bin/xray ]] || return 1
  /usr/local/bin/xray run -test -config /etc/xray/config.json
  haproxy -c -f /etc/hextunnel/haproxy-xray.cfg >/dev/null
}

xray_doctor() {
  local failed=0
  printf 'service=%s grpc-router=%s version=' \
    "$(systemctl is-active xray 2>/dev/null || true)" \
    "$(systemctl is-active hextunnel-haproxy 2>/dev/null || true)"
  systemctl is-active --quiet xray || failed=1
  systemctl is-active --quiet hextunnel-haproxy || failed=1
  /usr/local/bin/xray version 2>/dev/null | head -n1 || { printf 'not-installed'; failed=1; }
  printf ' config='
  if /usr/local/bin/xray run -test -config /etc/xray/config.json >/dev/null 2>&1; then printf valid; else printf invalid; failed=1; fi
  printf ' haproxy='
  if haproxy -c -f /etc/hextunnel/haproxy-xray.cfg >/dev/null 2>&1; then printf valid; else printf invalid; failed=1; fi
  printf '\n'
  return "$failed"
}
