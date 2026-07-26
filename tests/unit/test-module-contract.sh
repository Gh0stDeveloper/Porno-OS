#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export HEXTUNNEL_ROOT="$ROOT"
export HEXTUNNEL_DRY_RUN=1
export HEXTUNNEL_STATE="$(mktemp -d /tmp/hextunnel-contract-state.XXXXXX)"
trap 'rm -rf "$HEXTUNNEL_STATE"' EXIT
for file in common logging backup rollback systemd firewall secrets validation modules; do source "$ROOT/lib/$file.sh"; done
load_module_registry
required=(ports dependencies install uninstall validate doctor)
for module in "${HEXTUNNEL_AVAILABLE_MODULES[@]}"; do
  for action in "${required[@]}"; do
    function="$(module_function "$module" "$action")"
    declare -F "$function" >/dev/null || { printf 'missing %s for %s\n' "$action" "$module" >&2; exit 1; }
  done
  while read -r protocol port source; do
    [[ -z "$protocol" ]] && continue
    [[ "$protocol" =~ ^(tcp|udp)$ ]]
    [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]]
    [[ -z "${source:-}" || "$source" =~ ^[A-Za-z0-9:./_-]+$ ]]
  done < <(module_call "$module" ports || true)
done
printf 'module contracts: ok\n'
