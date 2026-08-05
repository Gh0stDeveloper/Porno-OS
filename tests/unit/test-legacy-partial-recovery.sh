#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
HELPER="$ROOT/bin/hextunnel-recover-legacy-partial"
WORK="$(mktemp -d /tmp/hextunnel-partial-recovery-test.XXXXXX)"
FAKEBIN="$WORK/bin"
LOG="$WORK/systemctl.log"
ACTIVE="$WORK/active-units"

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

bash -n "$HELPER"
mkdir -p "$FAKEBIN" "$WORK/evidence" "$WORK/recovery" "$WORK/modules" "$WORK/etc"

cat > "$FAKEBIN/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$HEXTUNNEL_TEST_SYSTEMCTL_LOG"
case "${1:-}" in
  is-active)
    unit="${*: -1}"
    grep -Fxq "$unit" "$HEXTUNNEL_TEST_ACTIVE_UNITS"
    ;;
  stop)
    unit="${2:-}"
    grep -Fxv "$unit" "$HEXTUNNEL_TEST_ACTIVE_UNITS" > "$HEXTUNNEL_TEST_ACTIVE_UNITS.tmp" || true
    mv "$HEXTUNNEL_TEST_ACTIVE_UNITS.tmp" "$HEXTUNNEL_TEST_ACTIVE_UNITS"
    ;;
  reset-failed)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF_SYSTEMCTL
chmod 700 "$FAKEBIN/systemctl"

run_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -E "$@"
  else
    echo 'test-legacy-partial-recovery requiere root o sudo' >&2
    exit 1
  fi
}

for name in zorro deekay ws-proxy slowdns hysteria2; do
  touch "$WORK/evidence/$name"
done
EVIDENCE_PATHS="$WORK/evidence/zorro:$WORK/evidence/deekay:$WORK/evidence/ws-proxy:$WORK/evidence/slowdns:$WORK/evidence/hysteria2"

cat > "$ACTIVE" <<'EOF_ACTIVE'
ssh.service
systemd-resolved.service
ws-proxy@25.service
sslh.service
nginx.service
server-sldns.service
xray.service
hysteria2-server.service
udp-custom.service
zivpn.service
EOF_ACTIVE

common_env=(
  PATH="$FAKEBIN:$PATH"
  HEXTUNNEL_TEST_SYSTEMCTL_LOG="$LOG"
  HEXTUNNEL_TEST_ACTIVE_UNITS="$ACTIVE"
  HEXTUNNEL_SYSTEMCTL_BIN="$FAKEBIN/systemctl"
  HEXTUNNEL_PARTIAL_EVIDENCE_PATHS="$EVIDENCE_PATHS"
  HEXTUNNEL_LEGACY_FINAL_MARKER="$WORK/modules/legacy-all"
  HEXTUNNEL_INSTALL_MODE_FILE="$WORK/etc/install-mode.env"
  HEXTUNNEL_LEGACY_RECOVERY_DIR="$WORK/recovery"
)

run_root env "${common_env[@]}" bash "$HELPER" detect >/dev/null
run_root env "${common_env[@]}" bash "$HELPER" stop

for stopped in \
  ws-proxy@25.service sslh.service nginx.service server-sldns.service \
  xray.service hysteria2-server.service udp-custom.service zivpn.service; do
  grep -Fq "systemctl stop $stopped" "$LOG"
done

if grep -Eq 'systemctl stop (ssh|sshd|systemd-resolved)(\.service)?' "$LOG"; then
  echo 'la recuperación parcial no debe detener SSH ni systemd-resolved' >&2
  exit 1
fi

grep -Fxq 'ssh.service' "$ACTIVE"
grep -Fxq 'systemd-resolved.service' "$ACTIVE"
find "$WORK/recovery" -type f -name 'legacy-partial-stopped.*' -print -quit | grep -q .

: > "$LOG"
printf 'installed_at=now\nversion=test\n' > "$WORK/modules/legacy-all"
printf 'ws-proxy@25.service\nsslh.service\n' > "$ACTIVE"
run_root env "${common_env[@]}" bash "$HELPER" stop
if grep -Fq 'systemctl stop' "$LOG"; then
  echo 'una instalación finalizada no debe detener servicios durante el preflight' >&2
  exit 1
fi

rm -f "$WORK/modules/legacy-all"
printf 'HEXTUNNEL_INSTALL_MODE=complete-sanitized-panel\n' > "$WORK/etc/install-mode.env"
: > "$LOG"
run_root env "${common_env[@]}" bash "$HELPER" stop
if grep -Fq 'systemctl stop' "$LOG"; then
  echo 'install-mode finalizado debe impedir recuperación parcial' >&2
  exit 1
fi

printf 'interrupted legacy service recovery preserves SSH and systemd-resolved: ok\n'
