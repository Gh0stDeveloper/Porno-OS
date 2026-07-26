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

stage configurable-dns-listeners
HEXTUNNEL_SLOWDNS_LISTEN_PORT=5353
unset HEXTUNNEL_SLOWDNS_LISTEN_ADDRESS || true
[[ "$(slowdns_ports)" == 'udp 5353 0.0.0.0/0 public' ]]
HEXTUNNEL_SLOWDNS_LISTEN_ADDRESS=127.0.0.1
[[ -z "$(slowdns_ports)" ]]
HEXTUNNEL_SLIPSTREAM_DNS_PORT=5354
unset HEXTUNNEL_SLIPSTREAM_DNS_ADDRESS || true
[[ "$(slipstream_ports)" == 'udp 5354 0.0.0.0/0 public' ]]
HEXTUNNEL_SLIPSTREAM_DNS_ADDRESS=127.0.0.1
[[ -z "$(slipstream_ports)" ]]
unset HEXTUNNEL_SLOWDNS_LISTEN_PORT HEXTUNNEL_SLOWDNS_LISTEN_ADDRESS
aunset=0
unset HEXTUNNEL_SLIPSTREAM_DNS_PORT HEXTUNNEL_SLIPSTREAM_DNS_ADDRESS || aunset=$?
((aunset == 0))

stage configurable-nat-ranges
HEXTUNNEL_HYSTERIA1_NAT_START=21000
HEXTUNNEL_HYSTERIA1_NAT_END=22000
HEXTUNNEL_HYSTERIA1_PORT=36712
HEXTUNNEL_HYSTERIA1_NAT_EXEMPT=36713
read -r nat_start nat_end nat_target nat_exempt < <(nat_profile_values hysteria1)
[[ "$nat_start $nat_end $nat_target $nat_exempt" == '21000 22000 36712 36713' ]]
nat_validate_values "$nat_start" "$nat_end" "$nat_target" "$nat_exempt"
if (nat_validate_values 50000 20000 5667 ""); then
  printf 'invalid NAT range was accepted\n' >&2
  exit 1
fi
unset HEXTUNNEL_HYSTERIA1_NAT_START HEXTUNNEL_HYSTERIA1_NAT_END HEXTUNNEL_HYSTERIA1_PORT HEXTUNNEL_HYSTERIA1_NAT_EXEMPT

stage secret-generation
secret="$(random_secret 32)"
[[ ${#secret} -eq 32 && "$secret" =~ ^[a-f0-9]+$ ]]

stage managed-user-removal
mkdir -p "$HEXTUNNEL_STATE/system-users"
printf 'created_at=%s\ngroup_created=0\n' "$(date -Is)" > "$HEXTUNNEL_STATE/system-users/test-service"
remove_managed_system_user test-service

stage empty-firewall-removal
(
  HEXTUNNEL_DRY_RUN=0
  firewall_backend() { printf ufw; }
  ufw() {
    if [[ "${1:-}" == status ]]; then
      printf 'Status: active\n'
    fi
    return 0
  }
  firewall_close_port tcp 443
)
(
  HEXTUNNEL_DRY_RUN=0
  firewall_backend() { printf nft; }
  nft() { return 0; }
  firewall_close_port udp 36713
)

stage transaction-commit-guard
transaction_dir="$HEXTUNNEL_STATE/transactions/rolled-back-test"
mkdir -p "$transaction_dir"
printf '%s\n' ROLLED_BACK > "$transaction_dir/status"
if (
  HEXTUNNEL_DRY_RUN=0
  HEXTUNNEL_TRANSACTION_DIR="$transaction_dir"
  transaction_commit
); then
  printf 'rolled-back transaction was incorrectly committed\n' >&2
  exit 1
fi
[[ "$(transaction_status "$transaction_dir")" == ROLLED_BACK ]]

printf 'core tests: ok\n'
