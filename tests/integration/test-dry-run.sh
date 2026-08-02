#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
WORK="$(mktemp -d /tmp/hextunnel-dry-run.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

export HEXTUNNEL_ROOT="$ROOT"
export HEXTUNNEL_DRY_RUN=1
export HEXTUNNEL_NON_INTERACTIVE=1
export HEXTUNNEL_NO_REBOOT=1
export HEXTUNNEL_CONFIG_FILE="$WORK/hextunnel.env"
export HEXTUNNEL_SECRETS_FILE="$WORK/secrets.env"

# The release gate must be deterministic and must not depend on listeners from
# the machine that builds/publishes the package. Real installations still use
# the system ss binary and enforce the full port-conflict preflight.
mkdir -p "$WORK/mock-bin"
cat > "$WORK/mock-bin/ss" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod 700 "$WORK/mock-bin/ss"
export PATH="$WORK/mock-bin:$PATH"

install -m 600 /dev/null "$HEXTUNNEL_CONFIG_FILE"
install -m 600 /dev/null "$HEXTUNNEL_SECRETS_FILE"
cat > "$HEXTUNNEL_CONFIG_FILE" <<'EOF'
HEXTUNNEL_ALLOW_ROOT_PASSWORD=0
HEXTUNNEL_WEBMIN_PUBLIC=0
EOF
cat > "$HEXTUNNEL_SECRETS_FILE" <<'EOF'
HEXTUNNEL_TELEGRAM_CHAT_ID=""
HEXTUNNEL_TELEGRAM_BOT_TOKEN=""
EOF

bash "$ROOT/install.sh" install --non-interactive --modules=ssh,xray --dry-run --no-reboot
printf 'installer dry-run: ok\n'
