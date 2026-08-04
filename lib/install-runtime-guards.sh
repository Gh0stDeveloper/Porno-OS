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

package_manager_prepare_tmp() {
  local tmp_dir="${HEXTUNNEL_TMP_DIR:-/tmp}" mode owner group repaired=0

  if [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]]; then
    return 0
  fi

  if [[ ! -d "$tmp_dir" ]]; then
    install -d -m 1777 "$tmp_dir"
    repaired=1
  fi

  mode="$(stat -c '%a' "$tmp_dir" 2>/dev/null || printf unknown)"
  if [[ "$mode" != 1777 ]]; then
    chmod 1777 "$tmp_dir" || die "No se pudieron restaurar los permisos 1777 de $tmp_dir."
    repaired=1
  fi

  if [[ "$tmp_dir" == /tmp ]]; then
    owner="$(stat -c '%U' "$tmp_dir" 2>/dev/null || printf unknown)"
    group="$(stat -c '%G' "$tmp_dir" 2>/dev/null || printf unknown)"
    if [[ "$owner" != root || "$group" != root ]]; then
      chown root:root "$tmp_dir" || die "No se pudo restaurar root:root en /tmp."
      repaired=1
    fi
  fi

  [[ -w "$tmp_dir" ]] || die "El directorio temporal $tmp_dir no permite escritura."

  if ((repaired == 1)); then
    log_warn "Se restauró $tmp_dir con permisos compartidos 1777 para APT/DPKG."
  fi
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
  package_manager_prepare_tmp
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

# Preserve permissions of existing shared directories such as /tmp. Some
# components, notably ZiVPN, use a temporary file directly below /tmp; applying
# install -d -m 700 to its parent would incorrectly change /tmp from 1777 to 700.
artifact_prefetch_materialize_url() {
  local url="$1" destination="$2" key path parent
  key="${HEXTUNNEL_PREFETCH_URL_KEYS[$url]:-}"
  [[ -n "$key" ]] || return 1
  artifact_prefetch_wait_key "$key" || return 1
  artifact_cache_validate "$key" || return 1
  path="$(artifact_cache_key_path "$key")"
  parent="$(dirname "$destination")"
  if [[ ! -d "$parent" ]]; then
    install -d -m 700 "$parent"
  fi
  cp -f "$path" "$destination"
  log_success "Artefacto reutilizado desde caché verificada: $key"
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
