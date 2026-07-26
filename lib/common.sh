#!/usr/bin/env bash
[[ -n "${HEXTUNNEL_COMMON_LOADED:-}" ]] && return 0
HEXTUNNEL_COMMON_LOADED=1

HEXTUNNEL_ROOT="${HEXTUNNEL_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
HEXTUNNEL_ETC="${HEXTUNNEL_ETC:-/etc/hextunnel}"
HEXTUNNEL_STATE="${HEXTUNNEL_STATE:-/var/lib/hextunnel}"
HEXTUNNEL_LOG_DIR="${HEXTUNNEL_LOG_DIR:-/var/log/hextunnel}"
HEXTUNNEL_INSTALL_DIR="${HEXTUNNEL_INSTALL_DIR:-/opt/hextunnel}"
HEXTUNNEL_CONFIG_FILE="${HEXTUNNEL_CONFIG_FILE:-$HEXTUNNEL_ETC/hextunnel.env}"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

join_by() {
  local separator="$1" first=1 item
  shift
  for item in "$@"; do
    ((first)) || printf '%s' "$separator"
    printf '%s' "$item"
    first=0
  done
}

require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Hex Tunnel debe ejecutarse como root."
}

ensure_dir() {
  local mode="$1" path="$2"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && { log_dry "install -d -m $mode $path"; return 0; }
  install -d -m "$mode" "$path"
}

run_cmd() {
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]]; then
    log_dry "$(printf '%q ' "$@")"
    return 0
  fi
  log_debug "Ejecutando: $(printf '%q ' "$@")"
  "$@"
}

write_file() {
  local path="$1" mode="${2:-600}" content tmp
  content="$(cat)"
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]]; then
    log_dry "escribir $path modo $mode"
    return 0
  fi
  backup_path "$path"
  install -d -m 755 "$(dirname "$path")"
  tmp="$(mktemp "${path}.tmp.XXXXXX")"
  printf '%s\n' "$content" > "$tmp"
  chmod "$mode" "$tmp"
  chown root:root "$tmp"
  mv -f "$tmp" "$path"
}

random_secret() {
  local length="${1:-32}" bytes value
  [[ "$length" =~ ^[0-9]+$ && "$length" -ge 16 ]] || die "La longitud mínima de un secreto es 16."
  bytes=$(((length + 1) / 2))
  if command_exists openssl; then
    value="$(openssl rand -hex "$bytes")"
  else
    value="$(od -An -N "$bytes" -tx1 /dev/urandom | tr -d '[:space:]')"
  fi
  printf '%.*s' "$length" "$value"
}

validate_private_env_file() {
  local path="$1" owner mode numeric_mode
  owner="$(stat -c '%U' "$path" 2>/dev/null || printf unknown)"
  mode="$(stat -c '%a' "$path" 2>/dev/null || printf 000)"
  [[ "$owner" == root || "${EUID:-$(id -u)}" -ne 0 ]] || die "$path debe pertenecer a root."
  numeric_mode=$((8#$mode))
  (( (numeric_mode & 022) == 0 )) || die "$path no puede ser escribible por grupo u otros."
}

load_runtime_config() {
  ensure_dir 700 "$HEXTUNNEL_ETC"
  if [[ -f "$HEXTUNNEL_CONFIG_FILE" ]]; then
    validate_private_env_file "$HEXTUNNEL_CONFIG_FILE"
    # shellcheck disable=SC1090
    source "$HEXTUNNEL_CONFIG_FILE"
  fi
}

ensure_system_user() {
  local username="$1" group_created=0 marker_dir marker
  id -u "$username" >/dev/null 2>&1 && return 0
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]]; then
    log_dry "crear usuario de sistema $username"
    return 0
  fi
  if ! getent group "$username" >/dev/null 2>&1; then
    groupadd --system "$username"
    group_created=1
  fi
  useradd --system --gid "$username" --home-dir /nonexistent --shell /usr/sbin/nologin "$username"
  if [[ -n "${HEXTUNNEL_TRANSACTION_DIR:-}" ]]; then
    printf 'USER|%s|%s\n' "$username" "$group_created" >> "$HEXTUNNEL_TRANSACTION_DIR/created-users.manifest"
  fi
  marker_dir="$HEXTUNNEL_STATE/system-users"
  marker="$marker_dir/$username"
  ensure_dir 700 "$marker_dir"
  backup_path "$marker"
  printf 'created_at=%s\ngroup_created=%s\n' "$(date -Is)" "$group_created" > "$marker"
  chmod 600 "$marker"
}

remove_managed_system_user() {
  local username="$1" marker="$HEXTUNNEL_STATE/system-users/$username" group_created=0
  [[ -f "$marker" ]] || return 0
  # shellcheck disable=SC1090
  source "$marker"
  backup_path "$marker"
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]]; then
    log_dry "eliminar usuario administrado $username"
    return 0
  fi
  userdel "$username" >/dev/null 2>&1 || true
  [[ "${group_created:-0}" == 1 ]] && groupdel "$username" >/dev/null 2>&1 || true
  rm -f "$marker"
}

confirm_action() {
  local prompt="$1" answer
  [[ "${HEXTUNNEL_FORCE:-0}" == 1 ]] && return 0
  [[ "${HEXTUNNEL_NON_INTERACTIVE:-0}" == 1 ]] && return 1
  read -r -p "$prompt [s/N]: " answer
  [[ "$answer" =~ ^[SsYy]$ ]]
}

sanitize_text() {
  awk '
    /-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----/ {
      print "[PRIVATE_KEY_REDACTED]"
      private_key=1
      next
    }
    private_key && /-----END (RSA |EC |OPENSSH )?PRIVATE KEY-----/ {
      private_key=0
      next
    }
    private_key { next }
    { print }
  ' | sed -E \
    -e 's/[0-9]{8,12}:[A-Za-z0-9_-]{20,}/[TELEGRAM_TOKEN]/g' \
    -e 's/(password|token|secret|auth)(["=: ]+)[^ ,"}]*/\1\2[REDACTED]/Ig'
}
