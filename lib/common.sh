#!/usr/bin/env bash
[[ -n "${HEXTUNNEL_COMMON_LOADED:-}" ]] && return 0
HEXTUNNEL_COMMON_LOADED=1
HEXTUNNEL_ROOT="${HEXTUNNEL_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
HEXTUNNEL_ETC="${HEXTUNNEL_ETC:-/etc/hextunnel}"
HEXTUNNEL_STATE="${HEXTUNNEL_STATE:-/var/lib/hextunnel}"
HEXTUNNEL_LOG_DIR="${HEXTUNNEL_LOG_DIR:-/var/log/hextunnel}"
HEXTUNNEL_INSTALL_DIR="${HEXTUNNEL_INSTALL_DIR:-/opt/hextunnel}"
HEXTUNNEL_CONFIG_FILE="${HEXTUNNEL_CONFIG_FILE:-$HEXTUNNEL_ETC/hextunnel.env}"
command_exists() { command -v "$1" >/dev/null 2>&1; }
join_by() { local sep="$1" first=1 item; shift; for item in "$@"; do ((first)) || printf '%s' "$sep"; printf '%s' "$item"; first=0; done; }
require_root() { [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Hex Tunnel debe ejecutarse como root."; }
ensure_dir() { local mode="$1" path="$2"; [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && { log_dry "install -d -m $mode $path"; return 0; }; install -d -m "$mode" "$path"; }
run_cmd() { if [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]]; then log_dry "$(printf '%q ' "$@")"; return 0; fi; log_debug "Ejecutando: $(printf '%q ' "$@")"; "$@"; }
write_file() { local path="$1" mode="${2:-600}" content tmp; content="$(cat)"; if [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]]; then log_dry "escribir $path modo $mode"; return 0; fi; backup_path "$path"; install -d -m 755 "$(dirname "$path")"; tmp="$(mktemp "${path}.tmp.XXXXXX")"; printf '%s\n' "$content" > "$tmp"; chmod "$mode" "$tmp"; chown root:root "$tmp"; mv -f "$tmp" "$path"; }
random_secret() { local length="${1:-32}"; if command_exists openssl; then openssl rand -base64 "$((length * 2))" | tr -dc 'A-Za-z0-9_-' | head -c "$length"; else tr -dc 'A-Za-z0-9_-' < /dev/urandom | head -c "$length"; fi; }
load_runtime_config() { ensure_dir 700 "$HEXTUNNEL_ETC"; if [[ -f "$HEXTUNNEL_CONFIG_FILE" ]]; then source "$HEXTUNNEL_CONFIG_FILE"; fi; }
confirm_action() { local prompt="$1" answer; [[ "${HEXTUNNEL_FORCE:-0}" == 1 ]] && return 0; [[ "${HEXTUNNEL_NON_INTERACTIVE:-0}" == 1 ]] && return 1; read -r -p "$prompt [s/N]: " answer; [[ "$answer" =~ ^[SsYy]$ ]]; }
sanitize_text() { sed -E -e 's/[0-9]{8,12}:[A-Za-z0-9_-]{20,}/[TELEGRAM_TOKEN]/g' -e 's/(password|token|secret|auth)(["=: ]+)[^ ,"}]*/\1\2[REDACTED]/Ig' -e 's/-----BEGIN [^-]+ PRIVATE KEY-----/[PRIVATE_KEY_REDACTED]/g'; }
