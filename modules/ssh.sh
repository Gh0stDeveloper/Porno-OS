#!/usr/bin/env bash

ssh_ports() {
  cat <<'EOF'
tcp 22
tcp 299
tcp 4443
tcp 25
tcp 2082
tcp 2086
tcp 10080
EOF
}
ssh_dependencies() { :; }
ssh_allow_port_conflict() {
  local protocol="$1" port="$2" owner="$3"
  [[ "$protocol" == tcp && "$port" == 22 && "$owner" == *sshd* ]]
}

ssh_install_packages() {
  run_cmd apt-get update
  run_cmd apt-get install -y openssh-server stunnel4 sslh nodejs openssl ca-certificates fail2ban
}

ssh_ensure_certificate() {
  ensure_dir 700 /etc/xray
  if [[ -s /etc/xray/xray.crt && -s /etc/xray/xray.key ]]; then return 0; fi
  backup_paths /etc/xray/xray.crt /etc/xray/xray.key
  local subject="/CN=${HEXTUNNEL_DOMAIN:-$(hostname -f 2>/dev/null || hostname)}/O=HexTunnel"
  run_cmd openssl req -x509 -nodes -days 825 -newkey rsa:3072 \
    -keyout /etc/xray/xray.key -out /etc/xray/xray.crt -subj "$subject"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || chmod 600 /etc/xray/xray.key
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || chmod 644 /etc/xray/xray.crt
}

ssh_install_session_limiter() {
  ensure_dir 700 /etc/hextunnel
  [[ -f /etc/hextunnel/ssh-limits.tsv || "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || {
    touch /etc/hextunnel/ssh-limits.tsv
    chmod 600 /etc/hextunnel/ssh-limits.tsv
  }
  write_file /usr/local/sbin/hextunnel-ssh-limit 700 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
limits=/etc/hextunnel/ssh-limits.tsv
[[ -s "$limits" ]] || exit 0
exec 9>/run/lock/hextunnel-ssh-limit.lock
flock -n 9 || exit 0
while IFS=$'\t ' read -r username maximum _; do
  [[ -n "$username" && "$username" != \#* && "$maximum" =~ ^[0-9]+$ && "$maximum" -gt 0 ]] || continue
  id "$username" >/dev/null 2>&1 || continue
  mapfile -t sessions < <(
    ps -eo pid=,etimes=,user=,comm=,args= \
      | awk -v user="$username" '$3 == user && $4 == "sshd" {print $1 " " $2}' \
      | sort -k2,2nr
  )
  count=${#sessions[@]}
  ((count > maximum)) || continue
  excess=$((count - maximum))
  for ((index=0; index<excess; index++)); do
    pid="${sessions[$index]%% *}"
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -TERM "$pid" 2>/dev/null || true
  done
done < "$limits"
EOF
  install_systemd_unit hextunnel-ssh-limit.service 644 <<'EOF'
[Unit]
Description=Enforce Hex Tunnel SSH per-user session limits
After=ssh.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/hextunnel-ssh-limit
User=root
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadOnlyPaths=/etc/hextunnel/ssh-limits.tsv
EOF
  install_systemd_unit hextunnel-ssh-limit.timer 644 <<'EOF'
[Unit]
Description=Run Hex Tunnel SSH session limiter

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
AccuracySec=10s
Persistent=true

[Install]
WantedBy=timers.target
EOF
  safe_restart_service hextunnel-ssh-limit.timer
}

ssh_install_fail2ban() {
  write_file /etc/fail2ban/jail.d/hextunnel-sshd.local 644 <<EOF
[sshd]
enabled = true
backend = systemd
port = 22,299
maxretry = ${HEXTUNNEL_SSH_MAX_RETRIES:-5}
findtime = ${HEXTUNNEL_SSH_FIND_TIME:-600}
bantime = ${HEXTUNNEL_SSH_BAN_TIME:-3600}
ignoreip = 127.0.0.1/8 ::1 ${HEXTUNNEL_ADMIN_IP:-}
EOF
  safe_restart_service fail2ban "fail2ban-client -t"
}

ssh_install() {
  ssh_install_packages
  ssh_ensure_certificate
  backup_paths \
    /etc/ssh/sshd_config.d/90-hextunnel.conf \
    /etc/stunnel/hextunnel.conf \
    /etc/default/stunnel4 \
    /etc/default/sslh \
    /etc/systemd/system/ws-proxy@.service \
    /etc/socksproxy/proxy.js

  local permit_root="prohibit-password"
  [[ "${HEXTUNNEL_ALLOW_ROOT_PASSWORD:-0}" == 1 ]] && permit_root=yes
  write_file /etc/ssh/sshd_config.d/90-hextunnel.conf 600 <<EOF
# Managed by Hex Tunnel. Local changes belong in another drop-in.
Port 22
Port 299
PermitRootLogin $permit_root
PasswordAuthentication yes
KbdInteractiveAuthentication no
UsePAM yes
X11Forwarding no
AllowTcpForwarding yes
GatewayPorts no
ClientAliveInterval 120
ClientAliveCountMax 2
MaxAuthTries 4
LoginGraceTime 30
Subsystem sftp internal-sftp
EOF

  write_file /etc/stunnel/hextunnel.conf 600 <<'EOF'
pid = /run/stunnel4/hextunnel.pid
cert = /etc/xray/xray.crt
key = /etc/xray/xray.key
client = no
foreground = no
setuid = stunnel4
setgid = stunnel4
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
[sslh]
accept = 0.0.0.0:4443
connect = 127.0.0.1:666
EOF

  write_file /etc/default/stunnel4 644 <<'EOF'
ENABLED=1
FILES="/etc/stunnel/*.conf"
OPTIONS=""
PPP_RESTART=0
EOF

  write_file /etc/default/sslh 644 <<'EOF'
RUN=yes
DAEMON=/usr/sbin/sslh
DAEMON_OPTS="--user sslh --listen 127.0.0.1:666 --ssh 127.0.0.1:22 --http 127.0.0.1:10080 --pidfile /run/sslh/sslh.pid"
EOF

  ensure_dir 755 /etc/socksproxy
  write_file /etc/socksproxy/proxy.js 644 <<'EOF'
'use strict';
const net = require('net');
const port = Number.parseInt(process.argv[2], 10);
if (!Number.isInteger(port) || port < 1 || port > 65535) process.exit(64);
const server = net.createServer((client) => {
  client.once('data', () => {
    const target = net.connect(22, '127.0.0.1', () => {
      client.write('HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n');
      client.pipe(target);
      target.pipe(client);
    });
    target.on('error', () => client.destroy());
  });
  client.on('error', () => {});
});
server.listen(port, '0.0.0.0');
EOF

  install_systemd_unit ws-proxy@.service 644 <<'EOF'
[Unit]
Description=Hex Tunnel TCP upgrade proxy on port %i
After=network-online.target ssh.service
Wants=network-online.target

[Service]
Type=simple
User=nobody
Group=nogroup
WorkingDirectory=/etc/socksproxy
ExecStart=/usr/bin/node /etc/socksproxy/proxy.js %i
Restart=on-failure
RestartSec=2s
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

  safe_restart_service ssh "sshd -t"
  safe_restart_service stunnel4 "openssl x509 -in /etc/xray/xray.crt -noout && test -s /etc/stunnel/hextunnel.conf"
  safe_restart_service sslh "test -s /etc/default/sslh"
  local port
  for port in 25 2082 2086 10080; do safe_restart_service "ws-proxy@$port"; done
  ssh_install_fail2ban
  ssh_install_session_limiter
}

ssh_uninstall() {
  local path port
  for port in 25 2082 2086 10080; do safe_stop_disable_service "ws-proxy@$port"; done
  safe_stop_disable_service hextunnel-ssh-limit.timer
  safe_stop_disable_service fail2ban
  safe_stop_disable_service stunnel4
  safe_stop_disable_service sslh
  for path in \
    /etc/ssh/sshd_config.d/90-hextunnel.conf \
    /etc/stunnel/hextunnel.conf \
    /etc/default/stunnel4 \
    /etc/default/sslh \
    /etc/systemd/system/ws-proxy@.service \
    /etc/socksproxy/proxy.js \
    /etc/fail2ban/jail.d/hextunnel-sshd.local \
    /usr/local/sbin/hextunnel-ssh-limit \
    /etc/systemd/system/hextunnel-ssh-limit.service \
    /etc/systemd/system/hextunnel-ssh-limit.timer; do
    backup_path "$path"
    run_cmd rm -f "$path"
  done
  systemd_reload
  safe_restart_service ssh "sshd -t"
  for port in 299 4443 25 2082 2086 10080; do firewall_close_port tcp "$port"; done
}

ssh_validate() {
  command_exists sshd && sshd -t
  [[ ! -f /etc/stunnel/hextunnel.conf ]] || test -s /etc/xray/xray.key
  [[ ! -f /etc/fail2ban/jail.d/hextunnel-sshd.local ]] || fail2ban-client -t >/dev/null
}

ssh_doctor() {
  local failed=0 port
  printf 'ssh=%s fail2ban=%s limiter=%s ports=' \
    "$(systemctl is-active ssh 2>/dev/null || true)" \
    "$(systemctl is-active fail2ban 2>/dev/null || true)" \
    "$(systemctl is-active hextunnel-ssh-limit.timer 2>/dev/null || true)"
  systemctl is-active --quiet ssh || failed=1
  sshd -t >/dev/null 2>&1 || failed=1
  for port in 22 299 4443 666 25 2082 2086 10080; do
    if port_is_listening tcp "$port"; then printf '%s:open ' "$port"; else printf '%s:closed ' "$port"; failed=1; fi
  done
  printf '\n'
  return "$failed"
}
