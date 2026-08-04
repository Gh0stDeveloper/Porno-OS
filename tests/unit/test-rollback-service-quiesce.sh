#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TMP="$(mktemp -d /tmp/hextunnel-rollback-service-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/mock-bin" "$TMP/state/transactions/001-rolled-back"
printf '%s\n' ROLLED_BACK > "$TMP/state/transactions/001-rolled-back/status"
cat > "$TMP/state/transactions/001-rolled-back/services.manifest" <<'EOF'
SERVICE|ssh|enabled|active
SERVICE|hextunnel-hysteria-nat|disabled|inactive
SERVICE|hextunnel-hysteria|disabled|inactive
EOF

cat > "$TMP/mock-bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_SYSTEMCTL_LOG"
command_name="${1:-}"
service="${@: -1}"
case "$command_name" in
  is-active)
    if [[ "$service" == hextunnel-hysteria || "$service" == hextunnel-hysteria-nat ]]; then
      [[ ! -e "$MOCK_STATE_DIR/$service.stopped" ]]
      exit
    fi
    [[ "$service" == ssh ]]
    ;;
  stop)
    touch "$MOCK_STATE_DIR/$service.stopped"
    ;;
  kill|reset-failed|daemon-reload|enable|disable|restart)
    exit 0
    ;;
  show)
    printf '%s\n' loaded
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod 700 "$TMP/mock-bin/systemctl"

export PATH="$TMP/mock-bin:$PATH"
export MOCK_SYSTEMCTL_LOG="$TMP/systemctl.log"
export MOCK_STATE_DIR="$TMP/mock-state"
mkdir -p "$MOCK_STATE_DIR"

require_root() { :; }
command_exists() { command -v "$1" >/dev/null 2>&1; }
die() { printf 'test failure: %s\n' "$*" >&2; return 1; }
log_info() { :; }
log_warn() { :; }
log_success() { :; }
ensure_dir() { mkdir -p "$2"; }
firewall_restore() { :; }

export HEXTUNNEL_STATE="$TMP/state"
export HEXTUNNEL_OPERATION_LOCK_FILE="$TMP/operation.lock"
export HEXTUNNEL_OPERATION_LOCK_HELD=0
export HEXTUNNEL_DRY_RUN=0
export HEXTUNNEL_FORCE=0

# shellcheck disable=SC1091
source "$ROOT/lib/rollback.sh"

cleanup_latest_rolled_back_services

grep -Fq 'stop hextunnel-hysteria' "$MOCK_SYSTEMCTL_LOG"
grep -Fq 'stop hextunnel-hysteria-nat' "$MOCK_SYSTEMCTL_LOG"
if grep -Fq 'stop ssh' "$MOCK_SYSTEMCTL_LOG"; then
  echo 'pre-existing active SSH service was stopped' >&2
  exit 1
fi

mkdir -p "$TMP/state/transactions/002-failed"
printf '%s\n' FAILED > "$TMP/state/transactions/002-failed/status"
: > "$TMP/state/transactions/002-failed/files.manifest"
: > "$TMP/state/transactions/002-failed/services.manifest"
: > "$TMP/state/transactions/002-failed/created-users.manifest"

events="$TMP/order.log"
quiesce_transaction_services() { printf '%s\n' quiesce >> "$events"; }
restore_transaction_files() { printf '%s\n' files >> "$events"; }
restore_ipv6_runtime_state() { printf '%s\n' ipv6 >> "$events"; }
firewall_restore() { printf '%s\n' firewall >> "$events"; }
restore_transaction_services() { printf '%s\n' services >> "$events"; }
restore_created_users() { printf '%s\n' users >> "$events"; }
HEXTUNNEL_OPERATION_LOCK_HELD=1

rollback_transaction "$TMP/state/transactions/002-failed"

cat > "$TMP/expected-order.log" <<'EOF'
quiesce
files
ipv6
firewall
services
users
EOF
cmp -s "$TMP/expected-order.log" "$events"
[[ "$(cat "$TMP/state/transactions/002-failed/status")" == ROLLED_BACK ]]

printf 'rollback service quiesce and recovery cleanup: ok\n'
