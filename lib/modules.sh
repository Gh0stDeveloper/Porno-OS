#!/usr/bin/env bash
HEXTUNNEL_AVAILABLE_MODULES=(ssh xray hysteria2 slowdns slipstream zivpn webmin legacy-all)
declare -A HEXTUNNEL_MODULE_FILES=()
load_module_registry() { local module file; for module in "${HEXTUNNEL_AVAILABLE_MODULES[@]}"; do file="$HEXTUNNEL_ROOT/modules/$module.sh"; [[ -r "$file" ]] || die "Falta el módulo: $file"; source "$file"; HEXTUNNEL_MODULE_FILES["$module"]="$file"; done; }
module_exists() { [[ -n "${HEXTUNNEL_MODULE_FILES[$1]:-}" ]]; }
module_function() { printf '%s_%s' "${1//-/_}" "$2"; }
module_call() { local module="$1" action="$2" function; shift 2; module_exists "$module" || die "Módulo desconocido: $module"; function="$(module_function "$module" "$action")"; declare -F "$function" >/dev/null 2>&1 || return 0; "$function" "$@"; }
resolve_module_dependencies() { local -n requested="$1"; local resolved=() module dependency present item; for module in "${requested[@]}"; do module_exists "$module" || die "Módulo desconocido: $module"; while read -r dependency; do [[ -n "$dependency" ]] || continue; present=0; for item in "${resolved[@]}"; do [[ "$item" == "$dependency" ]] && present=1; done; ((present)) || resolved+=("$dependency"); done < <(module_call "$module" dependencies || true); present=0; for item in "${resolved[@]}"; do [[ "$item" == "$module" ]] && present=1; done; ((present)) || resolved+=("$module"); done; requested=("${resolved[@]}"); }
module_install() { local module="$1"; log_info "Instalando módulo: $module"; module_call "$module" install; firewall_apply_module_ports "$module"; module_call "$module" validate; log_success "Módulo instalado: $module"; }
module_uninstall() { local module="$1"; log_warn "Desinstalando módulo: $module"; module_call "$module" uninstall; log_success "Módulo desinstalado: $module"; }
module_validate() { module_call "$1" validate; }
module_doctor() { module_call "$1" doctor; }
