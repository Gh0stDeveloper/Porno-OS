#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export HEXTUNNEL_ROOT="$ROOT"
export HEXTUNNEL_DRY_RUN=1
export HEXTUNNEL_NON_INTERACTIVE=1
export HEXTUNNEL_NO_REBOOT=1
export HEXTUNNEL_CONFIG_FILE="$(mktemp /tmp/hextunnel-config.XXXXXX)"
export HEXTUNNEL_SECRETS_FILE="$(mktemp /tmp/hextunnel-secrets.XXXXXX)"
trap 'rm -f "$HEXTUNNEL_CONFIG_FILE" "$HEXTUNNEL_SECRETS_FILE"' EXIT
chmod 600 "$HEXTUNNEL_CONFIG_FILE" "$HEXTUNNEL_SECRETS_FILE"
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
