#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export HEXTUNNEL_ROOT="$ROOT"
export HEXTUNNEL_DRY_RUN=1
export HEXTUNNEL_STATE="$(mktemp -d /tmp/hextunnel-test-state.XXXXXX)"
trap 'rm -rf "$HEXTUNNEL_STATE"' EXIT
for file in common logging backup rollback systemd firewall secrets validation modules; do
  source "$ROOT/lib/$file.sh"
done
[[ "$(join_by , a b c)" == a,b,c ]]
[[ "$(normalize_architecture)" =~ ^(amd64|arm64|arm|386)$ ]]
load_module_registry
module_exists ssh
module_exists xray
module_exists hysteria2
requested=(hysteria2 slipstream)
resolve_module_dependencies requested
[[ "${requested[*]}" == "ssh xray hysteria2 slowdns slipstream" ]]
module_mark_installed ssh
module_is_installed ssh || true
printf 'core tests: ok\n'
