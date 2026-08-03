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

cat > "$TMP/mock-bin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$MOCK_APT_LOG"
EOF

cat > "$TMP/mock-bin/dpkg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$MOCK_DPKG_LOG"
EOF

chmod 700 "$TMP/mock-bin/pgrep" "$TMP/mock-bin/apt-get" "$TMP/mock-bin/dpkg"

export PATH="$TMP/mock-bin:$PATH"
export MOCK_APT_LOG="$TMP/apt.log"
export MOCK_DPKG_LOG="$TMP/dpkg.log"
export HEXTUNNEL_ROOT="$ROOT"
export HEXTUNNEL_DRY_RUN=0
export HEXTUNNEL_APT_LOCK_TIMEOUT=37
export HEXTUNNEL_APT_LOCK_POLL_INTERVAL=1

# shellcheck disable=SC1091
source "$ROOT/lib/common.sh"
# shellcheck disable=SC1091
source "$ROOT/lib/logging.sh"

export MOCK_PACKAGE_MANAGER_BUSY=1
package_manager_busy
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

printf 'package manager lock handling: ok\n'
