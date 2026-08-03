#!/usr/bin/env bash
[[ -n "${HEXTUNNEL_INSTALL_RUNTIME_LOADED:-}" ]] && return 0
HEXTUNNEL_INSTALL_RUNTIME_LOADED=1

HEXTUNNEL_ARTIFACT_CACHE_DIR="${HEXTUNNEL_ARTIFACT_CACHE_DIR:-/var/cache/hextunnel/artifacts}"
declare -Ag HEXTUNNEL_PREFETCH_URL_KEYS=()
declare -Ag HEXTUNNEL_PREFETCH_PIDS=()
declare -Ag HEXTUNNEL_PREFETCH_LOGS=()
HEXTUNNEL_PREFETCH_STARTED="${HEXTUNNEL_PREFETCH_STARTED:-0}"

package_manager_process_snapshot() {
  ps -eo pid=,etime=,stat=,comm=,args= 2>/dev/null | awk '
    $4 ~ /^(apt|apt-get|dpkg|unattended-upgr|unattended-upgrade)$/ ||
    $0 ~ /[a]pt\.systemd\.daily/ ||
    $0 ~ /[u]nattended-upgrade/ {
      printf "pid=%s elapsed=%s state=%s command=%s", $1, $2, $3, $4
      for (i = 5; i <= NF && i <= 10; i++) printf " %s", $i
      printf "\n"
    }
  '
}

package_manager_busy() {
  local process
  command_exists pgrep || return 1
  for process in apt apt-get dpkg unattended-upgr unattended-upgrade; do
    pgrep -x "$process" >/dev/null 2>&1 && return 0
  done
  pgrep -f '(^|/)(apt\.systemd\.daily|unattended-upgrade)([[:space:]]|$)' \
    >/dev/null 2>&1
}

package_manager_wait() {
  local timeout="${HEXTUNNEL_APT_LOCK_TIMEOUT:-1200}"
  local interval="${HEXTUNNEL_APT_LOCK_POLL_INTERVAL:-5}"
  local heartbeat="${HEXTUNNEL_APT_LOCK_HEARTBEAT:-15}"
  local started deadline next_report elapsed remaining snapshot

  [[ "$timeout" =~ ^[0-9]+$ && "$timeout" -ge 1 ]] \
    || die "HEXTUNNEL_APT_LOCK_TIMEOUT debe ser un entero positivo."
  [[ "$interval" =~ ^[0-9]+$ && "$interval" -ge 1 ]] \
    || die "HEXTUNNEL_APT_LOCK_POLL_INTERVAL debe ser un entero positivo."
  [[ "$heartbeat" =~ ^[0-9]+$ && "$heartbeat" -ge 1 ]] \
    || die "HEXTUNNEL_APT_LOCK_HEARTBEAT debe ser un entero positivo."

  started=$SECONDS
  deadline=$((started + timeout))
  next_report=$started

  while package_manager_busy; do
    elapsed=$((SECONDS - started))
    remaining=$((deadline - SECONDS))
    if ((remaining <= 0)); then
      snapshot="$(package_manager_process_snapshot | paste -sd ';' -)"
      die "APT/DPKG continúa ocupado después de ${timeout}s. Proceso detectado: ${snapshot:-desconocido}."
    fi

    if ((SECONDS >= next_report)); then
      snapshot="$(package_manager_process_snapshot | paste -sd ';' -)"
      log_info "APT/DPKG ocupado; esperando sin interrumpirlo. Transcurrido=${elapsed}s restante<=${remaining}s proceso=${snapshot:-detectado-sin-detalle}"
      next_report=$((SECONDS + heartbeat))
    fi
    sleep "$interval"
  done

  if ((SECONDS > started)); then
    log_success "APT/DPKG quedó disponible después de $((SECONDS - started))s; continuando."
  fi
}

artifact_cache_key_path() {
  local key="$1"
  [[ "$key" =~ ^[A-Za-z0-9._-]+$ ]] || die "Clave de caché inválida: $key"
  printf '%s/%s' "$HEXTUNNEL_ARTIFACT_CACHE_DIR" "$key"
}

artifact_cache_validate() {
  local key="$1" path checksum expected actual
  path="$(artifact_cache_key_path "$key")"
  checksum="$path.sha256"
  [[ -s "$path" && -s "$checksum" ]] || return 1
  expected="$(tr -d '\r\n[:space:]' < "$checksum")"
  [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || return 1
  actual="$(sha256sum "$path" | awk '{print tolower($1)}')"
  [[ "$actual" == "${expected,,}" ]]
}

artifact_cache_store_locked() {
  local key="$1" url="$2" expected="${3,,}" path lock tmp actual fd
  [[ "$url" == https://* || "$url" == file://* ]] || return 1
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 1
  install -d -m 700 "$HEXTUNNEL_ARTIFACT_CACHE_DIR"
  path="$(artifact_cache_key_path "$key")"
  lock="$path.lock"
  exec {fd}>"$lock"
  flock "$fd"
  if artifact_cache_validate "$key"; then
    flock -u "$fd"
    exec {fd}>&-
    return 0
  fi
  rm -f "$path" "$path.sha256"
  tmp="$path.partial.$$"
  rm -f "$tmp"
  if ! curl -fL --retry 3 --connect-timeout 10 --max-time 900 -o "$tmp" "$url"; then
    rm -f "$tmp"
    flock -u "$fd"
    exec {fd}>&-
    return 1
  fi
  actual="$(sha256sum "$tmp" | awk '{print tolower($1)}')"
  if [[ "$actual" != "$expected" ]]; then
    rm -f "$tmp"
    flock -u "$fd"
    exec {fd}>&-
    return 1
  fi
  chmod 600 "$tmp"
  mv -f "$tmp" "$path"
  printf '%s\n' "$expected" > "$path.sha256"
  chmod 600 "$path.sha256"
  flock -u "$fd"
  exec {fd}>&-
}

artifact_cache_store_from_manifest() {
  local key="$1" url="$2" manifest_url="$3" kind="$4" asset="$5"
  local tmp expected
  tmp="$(mktemp -d /tmp/hextunnel-prefetch.XXXXXX)"
  if ! curl -fsSL --retry 3 --connect-timeout 10 --max-time 120 \
      -o "$tmp/manifest" "$manifest_url"; then
    rm -rf "$tmp"
    return 1
  fi
  case "$kind" in
    xray)
      expected="$(awk -F'= *' 'toupper($1) == "SHA2-256" {print tolower($2); exit}' "$tmp/manifest")"
      ;;
    hysteria2)
      expected="$(awk -v asset="$asset" '$2 == asset || $2 == "build/" asset || $2 == "*" asset {print tolower($1); exit}' "$tmp/manifest")"
      ;;
    *)
      rm -rf "$tmp"
      return 1
      ;;
  esac
  rm -rf "$tmp"
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 1
  artifact_cache_store_locked "$key" "$url" "$expected"
}

artifact_prefetch_register() {
  local key="$1" url="$2" worker="$3"
  shift 3
  local log_path pid
  install -d -m 700 "$HEXTUNNEL_ARTIFACT_CACHE_DIR"
  HEXTUNNEL_PREFETCH_URL_KEYS["$url"]="$key"
  if artifact_cache_validate "$key"; then
    return 0
  fi
  log_path="$HEXTUNNEL_ARTIFACT_CACHE_DIR/$key.prefetch.log"
  (
    "$worker" "$@"
  ) >"$log_path" 2>&1 &
  pid=$!
  HEXTUNNEL_PREFETCH_PIDS["$key"]="$pid"
  HEXTUNNEL_PREFETCH_LOGS["$key"]="$log_path"
  log_info "Descarga anticipada iniciada: $key (pid=$pid)"
}

artifact_prefetch_wait_key() {
  local key="$1" pid="${HEXTUNNEL_PREFETCH_PIDS[$key]:-}" log_path
  [[ -n "$pid" ]] || return 0
  log_path="${HEXTUNNEL_PREFETCH_LOGS[$key]:-}"
  if kill -0 "$pid" 2>/dev/null; then
    log_info "Esperando descarga anticipada: $key"
  fi
  if wait "$pid" 2>/dev/null; then
    unset 'HEXTUNNEL_PREFETCH_PIDS[$key]'
    artifact_cache_validate "$key"
    return
  fi
  unset 'HEXTUNNEL_PREFETCH_PIDS[$key]'
  if [[ -s "$log_path" ]]; then
    log_warn "La descarga anticipada falló para $key: $(tail -n 1 "$log_path" | tr -d '\r\n')"
  else
    log_warn "La descarga anticipada falló para $key; se descargará en primer plano."
  fi
  return 1
}

artifact_prefetch_materialize_url() {
  local url="$1" destination="$2" key path
  key="${HEXTUNNEL_PREFETCH_URL_KEYS[$url]:-}"
  [[ -n "$key" ]] || return 1
  artifact_prefetch_wait_key "$key" || return 1
  artifact_cache_validate "$key" || return 1
  path="$(artifact_cache_key_path "$key")"
  install -d -m 700 "$(dirname "$destination")"
  cp -f "$path" "$destination"
  log_success "Artefacto reutilizado desde caché verificada: $key"
}

artifact_prefetch_cancel_all() {
  local key pid
  for key in "${!HEXTUNNEL_PREFETCH_PIDS[@]}"; do
    pid="${HEXTUNNEL_PREFETCH_PIDS[$key]}"
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
    unset 'HEXTUNNEL_PREFETCH_PIDS[$key]'
  done
}

artifact_cache_prune() {
  local days="${HEXTUNNEL_ARTIFACT_CACHE_TTL_DAYS:-7}"
  [[ "$days" =~ ^[0-9]+$ ]] || days=7
  install -d -m 700 "$HEXTUNNEL_ARTIFACT_CACHE_DIR"
  find "$HEXTUNNEL_ARTIFACT_CACHE_DIR" -maxdepth 1 -type f \
    \( -name '*.partial.*' -o -name '*.prefetch.log' -o -mtime "+$days" \) \
    -delete 2>/dev/null || true
}

artifact_prefetch_xray() {
  local version asset base key
  version="${HEXTUNNEL_XRAY_VERSION:-v26.3.27}"
  asset="$(xray_asset_name)" || return 1
  base="https://github.com/XTLS/Xray-core/releases/download/${version}/${asset}"
  key="xray-${version//[^A-Za-z0-9._-]/-}-${asset}"
  artifact_prefetch_register "$key" "$base" artifact_cache_store_from_manifest \
    "$key" "$base" "$base.dgst" xray "$asset"
}

artifact_prefetch_hysteria2() {
  local version asset base url key
  version="${HEXTUNNEL_HYSTERIA2_VERSION:-app/v2.9.3}"
  asset="$(hysteria2_asset_name)" || return 1
  base="https://github.com/apernet/hysteria/releases/download/${version}"
  url="$base/$asset"
  key="hysteria2-${version//[^A-Za-z0-9._-]/-}-${asset}"
  artifact_prefetch_register "$key" "$url" artifact_cache_store_from_manifest \
    "$key" "$url" "$base/hashes.txt" hysteria2 "$asset"
}

artifact_prefetch_singbox() {
  local version asset api metadata url digest expected key
  version="${HEXTUNNEL_SINGBOX_VERSION:-1.12.22}"
  asset="$(hysteria_singbox_asset)" || return 1
  api="https://api.github.com/repos/SagerNet/sing-box/releases/tags/v${version}"
  metadata="$(curl -fsSL --retry 3 --connect-timeout 10 --max-time 30 "$api")" || return 1
  url="$(jq -r --arg asset "$asset" '.assets[] | select(.name == $asset) | .browser_download_url' <<< "$metadata" | head -n1)"
  digest="$(jq -r --arg asset "$asset" '.assets[] | select(.name == $asset) | (.digest // empty)' <<< "$metadata" | head -n1)"
  [[ -n "$url" && "$url" != null && "$digest" == sha256:* ]] || return 1
  expected="${digest#sha256:}"
  key="singbox-${version}-${asset}"
  artifact_prefetch_register "$key" "$url" artifact_cache_store_locked \
    "$key" "$url" "$expected"
}

artifact_prefetch_zivpn() {
  local architecture tag url expected key
  architecture="${HEXTUNNEL_ARCH:-$(normalize_architecture)}"
  tag="${HEXTUNNEL_ZIVPN_VERSION:-udp-zivpn_1.4.9}"
  case "$architecture" in
    arm64)
      url="${HEXTUNNEL_ZIVPN_ARM64_BINARY_URL:-}"
      expected="${HEXTUNNEL_ZIVPN_ARM64_SHA256:-}"
      ;;
    amd64)
      url="${HEXTUNNEL_ZIVPN_AMD64_BINARY_URL:-${HEXTUNNEL_ZIVPN_BINARY_URL:-}}"
      expected="${HEXTUNNEL_ZIVPN_AMD64_SHA256:-${HEXTUNNEL_ZIVPN_SHA256:-}}"
      ;;
    *) return 0 ;;
  esac
  [[ -n "$url" && "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || return 1
  key="zivpn-${tag//[^A-Za-z0-9._-]/-}-${architecture}"
  artifact_prefetch_register "$key" "$url" artifact_cache_store_locked \
    "$key" "$url" "${expected,,}"
}

artifact_prefetch_selected_modules() {
  local module
  [[ "${HEXTUNNEL_PREFETCH_ENABLED:-1}" == 1 ]] || return 0
  [[ "$HEXTUNNEL_PREFETCH_STARTED" != 1 ]] || return 0
  HEXTUNNEL_PREFETCH_STARTED=1
  artifact_cache_prune
  for module in "$@"; do
    case "$module" in
      xray) artifact_prefetch_xray || log_warn "No se pudo anticipar Xray; seguirá en primer plano." ;;
      hysteria) artifact_prefetch_singbox || log_warn "No se pudo anticipar Sing-box; seguirá en primer plano." ;;
      hysteria2) artifact_prefetch_hysteria2 || log_warn "No se pudo anticipar Hysteria 2; seguirá en primer plano." ;;
      zivpn) artifact_prefetch_zivpn || log_warn "No se pudo anticipar ZiVPN; seguirá en primer plano." ;;
    esac
  done
}

curl_output_and_url() {
  local -n output_ref="$1" url_ref="$2"
  shift 2
  local previous="" argument
  output_ref=""
  url_ref=""
  for argument in "$@"; do
    if [[ "$previous" == output ]]; then
      output_ref="$argument"
      previous=""
      continue
    fi
    case "$argument" in
      -o|--output) previous=output ;;
      https://*|file://*) url_ref="$argument" ;;
    esac
  done
}

run_cmd() {
  local command_name="${1:-}" apt_timeout="${HEXTUNNEL_APT_LOCK_TIMEOUT:-1200}"
  local output="" url=""
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]]; then
    log_dry "$(printf '%q ' "$@")"
    return 0
  fi
  log_debug "Ejecutando: $(printf '%q ' "$@")"
  case "$command_name" in
    apt-get|apt)
      shift
      package_manager_wait
      env DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}" \
        "$command_name" \
        -o "DPkg::Lock::Timeout=$apt_timeout" \
        -o "APT::Update::Lock::Timeout=$apt_timeout" \
        "$@"
      ;;
    dpkg)
      shift
      package_manager_wait
      command dpkg "$@"
      ;;
    curl)
      shift
      curl_output_and_url output url "$@"
      if [[ -n "$output" && -n "$url" ]] \
        && artifact_prefetch_materialize_url "$url" "$output"; then
        return 0
      fi
      command curl "$@"
      ;;
    *)
      "$@"
      ;;
  esac
}

ipv6_ssh_session_active() {
  local remote="${SSH_CONNECTION%% *}"
  [[ -n "$remote" && "$remote" == *:* ]]
}

network_ipv6_capture_runtime() {
  local file="$HEXTUNNEL_TRANSACTION_DIR/ipv6-runtime.env"
  [[ -n "${HEXTUNNEL_TRANSACTION_DIR:-}" && "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]] || return 0
  cat > "$file" <<EOF
IPV6_ALL_PREVIOUS=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || printf 0)
IPV6_DEFAULT_PREVIOUS=$(cat /proc/sys/net/ipv6/conf/default/disable_ipv6 2>/dev/null || printf 0)
EOF
  chmod 600 "$file"
}

network_prepare_ipv4_only_configs() {
  local tmp
  if [[ -s /etc/hysteria1/config.json ]]; then
    backup_path /etc/hysteria1/config.json
    tmp="$(mktemp /tmp/hextunnel-hysteria-ipv4.XXXXXX)"
    jq '(.inbounds[] | select(.tag == "hy1-inbound") | .listen)="0.0.0.0"' \
      /etc/hysteria1/config.json > "$tmp"
    install -m 640 -o root -g hextunnel-hysteria "$tmp" /etc/hysteria1/config.json
    rm -f "$tmp"
  fi
  if [[ -s /etc/hysteria2/config.yaml ]]; then
    backup_path /etc/hysteria2/config.yaml
    sed -i -E 's|^listen:.*|listen: 0.0.0.0:36713|' /etc/hysteria2/config.yaml
  fi
  if [[ -s /etc/zivpn/config.json ]]; then
    backup_path /etc/zivpn/config.json
    tmp="$(mktemp /tmp/hextunnel-zivpn-ipv4.XXXXXX)"
    jq '.listen="0.0.0.0:5667"' /etc/zivpn/config.json > "$tmp"
    install -m 600 "$tmp" /etc/zivpn/config.json
    rm -f "$tmp"
  fi
}

network_restart_ipv4_services() {
  local service
  for service in hextunnel-hysteria hysteria2 zivpn xray; do
    systemctl is-active --quiet "$service" 2>/dev/null || continue
    systemctl restart "$service"
  done
}

network_apply_ipv6_policy() {
  [[ "${HEXTUNNEL_DISABLE_IPV6:-1}" == 1 ]] || {
    log_info "IPv6 permanece habilitado por configuración."
    return 0
  }
  if ipv6_ssh_session_active; then
    log_warn "La sesión SSH actual usa IPv6; se omite deshabilitar IPv6 para no cortar el acceso."
    return 0
  fi
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]]; then
    log_dry "configurar IPv4-only y deshabilitar IPv6 mediante sysctl"
    return 0
  fi
  network_ipv6_capture_runtime
  network_prepare_ipv4_only_configs
  write_file /etc/sysctl.d/99-hextunnel-disable-ipv6.conf 644 <<'EOF'
# Administrado por Hex Tunnel.
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
  sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null
  sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null
  network_restart_ipv4_services
  log_success "IPv6 deshabilitado; los listeners administrados quedaron fijados a IPv4."
}

restore_ipv6_runtime_state() {
  local dir="$1" file="$1/ipv6-runtime.env" all_value default_value
  [[ -s "$file" ]] || return 0
  all_value="$(awk -F= '$1=="IPV6_ALL_PREVIOUS"{print $2}' "$file")"
  default_value="$(awk -F= '$1=="IPV6_DEFAULT_PREVIOUS"{print $2}' "$file")"
  [[ "$all_value" =~ ^[01]$ ]] || all_value=0
  [[ "$default_value" =~ ^[01]$ ]] || default_value=0
  sysctl -w "net.ipv6.conf.all.disable_ipv6=$all_value" >/dev/null 2>&1 || true
  sysctl -w "net.ipv6.conf.default.disable_ipv6=$default_value" >/dev/null 2>&1 || true
}

install_progress_label() {
  case "$1" in
    ssh) printf 'SSH + TLS' ;;
    xray) printf 'Xray / VLESS / VMess / Trojan' ;;
    hysteria) printf 'Hysteria v1' ;;
    hysteria2) printf 'Hysteria 2' ;;
    udp-custom) printf 'UDP Custom' ;;
    slowdns) printf 'SlowDNS' ;;
    slipstream) printf 'SlipStream' ;;
    zivpn) printf 'ZiVPN' ;;
    webmin) printf 'Webmin' ;;
    legacy-all) printf 'Compatibilidad monolítica' ;;
    *) printf '%s' "$1" ;;
  esac
}

install_progress_begin_module() {
  local module="$1" total label percent
  if ! declare -p HEXTUNNEL_REQUESTED_MODULES >/dev/null 2>&1; then
    return 0
  fi
  total="${#HEXTUNNEL_REQUESTED_MODULES[@]}"
  ((total > 0)) || return 0

  if [[ "${HEXTUNNEL_PROGRESS_CURRENT:-0}" == 0 ]]; then
    artifact_prefetch_selected_modules "${HEXTUNNEL_REQUESTED_MODULES[@]}"
  fi
  HEXTUNNEL_PROGRESS_CURRENT=$(( ${HEXTUNNEL_PROGRESS_CURRENT:-0} + 1 ))
  HEXTUNNEL_PROGRESS_MODULE_STARTED=$SECONDS
  label="$(install_progress_label "$module")"
  percent=$(( (HEXTUNNEL_PROGRESS_CURRENT - 1) * 100 / total ))
  log_info "[FASE ${HEXTUNNEL_PROGRESS_CURRENT}/${total} | ${percent}%] Iniciando ${label}."
}

install_progress_end_module() {
  local module="$1" total label percent elapsed
  if ! declare -p HEXTUNNEL_REQUESTED_MODULES >/dev/null 2>&1; then
    return 0
  fi
  total="${#HEXTUNNEL_REQUESTED_MODULES[@]}"
  ((total > 0)) || return 0

  label="$(install_progress_label "$module")"
  percent=$(( ${HEXTUNNEL_PROGRESS_CURRENT:-0} * 100 / total ))
  elapsed=$((SECONDS - ${HEXTUNNEL_PROGRESS_MODULE_STARTED:-SECONDS}))
  log_success "[FASE ${HEXTUNNEL_PROGRESS_CURRENT}/${total} | ${percent}%] ${label} completado en ${elapsed}s."
}

validate_selected_modules() {
  local module
  network_apply_ipv6_policy
  for module in "$@"; do module_validate "$module"; done
}
