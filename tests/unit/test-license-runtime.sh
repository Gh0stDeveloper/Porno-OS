#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

expires_at="$(date -u -d '+2 days' +%Y-%m-%dT%H:%M:%SZ)"
lease_at="$(date -u -d '+6 hours' +%Y-%m-%dT%H:%M:%SZ)"
cat > "$TMP/license-state.env" <<EOF
HEXTUNNEL_LICENSE_EXPIRES_AT='$expires_at'
HEXTUNNEL_LEASE_EXPIRES_AT='$lease_at'
HEXTUNNEL_LICENSE_SUBJECT='203.0.113.10'
HEXTUNNEL_INSTALLED_VERSION='1.0.0-rc.3'
HEXTUNNEL_LAST_OPERATION='install'
EOF
chmod 600 "$TMP/license-state.env"

status_output="$(HEXTUNNEL_LICENSE_STATE_DIR="$TMP" bash "$ROOT/bin/hextunnel-license" status)"
grep -Fq '1.0.0-rc.3' <<< "$status_output"
grep -Fq '203.0.113.10' <<< "$status_output"
grep -Fq '@Gh0stDeveloper y @Jotchua_DevzZ' <<< "$status_output"

remaining_output="$(HEXTUNNEL_LICENSE_STATE_DIR="$TMP" bash "$ROOT/bin/hextunnel-license" remaining)"
grep -Eq '^[0-9]+d [0-9]{2}h [0-9]{2}m$' <<< "$remaining_output"

for file in \
  "$ROOT/bin/hextunnel-license" \
  "$ROOT/bin/hextunnel-install-license-runtime" \
  "$ROOT/bin/hextunnel-private-install" \
  "$ROOT/bin/hextunnel-private-upgrade"; do
  bash -n "$file"
done

grep -Fq 'hextunnel-license-renew.timer' "$ROOT/bin/hextunnel-install-license-runtime"
grep -Fq 'https://ghostdeveloper.duckdns.org/install.sh' "$ROOT/bin/hextunnel-install-license-runtime"
grep -Fq 'HEXTUNNEL_BRANDED_MENU=1' "$ROOT/bin/hextunnel-install-license-runtime"
grep -Fq 'hextunnel-arm64-menu' "$ROOT/bin/hextunnel-install-license-runtime"
grep -Fq '/usr/local/bin/menu.new' "$ROOT/bin/hextunnel-install-license-runtime"
grep -Fq 'bash -n "$tmp"' "$ROOT/bin/hextunnel-install-license-runtime"
grep -Fq '@Gh0stDeveloper' "$ROOT/bin/hextunnel-install-license-runtime"
grep -Fq '@Jotchua_DevzZ' "$ROOT/bin/hextunnel-install-license-runtime"
grep -Fq 'HEXTUNNEL_OPERATION:-install' "$ROOT/bin/hextunnel-private-install"

upgrade="$ROOT/bin/hextunnel-private-upgrade"
grep -Fq 'transaction_begin licensed-framework-upgrade' "$upgrade"
grep -Fq 'backup_paths' "$upgrade"
grep -Fq '/usr/local/bin/menu' "$upgrade"
grep -Fq 'install_framework' "$upgrade"
grep -Fq 'hextunnel-install-license-runtime' "$upgrade"
grep -Fq 'module_validate "$module"' "$upgrade"
grep -Fq 'hextunnel-license status' "$upgrade"
grep -Fq 'systemctl is-active --quiet hextunnel-license-renew.timer' "$upgrade"
commit_line="$(grep -nF 'transaction_commit' "$upgrade" | cut -d: -f1)"
validation_line="$(grep -nF 'module_validate "$module"' "$upgrade" | cut -d: -f1)"
runtime_line="$(grep -nF 'hextunnel-install-license-runtime' "$upgrade" | tail -n1 | cut -d: -f1)"
[[ "$commit_line" -gt "$validation_line" && "$commit_line" -gt "$runtime_line" ]]
! grep -Eq 'install_selected_modules|legacy/install-all' "$upgrade"

[[ "$(tr -d '\r\n' < "$ROOT/VERSION")" == '1.0.0-rc.3' ]]
echo 'license runtime: ok'
