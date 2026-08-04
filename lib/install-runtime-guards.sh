#!/usr/bin/env bash
[[ -n "${HEXTUNNEL_INSTALL_RUNTIME_GUARDS_LOADED:-}" ]] && return 0
HEXTUNNEL_INSTALL_RUNTIME_GUARDS_LOADED=1

package_manager_lock_paths() {
  if [[ -n "${HEXTUNNEL_APT_LOCK_FILES:-}" ]]; then
    # Paths administratively overridden for tests or unusual distributions.
    printf '%s\n' ${HEXTUNNEL_APT_LOCK_FILES}
    return 0
  fi
  printf '%s\n' \
    /var/lib/dpkg/lock-frontend \
    /var/lib/dpkg/lock \
    /var/lib/apt/lists/lock \
    /var/cache/apt/archives/lock \
    /var/lib/apt/daily_lock
}

package_manager_lock_pids() {
  local path raw pid

  if command_exists fuser; then
    while IFS= read -r path; do
      [[ -e "$path" ]] || continue
      raw="$(fuser "$path" 2>/dev/null || true)"
      for pid in $raw; do
        [[ "$pid" =~ ^[0-9]+$ ]] && printf '%s\n' "$pid"
      done
    done < <(package_manager_lock_paths)
    return 0
  fi

  if command_exists lslocks; then
    while read -r pid path; do
      [[ "$pid" =~ ^[0-9]+$ ]] || continue
      while IFS= read -r candidate; do
        [[ "$path" == "$candidate" ]] && printf '%s\n' "$pid"
      done < <(package_manager_lock_paths)
    done < <(lslocks -rn -o PID,PATH 2>/dev/null || true)
    return 0
  fi

  # Minimal fallback for distributions without fuser/lslocks. The permanent
  # unattended-upgrade-shutdown --wait-for-signal daemon is intentionally not
  # considered package-manager activity.
  for path in apt apt-get dpkg; do
    pgrep -x "$path" 2>/dev/null || true
  done
  pgrep -f '(^|/)(apt\.systemd\.daily|unattended-upgrade)([[:space:]]|$)' \
    2>/dev/null || true
}

package_manager_busy() {
  [[ -n "$(package_manager_lock_pids | sort -u)" ]]
}

package_manager_process_snapshot() {
  local pids pid details=()
  pids="$(package_manager_lock_pids | sort -u)"
  [[ -n "$pids" ]] || return 0
  while IFS= read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    details+=("$(ps -p "$pid" -o pid=,etime=,stat=,comm=,args= 2>/dev/null || printf '%s ? ? unknown' "$pid")")
  done <<< "$pids"
  printf '%s\n' "${details[@]}" | awk '
    NF >= 4 {
      printf "pid=%s elapsed=%s state=%s command=%s", $1, $2, $3, $4
      for (i = 5; i <= NF && i <= 11; i++) printf " %s", $i
      printf "\n"
    }
  '
}

# Override the runtime helper so non-SSH contexts (CI, console and dry-run)
# remain compatible with `set -u`.
ipv6_ssh_session_active() {
  local connection="${SSH_CONNECTION:-}" remote
  [[ -n "$connection" ]] || return 1
  remote="${connection%% *}"
  [[ -n "$remote" && "$remote" == *:* ]]
}

# Dry-run must never create cache files, start background jobs or access the
# network. Real installations retain the verified parallel prefetch behavior.
artifact_prefetch_selected_modules() {
  local module
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]]; then
    log_dry "omitir descargas anticipadas en modo dry-run"
    return 0
  fi
  [[ "${HEXTUNNEL_PREFETCH_ENABLED:-1}" == 1 ]] || return 0
  [[ "${HEXTUNNEL_PREFETCH_STARTED:-0}" != 1 ]] || return 0
  HEXTUNNEL_PREFETCH_STARTED=1
  artifact_cache_prune
  for module in "$@"; do
    case "$module" in
      xray)
        artifact_prefetch_xray \
          || log_warn "No se pudo anticipar Xray; seguirá en primer plano."
        ;;
      hysteria)
        artifact_prefetch_singbox \
          || log_warn "No se pudo anticipar Sing-box; seguirá en primer plano."
        ;;
      hysteria2)
        artifact_prefetch_hysteria2 \
          || log_warn "No se pudo anticipar Hysteria 2; seguirá en primer plano."
        ;;
      zivpn)
        artifact_prefetch_zivpn \
          || log_warn "No se pudo anticipar ZiVPN; seguirá en primer plano."
        ;;
    esac
  done
}
