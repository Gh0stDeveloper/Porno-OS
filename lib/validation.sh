#!/usr/bin/env bash

normalize_architecture() {
  case "$(uname -m)" in
    x86_64|amd64) printf amd64 ;;
    aarch64|arm64) printf arm64 ;;
    armv7l|armv7*) printf arm ;;
    i386|i486|i586|i686) printf 386 ;;
    *) return 1 ;;
  esac
}

validate_operating_system() {
  [[ -r /etc/os-release ]] || die "No se pudo leer /etc/os-release."
  # shellcheck disable=SC1091
  source /etc/os-release
  case "${ID:-}:${VERSION_ID:-}" in
    debian:11|debian:12|ubuntu:20.04|ubuntu:22.04|ubuntu:24.04) ;;
    *) die "Sistema no soportado: ${ID:-desconocido} ${VERSION_ID:-}." ;;
  esac
}

validate_resources() {
  local mem_kb disk_kb
  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
  disk_kb="$(df -Pk / | awk 'NR==2 {print $4}')"
  ((mem_kb >= ${HEXTUNNEL_MIN_RAM_KB:-524288})) || die "Se requieren al menos 512 MiB de RAM."
  ((disk_kb >= ${HEXTUNNEL_MIN_DISK_KB:-1048576})) || die "Se requiere al menos 1 GiB libre en /."
}

validate_connectivity() {
  local url
  for url in https://github.com https://api.github.com https://1.1.1.1; do
    curl -fsSI --connect-timeout 5 --max-time 10 "$url" >/dev/null 2>&1 && return 0
  done
  die "No hay conectividad HTTPS utilizable."
}

primary_ipv4() {
  local address
  address="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}')"
  [[ -n "$address" ]] || address="$(hostname -I 2>/dev/null | awk '{print $1}')"
  printf '%s' "$address"
}

port_listener_lines() {
  local protocol="$1" port="$2"
  if [[ "$protocol" == udp ]]; then
    ss -H -lunp "sport = :$port" 2>/dev/null || true
  else
    ss -H -ltnp "sport = :$port" 2>/dev/null || true
  fi
}

port_is_listening() {
  local protocol="$1" port="$2" scope="${3:-any}" lines public_ip escaped_ip
  lines="$(port_listener_lines "$protocol" "$port")"
  [[ -n "$lines" ]] || return 1
  [[ "$scope" != public ]] && return 0
  public_ip="$(primary_ipv4)"
  escaped_ip="${public_ip//./\.}"
  grep -Eq "(^|[[:space:]])(\\*|0\\.0\\.0\\.0|\\[::\\]|${escaped_ip}):${port}([[:space:]]|$)" <<< "$lines"
}

module_allows_existing_listener() {
  local module="$1" protocol="$2" port="$3" owner="$4" function

  # Existing OpenSSH installations may be owned by sshd directly or by
  # systemd socket activation. Only tcp/22 receives this built-in exception.
  if [[ "$module" == ssh && "$protocol" == tcp && "$port" == 22 ]]; then
    [[ "$owner" == *sshd* || "$owner" == *systemd* ]] && return 0
  fi

  function="$(module_function "$module" allow_port_conflict)"
  declare -F "$function" >/dev/null 2>&1 || return 1
  "$function" "$protocol" "$port" "$owner"
}

validate_requested_ports() {
  local module protocol port source scope owner
  for module in "$@"; do
    module_is_installed "$module" && continue
    while read -r protocol port source scope; do
      [[ -n "$protocol" && -n "$port" ]] || continue
      if port_is_listening "$protocol" "$port" "${scope:-any}"; then
        owner="$(port_listener_lines "$protocol" "$port" | head -n1)"
        if module_allows_existing_listener "$module" "$protocol" "$port" "$owner"; then
          log_info "Puerto existente aceptado por $module: $protocol/$port"
          continue
        fi
        [[ "${HEXTUNNEL_FORCE:-0}" == 1 ]] || die "El puerto $protocol/$port ya está ocupado: ${owner:-proceso desconocido}."
        log_warn "Puerto ocupado permitido por --force: $protocol/$port"
      fi
    done < <(module_call "$module" ports || true)
  done
}

preflight_all() {
  require_root
  command_exists systemctl || die "systemd/systemctl es obligatorio."
  command_exists curl || die "curl es obligatorio."
  command_exists ss || die "iproute2/ss es obligatorio."
  validate_operating_system
  HEXTUNNEL_ARCH="$(normalize_architecture)" || die "Arquitectura no soportada: $(uname -m)."
  export HEXTUNNEL_ARCH
  validate_resources
  validate_connectivity
  validate_requested_ports "$@"
  log_success "Preflight correcto: OS, arquitectura, RAM, disco, red y puertos."
}

validate_selected_modules() {
  local module
  for module in "$@"; do module_validate "$module"; done
}
