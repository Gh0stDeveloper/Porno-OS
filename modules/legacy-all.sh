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
legacy_all_install() { local script="$HEXTUNNEL_ROOT/legacy/install-all.sh"; [[ -x "$script" ]] || die "No se encontró el instalador original."; log_warn "El modo legacy conserva el comportamiento original y no puede ofrecer rollback completo."; confirm_action "¿Ejecutar el instalador original completo?" || die "Operación cancelada."; run_cmd bash "$script"; }
legacy_all_uninstall() { die "El instalador heredado no dispone de desinstalación segura global."; }
legacy_all_validate() { bash -n "$HEXTUNNEL_ROOT/legacy/install-all.sh"; }
legacy_all_doctor() { printf 'compatibilidad: %s\n' "$HEXTUNNEL_ROOT/legacy/install-all.sh"; }
