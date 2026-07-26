cat <<'EOF_HYST2_SERVICE' > /etc/systemd/system/hysteria2-server.service
[Unit]
Description=Official Hysteria 2 Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/hysteria2 server --config /etc/hysteria2/config.json
Restart=on-failure
RestartSec=2s
LimitNOFILE=1048576
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=full
ReadOnlyPaths=/etc/xray/xray.crt /etc/xray/xray.key
ReadWritePaths=/etc/hysteria2

[Install]
WantedBy=multi-user.target
EOF_HYST2_SERVICE

iptables -C INPUT -p udp --dport "$HYST2_PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport "$HYST2_PORT" -j ACCEPT
netfilter-persistent save >/dev/null 2>&1 || true
systemctl daemon-reload
systemctl enable hysteria2-server.service
if ! systemctl restart hysteria2-server.service; then
  journalctl -u hysteria2-server -n 50 --no-pager
  echo "Hysteria 2 failed to start."
  exit 1
fi

# Creating startup script
cat <<'deekayz' > /etc/deekaystartup
#!/bin/sh
ln -fs /usr/share/zoneinfo/MyTimeZone /etc/localtime
export DEBIAN_FRONTEND=noninteractive
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
echo "nameserver DNS1" > /etc/resolv.conf; echo "nameserver DNS2" >> /etc/resolv.conf
mkdir -p /var/run/sslh; touch /var/run/sslh/sslh.pid; chmod 777 /var/run/sslh/sslh.pid
iptables -C INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 53 -j ACCEPT

# Keep Hysteria 2 out of the broad Hysteria 1 DNAT range.
# This exemption must remain ahead of all range/catch-all DNAT rules.
iptables -t nat -C PREROUTING -p udp --dport 36713 -j ACCEPT 2>/dev/null || iptables -t nat -I PREROUTING 1 -p udp --dport 36713 -j ACCEPT
iptables -C INPUT -p udp --dport 36713 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 36713 -j ACCEPT

IFACE=$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)
iptables -t nat -C PREROUTING -i "$IFACE" -p udp --dport 20000:50000 -j DNAT --to-destination :36712 2>/dev/null || iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 20000:50000 -j DNAT --to-destination :36712
deekayz

sed -i "s|MyTimeZone|$MyVPS_Time|g" /etc/deekaystartup
sed -i "s|DNS1|$Dns_1|g" /etc/deekaystartup
sed -i "s|DNS2|$Dns_2|g" /etc/deekaystartup

cat <<'deekayx' > /etc/systemd/system/deekaystartup.service
[Unit]
Description=Custom startup script
ConditionPathExists=/etc/deekaystartup
[Service]
Type=oneshot
ExecStart=/etc/deekaystartup
RemainAfterExit=true
[Install]
WantedBy=multi-user.target
deekayx
chmod +x /etc/deekaystartup; systemctl enable deekaystartup

# BadVPN Binary (Provides 127.0.0.1:7300 upstream for UDP Custom)
if [ "$(getconf LONG_BIT)" == "64" ]; then
 wget -q -O /usr/bin/badvpn-udpgw "https://www.dropbox.com/s/jo6qznzwbsf1xhi/badvpn-udpgw64"
else
 wget -q -O /usr/bin/badvpn-udpgw "https://www.dropbox.com/s/8gemt9c6k1fph26/badvpn-udpgw"
fi
chmod +x /usr/bin/badvpn-udpgw

cat <<'deekayb' > /etc/systemd/system/badvpn.service
[Unit]
Description=badvpn tun2socks service
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/badvpn-udpgw --loglevel none --listen-addr 127.0.0.1:7300 --max-clients 1000 --max-connections-for-client 10
[Install]
WantedBy=multi-user.target
deekayb
systemctl enable badvpn; systemctl start badvpn
clear
# === UDP CUSTOM (Port 36717) ===
echo "Instalando UDP Custom..."
mkdir -p /root/udp
wget -q -O /root/udp/udp-custom "https://raw.githubusercontent.com/mahpud896/UDP-Custom/main/bin/udp-custom-linux-amd64" || true
chmod +x /root/udp/udp-custom 2>/dev/null || true
wget -q -O /root/udp/config.json "https://raw.githubusercontent.com/mahpud896/UDP-Custom/main/config/config.json" || true
sed -i "s/\":36712\"/\":36717\"/g" /root/udp/config.json 2>/dev/null || true
chmod 644 /root/udp/config.json 2>/dev/null || true

cat > /etc/systemd/system/udp-custom.service <<EOF
[Unit]
Description=UDP Custom Proxy
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/root/udp
ExecStart=/root/udp/udp-custom server -c /root/udp/config.json
Restart=always
RestartSec=2s
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload; systemctl enable udp-custom; systemctl start udp-custom 2>/dev/null || true
clear
# === ZIVPN (Port 5667) ===
echo "Instalando ZiVPN..."
mkdir -p /etc/zivpn
wget -q -O /usr/local/bin/zivpn "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64" || true
chmod +x /usr/local/bin/zivpn 2>/dev/null || true
cp /etc/hysteria/hysteria.crt /etc/zivpn/zivpn.crt 2>/dev/null || true
cp /etc/hysteria/hysteria.key /etc/zivpn/zivpn.key 2>/dev/null || true
chmod 644 /etc/zivpn/zivpn.crt /etc/zivpn/zivpn.key 2>/dev/null || true

cat > /etc/zivpn/config.json <<EOF
{
  "listen": ":5667",
   "cert": "/etc/zivpn/zivpn.crt",
   "key": "/etc/zivpn/zivpn.key",
   "obfs": "hu\`\`hqb\`c",
   "auth": {
    "mode": "passwords", 
    "config": ["$PASSWORD"]
  }
}
EOF
chmod 644 /etc/zivpn/config.json
echo "$PASSWORD $(date -d "+365 days" +"%Y-%m-%d")" > /etc/zivpn/users.txt

cat > /etc/systemd/system/zivpn.service <<EOF
[Unit]
Description=zivpn VPN Server
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/zivpn-nat.service <<EOF
[Unit]
Description=Restore ZiVPN UDP NAT rules
After=network-online.target
Wants=network-online.target
Before=zivpn.service
[Service]
Type=oneshot
ExecStart=/bin/bash -c 'IFACE=\$(ip -4 route ls|grep default|grep -Po "(?<=dev )(\\\\S+)"|head -1); [ -n "\$IFACE" ] && (iptables -t nat -C PREROUTING -i "\$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || iptables -t nat -A PREROUTING -i "\$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667)'
ExecStart=/bin/bash -c 'iptables -C INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 5667 -j ACCEPT'
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload; systemctl enable zivpn.service; systemctl start zivpn.service 2>/dev/null || true
systemctl enable zivpn-nat.service; systemctl start zivpn-nat.service 2>/dev/null || true

# VNSTAT INITIALIZATION
IFACE="$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)"
vnstat -u -i "$IFACE" 2>/dev/null || true
systemctl enable vnstat
systemctl restart vnstat

# MENU CREATION - FULL AND UNCOMPRESSED
mkdir -p /usr/local/bin
cat > /usr/local/bin/menu <<'EOF_MENU'
#!/bin/bash

# Detecta si el certificado activo es real (Let's Encrypt) o autofirmado
if [ -f /etc/xray/cert_type ] && grep -q "letsencrypt" /etc/xray/cert_type; then
    XRAY_INSECURE="0"
else
    XRAY_INSECURE="1"
fi
if [ "$XRAY_INSECURE" = "1" ]; then
    INSECURE_PARAM="&allowInsecure=1"
else
    INSECURE_PARAM=""
fi

# Modern Color Palette
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

DOMAIN=$(cat /etc/deekayvpn/domain.txt 2>/dev/null || curl -4 -s --max-time 2 ipv4.icanhazip.com)
SLIPSTREAM_DOMAIN=$(cat /etc/deekayvpn/slipstream_domain.txt 2>/dev/null || echo "No configurado")

HYST_CONFIG="/etc/hysteria/config.json"
HYST_USER_DB="/etc/hysteria/users.txt"
touch "$HYST_USER_DB" 2>/dev/null || true

HYST2_CONFIG="/etc/hysteria2/config.json"
HYST2_USER_DB="/etc/hysteria2/users.txt"
HYST2_PORT="${HYST2_PORT:-36713}"
touch "$HYST2_USER_DB" 2>/dev/null || true
ZIVPN_CONFIG="/etc/zivpn/config.json"
ZIVPN_USER_DB="/etc/zivpn/users.txt"
SSH_LIMIT_DB="/etc/deekayvpn/ssh_limits.txt"
mkdir -p /etc/deekayvpn 2>/dev/null || true
touch "$SSH_LIMIT_DB" 2>/dev/null || true

# --- Utility Functions ---
server_ip() { curl -4 -s --max-time 2 ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}'; }
cpu_count() { nproc 2>/dev/null || echo "1"; }
mem_stats() { free -h 2>/dev/null | awk '/Mem:/ {print $2 "|" $7 "|" $3}'; }
ram_percent() { free 2>/dev/null | awk '/Mem:/ { if ($2>0) printf "%.1f%%", ($3/$2)*100; else print "0.0%" }'; }
cpu_percent() { top -bn1 2>/dev/null | awk -F',' '/Cpu\(s\)/ { gsub("%us","",$1); gsub(" ","",$1); split($1,a,":"); if (a[2] == "") print "0.0%"; else printf "%.1f%%", a[2]+0 }'; }
buffer_mem() { free -m 2>/dev/null | awk '/Mem:/ {print $6 "M"}'; }

server_status() {
  local ok=0
  for s in ssh stunnel4 squid nginx server-sldns hysteria-server hysteria2-server ws-proxy@10080 xray slipstream danted dnsdist; do
    systemctl is-active --quiet "$s" 2>/dev/null && ok=$((ok+1))
  done
  [ "$ok" -ge 4 ] && echo -e "${GREEN}EN LÍNEA${NC}" || echo -e "${RED}PROBLEMAS DETECTADOS${NC}"
}
pause_return() { echo; read -rp "Presiona ENTER para volver... " _; }

# --- ZIVPN MANAGEMENT FUNCTIONS ---
add_zivpn() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}CREAR USUARIO ZIVPN${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    read -rp " Ingresa Contraseña: " new_pass
    
    if grep -qw "^$new_pass" "$ZIVPN_USER_DB" 2>/dev/null; then
        echo -e "\n${RED}Error: Contraseña ya existe!${NC}"
        pause_return; return
    fi
    read -rp " Validez (Dias): " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then echo -e "${RED}Numero Invalido.${NC}"; pause_return; return; fi
    exp_date=$(date -d "+${days} days" +"%Y-%m-%d")
    
    jq ".auth.config += [\"$new_pass\"]" "$ZIVPN_CONFIG" > /tmp/z.json && mv /tmp/z.json "$ZIVPN_CONFIG"
    echo "$new_pass $exp_date" >> "$ZIVPN_USER_DB"
    systemctl restart zivpn.service
    
    OBFS_VAL=$(jq -r '.obfs' "$ZIVPN_CONFIG" 2>/dev/null || echo "hu\`\`hqb\`c")
    
    echo -e "\n${GREEN}✔ Usuario creado exitosamente!${NC}"
    echo -e "${CYAN}--------------------------------------------------------------${NC}"
    echo -e " ${BOLD}IP:${NC}          ${YELLOW}$(server_ip)${NC}"
    echo -e " ${BOLD}Dominio:${NC}      ${YELLOW}${DOMAIN:-$(server_ip)}${NC}"
    echo -e " ${BOLD}Puerto De Rango:${NC}  ${YELLOW}6000-19999${NC}"
    echo -e " ${BOLD}Usuario (Contraseña):${NC} ${YELLOW}${new_pass}${NC}"
    echo -e " ${BOLD}Fecha de Expiración:${NC} ${YELLOW}${exp_date}${NC}"
    echo -e "${CYAN}--------------------------------------------------------------${NC}"
    pause_return
}

del_zivpn() {
    clear
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}ELIMINAR USUARIO ZIVPN${NC}"
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    if [ ! -s "$ZIVPN_USER_DB" ]; then echo -e "No Hay Usuarios."; pause_return; return; fi
    cat -n "$ZIVPN_USER_DB" | awk '{print " ["$1"] User: "$2" | Exp: "$3}'
    echo ""
    read -rp " Ingrese el número de ID del usuario a eliminar: " del_id
    if ! [[ "$del_id" =~ ^[0-9]+$ ]]; then echo -e "${RED}ID inválido.${NC}"; pause_return; return; fi

    del_pass=$(sed -n "${del_id}p" "$ZIVPN_USER_DB" | awk '{print $1}')
    if [ -z "$del_pass" ]; then echo -e "${RED}ID no encontrado.${NC}"; pause_return; return; fi
    jq ".auth.config |= map(select(. != \"$del_pass\"))" "$ZIVPN_CONFIG" > /tmp/z.json && mv /tmp/z.json "$ZIVPN_CONFIG"
    sed -i "${del_id}d" "$ZIVPN_USER_DB"
    systemctl restart zivpn.service
    echo -e "\n${GREEN}✔ Usuario '$del_pass' eliminado exitosamente!${NC}"
    pause_return
}

extend_zivpn() {
    clear
      echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
      echo -e "                 ${BOLD}EXTENDER USUARIO ZIVPN${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    if [ ! -s "$ZIVPN_USER_DB" ]; then echo -e "Usuarios No Encontrados."; pause_return; return; fi

    cat -n "$ZIVPN_USER_DB" | awk '{print " ["$1"] User: "$2" | Exp: "$3}'
    echo ""
    read -rp " Ingrese el número de ID del usuario a extender: " ext_id
    if ! [[ "$ext_id" =~ ^[0-9]+$ ]]; then echo -e "${RED}Número de ID inválido.${NC}"; pause_return; return; fi
    
    ext_pass=$(sed -n "${ext_id}p" "$ZIVPN_USER_DB" | awk '{print $1}')
    current_exp=$(sed -n "${ext_id}p" "$ZIVPN_USER_DB" | awk '{print $2}')
    if [ -z "$ext_pass" ]; then echo -e "${RED}ID No Encontrado.${NC}"; pause_return; return; fi
  
    read -rp " Agregar Validez (Dias): " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then echo -e "${RED}Numero Invalido.${NC}"; pause_return; return; fi
    
    new_exp=$(date -d "$current_exp + $days days" +"%Y-%m-%d")
    sed -i "${ext_id}s/.*/$ext_pass $new_exp/" "$ZIVPN_USER_DB"
    
    echo -e "\n${GREEN}✔ Usuario '$ext_pass' Extendido Exitosamente!${NC}\n New Expiry: ${YELLOW}$new_exp${NC}"
    pause_return
}

list_zivpn() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}LISTA DE USUARIOS ZIVPN${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    if [ ! -s "$ZIVPN_USER_DB" ]; then echo -e "\n No Hay Usuarios En Linea.\n"
    else
        printf " %-5s | %-25s | %-15s\n" "ID" "PASSWORD" "EXPIRY DATE"
        echo -e "${CYAN}--------------------------------------------------------------${NC}"
        cat -n "$ZIVPN_USER_DB" | while read -r num user exp; do
            printf " [%-3s] | %-25s | %-15s\n" "$num" "$user" "$exp"
        done
        echo -e "${CYAN}--------------------------------------------------------------${NC}"
        echo -e " Total Usuarios Activos: ${YELLOW}$(wc -l < "$ZIVPN_USER_DB")${NC}"
    fi
    pause_return
}


# --- HYSTERIA MANAGEMENT FUNCTIONS ---
add_hysteria() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}CREAR USUARIO HYSTERIA${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    read -rp " Ingresa Contraseña/Cadena de Auth: " new_pass
    
    if grep -qw "^$new_pass" "$HYST_USER_DB" 2>/dev/null || jq -e ".inbounds[0].users[] | select(.auth_str == \"$new_pass\")" "$HYST_CONFIG" >/dev/null; then
        echo -e "\n${RED}Error: ¡El usuario/contraseña ya existe!${NC}"
        pause_return; return
    fi
    read -rp " Validez (Días): " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then echo -e "${RED}Número inválido.${NC}"; pause_return; return; fi
    exp_date=$(date -d "+${days} days" +"%Y-%m-%d")
    
    jq ".inbounds[0].users += [{\"auth_str\": \"$new_pass\"}]" "$HYST_CONFIG" > /tmp/h.json && mv /tmp/h.json "$HYST_CONFIG"
    echo "$new_pass $exp_date" >> "$HYST_USER_DB"
    systemctl restart hysteria-server
    
    OBFS_VAL=$(jq -r '.inbounds[0].obfs' "$HYST_CONFIG" 2>/dev/null || echo "HexTunnel")
    
    echo -e "\n${GREEN}✔ ¡Usuario creado exitosamente!${NC}"
    echo -e "${CYAN}--------------------------------------------------------------${NC}"
    echo -e " ${BOLD}IP:${NC}          ${YELLOW}$(server_ip)${NC}"
    echo -e " ${BOLD}Dominio:${NC}      ${YELLOW}${DOMAIN:-$(server_ip)}${NC}"
    echo -e " ${BOLD}Rango de Puertos:${NC}  ${YELLOW}20000-50000 (-> 36712)${NC}"
    echo -e " ${BOLD}Usuario (Contraseña):${NC} ${YELLOW}${new_pass}${NC}"
    echo -e " ${BOLD}Obfs:${NC}        ${YELLOW}${OBFS_VAL}${NC}"
    echo -e " ${BOLD}Fecha de Expiración:${NC} ${YELLOW}${exp_date}${NC}"
    echo -e "${CYAN}--------------------------------------------------------------${NC}"
    pause_return
}

del_hysteria() {
    clear
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}ELIMINAR USUARIO HYSTERIA${NC}"
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    if [ ! -s "$HYST_USER_DB" ]; then echo -e "No se encontraron usuarios."; pause_return; return; fi
    cat -n "$HYST_USER_DB" | awk '{print " ["$1"] User: "$2" | Exp: "$3}'
    echo ""
    read -rp " Ingresa el número de ID del usuario a eliminar: " del_id
    if ! [[ "$del_id" =~ ^[0-9]+$ ]]; then echo -e "${RED}ID inválido.${NC}"; pause_return; return; fi

    del_pass=$(sed -n "${del_id}p" "$HYST_USER_DB" | awk '{print $1}')
    if [ -z "$del_pass" ]; then echo -e "${RED}ID no encontrado.${NC}"; pause_return; return; fi

    jq ".inbounds[0].users |= map(select(.auth_str != \"$del_pass\"))" "$HYST_CONFIG" > /tmp/h.json && mv /tmp/h.json "$HYST_CONFIG"
    sed -i "${del_id}d" "$HYST_USER_DB"
    systemctl restart hysteria-server
    echo -e "\n${GREEN}✔ ¡Usuario '$del_pass' eliminado exitosamente!${NC}"
    pause_return
}

extend_hysteria() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}EXTENDER USUARIO HYSTERIA${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    if [ ! -s "$HYST_USER_DB" ]; then echo -e "No se encontraron usuarios."; pause_return; return; fi

    cat -n "$HYST_USER_DB" | awk '{print " ["$1"] User: "$2" | Exp: "$3}'
    echo ""
    read -rp " Ingresa el número de ID del usuario a extender: " ext_id
    if ! [[ "$ext_id" =~ ^[0-9]+$ ]]; then echo -e "${RED}ID inválido.${NC}"; pause_return; return; fi
    
    ext_pass=$(sed -n "${ext_id}p" "$HYST_USER_DB" | awk '{print $1}')
    current_exp=$(sed -n "${ext_id}p" "$HYST_USER_DB" | awk '{print $2}')
    if [ -z "$ext_pass" ]; then echo -e "${RED}ID no encontrado.${NC}"; pause_return; return; fi
    
    read -rp " Días a Agregar: " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then echo -e "${RED}Número inválido.${NC}"; pause_return; return; fi
    
    new_exp=$(date -d "$current_exp + $days days" +"%Y-%m-%d")
    sed -i "${ext_id}s/.*/$ext_pass $new_exp/" "$HYST_USER_DB"
    
    echo -e "\n${GREEN}✔ ¡Usuario '$ext_pass' extendido exitosamente!${NC}\n Nueva Expiración: ${YELLOW}$new_exp${NC}"
    pause_return
}

list_hysteria() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}LISTA DE USUARIOS HYSTERIA${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    if [ ! -s "$HYST_USER_DB" ]; then echo -e "\n No se encontraron usuarios activos.\n"
    else
        printf " %-5s | %-25s | %-15s\n" "ID" "PASSWORD (AUTH STRING)" "EXPIRY DATE"
        echo -e "${CYAN}--------------------------------------------------------------${NC}"
        cat -n "$HYST_USER_DB" | while read -r num user exp; do
            printf " [%-3s] | %-25s | %-15s\n" "$num" "$user" "$exp"
        done
        echo -e "${CYAN}--------------------------------------------------------------${NC}"
        echo -e " Total de Usuarios Activos: ${YELLOW}$(wc -l < "$HYST_USER_DB")${NC}"
    fi
    pause_return
}

speed_hysteria() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}EDITAR VELOCIDADES SUBIDA/BAJADA${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    current_up=$(jq -r '.inbounds[0].up_mbps' "$HYST_CONFIG" 2>/dev/null || echo "100")
    current_down=$(jq -r '.inbounds[0].down_mbps' "$HYST_CONFIG" 2>/dev/null || echo "100")
    echo -e " Subida Actual:    ${YELLOW}${current_up} Mbps${NC}"
    echo -e " Bajada Actual:    ${YELLOW}${current_down} Mbps${NC}\n"
    read -rp " Ingresa Nueva Velocidad de Subida (Mbps): " new_up
    read -rp " Ingresa Nueva Velocidad de Bajada (Mbps): " new_down
    if [[ "$new_up" =~ ^[0-9]+$ ]] && [[ "$new_down" =~ ^[0-9]+$ ]]; then
        jq ".inbounds[0].up_mbps = $new_up | .inbounds[0].down_mbps = $new_down" "$HYST_CONFIG" > /tmp/h.json && mv /tmp/h.json "$HYST_CONFIG"
        systemctl restart hysteria-server
        echo -e "\n${GREEN}✔ ¡Velocidades actualizadas exitosamente!${NC}"
    else echo -e "\n${RED}Entrada inválida. Solo números.${NC}"; fi
    pause_return
}

change_obfs_hysteria() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}CAMBIAR OBFS DE HYSTERIA${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    current_obfs=$(jq -r '.inbounds[0].obfs' "$HYST_CONFIG" 2>/dev/null || echo "HexTunnel")
    echo -e " Obfs Actual: ${YELLOW}${current_obfs}${NC}\n"
    read -rp " Ingresa Nuevo Obfs: " new_obfs
    if [ -n "$new_obfs" ]; then
        jq ".inbounds[0].obfs = \"$new_obfs\"" "$HYST_CONFIG" > /tmp/h.json && mv /tmp/h.json "$HYST_CONFIG"
        systemctl restart hysteria-server
        echo -e "\n${GREEN}✔ ¡Obfs actualizado exitosamente a: $new_obfs!${NC}"
    else echo -e "\n${RED}Acción cancelada.${NC}"; fi
    pause_return
}

# --- HYSTERIA 2 MANAGEMENT FUNCTIONS ---
print_hysteria2_link() {
  local user="$1" token="$2" encoded_token encoded_obfs insecure
  encoded_token=$(jq -nr --arg v "$token" '$v|@uri')
  encoded_obfs=$(jq -nr --arg v "$(jq -r '.obfs.salamander.password' "$HYST2_CONFIG")" '$v|@uri')
  insecure="1"
  echo "hysteria2://${encoded_token}@${DOMAIN}:${HYST2_PORT}?insecure=${insecure}&sni=${DOMAIN}&obfs=salamander&obfs-password=${encoded_obfs}#${user}-HY2"
}

add_hysteria2() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}CREAR CUENTA HYSTERIA 2${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    read -rp " Usuario: " user
    [[ "$user" =~ ^[A-Za-z0-9._-]+$ ]] || { echo -e "\n${RED}Usuario inválido.${NC}"; pause_return; return; }
    if awk -v u="$user" '$1 == u {found=1} END {exit !found}' "$HYST2_USER_DB" 2>/dev/null; then
        echo -e "\n${RED}El usuario ya existe.${NC}"; pause_return; return
    fi
    read -rp " Validez (Días): " days
    [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -gt 0 ] || { echo -e "\n${RED}Validez inválida.${NC}"; pause_return; return; }

    read -rp " ¿Usar un token/UUID personalizado (ej. el mismo que ya usas en V2Ray)? (y/N): " custom_token_prompt
    if [[ "$custom_token_prompt" =~ ^[Yy]$ ]]; then
        read -rp " Ingresa el token/UUID personalizado: " token
        if [[ -z "$token" ]] || [[ "$token" =~ [[:space:]] ]]; then
            echo -e "\n${RED}Token inválido: no puede estar vacío ni contener espacios.${NC}"; pause_return; return
        fi
        if awk -v t="$token" '$2 == t {found=1} END {exit !found}' "$HYST2_USER_DB" 2>/dev/null; then
            echo -e "\n${RED}Ese token ya está en uso por otro usuario de Hysteria 2.${NC}"; pause_return; return
        fi
    else
        token=$(cat /proc/sys/kernel/random/uuid)
    fi

    exp=$(date -d "+${days} days" +%Y-%m-%d)
    printf '%s %s %s\n' "$user" "$token" "$exp" >> "$HYST2_USER_DB"
    chmod 600 "$HYST2_USER_DB"
    echo -e "\n${GREEN}✔ Cuenta Hysteria 2 creada.${NC}\nUsuario: $user\nToken: $token\nExpira: $exp\n"
    print_hysteria2_link "$user" "$token"
    pause_return
}

del_hysteria2() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}ELIMINAR USUARIO HYSTERIA 2${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    [ -s "$HYST2_USER_DB" ] || { echo "No se encontraron usuarios Hysteria 2."; pause_return; return; }
    nl -w2 -s'. ' "$HYST2_USER_DB"
    read -rp " ID de usuario a eliminar: " id
    [[ "$id" =~ ^[0-9]+$ ]] || { echo -e "\n${RED}ID inválido.${NC}"; pause_return; return; }
    user=$(sed -n "${id}p" "$HYST2_USER_DB" | awk '{print $1}')
    [ -n "$user" ] || { echo -e "\n${RED}ID no encontrado.${NC}"; pause_return; return; }
    sed -i "${id}d" "$HYST2_USER_DB"
    echo -e "\n${GREEN}✔ Usuario Hysteria 2 '$user' eliminado.${NC}"
    pause_return
}

extend_hysteria2() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}EXTENDER USUARIO HYSTERIA 2${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    [ -s "$HYST2_USER_DB" ] || { echo "No se encontraron usuarios Hysteria 2."; pause_return; return; }
    nl -w2 -s'. ' "$HYST2_USER_DB"
    read -rp " ID de usuario a renovar: " id
    [[ "$id" =~ ^[0-9]+$ ]] || { echo -e "\n${RED}ID inválido.${NC}"; pause_return; return; }
    line=$(sed -n "${id}p" "$HYST2_USER_DB")
    user=$(awk '{print $1}' <<< "$line"); token=$(awk '{print $2}' <<< "$line"); old_exp=$(awk '{print $3}' <<< "$line")
    [ -n "$user" ] || { echo -e "\n${RED}ID no encontrado.${NC}"; pause_return; return; }
    read -rp " Días a agregar: " days
    [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -gt 0 ] || { echo -e "\n${RED}Validez inválida.${NC}"; pause_return; return; }
    base="$old_exp"; [ "$old_exp" \< "$(date +%Y-%m-%d)" ] && base="$(date +%Y-%m-%d)"
    new_exp=$(date -d "$base +${days} days" +%Y-%m-%d)
    sed -i "${id}s/.*/$user $token $new_exp/" "$HYST2_USER_DB"
    echo -e "\n${GREEN}✔ Usuario Hysteria 2 renovado hasta $new_exp.${NC}"
    pause_return
}

list_hysteria2() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}LISTA DE USUARIOS HYSTERIA 2${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    if [ -s "$HYST2_USER_DB" ]; then nl -w2 -s'. ' "$HYST2_USER_DB"; else echo "No se encontraron usuarios."; fi
    pause_return
}

show_hysteria2() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}ENLACE HYSTERIA 2${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    [ -s "$HYST2_USER_DB" ] || { echo "No se encontraron usuarios Hysteria 2."; pause_return; return; }
    nl -w2 -s'. ' "$HYST2_USER_DB"
    read -rp " ID de usuario: " id
    line=$(sed -n "${id}p" "$HYST2_USER_DB")
    user=$(awk '{print $1}' <<< "$line"); token=$(awk '{print $2}' <<< "$line")
    [ -n "$user" ] || { echo -e "\n${RED}ID no encontrado.${NC}"; pause_return; return; }
    echo
    print_hysteria2_link "$user" "$token"
    pause_return
}

# --- XRAY MANAGEMENT FUNCTIONS ---
add_xray() {
  clear
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "                   ${BOLD}CREAR CUENTA XRAY${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e " [1] VLESS (TCP, WS, XHTTP, HTTPUpgrade Y gRPC)"
  echo -e " [2] VMESS (TCP, WS, XHTTP, HTTPUpgrade Y gRPC)"
  echo -e " [3] TROJAN (TLS)"
  echo -e " [4] TODO-EN-UNO (VLESS + VMESS + TROJAN)"
  read -rp " Selecciona Protocolo: " prot
  read -rp " Nombre de usuario: " user
  
  if grep -qw "^$user" /etc/xray/vless.txt /etc/xray/vmess.txt /etc/xray/trojan.txt 2>/dev/null; then
    echo -e "${RED}¡El nombre de usuario ya existe!${NC}"; pause_return; return
  fi

  read -rp " Validez (Días): " masa
  exp=$(date -d "+${masa} days" +"%Y-%m-%d")

  read -rp " ¿Quieres usar un UUID personalizado? (y/N): " custom_uuid_prompt
  if [[ "$custom_uuid_prompt" =~ ^[Yy]$ ]]; then
    read -rp " Ingresa el UUID personalizado: " uuid
  else
    uuid=$(cat /proc/sys/kernel/random/uuid)
  fi

  pass="HexTunnel${uuid:0:6}"
  
  VLESS_TAGS='["vless-tls-dispatcher","vless-tcp-http","vless-plain-public","vless-ws","vless-xhttp","vless-httpupgrade","vless-grpc"]'
  VMESS_TAGS='["vmess-tcp-http","vmess-ws","vmess-xhttp","vmess-httpupgrade","vmess-grpc"]'
  TROJAN_TAGS='["trojan-ws"]'

  if [ "$prot" == "1" ]; then
    jq --arg uuid "$uuid" --arg user "$user" --argjson tags "$VLESS_TAGS" \
      '(.inbounds[] | select(.tag as $t | $tags | index($t)) | .settings.clients) += [{"id": $uuid, "email": $user}]' \
      /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
    echo "$user $uuid $exp" >> /etc/xray/vless.txt
    
    clear
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}CUENTA VLESS CREADA${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "Usuario  : $user\nExpira   : $exp"
  echo -e "\n${YELLOW}[ VLESS TLS / SHARED PORT 443 ]${NC}\n"
  echo -e "TCP HTTP:  vless://${uuid}@${DOMAIN}:443?type=tcp&headerType=http&security=tls&encryption=none&host=${DOMAIN}&path=%2Fvless-tcp&sni=${DOMAIN}${INSECURE_PARAM}#${user}-VLESS-TCP\n"
  echo -e "WS:        vless://${uuid}@${DOMAIN}:443?type=ws&security=tls&encryption=none&path=%2Fvless&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}-VLESS-WS\n"
  echo -e "XHTTP:     vless://${uuid}@${DOMAIN}:443?type=xhttp&security=tls&encryption=none&path=%2Fxhttp&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}&mode=auto&alpn=h2%2Chttp%2F1.1#${user}-VLESS-XHTTP\n"
  echo -e "HTTPUp:    vless://${uuid}@${DOMAIN}:443?type=httpupgrade&security=tls&encryption=none&path=%2Fhttpupgrade&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}-VLESS-HTTPUp\n"
  echo -e "gRPC:      vless://${uuid}@${DOMAIN}:443?type=grpc&security=tls&encryption=none&serviceName=grpc-svc&sni=${DOMAIN}${INSECURE_PARAM}&alpn=h2#${user}-VLESS-gRPC\n"

  echo -e "${YELLOW}[ VLESS NTLS (80/8080/8880) ]${NC}\n"
  echo -e "TCP: vless://${uuid}@${DOMAIN}:80?type=tcp&headerType=http&security=none&encryption=none&path=%2Fvless-tcp&host=${DOMAIN}#${user}-VLESS-NTLS-TCP\n"
  echo -e "WS:  vless://${uuid}@${DOMAIN}:80?type=ws&security=none&encryption=none&path=%2Fvless&host=${DOMAIN}#${user}-VLESS-NTLS-WS\n"
  echo -e "HUP: vless://${uuid}@${DOMAIN}:80?type=httpupgrade&security=none&encryption=none&path=%2Fhttpupgrade&host=${DOMAIN}#${user}-VLESS-NTLS-HTTPUp\n"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
  
  elif [ "$prot" == "2" ]; then
    jq --arg uuid "$uuid" --arg user "$user" --argjson tags "$VMESS_TAGS" \
      '(.inbounds[] | select(.tag as $t | $tags | index($t)) | .settings.clients) += [{"id": $uuid, "alterId": 0, "email": $user}]' \
      /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
    echo "$user $uuid $exp" >> /etc/xray/vmess.txt
    
    clear
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}CUENTA VMESS CREADA${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "Usuario: $user\nExpira: $exp"
      echo -e "\n${YELLOW}[ VMESS TLS / PORT 443 ]${NC}"
VMESS_TCP_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-TCP\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"tcp\",\"type\":\"http\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-tcp\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
echo -e "TCP:        vmess://$(echo -n "$VMESS_TCP_JSON" | base64 -w 0)"
VMESS_WS_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-WS\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
echo -e "WS:         vmess://$(echo -n "$VMESS_WS_JSON" | base64 -w 0)"
VMESS_XHTTP_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-XHTTP\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"xhttp\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-xhttp\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
echo -e "XHTTP:      vmess://$(echo -n "$VMESS_XHTTP_JSON" | base64 -w 0)"
VMESS_HUP_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-HUP\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"httpupgrade\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-hup\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
echo -e "HTTPUp:     vmess://$(echo -n "$VMESS_HUP_JSON" | base64 -w 0)"
VMESS_GRPC_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-gRPC\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"grpc\",\"type\":\"none\",\"host\":\"\",\"path\":\"\",\"serviceName\":\"vmess-grpc-svc\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
echo -e "gRPC:       vmess://$(echo -n "$VMESS_GRPC_JSON" | base64 -w 0)"
echo -e "\n${YELLOW}[ VMESS NTLS / PORT 80 ]${NC}"
VMESS_NTCP_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS-TCP\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"tcp\",\"type\":\"http\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-tcp\",\"tls\":\"\"}"
echo -e "TCP:        vmess://$(echo -n "$VMESS_NTCP_JSON" | base64 -w 0)"
VMESS_NWS_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS-WS\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"\"}"
echo -e "WS:         vmess://$(echo -n "$VMESS_NWS_JSON" | base64 -w 0)"
VMESS_NHUP_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS-HUP\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"httpupgrade\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-hup\",\"tls\":\"\"}"
echo -e "HTTPUp:     vmess://$(echo -n "$VMESS_NHUP_JSON" | base64 -w 0)"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
  
  elif [ "$prot" == "3" ]; then
    jq --arg pass "$pass" --arg user "$user" --argjson tags "$TROJAN_TAGS" \
      '(.inbounds[] | select(.tag as $t | $tags | index($t)) | .settings.clients) += [{"password": $pass, "email": $user}]' \
      /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
    echo "$user $pass $exp" >> /etc/xray/trojan.txt
    
    clear
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}CUENTA TROJAN CREADA${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "Usuario: $user\nContraseña: $pass\nExpira: $exp"
    echo -e "\n${YELLOW}TLS (443):${NC}\ntrojan://${pass}@${DOMAIN}:443?type=ws&security=tls&path=%2Ftrojan&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"

  elif [ "$prot" == "4" ]; then
    jq --arg uuid "$uuid" --arg pass "$pass" --arg user "$user" \
      --argjson vtags "$VLESS_TAGS" --argjson mtags "$VMESS_TAGS" --argjson ttags "$TROJAN_TAGS" \
      '(.inbounds[] | select(.tag as $t | $vtags | index($t)) | .settings.clients) += [{"id": $uuid, "email": $user}]
       | (.inbounds[] | select(.tag as $t | $mtags | index($t)) | .settings.clients) += [{"id": $uuid, "alterId": 0, "email": $user}]
       | (.inbounds[] | select(.tag as $t | $ttags | index($t)) | .settings.clients) += [{"password": $pass, "email": $user}]' \
      /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
    
    echo "$user $uuid $exp" >> /etc/xray/vless.txt
    echo "$user $uuid $exp" >> /etc/xray/vmess.txt
    echo "$user $pass $exp" >> /etc/xray/trojan.txt

    clear
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "               ${BOLD}CUENTA TODO-EN-UNO CREADA${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "Usuario: $user\nExpira:   $exp"
    echo -e "${CYAN}--------------------------------------------------------------${NC}"
    
      echo -e "\n${YELLOW}[ VLESS TLS / SHARED PORT 443 ]${NC}\n"
  echo -e "TCP HTTP:  vless://${uuid}@${DOMAIN}:443?type=tcp&headerType=http&security=tls&encryption=none&host=${DOMAIN}&path=%2Fvless-tcp&sni=${DOMAIN}${INSECURE_PARAM}#${user}-VLESS-TCP\n"
  echo -e "WS:        vless://${uuid}@${DOMAIN}:443?type=ws&security=tls&encryption=none&path=%2Fvless&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}-VLESS-WS\n"
  echo -e "XHTTP:     vless://${uuid}@${DOMAIN}:443?type=xhttp&security=tls&encryption=none&path=%2Fxhttp&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}&mode=auto&alpn=h2%2Chttp%2F1.1#${user}-VLESS-XHTTP\n"
  echo -e "HTTPUp:    vless://${uuid}@${DOMAIN}:443?type=httpupgrade&security=tls&encryption=none&path=%2Fhttpupgrade&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}-VLESS-HTTPUp\n"
  echo -e "gRPC:      vless://${uuid}@${DOMAIN}:443?type=grpc&security=tls&encryption=none&serviceName=grpc-svc&sni=${DOMAIN}${INSECURE_PARAM}&alpn=h2#${user}-VLESS-gRPC\n"

  echo -e "${YELLOW}[ VLESS NTLS (80/8080/8880) ]${NC}\n"
  echo -e "TCP: vless://${uuid}@${DOMAIN}:80?type=tcp&headerType=http&security=none&encryption=none&path=%2Fvless-tcp&host=${DOMAIN}#${user}-VLESS-NTLS-TCP\n"
  echo -e "WS:  vless://${uuid}@${DOMAIN}:80?type=ws&security=none&encryption=none&path=%2Fvless&host=${DOMAIN}#${user}-VLESS-NTLS-WS\n"
  echo -e "HUP: vless://${uuid}@${DOMAIN}:80?type=httpupgrade&security=none&encryption=none&path=%2Fhttpupgrade&host=${DOMAIN}#${user}-VLESS-NTLS-HTTPUp\n"

  echo -e "\n${YELLOW}[ VMESS TLS / PORT 443 ]${NC}"
VMESS_TCP_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-TCP\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"tcp\",\"type\":\"http\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-tcp\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
echo -e "TCP:        vmess://$(echo -n "$VMESS_TCP_JSON" | base64 -w 0)"
VMESS_WS_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-WS\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
echo -e "WS:         vmess://$(echo -n "$VMESS_WS_JSON" | base64 -w 0)"
VMESS_XHTTP_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-XHTTP\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"xhttp\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-xhttp\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
echo -e "XHTTP:      vmess://$(echo -n "$VMESS_XHTTP_JSON" | base64 -w 0)"
VMESS_HUP_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-HUP\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"httpupgrade\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-hup\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
echo -e "HTTPUp:     vmess://$(echo -n "$VMESS_HUP_JSON" | base64 -w 0)"
VMESS_GRPC_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-gRPC\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"grpc\",\"type\":\"none\",\"host\":\"\",\"path\":\"\",\"serviceName\":\"vmess-grpc-svc\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
echo -e "gRPC:       vmess://$(echo -n "$VMESS_GRPC_JSON" | base64 -w 0)"
echo -e "\n${YELLOW}[ VMESS NTLS / PORT 80 ]${NC}"
VMESS_NTCP_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS-TCP\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"tcp\",\"type\":\"http\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-tcp\",\"tls\":\"\"}"
echo -e "TCP:        vmess://$(echo -n "$VMESS_NTCP_JSON" | base64 -w 0)"
VMESS_NWS_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS-WS\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"\"}"
echo -e "WS:         vmess://$(echo -n "$VMESS_NWS_JSON" | base64 -w 0)"
VMESS_NHUP_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS-HUP\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"httpupgrade\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-hup\",\"tls\":\"\"}"
echo -e "HTTPUp:     vmess://$(echo -n "$VMESS_NHUP_JSON" | base64 -w 0)"

    echo -e "\n${YELLOW}[ TROJAN TLS (443) ]${NC}\ntrojan://${pass}@${DOMAIN}:443?type=ws&security=tls&path=%2Ftrojan&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
  fi
  systemctl restart xray
  pause_return
}

del_xray() {
  clear
  echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
  echo -e "                   ${BOLD}ELIMINAR CUENTA XRAY${NC}"
  echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
  
  mapfile -t users < <(cat /etc/xray/*.txt 2>/dev/null | awk '{print $1}' | sort -u)
  
  if [ ${#users[@]} -eq 0 ]; then 
      echo -e "${YELLOW}No se encontraron usuarios de Xray.${NC}"; pause_return; return
  fi
  for i in "${!users[@]}"; do printf "  [${YELLOW}%02d${NC}] %s\n" $((i+1)) "${users[$i]}"; done
  echo -e "\n  [${YELLOW}00${NC}] Cancelar\n"

  read -rp "  Selecciona usuario a eliminar: " idx
  if [[ "$idx" == "00" || "$idx" == "0" ]]; then return; fi
  if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -le 0 ] || [ "$idx" -gt "${#users[@]}" ]; then 
      echo -e "${RED}Selección inválida.${NC}"; pause_return; return 
  fi

  user="${users[$((idx-1))]}"
  jq "(.inbounds[].settings.clients) |= map(select(.email != \"$user\"))" /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
  sed -i "/^$user /d" /etc/xray/vless.txt /etc/xray/vmess.txt /etc/xray/trojan.txt 2>/dev/null
  systemctl restart xray
  echo -e "\n${GREEN}✔ Usuario $user eliminado exitosamente.${NC}"
  pause_return
}

renew_xray() {
  clear
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "                   ${BOLD}RENOVAR CUENTA XRAY${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  read -rp " Usuario a renovar: " user
  
  if ! grep -qw "^$user" /etc/xray/vless.txt /etc/xray/vmess.txt /etc/xray/trojan.txt 2>/dev/null; then 
    echo -e "${RED}Usuario no encontrado.${NC}"; pause_return; return
  fi
  read -rp " Días a Agregar: " days
  for proto in vless vmess trojan; do 
    if grep -qw "^$user" "/etc/xray/${proto}.txt"; then
      current_exp=$(grep -w "^$user" "/etc/xray/${proto}.txt" | awk '{print $3}')
      new_exp=$(date -d "$current_exp + $days days" +"%Y-%m-%d")
      sed -i "s/^$user .* $current_exp/$(grep -w "^$user" "/etc/xray/${proto}.txt" | awk '{print $1 " " $2}') $new_exp/" "/etc/xray/${proto}.txt"
    fi
  done
  echo -e "\n${GREEN}✔ Usuario '$user' renovado exitosamente.${NC}\nNueva Expiración: $new_exp"
  pause_return
}

show_xray() {
  clear
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "                   ${BOLD}MOSTRAR ENLACES DE CONFIG XRAY${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  read -rp " Usuario a ver: " user
  local found=0
  if grep -qw "^$user" /etc/xray/vless.txt; then
    uuid=$(grep -w "^$user" /etc/xray/vless.txt | awk '{print $2}')
    echo -e "${YELLOW}VLESS TLS (443):${NC}\nvless://${uuid}@${DOMAIN}:443?type=ws&security=tls&encryption=none&path=%2Fvless&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}"
    echo -e "\n${YELLOW}VLESS NTLS (80):${NC}\nvless://${uuid}@${DOMAIN}:80?type=ws&security=none&encryption=none&path=%2Fvless&host=${DOMAIN}#${user}\n"
    found=1
  fi
  if grep -qw "^$user" /etc/xray/vmess.txt; then
    uuid=$(grep -w "^$user" /etc/xray/vmess.txt | awk '{print $2}')
    VMESS_TLS_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
    echo -e "${YELLOW}VMESS TLS (443):${NC}\nvmess://$(echo -n "$VMESS_TLS_JSON" | base64 -w 0)"
    VMESS_NTLS_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"\"}"
    echo -e "\n${YELLOW}VMESS NTLS (80):${NC}\nvmess://$(echo -n "$VMESS_NTLS_JSON" | base64 -w 0)\n"
    found=1
  fi
  if grep -qw "^$user" /etc/xray/trojan.txt; then
    pass=$(grep -w "^$user" /etc/xray/trojan.txt | awk '{print $2}')
    echo -e "${YELLOW}TROJAN TLS (443):${NC}\ntrojan://${pass}@${DOMAIN}:443?type=ws&security=tls&path=%2Ftrojan&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}\n"
    found=1
  fi
  if [ "$found" -eq 0 ]; then echo -e "${RED}Usuario no encontrado en ningún protocolo.${NC}"; fi
  pause_return
}

# --- SSH USER FUNCTIONS ---
list_real_users() { awk -F: '$3 >= 1000 && $1 != "nobody" && $1 != "systemd-network" && $1 != "messagebus" {print $1}' /etc/passwd 2>/dev/null; }

select_user() {
  local purpose="$1"
  mapfile -t USERS < <(list_real_users)
  if [ "${#USERS[@]}" -eq 0 ]; then echo -e "${RED}No se encontraron cuentas de usuario activas.${NC}"; return 1; fi
  clear
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  printf " %-56s \n" "${BOLD}$purpose${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  for i in "${!USERS[@]}"; do printf "  [${YELLOW}%02d${NC}] %s\n" $((i+1)) "${USERS[$i]}"; done
  echo -e "\n  [${YELLOW}00${NC}] Atrás\n"
  read -rp "  Selecciona un número de cuenta: " idx
  [[ "$idx" == "00" || "$idx" == "0" ]] && return 1
  if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#USERS[@]}" ]; then echo -e "${RED}  Selección inválida.${NC}"; return 1; fi
  SELECTED_USER="${USERS[$((idx-1))]}"
  return 0
}

create_user() {
  clear
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "                   ${BOLD}CREAR NUEVO USUARIO SSH${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "  ${YELLOW}(Escribe 00 en cualquier campo para cancelar y volver)${NC}\n"

  while true; do
    read -rp "  Nombre de usuario: " user
    user="$(echo -n "$user" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ "$user" = "00" ] && return
    if [ -z "$user" ]; then echo -e "${RED}  Error: El usuario no puede estar vacío.${NC}\n"; continue; fi
    if ! [[ "$user" =~ ^[a-zA-Z_][a-zA-Z0-9_-]{0,31}$ ]]; then echo -e "${RED}  Error: Nombre inválido (letras/números/guiones, sin espacios).${NC}\n"; continue; fi
    if id "$user" >/dev/null 2>&1; then echo -e "${RED}  Error: El usuario '$user' ya existe.${NC}\n"; continue; fi
    break
  done

  while true; do
    read -rp "  Contraseña: " pass
    pass="$(echo -n "$pass" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ "$pass" = "00" ] && return
    if [ -z "$pass" ]; then echo -e "${RED}  Error: La contraseña no puede estar vacía.${NC}\n"; continue; fi
    if [[ "$pass" =~ [[:space:]] ]]; then echo -e "${RED}  Error: La contraseña no puede contener espacios.${NC}\n"; continue; fi
    break
  done

  while true; do
    read -rp "  Válido por (días): " days
    days="$(echo -n "$days" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ "$days" = "00" ] && return
    if ! [[ "$days" =~ ^[0-9]+$ ]] || [ "$days" -eq 0 ]; then echo -e "${RED}  Error: Debe ser un número de días mayor a 0.${NC}\n"; continue; fi
    break
  done

  while true; do
    read -rp "  Límite de conexiones simultáneas (0 = sin límite): " conn_limit
    conn_limit="$(echo -n "$conn_limit" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ "$conn_limit" = "00" ] && return
    [ -z "$conn_limit" ] && conn_limit=0
    if ! [[ "$conn_limit" =~ ^[0-9]+$ ]]; then echo -e "${RED}  Error: Debe ser un número.${NC}\n"; continue; fi
    break
  done

  ua_err=$(useradd --badname -e "$(date -d "+$days days" +%Y-%m-%d)" -s /bin/false -M "$user" 2>&1 1>/dev/null)
  if [ $? -ne 0 ]; then
    echo -e "\n${RED}  Error: No se pudo crear el usuario '$user'.${NC}"
    echo -e "  ${YELLOW}Detalle:${NC} ${ua_err:-desconocido}"
    echo "$(date '+%F %T') create_user FALLÓ useradd user=$user :: ${ua_err:-desconocido}" >> /var/log/deekayvpn-menu-errors.log
    pause_return; return
  fi
  cp_err=$(echo "$user:$pass" | chpasswd 2>&1 1>/dev/null)
  if [ $? -ne 0 ]; then
    echo -e "\n${RED}  Error: No se pudo establecer la contraseña. Eliminando cuenta incompleta...${NC}"
    echo -e "  ${YELLOW}Detalle:${NC} ${cp_err:-desconocido}"
    echo "$(date '+%F %T') create_user FALLÓ chpasswd user=$user :: ${cp_err:-desconocido}" >> /var/log/deekayvpn-menu-errors.log
    userdel -f "$user" 2>/dev/null
    pause_return; return
  fi

  sed -i "/^$user /d" "$SSH_LIMIT_DB" 2>/dev/null
  if [ "$conn_limit" -gt 0 ]; then echo "$user $conn_limit" >> "$SSH_LIMIT_DB"; fi

  IP=$(curl -s ipv4.icanhazip.com)
  CURRENT_NS=$(grep 'ExecStart=' /etc/systemd/system/server-sldns.service 2>/dev/null | sed 's/.*server\.key \([^ ]*\) .*/\1/')

  clear
  echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "                   ${BOLD}CUENTA CREADA EXITOSAMENTE${NC}"
  echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "  ${BOLD}Dominio/Host${NC}: ${YELLOW}$DOMAIN${NC}"
  echo -e "  ${BOLD}Dirección IP${NC} : ${YELLOW}$IP${NC}"
  echo -e "  ${BOLD}Usuario${NC}   : ${YELLOW}$user${NC}"
  echo -e "  ${BOLD}Contraseña${NC}   : ${YELLOW}$pass${NC}"
  echo -e "  ${BOLD}Expiración${NC}     : ${YELLOW}$(date -d "+$days days" +%Y-%m-%d)${NC}"
  echo -e "  ${BOLD}Límite Conexiones${NC}: ${YELLOW}$([ "$conn_limit" -gt 0 ] && echo "$conn_limit" || echo "Sin límite")${NC}"
  echo -e "${CYAN}--------------------------------------------------------------${NC}"
  echo -e "  SSH Port   : 22, 299"
  echo -e "  SSL/TLS    : 443"
  echo -e "  SSL/WS     : 443"
  echo -e "  WebSocket  : 80, 8080, 8880, 2082, 2086, 25"
  echo -e "  SlowDNS/SlipStream (dnsdist): 53"
  echo -e "  BadVPN     : 7300"
  echo -e "  UDP Custom : 1-65535"
  echo -e "${CYAN}--------------------------------------------------------------${NC}"
  echo -e "  ${BOLD}Payload HTTP     :${NC}"
  echo -e "  ${YELLOW}GET / HTTP/1.1[crlf]Host: ${DOMAIN}[crlf]Connection: upgrade[crlf]Upgrade: websocket[crlf][crlf]${NC}"
  echo -e ""
  echo -e "  ${BOLD}Payload Mejorado :${NC}"
  echo -e "  ${YELLOW}GET / HTTP/1.1[crlf]Host: bug.com[crlf][crlf]PATCH / HTTP/1.1[crlf]Host: ${DOMAIN}[crlf]Connection: upgrade[crlf]Upgrade: websocket[crlf][crlf]${NC}"
  echo -e "${CYAN}--------------------------------------------------------------${NC}"
  echo -e "  ${BOLD}SlowDNS NS ${NC}: ${YELLOW}${CURRENT_NS:-No configurado}${NC}"
  echo -e "  ${BOLD}SlipStream ${NC}: ${YELLOW}${SLIPSTREAM_DOMAIN}${NC}"
  echo -e "  ${BOLD}DNS PUB KEY${NC}: 7fbd1f8aa0abfe15a7903e837f78aba39cf61d36f183bd604daa2fe4ef3b7b59"
  echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
  pause_return
}

delete_user() {
  if ! select_user "DELETE SSH USER"; then pause_return; return; fi
  clear; echo -e "${RED}Advertencia: Estás a punto de eliminar al usuario: ${YELLOW}$SELECTED_USER${NC}"
  read -rp "¿Estás seguro? [y/N]: " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    # Force kill all processes owned by the user to free up the account
    pkill -u "$SELECTED_USER" 2>/dev/null
    
    # Execute forced deletion
    if userdel -r -f "$SELECTED_USER" 2>/dev/null || userdel -f "$SELECTED_USER" 2>/dev/null; then
        sed -i "/^$SELECTED_USER /d" "$SSH_LIMIT_DB" 2>/dev/null
        echo -e "${GREEN}El usuario $SELECTED_USER ha sido eliminado.${NC}"
    else
        echo -e "${RED}Fallo al eliminar $SELECTED_USER. Revisa archivos bloqueados.${NC}"
    fi
  fi
  pause_return
}

extend_user() {
  if ! select_user "EXTEND USER EXPIRY"; then pause_return; return; fi
  clear; echo -e "Extendiendo cuenta de: ${YELLOW}$SELECTED_USER${NC}"
  read -rp "Ingresa número de días a agregar: " days
  if ! [[ "$days" =~ ^[0-9]+$ ]]; then echo -e "${RED}Formato de número inválido.${NC}"; pause_return; return; fi
  current=$(chage -l "$SELECTED_USER" 2>/dev/null | awk -F": " '/Account expires/ {print $2}')
  if [ "$current" = "never" ] || [ -z "$current" ]; then new_exp=$(date -d "+$days days" +%Y-%m-%d)
  else new_exp=$(date -d "$current +$days days" +%Y-%m-%d); fi
  chage -E "$new_exp" "$SELECTED_USER"
  echo -e "${GREEN}¡Éxito!${NC} Cuenta extendida.\nNueva Fecha de Expiración: ${YELLOW}$new_exp${NC}"
  pause_return
}

# --- Monitor ---
online_users() {
  clear
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "               ${BOLD}MONITOR DE SESIONES ACTIVAS${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"

  echo -e "${YELLOW}--- SSH LEGADO ---${NC}"
  declare -A active_ssh
  mapfile -t USERS < <(awk -F: '$3 >= 1000 && $1 != "nobody" && $1 != "systemd-network" && $1 != "messagebus" {print $1}' /etc/passwd 2>/dev/null)
  
  for user in "${USERS[@]}"; do
      ssh_count=$(ps -u "$user" 2>/dev/null | grep -c "sshd")
      total=$ssh_count
      if [ "$total" -gt 0 ]; then active_ssh["$user"]=$total; fi
  done

  if [ "${#active_ssh[@]}" -eq 0 ]; then 
      echo -e "  No hay usuarios de SSH legado autenticados en línea actualmente.\n"
  else
    printf "  %-25s %-15s\n" "USERNAME" "ACTIVE SESSIONS"
    echo -e "${CYAN}  ----------------------------------------------------------${NC}"
    for user in "${!active_ssh[@]}"; do 
        if [ "${active_ssh[$user]}" -gt 1 ]; then
            printf "  %-25s ${RED}%-15s (Multi-Login)${NC}\n" "$user" "${active_ssh[$user]}"
        else
            printf "  %-25s ${GREEN}%-15s${NC}\n" "$user" "${active_ssh[$user]}"
        fi
    done | sort
    echo
  fi

  echo -e "${YELLOW}--- INICIOS DE SESIÓN ACTIVOS XRAY CORE (IPs Únicas Recientes) ---${NC}"
  if grep -q '"loglevel": "warning"' /etc/xray/config.json 2>/dev/null; then
      sed -i 's/"loglevel": "warning"/"loglevel": "info"/g' /etc/xray/config.json
      systemctl restart xray 2>/dev/null
      echo -e "  [Nota del Sistema] Registro de Xray habilitado. Reconecta a los usuarios para ver los logs.\n"
  elif [ -f /var/log/xray/access.log ]; then
      active_xray=$(tail -n 10000 /var/log/xray/access.log 2>/dev/null | grep "accepted" | awk '{ user=""; for(i=1;i<=NF;i++) if($i=="email:") user=$(i+1); if(user!="") { split($3, a, ":"); print user " " a[1] } }' | sort -u | awk '{print $1}' | uniq -c | sort -nr)
      if [ -z "$active_xray" ]; then 
          echo -e "  No se encontraron usuarios activos de Xray en los logs recientes.\n"
      else
          printf "  %-15s %-25s\n" "UNIQUE IPs" "USERNAME"
          echo -e "${CYAN}  ----------------------------------------------------------${NC}"
          while read -r count username; do 
              if [ -n "$username" ]; then 
                  if [ "$count" -gt 1 ]; then
                      printf "  ${RED}%-15s${NC} %-25s ${RED}(Multi-IP)${NC}\n" "$count" "$username"
                  else
                      printf "  %-15s %-25s\n" "$count" "$username"
                  fi
              fi
          done <<< "$active_xray"
      fi
  else echo -e "  Log de acceso de Xray no encontrado.\n"; fi
  
  pause_return
}

# --- Service Controls ---
restart_service() {
  local service_name="$1"
  local display_name="$2"
  echo -e "Reiniciando ${display_name}..."
  systemctl restart $service_name 2>/dev/null || true
  echo -e "${GREEN}✔ ${display_name} reiniciado.${NC}"
}

service_control_menu() {
  while true; do
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}CONTROL DE SERVICIOS${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "  [${YELLOW}01${NC}] Reiniciar Todos Los Servicios"
    echo -e "  [${YELLOW}02${NC}] Reiniciar SSH"
    echo -e "  [${YELLOW}03${NC}] Reiniciar Proxies WebSocket de Node"
    echo -e "  [${YELLOW}04${NC}] Reiniciar Stunnel y Xray Core"
    echo -e "  [${YELLOW}05${NC}] Reiniciar Squid Proxy y Nginx"
    echo -e "  [${YELLOW}06${NC}] Reiniciar Núcleo UDP (SlowDNS / Hysteria / BadVPN)"
    echo -e "  [${YELLOW}07${NC}] Reiniciar Multiplexor (dnsdist / Slipstream / Dante)"
    echo -e "  [${YELLOW}00${NC}] Atrás\n"
    read -rp "  Selecciona una opción: " opt
    case "$opt" in
      1|01) restart_service "ssh stunnel4 sslh squid nginx server-sldns hysteria-server hysteria2-server badvpn ws-proxy@10080 ws-proxy@25 ws-proxy@2082 ws-proxy@2086 xray slipstream danted dnsdist" "All Services"; pause_return ;;
      2|02) restart_service "ssh" "SSH"; pause_return ;;
      3|03) restart_service "ws-proxy@10080 ws-proxy@25 ws-proxy@2082 ws-proxy@2086" "Node WebSocket Proxies"; pause_return ;;
      4|04) restart_service "stunnel4 xray" "Stunnel & Xray Core"; pause_return ;;
      5|05) restart_service "squid nginx" "Squid Proxy & Nginx"; pause_return ;;
      6|06) restart_service "server-sldns hysteria-server hysteria2-server badvpn" "UDP Core Services"; pause_return ;;
      7|07) restart_service "dnsdist slipstream danted" "Multiplexor (dnsdist/Slipstream/Dante)"; pause_return ;;
      0|00) break ;;
      *) echo -e "${RED}Opción inválida.${NC}"; sleep 1 ;;
    esac
  done
}

# --- Backup & Restore ---
backup_snapshot() {
  clear; local out="/root/hextunnel_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
  echo -e "Empaquetando configuraciones del servidor..."
  tar -czf "$out" /etc/ssh /etc/stunnel /etc/squid /etc/hysteria /etc/hysteria2 /etc/deekayvpn /etc/systemd/system/ws-proxy@.service /etc/xray 2>/dev/null
  echo -e "\n${GREEN}✔ ¡Respaldo creado exitosamente!${NC}\nUbicación: ${YELLOW}$out${NC}"
  pause_return
}

restore_snapshot() {
  clear
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "                   ${BOLD}RESTAURAR CONFIGURACIÓN${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  shopt -s nullglob
  backups=(/root/hextunnel_backup_*.tar.gz)
  if [ ${#backups[@]} -eq 0 ]; then echo -e "${RED}  No se encontraron archivos de respaldo en /root/.${NC}"; pause_return; return; fi
  echo -e "  Respaldos Disponibles:\n"
  for i in "${!backups[@]}"; do printf "  [${YELLOW}%02d${NC}] %s\n" $((i+1)) "$(basename "${backups[$i]}")"; done
  echo -e "\n  [${YELLOW}00${NC}] Cancelar\n"
  read -rp "  Selecciona respaldo a restaurar: " sel
  if [[ "$sel" == "00" || "$sel" == "0" ]]; then return; fi
  idx=$((sel-1))
  if [ -n "${backups[$idx]}" ]; then
    echo -e "\nRestaurando ${YELLOW}$(basename "${backups[$idx]}")${NC}..."
    tar -xzf "${backups[$idx]}" -C /
    systemctl daemon-reload; systemctl restart ssh stunnel4 sslh squid nginx server-sldns hysteria-server badvpn ws-proxy@10080 ws-proxy@25 ws-proxy@2082 ws-proxy@2086 xray slipstream danted dnsdist 2>/dev/null || true
    echo -e "${GREEN}✔ ¡Restauración completa!${NC}"
  else echo -e "${RED}Selección inválida.${NC}"; fi
  pause_return
}

# --- System Utilities ---
utilities_menu() {
  while true; do
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}UTILIDADES DEL SISTEMA${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "  [${YELLOW}1${NC}] Activar BBR Nativo del Kernel (Rápido y Silencioso)"
    echo -e "  [${YELLOW}2${NC}] Verificar Desbloqueos de Netflix y Streaming (Inglés)"
    echo -e "  [${YELLOW}0${NC}] Atrás\n"
    read -rp "  Selecciona una opción: " subopt
    case "$subopt" in 
      1) 
         echo -e "\nActivando BBR Nativo del Kernel..."
         sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
         sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
         echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
         echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
         sysctl -p >/dev/null 2>&1
         if [[ "$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null)" == *"bbr"* ]]; then echo -e "${GREEN}✔ ¡BBR Activado Exitosamente!${NC}"
         else echo -e "${RED}✖ Fallo al activar BBR (puede que el kernel no lo soporte).${NC}"; fi
         pause_return
         ;; 
      2) 
         clear
         echo -e "${YELLOW}Ejecutando Verificación de Restricción Regional (Inglés)...${NC}\n"
         bash <(curl -sL https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh) -E en
         echo ""
         pause_return 
         ;;
      0) break ;;
      *) echo -e "${RED}Opción inválida.${NC}"; sleep 1 ;;
    esac
  done
}

# --- Domain & DNS Management ---
change_domain() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}CAMBIAR DOMINIO DEL SERVIDOR${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    current_dom=$(cat /etc/deekayvpn/domain.txt 2>/dev/null || echo "No configurado")
    current_cert=$(cat /etc/xray/cert_type 2>/dev/null || echo "desconocido")
    echo -e " Dominio/IP Actual: ${YELLOW}$current_dom${NC}  (certificado: ${YELLOW}$current_cert${NC})\n"
    read -rp " Ingresa Nuevo Dominio o IP: " new_dom

    if [ -z "$new_dom" ]; then echo -e "\n${RED}Acción cancelada.${NC}"; pause_return; return; fi
    if [ "$new_dom" = "$current_dom" ]; then echo -e "\n${RED}Es el mismo dominio/IP, sin cambios.${NC}"; pause_return; return; fi

    SERVER_IP=$(curl -4 -s --max-time 2 ipv4.icanhazip.com || hostname -I | awk '{print $1}')

    if [[ "$new_dom" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "\n${YELLOW}Generando certificado autofirmado para la IP $new_dom...${NC}"
        systemctl stop xray 2>/dev/null || true
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
          -keyout /etc/xray/xray.key \
          -out /etc/xray/xray.crt \
          -subj "/CN=${new_dom}/O=HexTunnel/C=US"
        echo "selfsigned" > /etc/xray/cert_type
        rm -f /etc/cron.d/certbot-renew
        NEW_CERT_TYPE="selfsigned"
    else
        echo -e "\n${YELLOW}Verificando que $new_dom resuelva a $SERVER_IP...${NC}"
        command -v dig >/dev/null 2>&1 || apt-get install -y dnsutils >/dev/null 2>&1
        DOMAIN_IP=$(dig +short "$new_dom" @8.8.8.8 | tail -1)
        if [ "$DOMAIN_IP" != "$SERVER_IP" ]; then
            echo -e "\n${RED}✘ ERROR: $new_dom no apunta a $SERVER_IP todavía.${NC}"
            echo -e "  Crea/corrige el registro A en tu DNS y vuelve a intentar. No se cambió nada."
            pause_return; return
        fi
        echo -e "${GREEN}Dominio verificado. Solicitando certificado Let's Encrypt...${NC}"
        command -v certbot >/dev/null 2>&1 || apt-get install -y certbot >/dev/null 2>&1
        systemctl stop xray 2>/dev/null || true
        systemctl stop nginx 2>/dev/null || true
        if ! certbot certonly --standalone --non-interactive --agree-tos --email "admin@${new_dom}" -d "${new_dom}"; then
            echo -e "\n${RED}✘ Falló la emisión del certificado Let's Encrypt. No se cambió el dominio.${NC}"
            systemctl start xray 2>/dev/null || true
            pause_return; return
        fi
        cp "/etc/letsencrypt/live/${new_dom}/fullchain.pem" /etc/xray/xray.crt
        cp "/etc/letsencrypt/live/${new_dom}/privkey.pem" /etc/xray/xray.key
        echo "letsencrypt" > /etc/xray/cert_type
        NEW_CERT_TYPE="letsencrypt"

        mkdir -p /etc/letsencrypt/renewal-hooks/deploy
        cat <<'EOF_RENEW' > /etc/letsencrypt/renewal-hooks/deploy/hex-tunnel.sh
#!/bin/bash
set -e
for domain in $RENEWED_DOMAINS; do
    cp /etc/letsencrypt/live/$domain/fullchain.pem /etc/xray/xray.crt
    cp /etc/letsencrypt/live/$domain/privkey.pem /etc/xray/xray.key
    cat /etc/letsencrypt/live/$domain/privkey.pem /etc/letsencrypt/live/$domain/fullchain.pem > /etc/stunnel/stunnel.pem
    chmod 600 /etc/stunnel/stunnel.pem /etc/xray/xray.key
    chmod 644 /etc/xray/xray.crt
    systemctl restart xray stunnel4
    break
done
EOF_RENEW
        chmod +x /etc/letsencrypt/renewal-hooks/deploy/hex-tunnel.sh
        echo "0 3 * * * root certbot renew --quiet --deploy-hook /etc/letsencrypt/renewal-hooks/deploy/hex-tunnel.sh" > /etc/cron.d/certbot-renew
    fi

    chmod 644 /etc/xray/xray.crt
    chmod 600 /etc/xray/xray.key
    cat /etc/xray/xray.key /etc/xray/xray.crt > /etc/stunnel/stunnel.pem
    chmod 600 /etc/stunnel/stunnel.pem
    chown root:root /etc/stunnel/stunnel.pem

    echo "$new_dom" > /etc/deekayvpn/domain.txt
    DOMAIN="$new_dom"

    systemctl start xray 2>/dev/null || true
    if ! /usr/local/bin/xray run -test -config /etc/xray/config.json >/dev/null 2>&1; then
        echo -e "\n${RED}✘ Advertencia: el nuevo certificado no pasó la validación de Xray.${NC}"
    fi
    systemctl restart xray stunnel4 2>/dev/null || true
    systemctl restart nginx 2>/dev/null || true

    echo -e "\n${GREEN}✔ Dominio actualizado a: $new_dom${NC}"
    echo -e "${GREEN}✔ Certificado regenerado (${NEW_CERT_TYPE}) y Xray/Stunnel reiniciados.${NC}"
    echo -e "${YELLOW}Nota: los enlaces vless/vmess/trojan que ya diste a usuarios usaban el dominio/cert${NC}"
    echo -e "${YELLOW}anterior. Genera enlaces nuevos desde el menú de Xray (opción 4, Mostrar Enlaces).${NC}"
    pause_return
}

change_slowdns() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "               ${BOLD}CAMBIAR NAMESERVER DE SLOWDNS${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    svc_file="/etc/systemd/system/server-sldns.service"
    if [ ! -f "$svc_file" ]; then echo -e "${RED}Archivo de servicio SlowDNS no encontrado.${NC}"; pause_return; return; fi
    current_ns=$(grep 'ExecStart=' "$svc_file" | sed 's/.*server\.key \([^ ]*\) .*/\1/')
    echo -e " Nameserver Actual: ${YELLOW}$current_ns${NC}\n"
    read -rp " Ingresa Nuevo Nameserver (ej. ns1.dominio.com): " new_ns
    ss_dom=$(cat /etc/deekayvpn/slipstream_domain.txt 2>/dev/null || echo "")
    if [ -n "$new_ns" ] && [ "$new_ns" = "$ss_dom" ]; then
        echo -e "\n${RED}✘ Ese dominio ya lo usa Slipstream. dnsdist enruta por dominio, no pueden ser iguales.${NC}"
        pause_return; return
    fi
    if [ -n "$new_ns" ] && [ "$new_ns" != "$current_ns" ]; then
        sed -i "s/$current_ns/$new_ns/g" "$svc_file"
        systemctl daemon-reload; systemctl restart server-sldns
        echo -e "\n${GREEN}✔ Nameserver de SlowDNS actualizado a: $new_ns${NC}"
    else echo -e "\n${RED}Acción cancelada o se ingresó el mismo NS.${NC}"; fi
    pause_return
}

change_slipstream() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                     ${BOLD}SLIPSTREAM${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    svc_file="/etc/systemd/system/slipstream.service"
    dnsdist_conf="/etc/dnsdist/dnsdist.conf"
    sldns_svc="/etc/systemd/system/server-sldns.service"

    if [ ! -f "$svc_file" ]; then
        echo -e " SlipStream no está instalado en este servidor."
        read -rp " ¿Deseas instalarlo ahora? [y/N]: " ans
        if ! [[ "$ans" =~ ^[Yy]$ ]]; then echo -e "\n${RED}Cancelado.${NC}"; pause_return; return; fi
        install_slipstream
        return
    fi

    current_dom=$(cat /etc/deekayvpn/slipstream_domain.txt 2>/dev/null || echo "No configurado")
    echo -e " Dominio Actual: ${YELLOW}$current_dom${NC}\n"
    read -rp " Ingresa Nuevo Dominio (enter para dejarlo igual): " new_dom
    [ -z "$new_dom" ] && { echo -e "\n${RED}Sin cambios.${NC}"; pause_return; return; }
    current_ns=$(grep 'ExecStart=' "$sldns_svc" 2>/dev/null | sed 's/.*server\.key \([^ ]*\) .*/\1/')
    if [ "$new_dom" = "$current_ns" ]; then
        echo -e "\n${RED}✘ Ese dominio ya lo usa SlowDNS. dnsdist enruta por dominio, no pueden ser iguales.${NC}"
        pause_return; return
    fi
    if [ "$new_dom" != "$current_dom" ]; then
        sed -i "s/--domain ${current_dom} /--domain ${new_dom} /" "$svc_file"
        [ -f "$dnsdist_conf" ] && sed -i "s/${current_dom}\./${new_dom}./g" "$dnsdist_conf"
        echo "$new_dom" > /etc/deekayvpn/slipstream_domain.txt
        systemctl daemon-reload; systemctl restart slipstream dnsdist
        echo -e "\n${GREEN}✔ Dominio de Slipstream actualizado a: $new_dom${NC}"
    else echo -e "\n${RED}Se ingresó el mismo dominio, sin cambios.${NC}"; fi
    pause_return
}

# Instala SlipStream + Dante SOCKS + dnsdist en un servidor donde ya corre SlowDNS.
# Mueve SlowDNS del puerto 53 público a uno interno y pone dnsdist al frente como multiplexor.
install_slipstream() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}INSTALAR SLIPSTREAM${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"

    sldns_svc="/etc/systemd/system/server-sldns.service"
    if [ ! -f "$sldns_svc" ]; then
        echo -e "${RED}No se encontró el servicio de SlowDNS. Este servidor no tiene la base esperada.${NC}"
        pause_return; return
    fi
    current_ns=$(grep 'ExecStart=' "$sldns_svc" | sed 's/.*server\.key \([^ ]*\) .*/\1/')

    SlowDNS_Internal_Port='5301'
    Slipstream_Internal_Port='5300'
    SlipstreamSocksPort='1080'
    SlipstreamInstallDir='/opt/slipstream-rust'
    SlipstreamPinnedCommit='bc772dd07d9a136dbd7553b0da575526de207847'
    DnsdistConf='/etc/dnsdist/dnsdist.conf'

    read -rp " Ingresa el dominio para SlipStream (ej. ss.${current_ns}): " -e -i "ss.${current_ns}" SlipstreamDomain
    while [ "$SlipstreamDomain" = "$current_ns" ]; do
        echo -e "\n${RED}✘ No puede ser igual al Nameserver de SlowDNS ($current_ns).${NC}"
        read -rp " Ingresa un dominio distinto para SlipStream: " -e -i "ss.$current_ns" SlipstreamDomain
    done

    echo -e "\n${GREEN}Instalando dependencias...${NC}"
    command -v danted >/dev/null 2>&1 || apt-get install -y dante-server
    command -v dnsdist >/dev/null 2>&1 || apt-get install -y dnsdist
    apt-get install -y cmake pkg-config libssl-dev build-essential git >/dev/null 2>&1

    echo -e "${GREEN}Moviendo SlowDNS al puerto interno ${SlowDNS_Internal_Port}...${NC}"
    sed -i "s|-udp [^ ]* -privkey-file|-udp 127.0.0.1:${SlowDNS_Internal_Port} -privkey-file|" "$sldns_svc"
    systemctl daemon-reload; systemctl restart server-sldns

    echo -e "${GREEN}Configurando Dante SOCKS...${NC}"
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

    echo -e "${GREEN}Instalando Rust (si hace falta)...${NC}"
    if ! command -v cargo &>/dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y >/dev/null 2>&1
        source "$HOME/.cargo/env"
    else
        source "$HOME/.cargo/env" 2>/dev/null || true
    fi

    echo -e "${GREEN}Clonando y compilando Slipstream (esto tarda unos minutos)...${NC}"
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
    echo "$SlipstreamDomain" > /etc/deekayvpn/slipstream_domain.txt

    echo -e "${GREEN}Configurando dnsdist como multiplexor en el puerto 53...${NC}"
    mkdir -p "$(dirname "$DnsdistConf")"
    cat > "$DnsdistConf" <<DNSDIST_EOF
setLocal("0.0.0.0:53")

newServer({address="127.0.0.1:${SlowDNS_Internal_Port}", name="slowdns"})
newServer({address="127.0.0.1:${Slipstream_Internal_Port}", name="slipstream"})

addAction(SuffixMatchNodeRule("${current_ns}."), PoolAction("slowdns_pool"))
setPoolServers("slowdns_pool", {getServer(0)})

addAction(SuffixMatchNodeRule("${SlipstreamDomain}."), PoolAction("slipstream_pool"))
setPoolServers("slipstream_pool", {getServer(1)})

addAction(AllRule(), DropAction())
DNSDIST_EOF
    systemctl daemon-reload; systemctl enable dnsdist >/dev/null 2>&1; systemctl restart dnsdist

    if systemctl is-active --quiet slipstream && systemctl is-active --quiet dnsdist && systemctl is-active --quiet danted; then
        echo -e "\n${GREEN}✔ SlipStream instalado y multiplexado con SlowDNS en el puerto 53.${NC}"
        echo -e "  Dominio SlipStream : ${YELLOW}${SlipstreamDomain}${NC}"
        echo -e "  SOCKS interno      : 127.0.0.1:${SlipstreamSocksPort}"
    else
        echo -e "\n${RED}Algo no arrancó bien. Revisa:${NC}"
        echo -e "  journalctl -u slipstream --no-pager -n 30"
        echo -e "  journalctl -u dnsdist --no-pager -n 30"
        echo -e "  journalctl -u danted --no-pager -n 30"
    fi
    pause_return
}

change_status() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "             ${BOLD}CAMBIAR MENSAJE DE STATUS (WS)${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    proxy_file="/etc/socksproxy/proxy.js"
    if [ ! -f "$proxy_file" ]; then echo -e "${RED}Archivo proxy.js no encontrado.${NC}"; pause_return; return; fi
    line_num=$(grep -n "clientSocket.write('HTTP/1.1 101" "$proxy_file" | head -n1 | cut -d: -f1)
    if [ -z "$line_num" ]; then echo -e "${RED}No se encontró la línea de status en proxy.js.${NC}"; pause_return; return; fi
    current_status=$(sed -n "${line_num}p" "$proxy_file" | sed 's/^[[:space:]]*//')
    echo -e " Línea Actual:\n ${YELLOW}${current_status}${NC}\n"
    echo -e " Escribe el mensaje completo, libre: texto plano o HTML"
    echo -e " (ej: <font color=\"red\">Mi Texto</font> <b>Extra</b>)."
    echo -e " Nota: no uses comillas simples (') dentro del mensaje.\n"
    read -rp " Nuevo Mensaje de Status: " new_status
    if [ -n "$new_status" ]; then
        esc_msg=$(printf '%s' "$new_status" | sed "s/'/’/g")
        awk -v ln="$line_num" -v msg="$esc_msg" 'NR==ln{printf "            clientSocket.write(%cHTTP/1.1 101 %s\\r\\n\\r\\n%c);\n", 39, msg, 39; next} {print}' "$proxy_file" > "${proxy_file}.tmp" && mv "${proxy_file}.tmp" "$proxy_file"
        for u in $(systemctl list-units --all --type=service --no-legend 'ws-proxy@*' 2>/dev/null | awk '{print $1}'); do systemctl restart "$u"; done
        echo -e "\n${GREEN}✔ Mensaje de status actualizado.${NC}"
    else echo -e "\n${RED}Acción cancelada.${NC}"; fi
    pause_return
}

change_banner() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}EDITAR BANNER (SSH / STUNNEL)${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e " Se abrirá el banner en nano para que lo edites a tu gusto."
    echo -e " Guarda con ${YELLOW}CTRL+O${NC} + ENTER y sal con ${YELLOW}CTRL+X${NC}.\n"
    read -rp " Presiona ENTER para continuar o escribe 0 para cancelar: " conf
    if [ "$conf" = "0" ]; then echo -e "\n${RED}Acción cancelada.${NC}"; pause_return; return; fi
    nano /etc/zorro-luffy
    systemctl restart ssh stunnel4 2>/dev/null
    echo -e "\n${GREEN}✔ Banner actualizado y servicios reiniciados.${NC}"
    pause_return
}

# --- Advanced / Danger Zone ---
advanced_menu() {
  while true; do
    clear
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                     ${BOLD}CONFIGURACIÓN AVANZADA${NC}"
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    echo -e "  [${YELLOW}01${NC}] Ver JSON Crudo de Hysteria"
    echo -e "  [${YELLOW}02${NC}] Ver Logs de Acciones de Servicios (Journalctl)"
    echo -e "  [${YELLOW}03${NC}] Cambiar Dominio/IP del Servidor"
    echo -e "  [${YELLOW}04${NC}] Cambiar Nameserver de SlowDNS (NS)"
    echo -e "  [${RED}05${NC}] Desinstalar Script Completo (Peligro)"
    echo -e "  [${YELLOW}06${NC}] Cambiar Mensaje de Status (WS, HTML/Texto Libre)"
    echo -e "  [${YELLOW}07${NC}] Editar Banner (SSH / Stunnel)"
    echo -e "  [${YELLOW}08${NC}] SlipStream (Instalar / Cambiar Dominio)"
    echo -e "  [${YELLOW}09${NC}] Reiniciar UDP Core (SlowDNS/Hysteria/ZiVPN/UDP-Custom)"
    echo -e "  [${YELLOW}00${NC}] Atrás\n"
    read -rp "  Selecciona una opción: " opt
    case "$opt" in
      1|01) clear; cat /etc/hysteria/config.json 2>/dev/null || echo "No encontrado."; pause_return ;;
    2|02) 
        clear; echo -e "[1] SSH  [2] WS-Proxies  [3] Hysteria  [4] Stunnel  [5] SlowDNS  [6] Xray  [7] Slipstream  [8] dnsdist (Multiplexor)  [9] Dante SOCKS  [10] Hysteria 2\n"
        read -rp "Selecciona log: " lopt
        case "$lopt" in
          1) journalctl -u ssh -n 50 --no-pager ;;
          2) journalctl -u ws-proxy@10080 -n 50 --no-pager ;;
          3) journalctl -u hysteria-server -n 50 --no-pager ;;
          4) journalctl -u stunnel4 -n 50 --no-pager ;;
          5) journalctl -u server-sldns -n 50 --no-pager ;;
          6) journalctl -u xray -n 50 --no-pager ;;
          7) journalctl -u slipstream -n 50 --no-pager ;;
          8) journalctl -u dnsdist -n 50 --no-pager ;;
          9) journalctl -u danted -n 50 --no-pager ;;
          10) journalctl -u hysteria2-server -n 50 --no-pager ;;
        esac; pause_return ;;
      3|03) change_domain ;;
      4|04) change_slowdns ;;
      8|08) change_slipstream ;;
      6|06) change_status ;;
      7|07) change_banner ;;
      9|09) restart_service "server-sldns hysteria-server hysteria2-server badvpn udp-custom zivpn" "UDP Core Services"; pause_return ;;
      5|05) remove_script ;;
      0|00) break ;;
    esac
  done
}

remove_script() {
  clear
  echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
  echo -e "                     ${BOLD}DESINSTALACIÓN COMPLETA${NC}"
  echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
  read -rp "  ¿Estás completamente seguro? [y/N]: " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
      echo -e "\nDeteniendo servicios..."
      systemctl stop ws-proxy@* server-sldns badvpn hysteria-server hysteria2-server sslh stunnel4 squid nginx xray slipstream danted dnsdist 2>/dev/null || true
      systemctl disable ws-proxy@* server-sldns badvpn hysteria-server hysteria2-server xray slipstream danted dnsdist 2>/dev/null || true
      echo "Eliminando archivos..."
      rm -f /etc/systemd/system/ws-proxy@.service /etc/systemd/system/server-sldns.service /etc/systemd/system/badvpn.service /etc/systemd/system/xray.service /etc/systemd/system/slipstream.service /etc/systemd/system/hysteria2-server.service
      rm -f /etc/cron.d/service-checker /etc/cron.d/logrotate /etc/cron.d/xray-expiry /etc/cron.d/hysteria-expiry /etc/cron.d/hysteria2-expiry /etc/sysctl.d/99-freenet-tuning.conf /etc/security/limits.d/99-freenet.conf
      rm -rf /etc/deekayvpn /etc/slowdns /etc/socksproxy /etc/xray /etc/hysteria /etc/hysteria2 /usr/local/bin/hysteria2 /usr/local/libexec/hysteria2-auth /etc/dnsdist /etc/danted.conf /opt/slipstream-rust /usr/local/bin/menu /usr/bin/menu /usr/bin/Menu
      systemctl daemon-reload; sysctl --system >/dev/null 2>&1 || true
      echo -e "${GREEN}✔ Eliminación completa.${NC}"
  else echo "Cancelado."; fi
  pause_return
}

# --- Main Dashboard ---
draw_header() {
  local os_name=$(. /etc/os-release 2>/dev/null; echo "${ID:-UNKNOWN}" | tr '[:lower:]' '[:upper:]')
  local os_ver=$(. /etc/os-release 2>/dev/null; echo "${VERSION_ID:-}")
  local os="${os_name} ${os_ver}"
  local arch=$(uname -m)
  local cores=$(cpu_count)
  local ip=$(server_ip)
  local time=$(date '+%H:%M %Z')
  local status=$(server_status)
  local ram=$(ram_percent)
  local cpu=$(cpu_percent)
  local buf=$(buffer_mem)

  echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}       >>>>>  🐉  ${YELLOW}${BOLD}Hex Auto${NC}${BLUE}  ✸  ${YELLOW}${BOLD}Por JotchuaDevz${NC}${BLUE}  🐉  <<<<<${NC}"
  echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
  printf "  ${WHITE}%-5s${NC} ${YELLOW}%-17s${NC} ${WHITE}%-6s${NC} ${YELLOW}%-14s${NC} ${WHITE}%-7s${NC} ${YELLOW}%s${NC}\n" "OS:" "$os" "Arch:" "$arch" "Cores:" "$cores"
  printf "  ${WHITE}%-5s${NC} ${YELLOW}%-17s${NC} ${WHITE}%-6s${NC} ${YELLOW}%-14s${NC} ${WHITE}%-7s${NC} %s\n" "IP:" "$ip" "Time:" "$time" "Status:" "$status"
  echo -e "${CYAN}------------------------ ${BOLD}Puertos Abiertos${NC} ${CYAN}------------------------${NC}"
  printf "  ${WHITE}• %-12s${NC} ${GREEN}%-22s${NC} ${WHITE}• %-13s${NC} ${GREEN}%s${NC}\n" "SSH:" "22, 299" "System-DNS:" "53"
  printf "  ${WHITE}• %-12s${NC} ${GREEN}%-22s${NC} ${WHITE}• %-13s${NC} ${GREEN}%s${NC}\n" "WEB-Nginx:" "85" "SSL:" "443"
  printf "  ${WHITE}• %-12s${NC} ${GREEN}%-22s${NC} ${WHITE}• %-13s${NC} ${GREEN}%s${NC}\n" "SSL/PYTHON:" "443"  "Squid:" "3128, 8000"
  printf "  ${WHITE}• %-12s${NC} ${GREEN}%-22s${NC} ${WHITE}• %-13s${NC} ${GREEN}%s${NC}\n" "WS/PYTHON:" "80, 8080, 8880" "BadVPN:" "7300"
  printf "  ${WHITE}• %-12s${NC} ${GREEN}%-22s${NC} ${WHITE}• %-13s${NC} ${GREEN}%s${NC}\n" "WS/PYTHON:" "2082, 2086, 25" "XRAY NTLS:" "80, 8080, 8880"
  printf "  ${WHITE}• %-12s${NC} ${GREEN}%-22s${NC} ${WHITE}• %-13s${NC} ${GREEN}%s${NC}\n" "XRAY TLS:" "443" "SlowDNS/SS:" "53 (dnsdist)"
  printf "  ${WHITE}• %-12s${NC} ${GREEN}%-22s${NC} ${WHITE}• %-13s${NC} ${GREEN}%s${NC}\n" "SOCKS:" "127.0.0.1:1080" "Hysteria 1:" "20000-50000"
  printf "  ${WHITE}• %-12s${NC} ${GREEN}%-22s${NC} ${WHITE}• %-13s${NC} ${GREEN}%s${NC}\n" "Hysteria 2:" "36713/UDP" "UDPCustom:" "1-65535"
  printf "  ${WHITE}• %-12s${NC} ${GREEN}%-22s${NC} ${WHITE}• %-13s${NC} ${GREEN}%s${NC}\n" "ZiVPN:" "6000-19999"
  echo -e "${CYAN}----------------------- ${BOLD}Recursos Del Sistema${NC} ${CYAN}-----------------------${NC}"
  printf "  ${WHITE}%-10s${NC} ${YELLOW}%-14s${NC} ${WHITE}%-10s${NC} ${YELLOW}%-10s${NC} ${WHITE}%-8s${NC} ${YELLOW}%s${NC}\n" "RAM Usada:" "$ram" "CPU Usada:" "$cpu" "Buffer:" "$buf"
  echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
}

while true; do
  clear; draw_header; echo
  echo -e "  [${YELLOW}01${NC}] Gestión de Cuentas SSH (Legado)"
  echo -e "  [${YELLOW}02${NC}] Gestión de Cuentas Xray (V2ray)"
  echo -e "  [${YELLOW}03${NC}] Gestión de Cuentas Hysteria (UDP)"
  echo -e "  [${YELLOW}04${NC}] Gestión de Cuentas Hysteria 2 (UDP)"
  echo -e "  [${YELLOW}05${NC}] ZiVPN Account Management (UDP)"
  echo -e "  [${YELLOW}05${NC}] Monitorear Conexiones Activas"
  echo -e "  [${YELLOW}06${NC}] Control de Servicios (Reiniciar Protocolos)"
  echo -e "  [${YELLOW}07${NC}] Respaldar y Restaurar Datos"
  echo -e "  [${YELLOW}08${NC}] Utilidades del Sistema (BBR y Netflix)"
  echo -e "  [${YELLOW}09${NC}] Configuración Avanzada (Dominio / Nameserver)"
  echo -e "  [${YELLOW}10${NC}] Reiniciar Servidor"
  echo -e "  [${RED}00${NC}] Salir\n"
  read -rp "  ► Selecciona una opción: " opt
  case "$opt" in
    1|01) 
      while true; do
        clear; echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}\n                   ${BOLD}GESTIÓN DE CUENTAS SSH${NC}\n${CYAN}══════════════════════════════════════════════════════════════${NC}"
        echo -e "  [${YELLOW}1${NC}] Crear Usuario SSH\n  [${YELLOW}2${NC}] Extender Expiración\n  [${YELLOW}3${NC}] Eliminar Usuario SSH\n  [${YELLOW}4${NC}] Listar Todas Las Cuentas\n  [${YELLOW}0${NC}] Atrás\n"
        read -rp "  ► Opción: " sub; case "$sub" in 1) create_user;; 2) extend_user;; 3) delete_user;; 4) list_real_users | nl -w2 -s'. '; pause_return;; 0) break;; esac
      done ;;
    2|02) 
      while true; do
        clear; echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}\n                   ${BOLD}GESTIÓN DE CUENTAS XRAY${NC}\n${CYAN}══════════════════════════════════════════════════════════════${NC}"
        echo -e "  [${YELLOW}1${NC}] Agregar Cuenta Xray\n  [${YELLOW}2${NC}] Renovar Cuenta Xray\n  [${YELLOW}3${NC}] Eliminar Cuenta Xray\n  [${YELLOW}4${NC}] Mostrar Enlaces de Config\n  [${YELLOW}5${NC}] Forzar Eliminación de Usuarios Xray Expirados\n  [${YELLOW}6${NC}] Actualizar Versión de Xray Core\n  [${YELLOW}0${NC}] Atrás\n"
        read -rp "  ► Opción: " sub; case "$sub" in 1) add_xray;; 2) renew_xray;; 3) del_xray;; 4) show_xray;; 5) /usr/local/bin/exp-check; echo "Usuarios Xray expirados eliminados."; pause_return;; 6) systemctl stop xray; XRAY_VER="v26.5.9"; echo "Reinstalando Xray Core ${XRAY_VER}..."; wget -qO /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VER}/Xray-linux-64.zip"; unzip -q -o /tmp/xray.zip -d /tmp/xray/ && mv -f /tmp/xray/xray /usr/local/bin/xray; systemctl start xray; echo -e "${GREEN}✔ ¡Xray Restaurado a ${XRAY_VER}!${NC}"; pause_return;; 0) break;; esac
      done ;;
    3|03)
      while true; do
        clear; echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}\n                   ${BOLD}GESTIÓN DE CUENTAS HYSTERIA${NC}\n${CYAN}══════════════════════════════════════════════════════════════${NC}"
        echo -e "  [${YELLOW}1${NC}] Agregar Cuenta Hysteria\n  [${YELLOW}2${NC}] Renovar Cuenta Hysteria\n  [${YELLOW}3${NC}] Eliminar Cuenta Hysteria\n  [${YELLOW}4${NC}] Listar Todas Las Cuentas\n  [${YELLOW}5${NC}] Editar Velocidades Subida/Bajada\n  [${YELLOW}6${NC}] Cambiar Obfs\n  [${YELLOW}0${NC}] Atrás\n"
        read -rp "  ► Opción: " sub; case "$sub" in 1) add_hysteria;; 2) extend_hysteria;; 3) del_hysteria;; 4) list_hysteria;; 5) speed_hysteria;; 6) change_obfs_hysteria;; 0) break;; esac
      done ;;
    4|04)
      while true; do
        clear; echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}\n                   ${BOLD}GESTIÓN DE CUENTAS HYSTERIA 2${NC}\n${CYAN}══════════════════════════════════════════════════════════════${NC}"
        echo -e "  [${YELLOW}1${NC}] Agregar Cuenta Hysteria 2\n  [${YELLOW}2${NC}] Renovar Cuenta Hysteria 2\n  [${YELLOW}3${NC}] Eliminar Cuenta Hysteria 2\n  [${YELLOW}4${NC}] Listar Todas Las Cuentas\n  [${YELLOW}5${NC}] Mostrar Enlace de Cuenta\n  [${YELLOW}0${NC}] Atrás\n"
        read -rp "  ► Opción: " sub; case "$sub" in 1) add_hysteria2;; 2) extend_hysteria2;; 3) del_hysteria2;; 4) list_hysteria2;; 5) show_hysteria2;; 0) break;; esac
      done ;;
      5|05)
      while true; do
        clear; echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}\n                   ${BOLD}GESTION DE CUENTAS ZIVPN${NC}\n${CYAN}══════════════════════════════════════════════════════════════${NC}"
        echo -e "  [${YELLOW}1${NC}] Agregar Cuenta ZiVPN\n  [${YELLOW}2${NC}] Renovar Cuenta ZiVPN\n  [${YELLOW}3${NC}] Eliminar Cuenta ZiVPN\n  [${YELLOW}4${NC}] Listar Todas Las Cuentas\n  [${YELLOW}0${NC}] Atrás\n"
        read -rp "  ► Opción: " sub; case "$sub" in 1) add_zivpn;; 2) extend_zivpn;; 3) del_zivpn;; 4) list_zivpn;; 0) break;; esac
      done ;;
    6|06) online_users ;;
    7|07) service_control_menu ;;
    8|08)
      clear; echo -e "  [1] Respaldar Configuraciones del Sistema\n  [2] Restaurar Desde Respaldo\n  [0] Atrás"
      read -rp " Selecciona: " subopt; case "$subopt" in 1) backup_snapshot;; 2) restore_snapshot;; esac ;;
    9|09) utilities_menu ;;
    10) advanced_menu ;;
    11) clear; read -rp "¿Reiniciar el servidor ahora? [y/N]: " ans; [[ "$ans" =~ ^[Yy]$ ]] && reboot ;;
    0|00) clear; exit 0 ;;
  esac
done
EOF_MENU

