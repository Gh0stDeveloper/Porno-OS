#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
HELPER="$ROOT/bin/hextunnel-cloudflare-warp"
WORK="$(mktemp -d /tmp/hextunnel-warp-test.XXXXXX)"
FAKEBIN="$WORK/bin"
LOG="$WORK/commands.log"
TEST_TMP="$WORK/tmp"

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
mkdir -p "$FAKEBIN" "$WORK/etc/apt/sources.list.d" "$WORK/usr/share/keyrings" "$WORK/state" "$TEST_TMP"
chmod 700 "$TEST_TMP"

cat > "$FAKEBIN/apt-get" <<'EOF_APT'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >> "$HEXTUNNEL_TEST_COMMAND_LOG"
exit 0
EOF_APT

cat > "$FAKEBIN/curl" <<'EOF_CURL'
#!/usr/bin/env bash
output=''
while (($#)); do
  case "$1" in
    -o) output="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$output" ]] || exit 2
printf 'FAKE OPENPGP KEY\n' > "$output"
printf 'curl key\n' >> "$HEXTUNNEL_TEST_COMMAND_LOG"
EOF_CURL

cat > "$FAKEBIN/gpg" <<'EOF_GPG'
#!/usr/bin/env bash
printf 'gpg %s\n' "$*" >> "$HEXTUNNEL_TEST_COMMAND_LOG"
if [[ " $* " == *' --show-keys '* ]]; then
  printf 'pub:-:2048:1:6E2DD2174FA1C3BA:0:0::-:::scESC::::::23::0:\n'
  printf 'fpr:::::::::C068A2B5771775193CBE1F2F6E2DD2174FA1C3BA:\n'
  exit 0
fi
if [[ " $* " == *' --dearmor '* ]]; then
  output=''
  input=''
  while (($#)); do
    case "$1" in
      --output) output="$2"; shift 2 ;;
      --batch|--yes|--dearmor) shift ;;
      *) input="$1"; shift ;;
    esac
  done
  cp "$input" "$output"
  exit 0
fi
exit 0
EOF_GPG

cat > "$FAKEBIN/dpkg" <<'EOF_DPKG'
#!/usr/bin/env bash
if [[ "${1:-}" == --print-architecture ]]; then
  printf 'amd64\n'
  exit 0
fi
printf 'dpkg %s\n' "$*" >> "$HEXTUNNEL_TEST_COMMAND_LOG"
exit 0
EOF_DPKG

cat > "$FAKEBIN/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$HEXTUNNEL_TEST_COMMAND_LOG"
exit 0
EOF_SYSTEMCTL

cat > "$FAKEBIN/warp-cli" <<'EOF_WARP'
#!/usr/bin/env bash
printf 'warp-cli %s\n' "$*" >> "$HEXTUNNEL_TEST_COMMAND_LOG"
exit 0
EOF_WARP

cat > "$FAKEBIN/ss" <<'EOF_SS'
#!/usr/bin/env bash
printf 'LISTEN 0 4096 127.0.0.1:40000 0.0.0.0:* users:(("warp-svc",pid=20,fd=7))\n'
EOF_SS

chmod 700 "$FAKEBIN"/*

run_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -E "$@"
  else
    echo 'test-cloudflare-warp requiere root o sudo' >&2
    exit 1
  fi
}

SOURCE_FILE="$WORK/etc/apt/sources.list.d/cloudflare-client.list"
KEYRING_FILE="$WORK/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg"
STATE_DIR="$WORK/state"

printf 'deb https://pkg.cloudflareclient.com/ noble main\n' > "$SOURCE_FILE"
printf 'expired-key\n' > "$KEYRING_FILE"

run_root env \
  PATH="$FAKEBIN:$PATH" \
  HEXTUNNEL_TEST_COMMAND_LOG="$LOG" \
  HEXTUNNEL_WARP_SOURCE_FILE="$SOURCE_FILE" \
  HEXTUNNEL_WARP_KEYRING_FILE="$KEYRING_FILE" \
  HEXTUNNEL_WARP_STATE_DIR="$STATE_DIR" \
  bash "$HELPER" cleanup

[[ ! -e "$SOURCE_FILE" && ! -e "$KEYRING_FILE" ]]
run_root find "$STATE_DIR/backups" -type f -name 'cloudflare-client.list.*' -print -quit | grep -q .
run_root find "$STATE_DIR/backups" -type f -name 'cloudflare-warp-keyring.gpg.*' -print -quit | grep -q .

printf 'deb https://example.invalid/ stable main\n' > "$SOURCE_FILE"
if run_root env \
  PATH="$FAKEBIN:$PATH" \
  HEXTUNNEL_TEST_COMMAND_LOG="$LOG" \
  HEXTUNNEL_WARP_SOURCE_FILE="$SOURCE_FILE" \
  HEXTUNNEL_WARP_KEYRING_FILE="$KEYRING_FILE" \
  HEXTUNNEL_WARP_STATE_DIR="$STATE_DIR" \
  bash "$HELPER" cleanup >/dev/null 2>&1; then
  echo 'cleanup no debe reemplazar un archivo de repositorio ajeno' >&2
  exit 1
fi
grep -Fq 'example.invalid' "$SOURCE_FILE"
rm -f "$SOURCE_FILE"

run_root env \
  PATH="$FAKEBIN:$PATH" \
  HEXTUNNEL_TEST_COMMAND_LOG="$LOG" \
  HEXTUNNEL_TMP_DIR="$TEST_TMP" \
  HEXTUNNEL_WARP_CODENAME=noble \
  HEXTUNNEL_WARP_SOURCE_FILE="$SOURCE_FILE" \
  HEXTUNNEL_WARP_KEYRING_FILE="$KEYRING_FILE" \
  HEXTUNNEL_WARP_STATE_DIR="$STATE_DIR" \
  bash "$HELPER" install

[[ -s "$SOURCE_FILE" && -s "$KEYRING_FILE" ]]
run_root test -s "$STATE_DIR/state.env"
[[ "$(stat -c '%a' "$TEST_TMP")" == 1777 ]]
grep -Fq "signed-by=$KEYRING_FILE" "$SOURCE_FILE"
grep -Fq 'https://pkg.cloudflareclient.com/ noble main' "$SOURCE_FILE"
run_root grep -Eq 'apt-get .*install -y cloudflare-warp' "$LOG"
run_root grep -Fq 'DPkg::Lock::Timeout=' "$LOG"
run_root grep -Fq 'systemctl enable --now warp-svc' "$LOG"
run_root grep -Fq 'warp-cli --accept-tos mode proxy' "$LOG"
run_root grep -Fq 'warp-cli --accept-tos proxy port 40000' "$LOG"
run_root grep -Fq 'warp-cli --accept-tos connect' "$LOG"

if grep -Eq 'apt-key|trusted=yes' "$HELPER"; then
  echo 'el helper WARP no debe eludir la verificación criptográfica de APT' >&2
  exit 1
fi

printf 'Cloudflare WARP repository recovery, tmp repair and guarded proxy setup: ok\n'
