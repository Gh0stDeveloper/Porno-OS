#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TMP="$(mktemp -d /tmp/hextunnel-install-runtime-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

command_exists() { command -v "$1" >/dev/null 2>&1; }
die() { printf 'test failure: %s\n' "$*" >&2; return 1; }
log_info() { :; }
log_warn() { :; }
log_success() { :; }
log_debug() { :; }
log_dry() { :; }

export HEXTUNNEL_ARTIFACT_CACHE_DIR="$TMP/cache"
export HEXTUNNEL_DRY_RUN=0

# shellcheck disable=SC1091
source "$ROOT/lib/install-runtime.sh"
# shellcheck disable=SC1091
source "$ROOT/lib/install-runtime-guards.sh"

unset SSH_CONNECTION || true
if ipv6_ssh_session_active; then
  echo 'missing SSH_CONNECTION was incorrectly detected as IPv6' >&2
  exit 1
fi

SSH_CONNECTION='2001:db8::10 12345 2001:db8::20 22'
ipv6_ssh_session_active
SSH_CONNECTION='192.0.2.10 12345 192.0.2.20 22'
if ipv6_ssh_session_active; then
  echo 'IPv4 SSH session was incorrectly detected as IPv6' >&2
  exit 1
fi

HEXTUNNEL_DRY_RUN=1
HEXTUNNEL_PREFETCH_STARTED=0
artifact_prefetch_xray() {
  printf 'unexpected\n' > "$TMP/dry-run-prefetch-called"
}
artifact_prefetch_selected_modules xray
[[ "$HEXTUNNEL_PREFETCH_STARTED" == 0 ]]
[[ ! -e "$TMP/dry-run-prefetch-called" ]]
HEXTUNNEL_DRY_RUN=0

printf 'verified parallel artifact\n' > "$TMP/source.bin"
expected="$(sha256sum "$TMP/source.bin" | awk '{print $1}')"
url="file://$TMP/source.bin"
key='test-artifact'

artifact_prefetch_register "$key" "$url" artifact_cache_store_locked \
  "$key" "$url" "$expected"

shared_tmp="$TMP/shared-tmp"
mkdir -p "$shared_tmp"
chmod 1777 "$shared_tmp"
run_cmd curl -fsSL -o "$shared_tmp/materialized.bin" "$url"
cmp -s "$TMP/source.bin" "$shared_tmp/materialized.bin"
[[ "$(stat -c '%a' "$shared_tmp")" == 1777 ]]
artifact_cache_validate "$key"

printf 'corrupt\n' > "$HEXTUNNEL_ARTIFACT_CACHE_DIR/$key"
if artifact_cache_validate "$key"; then
  echo 'corrupt cached artifact was accepted' >&2
  exit 1
fi
artifact_cache_store_locked "$key" "$url" "$expected"
artifact_cache_validate "$key"

output=''; parsed_url=''
curl_output_and_url output parsed_url -fL --retry 3 -o /tmp/example "$url"
[[ "$output" == /tmp/example && "$parsed_url" == "$url" ]]

artifact_prefetch_cancel_all
printf 'install runtime network and prefetch: ok\n'
