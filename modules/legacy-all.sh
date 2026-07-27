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
    systemctl is-active --quiet "$unit" 2>/dev/null && return 0
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
  [[ -x /usr/local/bin/menu ]] && menu_state=present || failed=1
  legacy_all_service_active ssh sshd && ssh_state=active || failed=1
  legacy_all_service_active xray && xray_state=active || failed=1
  legacy_all_service_active stunnel4 && stunnel_state=active || failed=1
  printf 'menu=%s ssh=%s xray=%s stunnel=%s\n' "$menu_state" "$ssh_state" "$xray_state" "$stunnel_state"
  return "$failed"
}
