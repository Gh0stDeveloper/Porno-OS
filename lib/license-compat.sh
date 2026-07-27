#!/usr/bin/env bash

# Compatibility bridge for the existing TeleBotGen one-time key service.
# This path is disabled by default and must be enabled explicitly by the
# bootstrap command issued by the bot. The production distribution flow keeps
# using the signed HTTPS authorization implemented by install.sh.

hextunnel_legacy_key_codec() {
  local input="${1:-}" output="" char index
  for ((index=0; index<${#input}; index++)); do
    char="${input:index:1}"
    case "$char" in
      '.') char='*' ;;
      '*') char='.' ;;
      '1') char='@' ;;
      '@') char='1' ;;
      '2') char='?' ;;
      '?') char='2' ;;
      '4') char='%' ;;
      '%') char='4' ;;
      '-') char='K' ;;
      'K') char='-' ;;
    esac
    output+="$char"
  done
  printf '%s' "$output" | rev
}

hextunnel_legacy_license_parse() {
  local key="${1:-}" encoded decoded endpoint token host port
  [[ "$key" == HexGen/* ]] || return 1
  encoded="${key#HexGen/}"
  [[ -n "$encoded" && "$encoded" != "$key" ]] || return 1
  decoded="$(hextunnel_legacy_key_codec "$encoded")" || return 1
  endpoint="${decoded%/*}"
  token="${decoded##*/}"
  [[ "$endpoint" != "$decoded" && "$token" =~ ^[A-Za-z0-9_-]{20,128}$ ]] || return 1
  host="${endpoint%:*}"
  port="${endpoint##*:}"
  [[ -n "$host" && "$host" != "$endpoint" ]] || return 1
  [[ "$host" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
  [[ "$port" =~ ^[0-9]{1,5}$ ]] || return 1
  ((10#$port >= 1 && 10#$port <= 65535)) || return 1
  HEXTUNNEL_LEGACY_LICENSE_ENDPOINT="$endpoint"
  HEXTUNNEL_LEGACY_LICENSE_TOKEN="$token"
  export HEXTUNNEL_LEGACY_LICENSE_ENDPOINT HEXTUNNEL_LEGACY_LICENSE_TOKEN
}

hextunnel_legacy_public_ip() {
  local value
  value="$(curl -4fsS --connect-timeout 5 --max-time 10 https://api.ipify.org 2>/dev/null || true)"
  [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  printf '%s' "$value"
}

hextunnel_legacy_license_store() {
  local state_dir="${HEXTUNNEL_LICENSE_STATE_DIR:-/etc/hextunnel}"
  local key="$1" subject="$2" activated_at
  activated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  install -d -m 700 "$state_dir"
  printf '%s\n' "$key" > "$state_dir/license.key"
  chmod 600 "$state_dir/license.key"
  cat > "$state_dir/license-state.env" <<EOF
HEXTUNNEL_LICENSE_PROVIDER=telebotgen-compat
HEXTUNNEL_LICENSE_SUBJECT=$(printf '%q' "$subject")
HEXTUNNEL_LICENSE_ACTIVATED_AT=$(printf '%q' "$activated_at")
EOF
  chmod 600 "$state_dir/license-state.env"
}

hextunnel_validate_telebotgen_key() {
  [[ "${HEXTUNNEL_REQUIRE_BOT_KEY:-0}" == 1 ]] || return 0
  [[ "${HEXTUNNEL_LICENSE_PREVALIDATED:-0}" == 1 ]] && return 0
  [[ "${HEXTUNNEL_ALLOW_LEGACY_HTTP_LICENSE:-0}" == 1 ]] || {
    printf 'ERROR: el canal TeleBotGen usa HTTP heredado y requiere HEXTUNNEL_ALLOW_LEGACY_HTTP_LICENSE=1.\n' >&2
    return 1
  }

  local key="${HEXTUNNEL_LICENSE_KEY:-}" public_ip response url attempt
  local max_attempts="${HEXTUNNEL_LICENSE_MAX_ATTEMPTS:-5}"
  [[ "$max_attempts" =~ ^[1-9][0-9]?$ ]] || max_attempts=5

  for ((attempt=1; attempt<=max_attempts; attempt++)); do
    if [[ -z "$key" ]]; then
      [[ -t 0 ]] || {
        printf 'ERROR: no se proporcionó HEXTUNNEL_LICENSE_KEY y no existe una terminal interactiva.\n' >&2
        return 1
      }
      printf '\n============================================================\n'
      printf '                 ACTIVACIÓN HEX TUNNEL\n'
      printf '============================================================\n'
      read -r -s -p 'KEY: ' key
      printf '\n'
    fi

    if ! hextunnel_legacy_license_parse "$key"; then
      printf 'Key con formato inválido. Debe comenzar con HexGen/.\n' >&2
    elif ! public_ip="$(hextunnel_legacy_public_ip)"; then
      printf 'No se pudo determinar la IP pública del VPS.\n' >&2
    else
      url="http://${HEXTUNNEL_LEGACY_LICENSE_ENDPOINT}/${HEXTUNNEL_LEGACY_LICENSE_TOKEN}/HexGen/${public_ip}"
      printf 'Verificando key de un solo uso...\n'
      response="$(curl -fsS --connect-timeout 5 --max-time 15 --retry 1 "$url" 2>/dev/null || true)"
      response="${response//$'\r'/}"
      response="${response//$'\n'/}"
      case "$response" in
        HexGen)
          hextunnel_legacy_license_store "$key" "$public_ip"
          export HEXTUNNEL_LICENSE_KEY="$key"
          export HEXTUNNEL_LICENSE_PREVALIDATED=1
          export HEXTUNNEL_LICENSE_SUBJECT="$public_ip"
          printf 'Key válida. Activación completada para %s.\n' "$public_ip"
          return 0
          ;;
        'KEY INVALIDA!') printf 'La key expiró, ya fue utilizada o no existe.\n' >&2 ;;
        'KEY DE GENERADOR!'|'KEY DE HEXGEN!') printf 'La key no corresponde a una instalación de Hex Tunnel.\n' >&2 ;;
        *) printf 'No se pudo validar la key con el servidor TeleBotGen.\n' >&2 ;;
      esac
    fi

    key=""
    ((attempt < max_attempts)) || break
    [[ -t 0 ]] || return 1
    read -r -p '¿Intentar con otra key? [s/N]: ' response
    [[ "$response" =~ ^[SsYy]$ ]] || return 1
  done

  printf 'ERROR: se agotaron los intentos de activación.\n' >&2
  return 1
}
