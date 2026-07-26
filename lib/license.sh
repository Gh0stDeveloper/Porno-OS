#!/usr/bin/env bash

HEXTUNNEL_REQUIRE_LICENSE="${HEXTUNNEL_REQUIRE_LICENSE:-0}"
HEXTUNNEL_LICENSE_ENDPOINT="${HEXTUNNEL_LICENSE_ENDPOINT:-}"
HEXTUNNEL_LICENSE_PUBLIC_KEY="${HEXTUNNEL_LICENSE_PUBLIC_KEY:-/etc/hextunnel/license-public.pem}"
HEXTUNNEL_LICENSE_FILE="${HEXTUNNEL_LICENSE_FILE:-/etc/hextunnel/license.key}"

license_read_key() {
  local key="${HEXTUNNEL_LICENSE_KEY:-}"
  if [[ -z "$key" && -f "$HEXTUNNEL_LICENSE_FILE" ]]; then
    validate_private_env_file "$HEXTUNNEL_LICENSE_FILE"
    IFS= read -r key < "$HEXTUNNEL_LICENSE_FILE"
  fi
  [[ -n "$key" ]] || return 1
  printf '%s' "$key"
}

license_canonical_payload() {
  local status="$1" expires_at="$2" nonce="$3" subject="$4"
  printf 'status=%s\nexpires_at=%s\nnonce=%s\nsubject=%s\n' "$status" "$expires_at" "$nonce" "$subject"
}

license_validate_remote() {
  local key endpoint public_key nonce timestamp public_ip request response status expires_at response_nonce subject signature work
  key="$(license_read_key)" || die "La licencia es obligatoria y no se encontró HEXTUNNEL_LICENSE_KEY ni $HEXTUNNEL_LICENSE_FILE."
  endpoint="$HEXTUNNEL_LICENSE_ENDPOINT"
  public_key="$HEXTUNNEL_LICENSE_PUBLIC_KEY"
  [[ "$endpoint" == https://* ]] || die "HEXTUNNEL_LICENSE_ENDPOINT debe usar HTTPS."
  [[ -s "$public_key" ]] || die "Falta la clave pública de licencia: $public_key"
  nonce="$(openssl rand -hex 24)"
  timestamp="$(date -u +%s)"
  public_ip="$(curl -fsS --max-time 8 https://api.ipify.org)" || die "No se pudo determinar la IP pública para validar la licencia."
  request="$(jq -n --arg key "$key" --arg ip "$public_ip" --arg nonce "$nonce" --argjson timestamp "$timestamp" '{key:$key,ip:$ip,nonce:$nonce,timestamp:$timestamp}')"
  response="$(curl -fsS --retry 2 --connect-timeout 8 --max-time 20 \
    -H 'Content-Type: application/json' \
    -H 'Cache-Control: no-store' \
    --data-binary "$request" \
    "$endpoint")" || die "El servidor de licencias no respondió correctamente."
  jq empty <<< "$response" || die "La respuesta de licencia no es JSON válido."
  status="$(jq -r '.status // empty' <<< "$response")"
  expires_at="$(jq -r '.expires_at // empty' <<< "$response")"
  response_nonce="$(jq -r '.nonce // empty' <<< "$response")"
  subject="$(jq -r '.subject // empty' <<< "$response")"
  signature="$(jq -r '.signature // empty' <<< "$response")"
  [[ "$response_nonce" == "$nonce" ]] || die "La respuesta de licencia no corresponde a la solicitud actual."
  [[ "$subject" == "$public_ip" ]] || die "La licencia fue emitida para otro sujeto/IP."
  [[ "$status" == valid && -n "$expires_at" && -n "$signature" ]] || die "La licencia no es válida."
  date -d "$expires_at" +%s >/dev/null 2>&1 || die "La expiración de licencia es inválida."
  (( $(date -d "$expires_at" +%s) > $(date -u +%s) )) || die "La licencia está expirada."
  work="$(mktemp -d /tmp/hextunnel-license.XXXXXX)"
  trap 'rm -rf "${work:-}"' RETURN
  license_canonical_payload "$status" "$expires_at" "$response_nonce" "$subject" > "$work/payload"
  printf '%s' "$signature" | base64 -d > "$work/signature" 2>/dev/null || die "La firma de licencia no usa Base64 válido."
  openssl dgst -sha256 -verify "$public_key" -signature "$work/signature" "$work/payload" >/dev/null \
    || die "La firma criptográfica de la licencia no es válida."
  log_success "Licencia válida hasta $expires_at."
}

license_validate_if_required() {
  [[ "$HEXTUNNEL_REQUIRE_LICENSE" == 1 ]] || {
    log_debug "Validación de licencia segura desactivada."
    return 0
  }
  command_exists jq || die "jq es obligatorio para la licencia segura."
  command_exists openssl || die "openssl es obligatorio para la licencia segura."
  license_validate_remote
}
