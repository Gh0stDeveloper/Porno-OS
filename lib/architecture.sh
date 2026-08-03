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

# A server migrating from the legacy/rc.2 layout can already have the managed
# listeners active without module marker files. Accept only the expected owner
# for each managed port; unrelated processes remain a hard conflict.
ssh_allow_port_conflict() {
  local protocol="$1" port="$2" owner="$3"
  [[ "$protocol" == tcp ]] || return 1
  case "$port" in
    22|299)
      [[ "$owner" == *sshd* || "$owner" == *systemd* ]]
      ;;
    4443)
      [[ "$owner" == *stunnel* ]]
      ;;
    25|2082|2086|10080)
      [[ "$owner" == *node* ]]
      ;;
    *)
      return 1
      ;;
  esac
}

xray_allow_port_conflict() {
  local protocol="$1" port="$2" owner="$3"
  [[ "$protocol" == tcp ]] || return 1
  case "$port" in
    80|443|8080|8880)
      [[ "$owner" == *xray* ]]
      ;;
    *)
      return 1
      ;;
  esac
}

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

  case "$module" in
    hysteria)
      # Sing-box publica digest para ARM64 y el módulo lo verifica al resolver
      # el activo exacto. El checksum genérico del lock corresponde a AMD64.
      unset HEXTUNNEL_SINGBOX_SHA256
      ;;
    zivpn)
      [[ "${HEXTUNNEL_ZIVPN_ARM64_SHA256:-}" =~ ^[0-9a-fA-F]{64}$ ]] \
        || die "La release no contiene el SHA-256 ARM64 fijado para ZiVPN."
      [[ -n "${HEXTUNNEL_ZIVPN_ARM64_BINARY_URL:-}" ]] \
        || die "La release no contiene la URL ARM64 fijada para ZiVPN."
      HEXTUNNEL_ZIVPN_SHA256="${HEXTUNNEL_ZIVPN_ARM64_SHA256,,}"
      HEXTUNNEL_ZIVPN_BINARY_URL="$HEXTUNNEL_ZIVPN_ARM64_BINARY_URL"
      export HEXTUNNEL_ZIVPN_SHA256 HEXTUNNEL_ZIVPN_BINARY_URL
      ;;
  esac
}

hextunnel_arm64_default_modules() {
  printf '%s\n' ssh xray hysteria hysteria2 zivpn webmin
}
