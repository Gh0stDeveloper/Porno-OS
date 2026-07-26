#!/usr/bin/env bash
init_logging() { ensure_dir 750 "$HEXTUNNEL_LOG_DIR"; HEXTUNNEL_LOG_FILE="${HEXTUNNEL_LOG_FILE:-$HEXTUNNEL_LOG_DIR/hextunnel-$(date +%Y%m%d).log}"; if [[ "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]]; then touch "$HEXTUNNEL_LOG_FILE"; chmod 640 "$HEXTUNNEL_LOG_FILE"; fi; }
_log() { local level="$1"; shift; local line="$(date '+%Y-%m-%d %H:%M:%S') [$level] $*"; printf '%s\n' "$line" >&2; [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 || -z "${HEXTUNNEL_LOG_FILE:-}" ]] || printf '%s\n' "$line" >> "$HEXTUNNEL_LOG_FILE"; }
log_info() { _log INFO "$@"; }
log_warn() { _log WARN "$@"; }
log_error() { _log ERROR "$@"; }
log_success() { _log OK "$@"; }
log_debug() { [[ "${HEXTUNNEL_DEBUG:-0}" == 1 ]] && _log DEBUG "$@" || true; }
log_dry() { _log DRY-RUN "$@"; }
die() { log_error "$*"; exit 1; }
