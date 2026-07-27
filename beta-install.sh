#!/usr/bin/env bash
# Copyright (c) 2026 Hex Applications.
# Bootstrap temporal para pruebas privadas antes de habilitar el servidor de licencias.
set -Eeuo pipefail
umask 077

beta_error() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

beta_require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || beta_error "Hex Tunnel Beta debe ejecutarse como root."
}

beta_install_dependencies() {
  local command missing=0
  for command in curl tar sha256sum; do
    command -v "$command" >/dev/null 2>&1 || missing=1
  done
  ((missing == 0)) && return 0
  command -v apt-get >/dev/null 2>&1 || beta_error "Faltan dependencias y apt-get no está disponible."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends curl ca-certificates tar coreutils
}

beta_validate_archive_paths() {
  local archive="$1"
  if tar -tzf "$archive" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
    beta_error "El paquete beta contiene rutas no seguras."
  fi
}

beta_main() {
  local repository="${HEXTUNNEL_BETA_REPOSITORY:-Gh0stDeveloper/Porno-OS}"
  local ref="${HEXTUNNEL_BETA_REF:-}"
  local expected_sha="${HEXTUNNEL_BETA_ARCHIVE_SHA256:-}"
  local acknowledgement="${HEXTUNNEL_BETA_ACK:-}"
  local verify_only="${HEXTUNNEL_BETA_VERIFY_ONLY:-0}"
  local tmp archive extract_root entrypoint package_root
  local -a entrypoint_matches=()

  beta_require_root
  beta_install_dependencies

  [[ "$acknowledgement" == "ACEPTO_BETA_PRIVADA" ]] \
    || beta_error "Debes establecer HEXTUNNEL_BETA_ACK=ACEPTO_BETA_PRIVADA."
  [[ "$repository" == "Gh0stDeveloper/Porno-OS" ]] \
    || beta_error "El bootstrap beta solo admite Gh0stDeveloper/Porno-OS."
  [[ "$ref" =~ ^[0-9a-fA-F]{40}$ ]] \
    || beta_error "HEXTUNNEL_BETA_REF debe ser el SHA completo de un commit, no una rama."
  [[ "$verify_only" == 0 || "$verify_only" == 1 ]] \
    || beta_error "HEXTUNNEL_BETA_VERIFY_ONLY solo admite 0 o 1."

  printf '%s\n' '============================================================'
  printf '%s\n' '              HEX TUNNEL — BETA PRIVADA'
  printf '%s\n' '============================================================'
  printf 'Commit fijado: %s\n' "${ref,,}"
  printf '%s\n' 'Esta edición no usa todavía el servidor de licencias.'
  printf '%s\n' 'Úsala únicamente en un VPS de prueba limpio y con snapshot.'
  printf '%s\n' '============================================================'

  tmp="$(mktemp -d /tmp/hextunnel-beta.XXXXXX)"
  trap 'rm -rf "${tmp:-}"' EXIT
  archive="$tmp/hextunnel-beta.tar.gz"
  extract_root="$tmp/package"
  mkdir -p "$extract_root"

  curl -fsSL --retry 3 --connect-timeout 10 --max-time 300 \
    "https://codeload.github.com/${repository}/tar.gz/${ref}" \
    -o "$archive" || beta_error "No se pudo descargar el commit beta fijado."

  if [[ -n "$expected_sha" ]]; then
    [[ "$expected_sha" =~ ^[0-9a-fA-F]{64}$ ]] \
      || beta_error "HEXTUNNEL_BETA_ARCHIVE_SHA256 debe contener 64 caracteres hexadecimales."
    printf '%s  %s\n' "${expected_sha,,}" "$archive" | sha256sum -c - >/dev/null \
      || beta_error "El paquete beta no coincide con el SHA-256 configurado."
  fi

  beta_validate_archive_paths "$archive"
  tar -xzf "$archive" -C "$extract_root"

  mapfile -t entrypoint_matches < <(find "$extract_root" -type f -path '*/bin/hextunnel-beta-install' -print)
  ((${#entrypoint_matches[@]} == 1)) \
    || beta_error "El paquete beta no contiene un entrypoint único."
  entrypoint="${entrypoint_matches[0]}"
  package_root="${entrypoint%/bin/hextunnel-beta-install}"
  chmod 700 "$entrypoint"

  if [[ "$verify_only" == 1 ]]; then
    printf 'Paquete beta verificado correctamente para el commit %s.\n' "${ref,,}"
    return 0
  fi

  export HEXTUNNEL_BETA_MODE=1
  export HEXTUNNEL_BETA_SOURCE_SHA="${ref,,}"
  export HEXTUNNEL_BETA_PACKAGE_ROOT="$package_root"
  export HEXTUNNEL_NO_REBOOT="${HEXTUNNEL_NO_REBOOT:-1}"
  exec bash "$entrypoint" "$@"
}

beta_main "$@"
