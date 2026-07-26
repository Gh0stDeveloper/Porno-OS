mkdir -p /var/log/xray
if ! /usr/local/bin/xray run -test -config /etc/xray/config.json; then
  echo "Xray configuration validation failed. Review the Xray error printed above."
  exit 1
fi

cat <<EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
After=network.target nss-lookup.target
[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartSec=2
LimitNPROC=10000
LimitNOFILE=1000000
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl disable --now haproxy 2>/dev/null || true
systemctl enable xray
systemctl restart xray

if false; then
mkdir -p /etc/haproxy/certs
install -m 600 /etc/stunnel/stunnel.pem /etc/haproxy/certs/xray.pem
cat <<EOF_HAPROXY > /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    maxconn 100000
    daemon

defaults
    log global
    mode tcp
    option dontlognull
    timeout connect 5s
    timeout client 1h
    timeout client-fin 1h
    timeout server 1h
    timeout tunnel 1h
    timeout http-request 15s

frontend public_tls_443
    bind :443 v4v6 tfo ssl crt /etc/haproxy/certs/xray.pem alpn h2,http/1.1
    mode tcp
    acl negotiated_h2 ssl_fc_alpn -i h2
    acl h2_preface req.payload(0,24) -m bin 505249202a20485454502f322e300d0a0d0a534d0d0a0d0a
    acl h1_vless_xhttp req.payload(0,500) -m reg /xhttp
    acl h1_vless_httpupgrade req.payload(0,500) -m reg /httpupgrade
    acl h1_vless_tcp req.payload(0,500) -m reg /vless-tcp
    acl h1_vless_ws req.payload(0,500) -m reg /vless
    acl clear_ssh req.payload(0,4) -m str SSH-

    # Do not accept generic HTTP as soon as its method is visible. Wait until
    # the complete VLESS path is buffered, otherwise /vless falls through to
    # the generic SSH WebSocket proxy.
    tcp-request inspect-delay 5s
    tcp-request content accept if h2_preface
    tcp-request content accept if h1_vless_xhttp
    tcp-request content accept if h1_vless_httpupgrade
    tcp-request content accept if h1_vless_tcp
    tcp-request content accept if h1_vless_ws
    tcp-request content accept if clear_ssh

    use_backend h2_dispatch if negotiated_h2 h2_preface

    # Specific paths must precede the shorter WebSocket path.
    use_backend vless_xhttp_h1 if h1_vless_xhttp
    use_backend vless_httpupgrade if h1_vless_httpupgrade
    use_backend vless_tcp_http if h1_vless_tcp
    use_backend vless_ws if h1_vless_ws

    use_backend sslh_clear if clear_ssh
    use_backend sslh_clear if HTTP

    default_backend sslh_clear

backend h2_dispatch
    server h2_router 127.0.0.1:10444 send-proxy-v2


frontend h2_router
    bind 127.0.0.1:10444 accept-proxy
    mode http

    # Match specific HTTP/2 transports first.
    use_backend vless_grpc_h2 if { path_beg /grpc-svc }
    use_backend vless_xhttp_h2 if { path_beg /xhttp }
    use_backend vless_httpupgrade if { path_beg /httpupgrade }
    use_backend vless_ws if { path_beg /vless }
    default_backend reject_h2

backend vless_tcp_http
    server xray 127.0.0.1:10007 send-proxy-v2

backend vless_ws
    mode http
    server xray 127.0.0.1:10003 send-proxy-v2

backend vless_httpupgrade
    mode http
    server xray 127.0.0.1:10005 send-proxy-v2

backend vless_xhttp_h1
    server xray 127.0.0.1:10004 send-proxy-v2

backend vless_xhttp_h2
    mode http
    server xray 127.0.0.1:10004 send-proxy-v2 proto h2

backend vless_grpc_h2
    mode http
    server xray 127.0.0.1:10006 send-proxy-v2 proto h2

backend sslh_clear
    server sslh 127.0.0.1:666

backend reject_h2
    mode http
    http-request return status 404
EOF_HAPROXY

if ! haproxy -c -f /etc/haproxy/haproxy.cfg; then
  echo "HAProxy configuration validation failed."
  exit 1
fi

mkdir -p /etc/systemd/system/haproxy.service.d
cat <<'EOF_HAPROXY_UNIT' > /etc/systemd/system/haproxy.service.d/xray-order.conf
[Unit]
After=xray.service network-online.target
Wants=xray.service network-online.target
EOF_HAPROXY_UNIT
systemctl daemon-reload
systemctl enable "$HAPROXY_SERVICE"
systemctl restart "$HAPROXY_SERVICE"
fi

cat <<'EOF_H2_ROUTER' > /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    maxconn 100000
    daemon

defaults
    log global
    mode http
    option dontlognull
    timeout connect 5s
    timeout client 1h
    timeout server 1h
    timeout tunnel 1h

frontend xray_h2_router
    bind 127.0.0.1:10444 accept-proxy proto h2
    mode http
    use_backend vless_grpc_h2 if { path_beg /grpc-svc/ }
    use_backend vmess_grpc_h2 if { path_beg /vmess-grpc-svc/ }
    use_backend vless_xhttp_h2 if { path_beg /xhttp }
    use_backend vmess_xhttp_h2 if { path_beg /vmess-xhttp }
    default_backend reject_h2

backend vless_grpc_h2
    mode http
    server xray 127.0.0.1:10006 send-proxy-v2 proto h2

backend vmess_grpc_h2
    mode http
    server xray 127.0.0.1:10012 send-proxy-v2 proto h2

backend vless_xhttp_h2
    mode http
    server xray 127.0.0.1:10004 send-proxy-v2 proto h2

backend vmess_xhttp_h2
    mode http
    server xray 127.0.0.1:10010 send-proxy-v2 proto h2

backend reject_h2
    mode http
    http-request return status 404
EOF_H2_ROUTER

if ! haproxy -c -f /etc/haproxy/haproxy.cfg; then
  echo "Internal HTTP/2 router validation failed."
  exit 1
fi
mkdir -p /etc/systemd/system/haproxy.service.d
cat <<'EOF_H2_UNIT' > /etc/systemd/system/haproxy.service.d/xray-order.conf
[Unit]
After=xray.service network-online.target
Wants=xray.service network-online.target
EOF_H2_UNIT
systemctl daemon-reload
systemctl enable haproxy
systemctl restart haproxy

# USER EXPIRY CRONJOB FOR XRAY
cat <<'EOF_EXP' > /usr/local/bin/exp-check
#!/bin/bash
set -o pipefail
umask 077
now=$(date +%Y-%m-%d)
CONFIG="/etc/xray/config.json"
[ -s "$CONFIG" ] || exit 0

exec 9>/run/lock/xray-config.lock
flock -w 30 9 || { logger -t xray-exp "Timed out waiting for the Xray config lock"; exit 1; }

work_dir=$(mktemp -d /tmp/xray-exp.XXXXXX) || exit 1
trap 'rm -rf "$work_dir"' EXIT

mapfile -t expired_users < <(
  for proto in vless vmess trojan; do
    db="/etc/xray/${proto}.txt"
    [ -f "$db" ] && awk -v d="$now" '$3 < d {print $1}' "$db"
  done | sort -u
)
[ "${#expired_users[@]}" -gt 0 ] || exit 0

expired_json=$(printf '%s\n' "${expired_users[@]}" | jq -R . | jq -s .) || exit 1
jq --argjson expired "$expired_json" '
  (.inbounds[] | select(((.settings.clients? // null) | type) == "array") | .settings.clients) |=
    map(. as $client | select(($expired | index($client.email)) == null)) |
  (.inbounds[] | select(((.settings.users? // null) | type) == "array") | .settings.users) |=
    map(. as $user | select(($expired | index($user.email)) == null))
' "$CONFIG" > "$work_dir/config.json" || exit 1

if ! /usr/local/bin/xray run -test -config "$work_dir/config.json" >/dev/null 2>&1; then
  logger -t xray-exp "Refusing expiry update: generated Xray config failed validation"
  exit 1
fi

cp -p "$CONFIG" "$work_dir/config.backup" || exit 1
install -m 600 "$work_dir/config.json" "$CONFIG" || exit 1
if ! systemctl restart xray; then
  install -m 600 "$work_dir/config.backup" "$CONFIG"
  systemctl restart xray || true
  logger -t xray-exp "Expiry update rolled back because Xray failed to restart"
  exit 1
fi

for proto in vless vmess trojan; do
  db="/etc/xray/${proto}.txt"
  [ -f "$db" ] || continue
  awk -v d="$now" '$3 >= d {print}' "$db" > "$work_dir/${proto}.txt" || exit 1
  install -m 600 "$work_dir/${proto}.txt" "$db" || exit 1
done
EOF_EXP
chmod +x /usr/local/bin/exp-check
echo "0 0 * * * root /usr/local/bin/exp-check >/dev/null 2>&1" > /etc/cron.d/xray-expiry

# USER EXPIRY CRONJOB FOR HYSTERIA
cat <<'EOF_HYST_EXP' > /usr/local/bin/hysteria-exp
#!/bin/bash
now=$(date +%Y-%m-%d)
USER_DB="/etc/hysteria/users.txt"
CONFIG="/etc/hysteria/config.json"
changed=0

if [ -f "$USER_DB" ]; then
  # Read expired users into an array securely to avoid modifying the file while reading it
  mapfile -t expired_users < <(awk -v d="$now" '$2 < d {print $1}' "$USER_DB")
  
  for user in "${expired_users[@]}"; do
    # Remove from JSON config
    jq ".inbounds[0].users |= map(select(.auth_str != \"$user\"))" "$CONFIG" > /tmp/h.json && mv /tmp/h.json "$CONFIG"
    # Remove from TXT DB
    sed -i "/^$user /d" "$USER_DB"
    changed=1
  done
  
  # Only restart the UDP core if an account was actually scrubbed
  if [ "$changed" -eq 1 ]; then
    systemctl restart hysteria-server
  fi
fi
EOF_HYST_EXP

chmod +x /usr/local/bin/hysteria-exp
echo "0 0 * * * root /usr/local/bin/hysteria-exp >/dev/null 2>&1" > /etc/cron.d/hysteria-expiry

# USER EXPIRY CRONJOB FOR HYSTERIA 2
cat <<'EOF_HYST2_EXP' > /usr/local/bin/hysteria2-exp
#!/bin/bash
now=$(date +%Y-%m-%d)
user_db="/etc/hysteria2/users.txt"
if [ -f "$user_db" ]; then
  exec 9>/run/lock/hysteria2-config.lock
  flock 9
  awk -v d="$now" '$3 >= d' "$user_db" > "${user_db}.tmp" && mv "${user_db}.tmp" "$user_db"
fi
EOF_HYST2_EXP
chmod 755 /usr/local/bin/hysteria2-exp
echo "5 0 * * * root /usr/local/bin/hysteria2-exp >/dev/null 2>&1" > /etc/cron.d/hysteria2-expiry

# USER EXPIRY CRONJOB FOR ZIVPN
cat <<'EOF_ZIVPN_EXP' > /usr/local/bin/zivpn-exp
#!/bin/bash
now=$(date +%Y-%m-%d)
ZIVPN_USER_DB="/etc/zivpn/users.txt"
ZIVPN_CONFIG="/etc/zivpn/config.json"
changed=0
if [ -f "$ZIVPN_USER_DB" ]; then
  mapfile -t expired_users < <(awk -v d="$now" '$2 < d {print $1}' "$ZIVPN_USER_DB")
  for user in "${expired_users[@]}"; do
    jq ".auth.config |= map(select(. != \"$user\"))" "$ZIVPN_CONFIG" > /tmp/z.json && mv /tmp/z.json "$ZIVPN_CONFIG"
    sed -i "/^$user /d" "$ZIVPN_USER_DB"
    changed=1
  done
  if [ "$changed" -eq 1 ]; then
    systemctl restart zivpn.service
  fi
fi
EOF_ZIVPN_EXP
chmod +x /usr/local/bin/zivpn-exp
echo "0 0 * * * root /usr/local/bin/zivpn-exp >/dev/null 2>&1" > /etc/cron.d/zivpn-expiry

# Nginx & Squid
rm -rf /home/vps/public_html /etc/nginx/sites-* /etc/nginx/nginx.conf; mkdir -p /home/vps/public_html
cat <<'myNginxC' > /etc/nginx/nginx.conf
user www-data; worker_processes auto; pid /var/run/nginx.pid;
events { multi_accept on; worker_connections 8192; }
http { gzip on; gzip_vary on; gzip_comp_level 5; gzip_types text/plain application/x-javascript text/xml text/css; autoindex on; sendfile on; tcp_nopush on; tcp_nodelay on; keepalive_timeout 65; types_hash_max_size 2048; server_tokens off; include /etc/nginx/mime.types; default_type application/octet-stream; access_log /var/log/nginx/access.log; error_log /var/log/nginx/error.log; client_max_body_size 32M; client_header_buffer_size 8m; large_client_header_buffers 8 8m; fastcgi_buffer_size 8m; fastcgi_buffers 8 8m; fastcgi_read_timeout 600; include /etc/nginx/conf.d/*.conf; }
myNginxC
cat <<'myvpsC' > /etc/nginx/conf.d/vps.conf
server { listen Nginx_Port; server_name 127.0.0.1 localhost; root /home/vps/public_html; location / { try_files $uri $uri/ /index.php?$args; } }
myvpsC
sed -i "s|Nginx_Port|$Nginx_Port|g" /etc/nginx/conf.d/vps.conf
systemctl restart "$NGINX_SERVICE"

rm -rf /etc/squid/squid.con*
cat <<'mySquid' > /etc/squid/squid.conf
acl server dst IP-ADDRESS/32 localhost
acl ports_ port 14 22 53 21 8081 25 8000 3128 443 80 8080 8880 2082 2086 36712
http_port Squid_Port1
http_port Squid_Port2
http_access allow server
http_access deny all
http_access allow all
visible_hostname IP-ADDRESS
mySquid
sed -i "s|IP-ADDRESS|$IPADDR|g" /etc/squid/squid.conf; sed -i "s|Squid_Port1|$Squid_Port1|g" /etc/squid/squid.conf; sed -i "s|Squid_Port2|$Squid_Port2|g" /etc/squid/squid.conf
systemctl restart "$SQUID_SERVICE"

# Health Checks
mkdir -p /etc/deekayvpn/health
cat <<'ServiceChecker' > /etc/deekayvpn/service_checker.sh
#!/bin/bash
MYID="MYCHATID"; KEY="MYBOTID"; URL="https://api.telegram.org/bot${KEY}/sendMessage"
send_telegram_message() { curl -s --max-time 10 --retry 5 --retry-delay 2 --retry-max-time 10 -d "chat_id=${MYID}&text=$1&disable_web_page_preview=true&parse_mode=markdown" "${URL}" >/dev/null 2>&1; }
server_ip="IPADDRESS"; datenow=$(date +"%Y-%m-%d %T"); IPCOUNTRY=$(curl -s "https://freeipapi.com/api/json/${server_ip}" | jq -r '.countryName')
STATE_DIR="/etc/deekayvpn/health"
check_port() { ss -lnt | awk '{print $4}' | grep -q ":$1$"; }
mark_fail() { local f="$STATE_DIR/$1.fail"; local n=0; [ -f "$f" ] && n=$(cat "$f"); n=$((n+1)); echo "$n" > "$f"; echo "$n"; }
clear_fail() { rm -f "$STATE_DIR/$1.fail"; }
restart_after_3_fails() {
    local fails=$(mark_fail "$1")
    if [ "$fails" -ge 3 ]; then
        systemctl restart "$2" >/dev/null 2>&1
        send_telegram_message "Service *$2* was offline or missing port(s) *$3* on server *${IPCOUNTRY}* ($server_ip). It has been auto-restarted at *${datenow}*."
        clear_fail "$1"
    fi
}
if check_port SSHPORT1 && check_port SSHPORT2 && systemctl is-active --quiet ssh; then clear_fail ssh; else restart_after_3_fails ssh ssh "SSHPORT1,SSHPORT2"; fi
if check_port STUNNELPORT && systemctl is-active --quiet stunnel4; then clear_fail stunnel4; else restart_after_3_fails stunnel4 stunnel4 "STUNNELPORT"; fi
if check_port SSLHPORT && systemctl is-active --quiet sslh; then clear_fail sslh; else restart_after_3_fails sslh sslh "SSLHPORT"; fi
if check_port SQUIDPORT1 && check_port SQUIDPORT2 && systemctl is-active --quiet squid; then clear_fail squid; else restart_after_3_fails squid squid "SQUIDPORT1,SQUIDPORT2"; fi
if check_port NGINXPORT && systemctl is-active --quiet nginx; then clear_fail nginx; else restart_after_3_fails nginx nginx "NGINXPORT"; fi
for port in 10080 25 2082 2086; do if check_port $port && systemctl is-active --quiet ws-proxy@$port; then clear_fail ws-proxy-$port; else restart_after_3_fails ws-proxy-$port ws-proxy@$port "$port"; fi; done
if check_port 443 && systemctl is-active --quiet xray; then clear_fail xray; else restart_after_3_fails xray xray "443, 80"; fi
if systemctl is-active --quiet hysteria-server; then clear_fail hysteria-server; else restart_after_3_fails hysteria-server hysteria-server "UDP"; fi
ServiceChecker

