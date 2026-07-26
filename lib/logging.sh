#!/usr/bin/env bash

init_logging() {
  ensure_dir 750 "$HEXTUNNEL_LOG_DIR"
  HEXTUNNEL_LOG_FILE="${HEXTUNNEL_LOG_FILE:-$HEXTUNNEL_LOG_DIR/hextunnel-$(date +%Y%m%d).log}"
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]]; then
    touch "$HEXTUNNEL_LOG_FILE"
    chmod 640 "$HEXTUNNEL_LOG_FILE"
  fi
}

_log() {
  local level="$1" line
  shift
  line="$(date '+%Y-%m-%d %H:%M:%S') [$level] $*"
  printf '%s\n' "$line" >&2
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 || -z "${HEXTUNNEL_LOG_FILE:-}" ]] \
    || printf '%s\n' "$line" >> "$HEXTUNNEL_LOG_FILE"
}

log_info() { _log INFO "$@"; }
log_warn() { _log WARN "$@"; }
log_error() { _log ERROR "$@"; }
log_success() { _log OK "$@"; }
log_debug() { [[ "${HEXTUNNEL_DEBUG:-0}" == 1 ]] && _log DEBUG "$@" || true; }
log_dry() { _log DRY-RUN "$@"; }

die() {
  local message="$*" status=UNKNOWN line="${BASH_LINENO[0]:-0}"
  log_error "$message"
  if declare -F transaction_status >/dev/null 2>&1 \
    && declare -F transaction_fail >/dev/null 2>&1 \
    && [[ -n "${HEXTUNNEL_TRANSACTION_DIR:-}" \
      && "${HEXTUNNEL_DRY_RUN:-0}" != 1 \
      && "${HEXTUNNEL_TRANSACTION_FAILING:-0}" != 1 ]]; then
    status="$(transaction_status "$HEXTUNNEL_TRANSACTION_DIR")"
    if [[ "$status" == RUNNING ]]; then
      transaction_fail 1 "$line" "fatal: $message"
    fi
  fi
  exit 1
}
