#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export HEXTUNNEL_ROOT="$ROOT"
export HEXTUNNEL_DRY_RUN=1
export HEXTUNNEL_STATE="$(mktemp -d /tmp/hextunnel-test-state.XXXXXX)"
trap 'rm -rf "$HEXTUNNEL_STATE"' EXIT

stage() { printf 'TEST: %s\n' "$1"; }
index_of() {
  local needle="$1" index
  shift
  local values=("$@")
  for index in "${!values[@]}"; do
    [[ "${values[$index]}" == "$needle" ]] && { printf '%s' "$index"; return 0; }
  done
  return 1
}

stage source-libraries
for file in common logging backup rollback systemd firewall secrets validation modules; do
  # shellcheck disable=SC1090
  source "$ROOT/lib/$file.sh"
done

stage utility-functions
[[ "$(join_by , a b c)" == a,b,c ]]
[[ "$(normalize_architecture)" =~ ^(amd64|arm64|arm|386)$ ]]

stage module-registry
load_module_registry
for module in ssh xray hysteria hysteria2 udp-custom slowdns slipstream zivpn webmin legacy-all; do
  module_exists "$module"
done

stage certificate-common-name
HEXTUNNEL_DOMAIN='invalid/domain:with spaces-and-a-name-that-is-deliberately-longer-than-sixty-four-characters.example'
common_name="$(ssh_certificate_common_name)"
[[ ${#common_name} -le 64 ]]
[[ "$common_name" =~ ^[A-Za-z0-9.-]+$ ]]
unset HEXTUNNEL_DOMAIN

stage recursive-dependencies
requested=(hysteria2 slipstream)
resolve_module_dependencies requested
printf 'resolved: %s\n' "${requested[*]}"
for module in ssh xray hysteria2 slowdns slipstream; do
  index_of "$module" "${requested[@]}" >/dev/null
done
ssh_index="$(index_of ssh "${requested[@]}")"
xray_index="$(index_of xray "${requested[@]}")"
hysteria_index="$(index_of hysteria2 "${requested[@]}")"
slowdns_index="$(index_of slowdns "${requested[@]}")"
slipstream_index="$(index_of slipstream "${requested[@]}")"
((ssh_index < xray_index && xray_index < hysteria_index))
((ssh_index < slowdns_index && slowdns_index < slipstream_index))

stage secret-generation
secret="$(random_secret 32)"
[[ ${#secret} -eq 32 && "$secret" =~ ^[a-f0-9]+$ ]]

stage managed-user-removal
mkdir -p "$HEXTUNNEL_STATE/system-users"
printf 'created_at=%s\ngroup_created=0\n' "$(date -Is)" > "$HEXTUNNEL_STATE/system-users/test-service"
remove_managed_system_user test-service

printf 'core tests: ok\n'
