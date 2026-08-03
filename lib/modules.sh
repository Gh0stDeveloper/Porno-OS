#!/usr/bin/env bash

HEXTUNNEL_AVAILABLE_MODULES=(ssh xray hysteria hysteria2 udp-custom slowdns slipstream zivpn webmin legacy-all)
HEXTUNNEL_MODULE_STATE_DIR="${HEXTUNNEL_MODULE_STATE_DIR:-$HEXTUNNEL_STATE/modules}"
declare -A HEXTUNNEL_MODULE_FILES=()
declare -A HEXTUNNEL_MODULE_RESOLVED=()
declare -A HEXTUNNEL_MODULE_RESOLVING=()
HEXTUNNEL_RESOLVED_ORDER=()

if [[ -r "$HEXTUNNEL_ROOT/lib/nat.sh" ]] && ! declare -F nat_is_present >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  source "$HEXTUNNEL_ROOT/lib/nat.sh"
fi

if [[ -r "$HEXTUNNEL_ROOT/lib/ssh-mode.sh" ]]; then
  # shellcheck disable=SC1091
  source "$HEXTUNNEL_ROOT/lib/ssh-mode.sh"
fi

load_module_registry() {
  local module file
  for module in "${HEXTUNNEL_AVAILABLE_MODULES[@]}"; do
    file="$HEXTUNNEL_ROOT/modules/$module.sh"
    [[ -r "$file" ]] || die "Falta el módulo: $file"
    # shellcheck disable=SC1090
    source "$file"
    HEXTUNNEL_MODULE_FILES["$module"]="$file"
  done
  if [[ -r "$HEXTUNNEL_ROOT/lib/architecture.sh" ]]; then
    # Loaded after modules so architecture contracts can override or extend them.
    # shellcheck disable=SC1091
    source "$HEXTUNNEL_ROOT/lib/architecture.sh"
  fi
}

module_exists() {
  [[ -n "${HEXTUNNEL_MODULE_FILES[$1]:-}" ]]
}

module_function() {
  printf '%s_%s' "${1//-/_}" "$2"
}

module_call() {
  local module="$1" action="$2" function
  shift 2
  module_exists "$module" || die "Módulo desconocido: $module"
  function="$(module_function "$module" "$action")"
  declare -F "$function" >/dev/null 2>&1 || return 0
  "$function" "$@"
}

module_resolve_visit() {
  local module="$1" dependency
  module_exists "$module" || die "Módulo desconocido: $module"
  [[ "${HEXTUNNEL_MODULE_RESOLVED[$module]:-0}" == 1 ]] && return 0
  [[ "${HEXTUNNEL_MODULE_RESOLVING[$module]:-0}" != 1 ]] || die "Dependencia circular detectada en $module"
  HEXTUNNEL_MODULE_RESOLVING["$module"]=1
  while IFS= read -r dependency; do
    [[ -n "$dependency" ]] || continue
    module_resolve_visit "$dependency"
  done < <(module_call "$module" dependencies || true)
  unset 'HEXTUNNEL_MODULE_RESOLVING[$module]'
  HEXTUNNEL_MODULE_RESOLVED["$module"]=1
  HEXTUNNEL_RESOLVED_ORDER+=("$module")
}

resolve_module_dependencies() {
  local -n requested_ref="$1"
  local module
  HEXTUNNEL_MODULE_RESOLVED=()
  HEXTUNNEL_MODULE_RESOLVING=()
  HEXTUNNEL_RESOLVED_ORDER=()
  for module in "${requested_ref[@]}"; do
    module_resolve_visit "$module"
  done
  requested_ref=("${HEXTUNNEL_RESOLVED_ORDER[@]}")
}

module_mark_installed() {
  local module="$1" marker="$HEXTUNNEL_MODULE_STATE_DIR/$module"
  ensure_dir 700 "$HEXTUNNEL_MODULE_STATE_DIR"
  backup_path "$marker"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  cat > "$marker" <<EOF
installed_at=$(date -Is)
version=${HEXTUNNEL_VERSION:-development}
EOF
  chmod 600 "$marker"
}

module_mark_uninstalled() {
  local module="$1" marker="$HEXTUNNEL_MODULE_STATE_DIR/$module"
  backup_path "$marker"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || rm -f "$marker"
}

module_is_installed() {
  [[ -f "$HEXTUNNEL_MODULE_STATE_DIR/$1" ]]
}

module_install() {
  local module="$1"

  if declare -F install_progress_begin_module >/dev/null 2>&1; then
    install_progress_begin_module "$module"
  fi
  log_info "Instalando módulo: $module"

  if declare -F prepare_module_architecture_environment >/dev/null 2>&1; then
    prepare_module_architecture_environment "$module"
  fi

  if [[ "$module" == ssh ]]; then
    ssh_capture_socket_mode
  fi

  firewall_apply_module_ports "$module"
  module_call "$module" install

  if [[ "$module" == ssh ]]; then
    ssh_switch_to_service_mode
  fi

  module_validate "$module"
  module_mark_installed "$module"
  log_success "Módulo instalado: $module"
  if declare -F install_progress_end_module >/dev/null 2>&1; then
    install_progress_end_module "$module"
  fi
}

module_uninstall() {
  local module="$1"
  log_warn "Desinstalando módulo: $module"
  module_call "$module" uninstall

  if [[ "$module" == ssh ]]; then
    ssh_restore_socket_mode
  fi

  module_mark_uninstalled "$module"
  log_success "Módulo desinstalado: $module"
}

module_validate() {
  local module="$1"
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]]; then
    log_dry "validar módulo $module"
    return 0
  fi
  module_call "$module" validate
}

module_doctor() {
  module_call "$1" doctor
}
