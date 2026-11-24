#!/usr/bin/env bash
# Copyright (c) 2026 Hex Applications.
# Bootstrap sin licencia y gestor transaccional de Hex Tunnel (rama instalacion-sin-licencia).
set -Eeuo pipefail

bootstrap_error() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

bootstrap_require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || bootstrap_error "Hex Tunnel debe ejecutarse como root."
}

bootstrap_install_dependencies() {
  local command missing=0
  for command in curl jq openssl tar sha256sum date; do
    command -v "$command" >/dev/null 2>&1 || missing=1
  done
  ((missing == 0)) && return 0
  command -v apt-get >/dev/null 2>&1 || bootstrap_error "Faltan dependencias y apt-get no está disponible."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends curl jq openssl ca-certificates tar coreutils
}

bootstrap_install_without_license() {
  local branch="instalacion-sin-licencia"
  local repository="Gh0stDeveloper/Porno-OS"
  local sha beta_installer tmp

  bootstrap_require_root
  bootstrap_install_dependencies

  printf 'Hex Tunnel — instalación sin licencia (rama %s).\n' "$branch"
  printf 'Resolviendo el commit de la rama...\n'

  sha="$(curl -fsSL --retry 2 --connect-timeout 8 --max-time 20 \
    "https://api.github.com/repos/${repository}/commits/${branch}" \
    | jq -r '.sha // empty')" \
    || bootstrap_error "No se pudo consultar el commit de la rama ${branch}."
  [[ "$sha" =~ ^[0-9a-fA-F]{40}$ ]] \
    || bootstrap_error "La rama ${branch} no devolvió un commit válido."

  tmp="$(mktemp -d /tmp/hextunnel-sin-licencia.XXXXXX)"
  trap 'rm -rf "${tmp:-}"' EXIT
  beta_installer="$tmp/beta-install.sh"
  curl -fsSL --retry 3 --connect-timeout 10 --max-time 60 \
    "https://raw.githubusercontent.com/${repository}/${sha}/beta-install.sh" \
    -o "$beta_installer" \
    || bootstrap_error "No se pudo descargar beta-install.sh."
  [[ -s "$beta_installer" ]] || bootstrap_error "beta-install.sh llegó vacío."
  bash -n "$beta_installer" || bootstrap_error "beta-install.sh no pasó la revisión de sintaxis."
  chmod 700 "$beta_installer"

  printf 'Instalando el script completo (legacy/install-all.sh)...\n'
  export HEXTUNNEL_BETA_ACK="ACEPTO_BETA_PRIVADA"
  export HEXTUNNEL_BETA_REF="${sha,,}"
  bash "$beta_installer" "$@"
  exit $?
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P || true)"
if [[ -z "$SCRIPT_DIR" || ! -f "$SCRIPT_DIR/lib/common.sh" ]]; then
  bootstrap_install_without_license "$@"
fi

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/backup.sh"
source "$SCRIPT_DIR/lib/rollback.sh"
source "$SCRIPT_DIR/lib/systemd.sh"
source "$SCRIPT_DIR/lib/firewall.sh"
source "$SCRIPT_DIR/lib/nat.sh"
source "$SCRIPT_DIR/lib/secrets.sh"
source "$SCRIPT_DIR/lib/validation.sh"
source "$SCRIPT_DIR/lib/modules.sh"
source "$SCRIPT_DIR/lib/framework.sh"

usage() {
  cat <<'EOF'
Uso:
  ./install.sh install [modulo ...] [opciones]
  ./install.sh uninstall <modulo|--all>
  ./install.sh doctor
  ./install.sh rollback [id]
  ./install.sh legacy

Módulos:
  ssh xray hysteria hysteria2 udp-custom slowdns slipstream zivpn webmin legacy-all

Opciones:
  --dry-run          Mostrar acciones sin modificar el VPS.
  --non-interactive  No solicitar datos; requiere --modules o nombres explícitos.
  --no-reboot        No reiniciar el VPS al finalizar.
  --force            Permitir reemplazar instalaciones existentes.
  --help             Mostrar esta ayuda.
EOF
}

parse_arguments() {
  HEXTUNNEL_COMMAND="install"
  HEXTUNNEL_DRY_RUN="${HEXTUNNEL_DRY_RUN:-0}"
  HEXTUNNEL_NON_INTERACTIVE="${HEXTUNNEL_NON_INTERACTIVE:-0}"
  HEXTUNNEL_NO_REBOOT="${HEXTUNNEL_NO_REBOOT:-0}"
  HEXTUNNEL_FORCE="${HEXTUNNEL_FORCE:-0}"
  HEXTUNNEL_REQUESTED_MODULES=()
  if (($# > 0)) && [[ "$1" != --* ]]; then HEXTUNNEL_COMMAND="$1"; shift; fi
  while (($# > 0)); do
    case "$1" in
      --dry-run) HEXTUNNEL_DRY_RUN=1 ;;
      --non-interactive) HEXTUNNEL_NON_INTERACTIVE=1 ;;
      --no-reboot) HEXTUNNEL_NO_REBOOT=1 ;;
      --force) HEXTUNNEL_FORCE=1 ;;
      --all) HEXTUNNEL_REQUESTED_MODULES=(--all) ;;
      --help|-h) usage; exit 0 ;;
      --modules=*) IFS=',' read -r -a HEXTUNNEL_REQUESTED_MODULES <<< "${1#*=}" ;;
      *) HEXTUNNEL_REQUESTED_MODULES+=("$1") ;;
    esac
    shift
  done
  export HEXTUNNEL_COMMAND HEXTUNNEL_DRY_RUN HEXTUNNEL_NON_INTERACTIVE HEXTUNNEL_NO_REBOOT HEXTUNNEL_FORCE
}

select_modules_interactively() {
  local choice item
  cat <<'EOF'

Componentes disponibles:
   1) SSH + TLS
   2) Xray
   3) Hysteria v1
   4) Hysteria 2
   5) UDP Custom
   6) SlowDNS
   7) SlipStream
   8) ZiVPN
   9) Webmin
  10) Instalar todos los módulos nuevos
  11) Instalador original completo (compatibilidad)
EOF
  read -r -p "Selecciona números separados por espacios: " choice
  HEXTUNNEL_REQUESTED_MODULES=()
  for item in $choice; do
    case "$item" in
      1) HEXTUNNEL_REQUESTED_MODULES+=(ssh) ;;
      2) HEXTUNNEL_REQUESTED_MODULES+=(xray) ;;
      3) HEXTUNNEL_REQUESTED_MODULES+=(hysteria) ;;
      4) HEXTUNNEL_REQUESTED_MODULES+=(hysteria2) ;;
      5) HEXTUNNEL_REQUESTED_MODULES+=(udp-custom) ;;
      6) HEXTUNNEL_REQUESTED_MODULES+=(slowdns) ;;
      7) HEXTUNNEL_REQUESTED_MODULES+=(slipstream) ;;
      8) HEXTUNNEL_REQUESTED_MODULES+=(zivpn) ;;
      9) HEXTUNNEL_REQUESTED_MODULES+=(webmin) ;;
      10) HEXTUNNEL_REQUESTED_MODULES=(ssh xray hysteria hysteria2 udp-custom slowdns slipstream zivpn webmin) ;;
      11) HEXTUNNEL_REQUESTED_MODULES=(legacy-all) ;;
      *) die "Selección desconocida: $item" ;;
    esac
  done
}

install_selected_modules() {
  local module answer
  if ((${#HEXTUNNEL_REQUESTED_MODULES[@]} == 0)); then
    if [[ "$HEXTUNNEL_NON_INTERACTIVE" == 1 ]]; then
      die "En modo no interactivo indica módulos, por ejemplo: --modules=ssh,xray,hysteria2"
    fi
    select_modules_interactively
  fi
  ((${#HEXTUNNEL_REQUESTED_MODULES[@]} > 0)) || die "No seleccionaste ningún módulo."
  resolve_module_dependencies HEXTUNNEL_REQUESTED_MODULES
  preflight_all "${HEXTUNNEL_REQUESTED_MODULES[@]}"
  load_hextunnel_secrets
  firewall_prepare_backend
  transaction_begin "install-$(join_by - "${HEXTUNNEL_REQUESTED_MODULES[@]}")"
  trap 'transaction_fail "$?" "$BASH_LINENO" "$BASH_COMMAND"' ERR INT TERM
  firewall_snapshot
  install_framework
  for module in "${HEXTUNNEL_REQUESTED_MODULES[@]}"; do module_install "$module"; done
  validate_selected_modules "${HEXTUNNEL_REQUESTED_MODULES[@]}"
  transaction_commit
  trap - ERR INT TERM
  log_success "Instalación completada: $(join_by ', ' "${HEXTUNNEL_REQUESTED_MODULES[@]}")"
  if [[ "$HEXTUNNEL_NO_REBOOT" != 1 ]]; then
    if [[ "$HEXTUNNEL_NON_INTERACTIVE" == 1 ]]; then
      log_warn "Reinicio automático omitido en modo no interactivo."
    else
      read -r -p "¿Reiniciar el VPS ahora? [s/N]: " answer
      [[ "$answer" =~ ^[SsYy]$ ]] && run_cmd reboot
    fi
  fi
}

uninstall_selected_modules() {
  require_root
  ((${#HEXTUNNEL_REQUESTED_MODULES[@]} > 0)) || die "Indica un módulo o --all."
  if [[ "${HEXTUNNEL_REQUESTED_MODULES[0]}" == --all ]]; then
    HEXTUNNEL_REQUESTED_MODULES=(webmin zivpn slipstream slowdns udp-custom hysteria2 hysteria xray ssh)
  fi
  firewall_prepare_backend
  transaction_begin "uninstall-$(join_by - "${HEXTUNNEL_REQUESTED_MODULES[@]}")"
  trap 'transaction_fail "$?" "$BASH_LINENO" "$BASH_COMMAND"' ERR INT TERM
  local module
  for module in "${HEXTUNNEL_REQUESTED_MODULES[@]}"; do module_uninstall "$module"; done
  transaction_commit
  trap - ERR INT TERM
}

main() {
  umask 077
  parse_arguments "$@"
  init_logging
  load_runtime_config
  load_module_registry
  case "$HEXTUNNEL_COMMAND" in
    install) install_selected_modules ;;
    uninstall) uninstall_selected_modules ;;
    doctor) exec "$SCRIPT_DIR/bin/hextunnel" doctor ;;
    rollback) rollback_transaction "${HEXTUNNEL_REQUESTED_MODULES[0]:-}" ;;
    legacy) module_install legacy-all ;;
    help) usage ;;
    *) die "Comando desconocido: $HEXTUNNEL_COMMAND" ;;
  esac
}

main "$@"
