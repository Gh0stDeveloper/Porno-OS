#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
HELPER="$ROOT/bin/hextunnel-package-manager"
LOCKED_COMPONENT="$ROOT/bin/hextunnel-install-locked-component"
WORK="$(mktemp -d /tmp/hextunnel-package-command-test.XXXXXX)"
FAKEBIN="$WORK/bin"
TEST_TMP="$WORK/tmp"
APT_LOG="$WORK/apt.log"
DPKG_LOG="$WORK/dpkg.log"
LOCK_FILE="$WORK/dpkg-lock"
BUSY_COUNT="$WORK/busy-count"
DPKG_FAIL_COUNT="$WORK/dpkg-fail-count"

cleanup() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    rm -rf "$WORK"
  elif command -v sudo >/dev/null 2>&1; then
    sudo rm -rf "$WORK"
  else
    rm -rf "$WORK" 2>/dev/null || true
  fi
}
trap cleanup EXIT

run_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -E "$@"
  else
    echo 'test-package-manager-command requiere root o sudo' >&2
    exit 1
  fi
}

bash -n "$HELPER"
bash -n "$LOCKED_COMPONENT"
mkdir -p "$FAKEBIN" "$TEST_TMP"
chmod 700 "$TEST_TMP"
touch "$LOCK_FILE"
printf '2\n' > "$BUSY_COUNT"
printf '1\n' > "$DPKG_FAIL_COUNT"

cat > "$FAKEBIN/fuser" <<'EOF_FUSER'
#!/usr/bin/env bash
[[ "${1:-}" == "$MOCK_LOCK_FILE" ]] || exit 0
count="$(cat "$MOCK_BUSY_COUNT" 2>/dev/null || printf 0)"
if [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]]; then
  printf '%s\n' 24846
  printf '%s\n' "$((count - 1))" > "$MOCK_BUSY_COUNT"
fi
EOF_FUSER

cat > "$FAKEBIN/ps" <<'EOF_PS'
#!/usr/bin/env bash
if [[ "$*" == *'-p 24846'* ]]; then
  printf '24846 00:00:03 S unattended-upgr /usr/bin/unattended-upgrade\n'
fi
EOF_PS

cat > "$FAKEBIN/apt-get" <<'EOF_APT'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >> "$MOCK_APT_LOG"
exit 0
EOF_APT

cat > "$FAKEBIN/apt" <<'EOF_APT_CMD'
#!/usr/bin/env bash
printf 'apt %s\n' "$*" >> "$MOCK_APT_LOG"
exit 0
EOF_APT_CMD

cat > "$FAKEBIN/dpkg" <<'EOF_DPKG'
#!/usr/bin/env bash
count="$(cat "$MOCK_DPKG_FAIL_COUNT" 2>/dev/null || printf 0)"
printf 'dpkg %s\n' "$*" >> "$MOCK_DPKG_LOG"
if [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]]; then
  printf '%s\n' "$((count - 1))" > "$MOCK_DPKG_FAIL_COUNT"
  echo 'dpkg: error: dpkg frontend lock is locked by another process' >&2
  exit 2
fi
exit 0
EOF_DPKG

cat > "$FAKEBIN/apt-mark" <<'EOF_APT_MARK'
#!/usr/bin/env bash
printf 'apt-mark %s\n' "$*" >> "$MOCK_APT_LOG"
exit 0
EOF_APT_MARK

chmod 700 "$FAKEBIN"/*

common_env=(
  PATH="$FAKEBIN:$PATH"
  HEXTUNNEL_PACKAGE_ROOT="$ROOT"
  HEXTUNNEL_TMP_DIR="$TEST_TMP"
  HEXTUNNEL_APT_LOCK_FILES="$LOCK_FILE"
  HEXTUNNEL_APT_LOCK_TIMEOUT=20
  HEXTUNNEL_APT_LOCK_POLL_INTERVAL=1
  HEXTUNNEL_APT_LOCK_HEARTBEAT=1
  HEXTUNNEL_DPKG_RETRY_ATTEMPTS=3
  MOCK_LOCK_FILE="$LOCK_FILE"
  MOCK_BUSY_COUNT="$BUSY_COUNT"
  MOCK_DPKG_FAIL_COUNT="$DPKG_FAIL_COUNT"
  MOCK_APT_LOG="$APT_LOG"
  MOCK_DPKG_LOG="$DPKG_LOG"
)

run_root env "${common_env[@]}" bash "$HELPER" apt-get update
[[ "$(stat -c '%a' "$TEST_TMP")" == 1777 ]]
run_root grep -Fq 'DPkg::Lock::Timeout=20' "$APT_LOG"
run_root grep -Fq 'APT::Update::Lock::Timeout=20' "$APT_LOG"
run_root grep -Eq '(^|[[:space:]])update($|[[:space:]])' "$APT_LOG"

run_root env "${common_env[@]}" bash "$HELPER" dpkg --configure -a
run_root grep -Fq 'dpkg --configure -a' "$DPKG_LOG"
[[ "$(run_root wc -l < "$DPKG_LOG" | tr -d ' ')" -eq 2 ]]

if grep -Fq 'install -d -m 700 "$(dirname "$output")"' "$LOCKED_COMPONENT"; then
  echo 'locked_download todavía puede convertir /tmp en 0700' >&2
  exit 1
fi
grep -Fq 'if [[ ! -d "$parent" ]]' "$LOCKED_COMPONENT"
grep -Fq 'run_package_manager dpkg -i' "$LOCKED_COMPONENT"
grep -Fq 'run_package_manager apt-get update' "$LOCKED_COMPONENT"

printf 'guarded package command repairs tmp and retries dpkg lock races: ok\n'
