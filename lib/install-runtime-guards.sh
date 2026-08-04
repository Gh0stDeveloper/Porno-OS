#!/usr/bin/env bash
[[ -n "${HEXTUNNEL_INSTALL_RUNTIME_GUARDS_LOADED:-}" ]] && return 0
HEXTUNNEL_INSTALL_RUNTIME_GUARDS_LOADED=1

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
