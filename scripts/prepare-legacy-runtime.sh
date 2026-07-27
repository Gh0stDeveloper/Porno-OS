#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SOURCE="${1:-}"
OUTPUT="${2:-}"
MODE="${3:-}"
[[ -r "$SOURCE" ]] || { echo "ERROR: no se puede leer el instalador original." >&2; exit 1; }
[[ -n "$OUTPUT" ]] || { echo "ERROR: falta el archivo de salida." >&2; exit 1; }
[[ "$MODE" == beta || "$MODE" == licensed ]] || { echo "ERROR: modo de preparación inválido." >&2; exit 1; }

awk -v mode="$MODE" '
function emit_header() {
  print "HEXTUNNEL_PACKAGE_ROOT=\"${HEXTUNNEL_PACKAGE_ROOT:?HEXTUNNEL_PACKAGE_ROOT no configurado}\""
  print "if [[ -r \"$HEXTUNNEL_PACKAGE_ROOT/config/component-lock.env\" ]]; then"
  print "  source \"$HEXTUNNEL_PACKAGE_ROOT/config/component-lock.env\""
  print "fi"
  print "if [[ -r /etc/hextunnel/hextunnel.env ]]; then"
  print "  source /etc/hextunnel/hextunnel.env"
  print "fi"
  print ": \"${HEXTUNNEL_SLOWDNS_BINARY_URL:?Falta URL bloqueada de SlowDNS}\""
  print ": \"${HEXTUNNEL_SLOWDNS_SHA256:?Falta SHA-256 bloqueado de SlowDNS}\""
  print ": \"${HEXTUNNEL_SINGBOX_BINARY_URL:?Falta URL bloqueada de sing-box}\""
  print ": \"${HEXTUNNEL_SINGBOX_SHA256:?Falta SHA-256 bloqueado de sing-box}\""
  print ": \"${HEXTUNNEL_BADVPN_SOURCE_URL:?Falta URL bloqueada de BadVPN}\""
  print ": \"${HEXTUNNEL_BADVPN_SHA256:?Falta SHA-256 bloqueado de BadVPN}\""
  print ": \"${HEXTUNNEL_UDP_CUSTOM_BINARY_URL:?Falta URL bloqueada de UDP Custom}\""
  print ": \"${HEXTUNNEL_UDP_CUSTOM_SHA256:?Falta SHA-256 bloqueado de UDP Custom}\""
  print ": \"${HEXTUNNEL_ZIVPN_BINARY_URL:?Falta URL bloqueada de ZiVPN}\""
  print ": \"${HEXTUNNEL_ZIVPN_SHA256:?Falta SHA-256 bloqueado de ZiVPN}\""
}
BEGIN {
  license=upgrade=resolved_stop=resolved_disable=resolv_rm=resolv_write=firewall_purge=0
  webmin=slowdns=singbox=badvpn=udp_binary=udp_config=zivpn=profile=menu_slip=0
  perm_slowdns=perm_udp=perm_zivpn=perm_hysteria=perm_xray=0
  skip_webmin=skip_profile=skip_badvpn=skip_menu_slip=0
}
NR == 1 { print; emit_header(); next }

skip_profile {
  if ($0 == "EOF_PROFILE") { skip_profile=0; print "echo \"Se conserva /root/.profile sin modificaciones.\"" }
  next
}
$0 == "cat > /root/.profile <<\047EOF_PROFILE\047" { profile++; skip_profile=1; next }

skip_webmin {
  if ($0 == "systemctl restart webmin || true") {
    skip_webmin=0
    print "echo \"Webmin se instalará mediante el módulo mantenido al finalizar.\""
  }
  next
}
$0 == "wget -q https://github.com/webmin/webmin/releases/download/2.111/webmin_2.111_all.deb" {
  webmin++; skip_webmin=1; next
}

skip_badvpn {
  if ($0 == "chmod +x /usr/bin/badvpn-udpgw") {
    skip_badvpn=0
    print "\"$HEXTUNNEL_PACKAGE_ROOT/bin/hextunnel-install-locked-component\" badvpn"
  }
  next
}
$0 == "# BadVPN Binary (Provides 127.0.0.1:7300 upstream for UDP Custom)" {
  badvpn++; print; skip_badvpn=1; next
}

skip_menu_slip {
  if ($0 == "change_status() {") {
    skip_menu_slip=0
    print "install_slipstream() {"
    print "    clear"
    print "    current_ns=$(grep \047ExecStart=\047 /etc/systemd/system/server-sldns.service 2>/dev/null | sed \047s/.*server\\.key \\([^ ]*\\) .*/\\1/\047)"
    print "    read -rp \" Ingresa el dominio para SlipStream: \" SlipstreamDomain"
    print "    if [[ -z \"$SlipstreamDomain\" || \"$SlipstreamDomain\" == \"$current_ns\" ]]; then"
    print "        echo \"Dominio inválido o igual al Nameserver de SlowDNS.\""
    print "        pause_return; return"
    print "    fi"
    print "    if /usr/local/bin/hextunnel-slipstream-compat \"$SlipstreamDomain\" \"$current_ns\"; then"
    print "        echo \"$SlipstreamDomain\" > /etc/deekayvpn/slipstream_domain.txt"
    print "        chmod 600 /etc/deekayvpn/slipstream_domain.txt"
    print "        echo \"SlipStream instalado mediante el módulo mantenido.\""
    print "    else"
    print "        echo \"No se pudo instalar SlipStream. Revisa hextunnel doctor.\""
    print "    fi"
    print "    pause_return"
    print "}"
    print ""
    print $0
  }
  next
}
$0 == "install_slipstream() {" { menu_slip++; skip_menu_slip=1; next }

$0 ~ /^[[:space:]]*validar_key_hextunnel[[:space:]]*$/ {
  license++
  if (mode == "beta") {
    print "[[ \"${HEXTUNNEL_BETA_MODE:-0}\" == 1 ]] || { echo \"ERROR: beta no autorizada.\" >&2; exit 1; }"
    print "echo \"Modo de prueba autorizado. Iniciando instalación completa saneada...\""
  } else {
    print "[[ \"${HEXTUNNEL_LICENSE_PREVALIDATED:-0}\" == 1 ]] || { echo \"ERROR: licencia no validada.\" >&2; exit 1; }"
    print "echo \"Licencia validada. Iniciando instalación completa saneada...\""
  }
  next
}

$0 == "echo \"  -> Actualizando el sistema (apt upgrade)...\"" {
  print "echo \"  -> Actualizando índices de paquetes...\""; next
}
$0 == "apt-get update -y && apt-get upgrade -y --with-new-pkgs" {
  upgrade++; print "apt-get update -y"; next
}
$0 == "systemctl stop systemd-resolved 2>/dev/null" {
  resolved_stop++; print "echo \"systemd-resolved se conserva activo.\""; next
}
$0 == "systemctl disable systemd-resolved 2>/dev/null" {
  resolved_disable++; print ": # systemd-resolved preservado"; next
}
$0 == "rm -f /etc/resolv.conf" {
  resolv_rm++; print "echo \"/etc/resolv.conf se conserva.\""; next
}
$0 ~ /^printf .nameserver %s/ && $0 ~ /> \/etc\/resolv.conf$/ {
  resolv_write++; print ": # resolver administrado por el sistema"; next
}
$0 == "apt -y --purge remove apache2 ufw firewalld" {
  firewall_purge++; print "echo \"No se eliminan firewalls ni servidores ajenos; los conflictos ya fueron revisados por preflight.\""; next
}
$0 == "MyVPS_Time=\047Africa/Accra\047" {
  print "MyVPS_Time=\"$(timedatectl show -p Timezone --value 2>/dev/null || printf UTC)\""; next
}
$0 == "PermitRootLogin yes" { print "PermitRootLogin prohibit-password"; next }
$0 == "X11Forwarding yes" { print "X11Forwarding no"; next }
$0 == "LogLevel QUIET" { print "LogLevel INFO"; next }
$0 == "chmod 666 /etc/slowdns/server.pub" { perm_slowdns++; print "chmod 644 /etc/slowdns/server.pub"; next }
$0 == "chmod 666 /root/udp/config.json" { perm_udp++; print "chmod 600 /root/udp/config.json"; next }
$0 == "chmod 666 /etc/zivpn/config.json" { perm_zivpn++; print "chmod 600 /etc/zivpn/config.json"; next }
$0 == "chmod 644 /etc/hysteria/config.json" { perm_hysteria++; print "chmod 600 /etc/hysteria/config.json"; next }
$0 ~ /^chmod 644 \/etc\/xray\/tcp_user\.txt \/etc\/xray\/tls_user\.txt \/etc\/xray\/ws_user\.txt \/etc\/xray\/xhttp_user\.txt \/etc\/xray\/httpupgrade_user\.txt$/ {
  perm_xray++; print "chmod 600 /etc/xray/tcp_user.txt /etc/xray/tls_user.txt /etc/xray/ws_user.txt /etc/xray/xhttp_user.txt /etc/xray/httpupgrade_user.txt"; next
}
$0 ~ /echo 1 > \/proc\/sys\/net\/ipv6\/conf\/all\/disable_ipv6/ {
  print "echo \"IPv6 se conserva para evitar cortar sesiones y rutas existentes.\""; next
}
$0 ~ /sysctl -w net\.ipv6\.conf\.all\.disable_ipv6=1/ {
  print ": # IPv6 preservado"; next
}
$0 ~ /echo \"nameserver DNS1\" > \/etc\/resolv\.conf/ {
  print ": # resolver preservado en el servicio de inicio"; next
}
$0 ~ /chmod 777 \/var\/run\/sslh\/sslh\.pid/ {
  print "install -d -m 755 /var/run/sslh; install -o sslh -g sslh -m 640 /dev/null /var/run/sslh/sslh.pid"; next
}
$0 == "    InstallSlipstream=\"y\"" {
  print "    InstallSlipstream=\"deferred\""
  print "    echo \"SlipStream se instalará mediante el módulo mantenido después del panel.\""
  next
}
$0 ~ /https:\/\/sh\.rustup\.rs[[:space:]]*\|[[:space:]]*sh/ {
  print "        echo \"El instalador Rust heredado está deshabilitado; use el módulo mantenido.\""; next
}
$0 ~ /SLDNS\/main\/slowdns\/sldns-server/ {
  slowdns++; print "\"$HEXTUNNEL_PACKAGE_ROOT/bin/hextunnel-install-locked-component\" slowdns"; next
}
$0 ~ /sing-box_1\.12\.22_linux_amd64\.deb/ {
  singbox++
  print "\"$HEXTUNNEL_PACKAGE_ROOT/bin/hextunnel-install-locked-component\" sing-box"
  next
}
$0 == "dpkg -i /tmp/sing-box.deb" || $0 == "apt-mark hold sing-box" || $0 == "rm -f /tmp/sing-box.deb" { next }
$0 ~ /UDP-Custom\/main\/bin\/udp-custom-linux-amd64/ {
  udp_binary++; print "\"$HEXTUNNEL_PACKAGE_ROOT/bin/hextunnel-install-locked-component\" udp-custom"; next
}
$0 ~ /UDP-Custom\/main\/config\/config.json/ { udp_config++; next }
$0 ~ /udp-zivpn\/releases\/download\/udp-zivpn_1\.4\.9\/udp-zivpn-linux-amd64/ {
  zivpn++; print "\"$HEXTUNNEL_PACKAGE_ROOT/bin/hextunnel-install-locked-component\" zivpn"; next
}

{ print }
END {
  bad=0
  if (license != 1) { print "ERROR: llamada de licencia inesperada: " license > "/dev/stderr"; bad=1 }
  if (upgrade != 1 || resolved_stop != 1 || resolved_disable != 1) { print "ERROR: controles del sistema heredado no identificados" > "/dev/stderr"; bad=1 }
  if (resolv_rm != 1 || resolv_write != 1 || firewall_purge != 1) { print "ERROR: controles de red heredados no identificados" > "/dev/stderr"; bad=1 }
  if (webmin != 1 || profile != 1 || badvpn != 1 || menu_slip != 1) { print "ERROR: bloques heredados esperados no identificados" > "/dev/stderr"; bad=1 }
  if (slowdns != 1 || singbox != 1 || udp_binary != 1 || udp_config != 1 || zivpn != 1) { print "ERROR: descargas heredadas esperadas no identificadas" > "/dev/stderr"; bad=1 }
  if (perm_slowdns != 1 || perm_udp != 1 || perm_zivpn != 1 || perm_hysteria != 1 || perm_xray != 1) { print "ERROR: permisos heredados esperados no identificados" > "/dev/stderr"; bad=1 }
  if (bad) exit 42
}
' "$SOURCE" > "$OUTPUT"

chmod 700 "$OUTPUT"
bash -n "$OUTPUT"

for forbidden in \
  'apt-get upgrade' \
  'systemctl disable systemd-resolved' \
  'systemctl stop systemd-resolved' \
  'rm -f /etc/resolv.conf' \
  'chmod 777' \
  'chmod 666' \
  'ssl=0' \
  'raw.githubusercontent.com/.*/main/' \
  'sh.rustup.rs.*|.*sh' \
  'dropbox.com/.*/badvpn'; do
  if grep -E "$forbidden" "$OUTPUT" >/dev/null; then
    printf 'ERROR: el runtime heredado conserva un patrón prohibido: %s\n' "$forbidden" >&2
    exit 1
  fi
done

printf 'Runtime heredado saneado: %s\n' "$OUTPUT"
