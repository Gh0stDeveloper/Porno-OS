#!/usr/bin/env bash

init_logging() {
  ensure_dir 750 "$HEXTUNNEL_LOG_DIR"
  HEXTUNNEL_LOG_FILE="${HEXTUNNEL_LOG_FILE:-$HEXTUNNEL_LOG_DIR/hextunnel-$(date +%Y%m%d).log}"
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]]; then
    touch "$HEXTUNNEL_LOG_FILE"
    chmod 640 "$HEXTUNNEL_LOG_FILE"
  fi
}

ui_colors_init() {
  if [[ -t 2 && "${TERM:-dumb}" != dumb && -z "${NO_COLOR:-}" ]]; then
    UI_RESET=$'\033[0m'
    UI_DIM=$'\033[2m'
    UI_CYAN=$'\033[1;36m'
    UI_GREEN=$'\033[1;32m'
    UI_YELLOW=$'\033[1;33m'
    UI_RED=$'\033[1;31m'
    UI_WHITE=$'\033[1;37m'
  else
    UI_RESET=''
    UI_DIM=''
    UI_CYAN=''
    UI_GREEN=''
    UI_YELLOW=''
    UI_RED=''
    UI_WHITE=''
  fi
}

ui_colors_init

ui_header() {
  local title="${1:-HEX TUNNEL}"
  printf '\n%s╭──────────────────────────────────────────────────────────╮%s\n' "$UI_CYAN" "$UI_RESET" >&2
  printf '%s│%s %-56s %s│%s\n' "$UI_CYAN" "$UI_WHITE" "$title" "$UI_CYAN" "$UI_RESET" >&2
  printf '%s╰──────────────────────────────────────────────────────────╯%s\n' "$UI_CYAN" "$UI_RESET" >&2
}

ui_step() {
  printf '%s[•]%s %s\n' "$UI_CYAN" "$UI_RESET" "$*" >&2
}

ui_success() {
  printf '%s[✓]%s %s\n' "$UI_GREEN" "$UI_RESET" "$*" >&2
}

ui_warning() {
  printf '%s[!]%s %s\n' "$UI_YELLOW" "$UI_RESET" "$*" >&2
}

ui_failure() {
  printf '%s[✗]%s %s\n' "$UI_RED" "$UI_RESET" "$*" >&2
}

ui_phase() {
  local current="$1" total="$2"
  shift 2
  printf '%s[•]%s Instalación parte %s[%s/%s]%s — %s\n' \
    "$UI_CYAN" "$UI_RESET" "$UI_WHITE" "$current" "$total" "$UI_RESET" "$*" >&2
}

ui_show_error_file() {
  local path="${1:-}"
  [[ -n "$path" && -s "$path" ]] || return 0
  printf '\n%sDetalles completos del error:%s\n' "$UI_RED" "$UI_RESET" >&2
  printf '%s────────────────────────────────────────────────────────────%s\n' "$UI_RED" "$UI_RESET" >&2
  cat -- "$path" >&2
  printf '%s────────────────────────────────────────────────────────────%s\n' "$UI_RED" "$UI_RESET" >&2
}

_log() {
  local level="$1" line message
  shift
  message="$*"
  line="$(date '+%Y-%m-%d %H:%M:%S') [$level] $message"

  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 || -z "${HEXTUNNEL_LOG_FILE:-}" ]] \
    || printf '%s\n' "$line" >> "$HEXTUNNEL_LOG_FILE"

  if [[ "${HEXTUNNEL_VERBOSE:-0}" == 1 ]]; then
    printf '%s\n' "$line" >&2
    return 0
  fi

  case "$level" in
    INFO) ui_step "$message" ;;
    WARN) ui_warning "$message" ;;
    ERROR) ui_failure "$message" ;;
    OK) ui_success "$message" ;;
    DRY-RUN) printf '%s[~]%s %s\n' "$UI_DIM" "$UI_RESET" "$message" >&2 ;;
    DEBUG) printf '%s[·] %s%s\n' "$UI_DIM" "$message" "$UI_RESET" >&2 ;;
    *) printf '%s\n' "$message" >&2 ;;
  esac
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
  if [[ -n "${HEXTUNNEL_LAST_ERROR_FILE:-}" ]]; then
    ui_show_error_file "$HEXTUNNEL_LAST_ERROR_FILE"
  fi
  [[ -z "${HEXTUNNEL_LOG_FILE:-}" ]] \
    || printf '%s[log]%s %s\n' "$UI_DIM" "$UI_RESET" "$HEXTUNNEL_LOG_FILE" >&2
  exit 1
}
