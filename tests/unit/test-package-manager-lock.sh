#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TMP="$(mktemp -d /tmp/hextunnel-package-manager-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/mock-bin"

cat > "$TMP/mock-bin/pgrep" <<'EOF'
#!/usr/bin/env bash
if [[ "${MOCK_PACKAGE_MANAGER_BUSY:-0}" == 1 && "$*" == *unattended-upgr* ]]; then
  exit 0
fi
exit 1
EOF

cat > "$TMP/mock-bin/ps" <<'EOF'
#!/usr/bin/env bash
if [[ "${MOCK_PACKAGE_MANAGER_BUSY:-0}" == 1 ]]; then
  printf '24846 00:03:12 S unattended-upgr /usr/bin/unattended-upgrade\n'
fi
EOF

cat > "$TMP/mock-bin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$MOCK_APT_LOG"
EOF

cat > "$TMP/mock-bin/dpkg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$MOCK_DPKG_LOG"
EOF

chmod 700 \
  "$TMP/mock-bin/pgrep" \
  "$TMP/mock-bin/ps" \
  "$TMP/mock-bin/apt-get" \
  "$TMP/mock-bin/dpkg"

export PATH="$TMP/mock-bin:$PATH"
export MOCK_APT_LOG="$TMP/apt.log"
export MOCK_DPKG_LOG="$TMP/dpkg.log"
export HEXTUNNEL_ROOT="$ROOT"
export HEXTUNNEL_DRY_RUN=0
export HEXTUNNEL_APT_LOCK_TIMEOUT=37
export HEXTUNNEL_APT_LOCK_POLL_INTERVAL=1
export HEXTUNNEL_APT_LOCK_HEARTBEAT=2

# shellcheck disable=SC1091
source "$ROOT/lib/common.sh"
# shellcheck disable=SC1091
source "$ROOT/lib/logging.sh"
# shellcheck disable=SC1091
source "$ROOT/lib/install-runtime.sh"

export MOCK_PACKAGE_MANAGER_BUSY=1
package_manager_busy
snapshot="$(package_manager_process_snapshot)"
grep -Fq 'pid=24846' <<< "$snapshot"
grep -Fq 'command=unattended-upgr' <<< "$snapshot"

export MOCK_PACKAGE_MANAGER_BUSY=0
if package_manager_busy; then
  echo 'package manager was reported busy without a matching process' >&2
  exit 1
fi

run_cmd apt-get update
run_cmd dpkg --configure -a

grep -Fq -- '-o DPkg::Lock::Timeout=37' "$MOCK_APT_LOG"
grep -Fq -- '-o APT::Update::Lock::Timeout=37' "$MOCK_APT_LOG"
grep -Eq '(^|[[:space:]])update($|[[:space:]])' "$MOCK_APT_LOG"
grep -Fqx -- '--configure -a' "$MOCK_DPKG_LOG"

if (
  HEXTUNNEL_APT_LOCK_TIMEOUT=invalid
  package_manager_wait
); then
  echo 'invalid package manager timeout was accepted' >&2
  exit 1
fi

if (
  HEXTUNNEL_APT_LOCK_HEARTBEAT=invalid
  package_manager_wait
); then
  echo 'invalid package manager heartbeat was accepted' >&2
  exit 1
fi

HEXTUNNEL_REQUESTED_MODULES=(ssh xray)
HEXTUNNEL_PROGRESS_CURRENT=0
progress_output="$({
  install_progress_begin_module ssh
  install_progress_end_module ssh
} 2>&1)"
grep -Fq '[FASE 1/2 | 0%] Iniciando SSH + TLS.' <<< "$progress_output"
grep -Fq '[FASE 1/2 | 50%] SSH + TLS completado' <<< "$progress_output"

printf 'package manager lock handling and install progress: ok\n'
