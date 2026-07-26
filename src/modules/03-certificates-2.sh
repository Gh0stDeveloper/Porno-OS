chmod 755 /etc/deekayvpn/service_checker.sh
sed -i "s|MYCHATID|$My_Chat_ID|g" /etc/deekayvpn/service_checker.sh
sed -i "s|MYBOTID|$My_Bot_Key|g" /etc/deekayvpn/service_checker.sh
sed -i "s|IPADDRESS|$IPADDR|g" /etc/deekayvpn/service_checker.sh
sed -i "s|STUNNELPORT|$Stunnel_Port_Num|g" /etc/deekayvpn/service_checker.sh
sed -i "s|SSLHPORT|$MainPort|g" /etc/deekayvpn/service_checker.sh
sed -i "s|SQUIDPORT1|$Squid_Port1|g" /etc/deekayvpn/service_checker.sh
sed -i "s|SQUIDPORT2|$Squid_Port2|g" /etc/deekayvpn/service_checker.sh
sed -i "s|NGINXPORT|$Nginx_Port|g" /etc/deekayvpn/service_checker.sh
sed -i "s|SSHPORT1|$SSH_Port1|g" /etc/deekayvpn/service_checker.sh
sed -i "s|SSHPORT2|$SSH_Port2|g" /etc/deekayvpn/service_checker.sh

echo "*/3 * * * * root /bin/bash /etc/deekayvpn/service_checker.sh >/dev/null 2>&1" > /etc/cron.d/service-checker

mkdir -p /etc/deekayvpn 2>/dev/null
touch /etc/deekayvpn/ssh_limits.txt
cat <<'SSHLimitChecker' > /etc/deekayvpn/ssh_limit_checker.sh
#!/bin/bash
DB="/etc/deekayvpn/ssh_limits.txt"
[ -s "$DB" ] || exit 0
while read -r suser slimit; do
  [ -z "$suser" ] && continue
  [[ "$slimit" =~ ^[0-9]+$ ]] || continue
  [ "$slimit" -le 0 ] && continue
  id "$suser" >/dev/null 2>&1 || continue
  mapfile -t sessions < <(ps -u "$suser" -o pid=,etimes=,cmd= 2>/dev/null | awk '$0 ~ /sshd/ {print $1" "$2}')
  count=${#sessions[@]}
  [ "$count" -le "$slimit" ] && continue
  excess=$((count - slimit))
  mapfile -t sorted < <(printf '%s\n' "${sessions[@]}" | sort -k2,2n)
  for ((i=0; i<excess; i++)); do
    pid=$(awk '{print $1}' <<< "${sorted[$i]}")
    [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
  done
done < "$DB"
SSHLimitChecker
chmod 755 /etc/deekayvpn/ssh_limit_checker.sh
echo "* * * * * root /bin/bash /etc/deekayvpn/ssh_limit_checker.sh >/dev/null 2>&1" > /etc/cron.d/ssh-limit-checker
rm -f /etc/logrotate.d/rsyslog
cat <<'logrotate' > /etc/logrotate.d/rsyslog
/var/log/syslog /var/log/kern.log /var/log/auth.log /var/log/xray/access.log /var/log/xray/error.log { rotate 7; daily; missingok; notifempty; compress; delaycompress; sharedscripts; postrotate; /usr/lib/rsyslog/rsyslog-rotate; endscript; }
logrotate
chown root:root /var/log; chmod 755 /var/log; chown syslog:adm /var/log/syslog; chmod 640 /var/log/syslog
echo "*/5 * * * * root /usr/sbin/logrotate -v -f /etc/logrotate.d/rsyslog >/dev/null 2>&1" > /etc/cron.d/logrotate
echo "0 3 * * * root sync; echo 3 > /proc/sys/vm/drop_caches" > /etc/cron.d/drop-cache

# ==========================================
# AGGRESSIVE SYSTEM & CONNTRACK TUNING
# ==========================================
# Force load nf_conntrack module
modprobe nf_conntrack 2>/dev/null || true; echo "nf_conntrack" > /etc/modules-load.d/freenet.conf
cat <<'SYSCTL' > /etc/sysctl.d/99-freenet-tuning.conf
# File Descriptors
fs.file-max = 1048576

# Network Core
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 16384

# TCP Settings
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 10

# SOCKS / WARP Local Loopback Optimization
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_mtu_probing = 1

# Connection Tracking Limits (Prevents silent drops)
net.netfilter.nf_conntrack_max = 2097152
net.netfilter.nf_conntrack_tcp_timeout_established = 1200
net.netfilter.nf_conntrack_udp_timeout = 60
SYSCTL
sysctl --system || true
mkdir -p /etc/security/limits.d
cat <<'LIMITS' > /etc/security/limits.d/99-freenet.conf
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
LIMITS

# SLOWDNS
rm -rf /etc/slowdns; mkdir -m 777 /etc/slowdns
cat > /etc/slowdns/server.key << END
$Serverkey
END
cat > /etc/slowdns/server.pub << END
$Serverpub
END
wget -q -O /etc/slowdns/sldns-server "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server"
chmod +x /etc/slowdns/server.key /etc/slowdns/server.pub /etc/slowdns/sldns-server
iptables -C INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 53 -j ACCEPT

if [ "$InstallSlipstream" = "y" ]; then
  SlowDNS_Listen="127.0.0.1:$SlowDNS_Internal_Port"
else
  SlowDNS_Listen=":53"
fi
cat > /etc/systemd/system/server-sldns.service << END
[Unit]
Description=Server SlowDNS
After=network.target
[Service]
ExecStart=/etc/slowdns/sldns-server -udp $SlowDNS_Listen -privkey-file /etc/slowdns/server.key $Nameserver 127.0.0.1:$SSH_Port2
Restart=on-failure
[Install]
WantedBy=multi-user.target
END
systemctl daemon-reload; systemctl enable server-sldns; systemctl restart server-sldns

# === SLIPSTREAM (segundo túnel DNS) + DANTE SOCKS + DNSDIST (multiplexor en :53) — OPCIONAL ===
if [ "$InstallSlipstream" = "y" ]; then

# Dante SOCKS: backend genérico al que Slipstream reenvía el tráfico ya desencriptado
command -v danted >/dev/null 2>&1 || apt-get install -y dante-server
EXT_IP="$(ip -4 addr show scope global 2>/dev/null | awk '/inet/{print $2}' | cut -d/ -f1 | head -1)"
[ -z "$EXT_IP" ] && EXT_IP="$(curl -s --max-time 5 ifconfig.me 2>/dev/null)"
cat > /etc/danted.conf <<DANTE_EOF
logoutput: syslog

internal: 127.0.0.1 port = ${SlipstreamSocksPort}
external: ${EXT_IP}

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
DANTE_EOF
systemctl restart danted; systemctl enable danted >/dev/null 2>&1

# Rust (necesario para compilar slipstream-server)
if ! command -v cargo &>/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y >/dev/null 2>&1
  source "$HOME/.cargo/env"
else
  source "$HOME/.cargo/env" 2>/dev/null || true
fi

# Clonar y compilar slipstream-server (commit fijado)
if [ -d "$SlipstreamInstallDir/.git" ]; then
  cd "$SlipstreamInstallDir"
else
  rm -rf "$SlipstreamInstallDir"
  git clone --quiet https://github.com/Mygod/slipstream-rust.git "$SlipstreamInstallDir"
  cd "$SlipstreamInstallDir"
fi
git fetch --quiet origin
git checkout --quiet "$SlipstreamPinnedCommit"
git submodule update --init --recursive --quiet
cargo build --release -p slipstream-server --quiet 2>&1
cd /root

# Servicio systemd de Slipstream, reenviando a Dante SOCKS en vez de SSH directo
cat > /etc/systemd/system/slipstream.service <<SLIPSTREAM_EOF
[Unit]
Description=Slipstream DNS Tunnel Server
After=network.target danted.service

[Service]
Type=simple
ExecStart=${SlipstreamInstallDir}/target/release/slipstream-server \\
    --dns-listen-port ${Slipstream_Internal_Port} \\
    --target-address 127.0.0.1:${SlipstreamSocksPort} \\
    --domain ${SlipstreamDomain} \\
    --cert ${SlipstreamInstallDir}/cert.pem \\
    --key ${SlipstreamInstallDir}/key.pem \\
    --reset-seed ${SlipstreamInstallDir}/reset-seed
WorkingDirectory=${SlipstreamInstallDir}
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SLIPSTREAM_EOF
systemctl daemon-reload; systemctl enable slipstream >/dev/null 2>&1; systemctl restart slipstream

# dnsdist: multiplexor público en :53, reenvía por dominio hacia SlowDNS y Slipstream
command -v dnsdist >/dev/null 2>&1 || apt-get install -y dnsdist
mkdir -p "$(dirname "$DnsdistConf")"
cat > "$DnsdistConf" <<DNSDIST_EOF
setLocal("0.0.0.0:53")

newServer({address="127.0.0.1:${SlowDNS_Internal_Port}", name="slowdns"})
newServer({address="127.0.0.1:${Slipstream_Internal_Port}", name="slipstream"})

addAction(SuffixMatchNodeRule("${Nameserver}."), PoolAction("slowdns_pool"))
setPoolServers("slowdns_pool", {getServer(0)})

addAction(SuffixMatchNodeRule("${SlipstreamDomain}."), PoolAction("slipstream_pool"))
setPoolServers("slipstream_pool", {getServer(1)})

addAction(AllRule(), DropAction())
DNSDIST_EOF
systemctl daemon-reload; systemctl enable dnsdist >/dev/null 2>&1; systemctl restart dnsdist

fi
# === FIN BLOQUE SLIPSTREAM OPCIONAL ===


# === HYSTERIA v1 (Sing-box v1.12.22) & CLOUDFLARE WARP ===
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
apt-get update && apt-get install -y cloudflare-warp

warp-cli --accept-tos disconnect 2>/dev/null || true
warp-cli --accept-tos registration delete 2>/dev/null || true
warp-cli --accept-tos registration new 2>/dev/null || warp-cli --accept-tos register
warp-cli --accept-tos mode proxy
warp-cli --accept-tos proxy port 40000
warp-cli --accept-tos connect
sleep 2

wget -qO /tmp/sing-box.deb "https://github.com/SagerNet/sing-box/releases/download/v1.12.22/sing-box_1.12.22_linux_amd64.deb"
dpkg -i /tmp/sing-box.deb
apt-mark hold sing-box
rm -f /tmp/sing-box.deb

mkdir -p /etc/hysteria
HYST_PORT="${UDP_PORT##*:}"

# Reuse the per-server Xray certificate instead of a shared embedded key.
rm -f /etc/hysteria/hysteria.crt /etc/hysteria/hysteria.key
ln -s /etc/xray/xray.crt /etc/hysteria/hysteria.crt
ln -s /etc/xray/xray.key /etc/hysteria/hysteria.key
cat > /etc/hysteria/config.json <<EOF
{
  "log": { "level": "fatal" },
  "inbounds": [
    {
      "type": "hysteria",
      "tag": "hy1-inbound",
      "listen": "::",
      "listen_port": $HYST_PORT,
      "up_mbps": 100, "down_mbps": 100,
      "obfs": "$OBFS",
      "users": [ { "auth_str": "$PASSWORD" } ],
      "tls": { "enabled": true, "certificate_path": "/etc/hysteria/hysteria.crt", "key_path": "/etc/hysteria/hysteria.key" }
    }
  ],
  "outbounds": [
    { "type": "socks", "tag": "warp-proxy", "server": "127.0.0.1", "server_port": 40000 },
    { "type": "direct", "tag": "direct" },
    { "type": "block", "tag": "block" }
  ],
  "route": {
    "rules": [
      {
        "inbound": "hy1-inbound",
        "network": "udp",
        "domain_suffix": [ "doubleclick.net", "googlesyndication.com", "googleadservices.com", "admob.com", "google-analytics.com", "app-measurement.com", "adservice.google.com", "g.doubleclick.net", "google.com", "pagead2.googlesyndication.com", "tpc.googlesyndication.com", "googlevideo.com", "gvt1.com", "gvt2.com", "gvt3.com", "ytimg.com", "youtube.com", "gstatic.com", "googleusercontent.com", "ggpht.com", "play.google.com", "firebaseio.com", "firebase.googleapis.com", "crashlytics.com", "fundingchoicesmessages.google.com", "imasdk.googleapis.com", "googleanalytics.com", "analytics.google.com", "fcm.googleapis.com", "mtalk.google.com", "firebaseinstallations.googleapis.com", "firebaselogging.googleapis.com", "firebaselogging-pa.googleapis.com", "firebaseremoteconfig.googleapis.com", "googleadapis.com", "accounts.google.com", "play.googleapis.com", "android.apis.google.com", "adsense.com", "1e100.net" ],
        "outbound": "block"
      },
      {
        "inbound": "hy1-inbound",
        "domain_suffix": [ "doubleclick.net", "googlesyndication.com", "googleadservices.com", "admob.com", "google-analytics.com", "app-measurement.com", "adservice.google.com", "g.doubleclick.net", "google.com", "pagead2.googlesyndication.com", "tpc.googlesyndication.com", "googlevideo.com", "gvt1.com", "gvt2.com", "gvt3.com", "ytimg.com", "youtube.com", "gstatic.com", "googleusercontent.com", "ggpht.com", "play.google.com", "firebaseio.com", "firebase.googleapis.com", "crashlytics.com", "fundingchoicesmessages.google.com", "imasdk.googleapis.com", "googleanalytics.com", "analytics.google.com", "fcm.googleapis.com", "mtalk.google.com", "firebaseinstallations.googleapis.com", "firebaselogging.googleapis.com", "firebaselogging-pa.googleapis.com", "firebaseremoteconfig.googleapis.com", "googleadapis.com", "accounts.google.com", "play.googleapis.com", "android.apis.google.com", "adsense.com", "1e100.net" ],
        "outbound": "warp-proxy"
      },
      { "inbound": "hy1-inbound", "outbound": "direct" }
    ],
    "auto_detect_interface": true
  }
}
EOF

chmod 755 /etc/hysteria/config.json /etc/hysteria/hysteria.crt /etc/hysteria/hysteria.key
echo "$PASSWORD $(date -d "+365 days" +"%Y-%m-%d")" > /etc/hysteria/users.txt

cat > /etc/systemd/system/hysteria-server.service <<EOF
[Unit]
Description=Sing-Box Hysteria v1 Core
After=network.target
[Service]
User=root
ExecStart=/usr/bin/sing-box run -c /etc/hysteria/config.json
Restart=on-failure
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload; systemctl enable hysteria-server.service; systemctl start hysteria-server.service

# NAT & Iptables Configuration
IFACE="$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)"
cat > /etc/systemd/system/hysteria-nat.service <<EOF
[Unit]
Description=Restore Hysteria UDP NAT rules
After=network-online.target
Wants=network-online.target
Before=hysteria-server.service
[Service]
Type=oneshot
ExecStart=/bin/bash -c 'IFACE=\$(ip -4 route ls|grep default|grep -Po "(?<=dev )(\\\\S+)"|head -1); [ -n "\$IFACE" ] && (iptables -t nat -C PREROUTING -i "\$IFACE" -p udp --dport 20000:50000 -j DNAT --to-destination :$HYST_PORT 2>/dev/null || iptables -t nat -A PREROUTING -i "\$IFACE" -p udp --dport 20000:50000 -j DNAT --to-destination :$HYST_PORT)'
ExecStart=/bin/bash -c 'iptables -C INPUT -p udp --dport $HYST_PORT -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport $HYST_PORT -j ACCEPT'
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload; systemctl enable hysteria-nat.service; systemctl start hysteria-nat.service

# === HYSTERIA 2 (official core, separate from Hysteria v1) ===
HYSTERIA2_VER="app/v2.9.3"
case "$(uname -m)" in
  x86_64|amd64) HYSTERIA2_ASSET="hysteria-linux-amd64" ;;
  i386|i486|i586|i686) HYSTERIA2_ASSET="hysteria-linux-386" ;;
  aarch64|arm64) HYSTERIA2_ASSET="hysteria-linux-arm64" ;;
  armv7l|armv7*) HYSTERIA2_ASSET="hysteria-linux-arm" ;;
  *) echo "Unsupported Hysteria 2 architecture: $(uname -m)"; exit 1 ;;
esac

HYSTERIA2_RELEASE_URL="https://github.com/apernet/hysteria/releases/download/${HYSTERIA2_VER}"
hyst2_tmp=$(mktemp -d /tmp/hysteria2-install.XXXXXX) || exit 1
if ! curl -fL --retry 3 -o "$hyst2_tmp/$HYSTERIA2_ASSET" "$HYSTERIA2_RELEASE_URL/$HYSTERIA2_ASSET" ||
   ! curl -fL --retry 3 -o "$hyst2_tmp/hashes.txt" "$HYSTERIA2_RELEASE_URL/hashes.txt"; then
  rm -rf "$hyst2_tmp"
  echo "Hysteria 2 download failed."
  exit 1
fi
hyst2_expected=$(awk -v asset="$HYSTERIA2_ASSET" '$2 == asset || $2 == "build/" asset || $2 == "*" asset {print tolower($1); exit}' "$hyst2_tmp/hashes.txt")
hyst2_actual=$(sha256sum "$hyst2_tmp/$HYSTERIA2_ASSET" | awk '{print tolower($1)}')
if [ -z "$hyst2_expected" ] || [ "$hyst2_actual" != "$hyst2_expected" ]; then
  rm -rf "$hyst2_tmp"
  echo "Hysteria 2 SHA-256 verification failed."
  exit 1
fi
install -m 755 "$hyst2_tmp/$HYSTERIA2_ASSET" /usr/local/bin/hysteria2
rm -rf "$hyst2_tmp"

mkdir -p /etc/hysteria2
mkdir -p /usr/local/libexec
cat <<'EOF_HYST2_AUTH' > /usr/local/libexec/hysteria2-auth
#!/bin/bash
user_db="/etc/hysteria2/users.txt"
auth="$2"
[ -n "$auth" ] && [ -r "$user_db" ] || exit 1
awk -v token="$auth" '$2 == token {print $1; found=1; exit} END {exit !found}' "$user_db"
EOF_HYST2_AUTH
chmod 700 /usr/local/libexec/hysteria2-auth

HYST2_INITIAL_TOKEN=$(cat /proc/sys/kernel/random/uuid)
jq -n \
  --arg listen ":$HYST2_PORT" \
  --arg cert "/etc/xray/xray.crt" \
  --arg key "/etc/xray/xray.key" \
  --arg obfs "$OBFS" '
  {
    listen: $listen,
    tls: {cert: $cert, key: $key},
    auth: {type: "command", command: "/usr/local/libexec/hysteria2-auth"},
    obfs: {type: "salamander", salamander: {password: $obfs}},
    masquerade: {
      type: "proxy",
      proxy: {url: "https://www.microsoft.com/", rewriteHost: true}
    }
  }
' > /etc/hysteria2/config.json
chmod 600 /etc/hysteria2/config.json
printf 'default %s %s\n' "$HYST2_INITIAL_TOKEN" "$(date -d '+365 days' +%Y-%m-%d)" > /etc/hysteria2/users.txt
chmod 600 /etc/hysteria2/users.txt

