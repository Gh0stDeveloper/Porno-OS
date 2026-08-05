#!/usr/bin/env bash

legacy_all_ports() { cat <<'EOF'
tcp 22
tcp 25
tcp 80
tcp 443
tcp 299
tcp 666
tcp 2082
tcp 2086
tcp 3128
tcp 4443
tcp 8000
tcp 8080
tcp 8880
tcp 10080
udp 53
udp 5667
udp 36712
udp 36713
udp 36717
EOF
}

legacy_all_dependencies() { :; }

legacy_all_resolved_loopback_listeners() {
  local listeners="$1" line found=0

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    found=1

    # Ubuntu systemd-resolved uses only its local stub listeners. A public or
    # wildcard listener must remain a hard conflict because Hex Tunnel needs
    # the interface address on UDP 53 for SlowDNS/dnsdist.
    [[ "$line" == *systemd-resolv* ]] || return 1
    [[ "$line" =~ 127\.0\.0\.(53|54)(%lo)?:53([[:space:]]|$) ]] || return 1
  done <<< "$listeners"

  ((found == 1))
}

# A clean Ubuntu/Debian VPS normally has OpenSSH listening on tcp/22 through
# sshd directly or through systemd socket activation. Hex Tunnel preserves that
# listener and later configures sshd on ports 22 and 299, so it is not a port
# conflict. Port 299 is also accepted when a previous/retried installation has
# already added it to OpenSSH.
#
# Ubuntu also runs systemd-resolved on 127.0.0.53/54:53. The sanitized runtime
# binds the DNS tunnel to the VPS interface address instead of 0.0.0.0, so the
# local resolver can remain active without occupying the public DNS listener.
legacy_all_allow_port_conflict() {
  local protocol="$1" port="$2" owner="$3"

  if [[ "$protocol" == tcp && ("$port" == 22 || "$port" == 299) ]]; then
    [[ "$owner" == *sshd* || "$owner" == *systemd* ]]
    return
  fi

  if [[ "$protocol" == udp && "$port" == 53 ]]; then
    legacy_all_resolved_loopback_listeners "$owner"
    return
  fi

  return 1
}

legacy_all_install() {
  local script="$HEXTUNNEL_ROOT/legacy/install-all.sh"
  [[ -x "$script" ]] || die "No se encontró el instalador original."
  log_warn "El modo completo conserva el panel original; usa snapshot del proveedor antes de instalar."
  confirm_action "¿Ejecutar el instalador original completo?" || die "Operación cancelada."
  run_cmd bash "$script"
}

legacy_all_uninstall() {
  die "La instalación completa no admite purga global automática. Restaura el snapshot del proveedor o desinstala módulos mantenidos por separado."
}

legacy_all_service_active() {
  local unit
  for unit in "$@"; do
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

legacy_all_validate() {
  bash -n "$HEXTUNNEL_ROOT/legacy/install-all.sh"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  [[ -x /usr/local/bin/menu ]] || die "El instalador completo no creó el menú."
  legacy_all_service_active ssh sshd || die "SSH no quedó activo."
  legacy_all_service_active xray || die "Xray no quedó activo."
  legacy_all_service_active stunnel4 || die "Stunnel no quedó activo."
}

legacy_all_doctor() {
  local failed=0 ssh_state=inactive xray_state=inactive stunnel_state=inactive menu_state=missing
  if [[ -x /usr/local/bin/menu ]]; then
    menu_state=present
  else
    failed=1
  fi
  if legacy_all_service_active ssh sshd; then
    ssh_state=active
  else
    failed=1
  fi
  if legacy_all_service_active xray; then
    xray_state=active
  else
    failed=1
  fi
  if legacy_all_service_active stunnel4; then
    stunnel_state=active
  else
    failed=1
  fi
  printf 'menu=%s ssh=%s xray=%s stunnel=%s\n' "$menu_state" "$ssh_state" "$xray_state" "$stunnel_state"
  return "$failed"
}
