#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TMP="$(mktemp -d /tmp/hextunnel-package-manager-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/mock-bin"
touch "$TMP/dpkg-lock"
mkdir -p "$TMP/test-tmp"
chmod 700 "$TMP/test-tmp"

cat > "$TMP/mock-bin/fuser" <<'EOF'
#!/usr/bin/env bash
if [[ "${MOCK_PACKAGE_MANAGER_BUSY:-0}" == 1 && "${1:-}" == "$MOCK_LOCK_FILE" ]]; then
  printf '%s\n' 24846
fi
EOF

cat > "$TMP/mock-bin/pgrep" <<'EOF'
#!/usr/bin/env bash
# Simula el daemon permanente que no posee locks. La implementación correcta
# no debe considerarlo actividad de APT/DPKG cuando fuser está disponible.
if [[ "$*" == *unattended-upgr* ]]; then
  printf '%s\n' 1189
  exit 0
fi
exit 1
EOF

cat > "$TMP/mock-bin/ps" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *'-p 24846'* ]]; then
  printf '24846 00:03:12 S unattended-upgr /usr/bin/unattended-upgrade\n'
elif [[ "$*" == *'-p 1189'* ]]; then
  printf '1189 09:07:33 Ssl unattended-upgr /usr/share/unattended-upgrades/unattended-upgrade-shutdown --wait-for-signal\n'
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

chmod 700 "$TMP/mock-bin"/*

export PATH="$TMP/mock-bin:$PATH"
export MOCK_APT_LOG="$TMP/apt.log"
export MOCK_DPKG_LOG="$TMP/dpkg.log"
export MOCK_LOCK_FILE="$TMP/dpkg-lock"
export HEXTUNNEL_APT_LOCK_FILES="$MOCK_LOCK_FILE"
export HEXTUNNEL_TMP_DIR="$TMP/test-tmp"
export HEXTUNNEL_ROOT="$ROOT"
export HEXTUNNEL_DRY_RUN=0
export HEXTUNNEL_APT_LOCK_TIMEOUT=37
export HEXTUNNEL_APT_LOCK_POLL_INTERVAL=1
export HEXTUNNEL_APT_LOCK_HEARTBEAT=2
export HEXTUNNEL_PREFETCH_ENABLED=0

# shellcheck disable=SC1091
source "$ROOT/lib/common.sh"
# shellcheck disable=SC1091
source "$ROOT/lib/logging.sh"
# shellcheck disable=SC1091
source "$ROOT/lib/install-runtime.sh"
# shellcheck disable=SC1091
source "$ROOT/lib/install-runtime-guards.sh"

export MOCK_PACKAGE_MANAGER_BUSY=1
package_manager_busy
snapshot="$(package_manager_process_snapshot)"
grep -Fq 'pid=24846' <<< "$snapshot"
grep -Fq 'command=unattended-upgr' <<< "$snapshot"
[[ "$(stat -c '%a' "$HEXTUNNEL_TMP_DIR")" == 1777 ]]

export MOCK_PACKAGE_MANAGER_BUSY=0
if package_manager_busy; then
  echo 'shutdown watcher without a real lock was reported as package-manager activity' >&2
  exit 1
fi
[[ -z "$(package_manager_process_snapshot)" ]]

chmod 700 "$HEXTUNNEL_TMP_DIR"
run_cmd apt-get update
run_cmd dpkg --configure -a
[[ "$(stat -c '%a' "$HEXTUNNEL_TMP_DIR")" == 1777 ]]

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

printf 'package manager real-lock, tmp repair and install progress: ok\n'
