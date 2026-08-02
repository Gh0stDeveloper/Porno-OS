#!/usr/bin/env bash

# Architecture policy and per-architecture runtime adjustments.
# This file is sourced after all module files so it can define module contracts
# without duplicating implementation logic.

hextunnel_current_architecture() {
  if [[ -n "${HEXTUNNEL_ARCH:-}" ]]; then
    printf '%s' "$HEXTUNNEL_ARCH"
  else
    normalize_architecture
  fi
}

# Modules without this contract are considered portable across all production
# architectures accepted by lib/validation.sh.
udp_custom_supported_architectures() { printf '%s\n' amd64; }
slowdns_supported_architectures() { printf '%s\n' amd64; }
slipstream_supported_architectures() { printf '%s\n' amd64; }
legacy_all_supported_architectures() { printf '%s\n' amd64; }

module_supports_architecture() {
  local module="$1" architecture="${2:-$(hextunnel_current_architecture)}"
  local function supported
  function="$(module_function "$module" supported_architectures)"
  declare -F "$function" >/dev/null 2>&1 || return 0
  while IFS= read -r supported; do
    [[ -n "$supported" ]] || continue
    [[ "$supported" == "$architecture" ]] && return 0
  done < <("$function")
  return 1
}

validate_module_architectures() {
  local architecture module unsupported=()
  architecture="$(hextunnel_current_architecture)" \
    || die "No se pudo normalizar la arquitectura del sistema."
  for module in "$@"; do
    module_supports_architecture "$module" "$architecture" \
      || unsupported+=("$module")
  done
  ((${#unsupported[@]} == 0)) || die \
    "Módulos no disponibles de forma segura para $architecture: $(join_by ', ' "${unsupported[@]}")."
}

prepare_module_architecture_environment() {
  local module="$1" architecture
  architecture="$(hextunnel_current_architecture)" || return 1
  [[ "$architecture" == arm64 ]] || return 0

  # The release component lock is generated on amd64. These two modules query
  # the exact ARM64 release asset and verify GitHub's SHA-256 digest at runtime;
  # retaining the amd64 checksum would correctly reject the ARM64 binary.
  case "$module" in
    hysteria)
      unset HEXTUNNEL_SINGBOX_SHA256
      ;;
    zivpn)
      unset HEXTUNNEL_ZIVPN_SHA256
      ;;
  esac
}

hextunnel_arm64_default_modules() {
  printf '%s\n' ssh xray hysteria hysteria2 zivpn webmin
}
