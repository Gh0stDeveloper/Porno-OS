#!/usr/bin/env bash
[[ -n "${HEXTUNNEL_INSTALL_RUNTIME_LOADED:-}" ]] && return 0
HEXTUNNEL_INSTALL_RUNTIME_LOADED=1

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

run_cmd() {
  local command_name="${1:-}" apt_timeout="${HEXTUNNEL_APT_LOCK_TIMEOUT:-1200}"
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
    *)
      "$@"
      ;;
  esac
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
