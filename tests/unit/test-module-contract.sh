#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export HEXTUNNEL_ROOT="$ROOT"
export HEXTUNNEL_DRY_RUN=1
export HEXTUNNEL_STATE="$(mktemp -d /tmp/hextunnel-contract-state.XXXXXX)"
trap 'rm -rf "$HEXTUNNEL_STATE"' EXIT
for file in common logging backup rollback systemd firewall secrets validation modules; do
  # shellcheck disable=SC1090
  source "$ROOT/lib/$file.sh"
done
load_module_registry
required=(ports dependencies install uninstall validate doctor)
for module in "${HEXTUNNEL_AVAILABLE_MODULES[@]}"; do
  for action in "${required[@]}"; do
    function="$(module_function "$module" "$action")"
    declare -F "$function" >/dev/null || {
      printf 'missing %s for %s\n' "$action" "$module" >&2
      exit 1
    }
  done

  while read -r protocol port source scope extra; do
    [[ -z "$protocol" ]] && continue
    [[ -z "${extra:-}" ]] || {
      printf 'too many port fields for %s: %s %s %s %s %s\n' \
        "$module" "$protocol" "$port" "${source:-}" "${scope:-}" "$extra" >&2
      exit 1
    }
    [[ "$protocol" =~ ^(tcp|udp)$ ]]
    [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]]
    [[ -z "${source:-}" || "$source" =~ ^[A-Za-z0-9:./_-]+$ ]]
    [[ -z "${scope:-}" || "$scope" =~ ^(any|public)$ ]]
  done < <(module_call "$module" ports || true)
done

# Legacy/rc.2 migrations may have managed listeners but no module markers.
ssh_allow_port_conflict tcp 22 'users:(("sshd",pid=1,fd=3))'
ssh_allow_port_conflict tcp 299 'users:(("sshd",pid=2,fd=3))'
ssh_allow_port_conflict tcp 299 'users:(("systemd",pid=1,fd=99))'
ssh_allow_port_conflict tcp 4443 'users:(("stunnel4",pid=3,fd=4))'
ssh_allow_port_conflict tcp 25 'users:(("node",pid=4,fd=5))'
ssh_allow_port_conflict tcp 2082 'users:(("node",pid=5,fd=6))'
ssh_allow_port_conflict tcp 2086 'users:(("node",pid=6,fd=7))'
ssh_allow_port_conflict tcp 10080 'users:(("node",pid=7,fd=8))'
! ssh_allow_port_conflict tcp 299 'users:(("nginx",pid=8,fd=9))'
! ssh_allow_port_conflict tcp 443 'users:(("sshd",pid=9,fd=10))'
! ssh_allow_port_conflict udp 299 'users:(("sshd",pid=10,fd=11))'

for port in 80 443 8080 8880; do
  xray_allow_port_conflict tcp "$port" 'users:(("xray",pid=11,fd=12))'
done
! xray_allow_port_conflict tcp 443 'users:(("nginx",pid=12,fd=13))'
! xray_allow_port_conflict tcp 4443 'users:(("xray",pid=13,fd=14))'
! xray_allow_port_conflict udp 443 'users:(("xray",pid=14,fd=15))'

HEXTUNNEL_ARCH=arm64
export HEXTUNNEL_ARCH
for module in ssh xray hysteria hysteria2 zivpn webmin; do
  module_supports_architecture "$module" arm64 || {
    printf 'expected ARM64 support for %s\n' "$module" >&2
    exit 1
  }
done
for module in udp-custom slowdns slipstream legacy-all; do
  if module_supports_architecture "$module" arm64; then
    printf 'unexpected ARM64 support for %s\n' "$module" >&2
    exit 1
  fi
done

HEXTUNNEL_SINGBOX_SHA256=amd64-checksum
HEXTUNNEL_ZIVPN_SHA256=amd64-checksum
prepare_module_architecture_environment hysteria
prepare_module_architecture_environment zivpn
[[ -z "${HEXTUNNEL_SINGBOX_SHA256+x}" ]]
[[ -z "${HEXTUNNEL_ZIVPN_SHA256+x}" ]]

mapfile -t arm64_defaults < <(hextunnel_arm64_default_modules)
[[ "${arm64_defaults[*]}" == "ssh xray hysteria hysteria2 zivpn webmin" ]]

printf 'module contracts: ok\n'
