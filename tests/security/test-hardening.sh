#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$ROOT"
maintained=(install.sh bin lib modules templates config)

reject() {
  local pattern="$1" message="$2"
  if grep -RIE --exclude='*.example' -- "$pattern" "${maintained[@]}"; then
    printf 'security invariant failed: %s\n' "$message" >&2
    exit 1
  fi
}

reject 'chmod[[:space:]]+777' 'world-writable permissions are forbidden'
reject 'ssl[[:space:]]*=[[:space:]]*0' 'Webmin TLS cannot be disabled'
reject 'systemctl[[:space:]]+(disable|mask|stop)[[:space:]]+systemd-resolved' 'the local resolver must be preserved'
reject 'rm[[:space:]]+-f[[:space:]]+/etc/resolv\.conf' 'resolv.conf must not be replaced'
reject '(curl|wget)[^|]*\|[[:space:]]*(ba)?sh' 'pipe-to-shell downloads are forbidden'
reject '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' 'private keys cannot be embedded'
reject 'PermitRootLogin[[:space:]]+yes' 'root password login must require an explicit runtime option'
reject 'openssl[[:space:]]+rand[[:space:]]+[0-9]+[[:space:]]*>[^\n]*reset-seed' 'SlipStream reset seed must be encoded as hexadecimal text'
reject 'QNameSuffixRule\(' 'dnsdist rules must remain compatible with supported LTS packages'

if grep -RIE --exclude='*.example' 'chmod[[:space:]]+755[^\n]*(\.key|key\.pem|server\.key)' modules lib bin install.sh; then
  echo 'private key permissions cannot be executable/world-readable' >&2
  exit 1
fi

grep -q "webmin_set_config_value ssl 1" modules/webmin.sh
grep -q "install -m 640 -o root -g hextunnel-hysteria2" lib/accounts.sh
grep -q "runuser -u hextunnel-slowdns -- test -r" modules/slowdns.sh
grep -q "openssl rand -hex 16 > /etc/slipstream/reset-seed" modules/slipstream.sh
grep -q "grep -Eq '\^\[0-9a-f\]{32}\$'" modules/slipstream.sh
grep -q "write_file /etc/dnsdist/dnsdist.conf 644" modules/slipstream.sh
grep -q "SuffixMatchNodeRule(slowdnsSuffixes)" modules/slipstream.sh
grep -q "dnsdist -C /etc/dnsdist/dnsdist.conf --check-config" modules/slipstream.sh
grep -q -- "--dns-listen-host 127.0.0.1 --dns-listen-port 5300" modules/slipstream.sh
printf 'hardening invariants: ok\n'
