#!/usr/bin/env bash
# Copyright (c) 2026 Hex Applications.
# Bootstrap privado y gestor transaccional de Hex Tunnel.
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

bootstrap_read_license_key() {
  local key="${HEXTUNNEL_LICENSE_KEY:-}"
  if [[ -z "$key" && -t 0 ]]; then
    read -r -s -p "KEY: " key
    printf '\n'
  fi
  [[ -n "$key" ]] || bootstrap_error "No se proporcionó una key de licencia."
  printf '%s' "$key"
}

bootstrap_prepare_public_key() {
  local destination="$1"
  local source_file="${HEXTUNNEL_LICENSE_PUBLIC_KEY:-}"
  local source_url="${HEXTUNNEL_LICENSE_PUBLIC_KEY_URL:-}"
  local expected_sha="${HEXTUNNEL_LICENSE_PUBLIC_KEY_SHA256:-}"

  if [[ -n "${HEXTUNNEL_LICENSE_PUBLIC_KEY_PEM:-}" ]]; then
    printf '%s\n' "$HEXTUNNEL_LICENSE_PUBLIC_KEY_PEM" > "$destination"
  elif [[ -n "$source_file" && -s "$source_file" ]]; then
    cp -- "$source_file" "$destination"
  elif [[ -n "$source_url" ]]; then
    [[ "$source_url" == https://* ]] || bootstrap_error "La clave pública solo puede descargarse mediante HTTPS."
    [[ "$expected_sha" =~ ^[0-9a-fA-F]{64}$ ]] \
      || bootstrap_error "HEXTUNNEL_LICENSE_PUBLIC_KEY_SHA256 debe contener 64 caracteres hexadecimales."
    curl -fsSL --retry 2 --connect-timeout 8 --max-time 20 "$source_url" -o "$destination" \
      || bootstrap_error "No se pudo descargar la clave pública de distribución."
    printf '%s  %s\n' "${expected_sha,,}" "$destination" | sha256sum -c - >/dev/null \
      || bootstrap_error "La clave pública descargada no coincide con el SHA-256 fijado."
  else
    bootstrap_error "Configura HEXTUNNEL_LICENSE_PUBLIC_KEY, HEXTUNNEL_LICENSE_PUBLIC_KEY_PEM o la URL y SHA-256 de la clave pública."
  fi

  openssl pkey -pubin -in "$destination" -noout >/dev/null 2>&1 \
    || bootstrap_error "La clave pública de distribución no es válida."
  chmod 600 "$destination"
}

bootstrap_canonical_authorization() {
  local status="$1" expires_at="$2" download_expires_at="$3" nonce="$4"
  local subject="$5" version="$6" download_url="$7" package_sha256="$8" entrypoint="$9"
  printf 'status=%s\nexpires_at=%s\ndownload_expires_at=%s\nnonce=%s\nsubject=%s\nversion=%s\ndownload_url=%s\npackage_sha256=%s\nentrypoint=%s\n' \
    "$status" "$expires_at" "$download_expires_at" "$nonce" "$subject" \
    "$version" "$download_url" "$package_sha256" "$entrypoint"
}

bootstrap_validate_time() {
  local value="$1" label="$2" epoch
  epoch="$(date -d "$value" +%s 2>/dev/null)" || bootstrap_error "$label no contiene una fecha válida."
  ((epoch > $(date -u +%s))) || bootstrap_error "$label ya expiró."
}

bootstrap_validate_archive_paths() {
  local archive="$1"
  if tar -tzf "$archive" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
    bootstrap_error "El paquete privado contiene rutas no seguras."
  fi
}

bootstrap_authorize_and_download() {
  local endpoint="${HEXTUNNEL_DISTRIBUTION_ENDPOINT:-${HEXTUNNEL_LICENSE_ENDPOINT:-}}"
  local key public_ip nonce timestamp request response tmp public_key
  local status expires_at download_expires_at response_nonce subject version
  local download_url package_sha256 entrypoint signature reason archive extract_root
  local signature_file payload_file entrypoint_file package_root
  local -a entrypoint_matches=()

  bootstrap_require_root
  bootstrap_install_dependencies
  [[ "$endpoint" == https://* ]] || bootstrap_error "Configura HEXTUNNEL_DISTRIBUTION_ENDPOINT con una URL HTTPS."

  key="$(bootstrap_read_license_key)"
  public_ip="$(curl -fsS --max-time 8 https://api.ipify.org)" \
    || bootstrap_error "No se pudo determinar la IP pública del VPS."
  nonce="$(openssl rand -hex 24)"
  timestamp="$(date -u +%s)"
  request="$(jq -n \
    --arg key "$key" \
    --arg ip "$public_ip" \
    --arg nonce "$nonce" \
    --argjson timestamp "$timestamp" \
    '{key:$key,ip:$ip,nonce:$nonce,timestamp:$timestamp,product:"hextunnel",action:"install"}')"

  printf 'Verificando licencia...\n'
  response="$(curl -fsS --retry 2 --connect-timeout 8 --max-time 25 \
    -H 'Content-Type: application/json' \
    -H 'Cache-Control: no-store' \
    --data-binary "$request" \
    "$endpoint")" || bootstrap_error "El servidor de licencias no respondió correctamente."
  jq empty <<< "$response" >/dev/null 2>&1 || bootstrap_error "El servidor devolvió una respuesta inválida."

  status="$(jq -r '.status // empty' <<< "$response")"
  reason="$(jq -r '.reason // empty' <<< "$response")"
  [[ "$status" == valid ]] || bootstrap_error "${reason:-La key es inválida, está expirada o no puede activarse en este VPS.}"

  expires_at="$(jq -r '.expires_at // empty' <<< "$response")"
  download_expires_at="$(jq -r '.download_expires_at // empty' <<< "$response")"
  response_nonce="$(jq -r '.nonce // empty' <<< "$response")"
  subject="$(jq -r '.subject // empty' <<< "$response")"
  version="$(jq -r '.version // empty' <<< "$response")"
  download_url="$(jq -r '.download_url // empty' <<< "$response")"
  package_sha256="$(jq -r '.package_sha256 // empty' <<< "$response")"
  entrypoint="$(jq -r '.entrypoint // "bin/hextunnel-private-install"' <<< "$response")"
  signature="$(jq -r '.signature // empty' <<< "$response")"

  [[ "$response_nonce" == "$nonce" ]] || bootstrap_error "La autorización no corresponde a esta solicitud."
  [[ "$subject" == "$public_ip" ]] || bootstrap_error "La autorización fue emitida para otro VPS."
  [[ -n "$version" ]] || bootstrap_error "La autorización no incluye la versión del paquete."
  [[ "$download_url" == https://* ]] || bootstrap_error "La URL privada de descarga debe usar HTTPS."
  [[ "$package_sha256" =~ ^[0-9a-fA-F]{64}$ ]] || bootstrap_error "El SHA-256 del paquete privado es inválido."
  [[ "$entrypoint" =~ ^[A-Za-z0-9._/-]+$ && "$entrypoint" != /* && "$entrypoint" != *".."* ]] \
    || bootstrap_error "El entrypoint autorizado no es seguro."
  [[ -n "$signature" ]] || bootstrap_error "La autorización no contiene firma criptográfica."
  bootstrap_validate_time "$expires_at" "La licencia"
  bootstrap_validate_time "$download_expires_at" "El enlace de descarga"

  tmp="$(mktemp -d /tmp/hextunnel-private.XXXXXX)"
  trap 'rm -rf "${tmp:-}"' EXIT
  public_key="$tmp/license-public.pem"
  payload_file="$tmp/authorization.payload"
  signature_file="$tmp/authorization.sig"
  archive="$tmp/hextunnel-private.tar.gz"
  extract_root="$tmp/package"
  mkdir -p "$extract_root"

  bootstrap_prepare_public_key "$public_key"
  bootstrap_canonical_authorization \
    "$status" "$expires_at" "$download_expires_at" "$response_nonce" "$subject" \
    "$version" "$download_url" "${package_sha256,,}" "$entrypoint" > "$payload_file"
  printf '%s' "$signature" | base64 -d > "$signature_file" 2>/dev/null \
    || bootstrap_error "La firma de autorización no usa Base64 válido."
  openssl dgst -sha256 -verify "$public_key" -signature "$signature_file" "$payload_file" >/dev/null \
    || bootstrap_error "La firma criptográfica de la autorización es inválida."

  printf 'Licencia válida. Descargando paquete privado %s...\n' "$version"
  curl -fsSL --retry 3 --connect-timeout 10 --max-time 300 "$download_url" -o "$archive" \
    || bootstrap_error "No se pudo descargar el paquete privado autorizado."
  printf '%s  %s\n' "${package_sha256,,}" "$archive" | sha256sum -c - >/dev/null \
    || bootstrap_error "El paquete privado no coincide con el SHA-256 autorizado."
  bootstrap_validate_archive_paths "$archive"
  tar -xzf "$archive" -C "$extract_root"

  if [[ -f "$extract_root/$entrypoint" ]]; then
    entrypoint_file="$extract_root/$entrypoint"
    package_root="$extract_root"
  else
    mapfile -t entrypoint_matches < <(find "$extract_root" -type f -path "*/$entrypoint" -print)
    ((${#entrypoint_matches[@]} == 1)) \
      || bootstrap_error "El paquete privado no contiene un entrypoint único: $entrypoint"
    entrypoint_file="${entrypoint_matches[0]}"
    package_root="${entrypoint_file%/$entrypoint}"
  fi
  chmod 700 "$entrypoint_file"

  install -d -m 700 /etc/hextunnel
  printf '%s\n' "$key" > /etc/hextunnel/license.key
  chmod 600 /etc/hextunnel/license.key
  cat > /etc/hextunnel/license-state.env <<EOF
HEXTUNNEL_LICENSE_EXPIRES_AT=$(printf '%q' "$expires_at")
HEXTUNNEL_LICENSE_SUBJECT=$(printf '%q' "$subject")
HEXTUNNEL_INSTALLED_VERSION=$(printf '%q' "$version")
EOF
  chmod 600 /etc/hextunnel/license-state.env

  export HEXTUNNEL_LICENSE_KEY="$key"
  export HEXTUNNEL_LICENSE_PREVALIDATED=1
  export HEXTUNNEL_LICENSE_EXPIRES_AT="$expires_at"
  export HEXTUNNEL_LICENSE_SUBJECT="$subject"
  export HEXTUNNEL_PRIVATE_PACKAGE_ROOT="$package_root"
  export HEXTUNNEL_NO_REBOOT="${HEXTUNNEL_NO_REBOOT:-1}"
  exec bash "$entrypoint_file" "$@"
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P || true)"
if [[ -z "$SCRIPT_DIR" || ! -f "$SCRIPT_DIR/lib/common.sh" ]]; then
  bootstrap_authorize_and_download "$@"
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
