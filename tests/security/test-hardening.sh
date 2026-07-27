#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$ROOT"
maintained=(install.sh beta-install.sh bin lib modules templates config scripts)

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

if grep -RIE --exclude='*.example' 'chmod[[:space:]]+755[^\n]*(\.key|key\.pem|server\.key)' modules lib bin install.sh beta-install.sh scripts; then
  echo 'private key permissions cannot be executable/world-readable' >&2
  exit 1
fi

if grep -q 'codeload.github.com' install.sh; then
  echo 'the production bootstrap must not download the project from GitHub before license authorization' >&2
  exit 1
fi

grep -q "webmin_set_config_value ssl 1" modules/webmin.sh
grep -q "install -m 640 -o root -g hextunnel-hysteria2" lib/accounts.sh
grep -q "runuser -u hextunnel-slowdns -- test -r" modules/slowdns.sh
grep -q "apt-get install -y git curl build-essential cmake pkg-config" modules/slipstream.sh
grep -q "local binary=/usr/local/libexec/hextunnel/slipstream-server" modules/slipstream.sh
grep -q "install -m 755 .*slipstream-server.*\$binary" modules/slipstream.sh
grep -q "runuser -u hextunnel-slipstream -- test -x \$binary" modules/slipstream.sh
grep -q "openssl rand -hex 16 > /etc/slipstream/reset-seed" modules/slipstream.sh
grep -q "grep -Eq '\^\[0-9a-f\]{32}\$'" modules/slipstream.sh
grep -q "write_file /etc/dnsdist/dnsdist.conf 644" modules/slipstream.sh
grep -q "SuffixMatchNodeRule(slowdnsSuffixes)" modules/slipstream.sh
grep -q "dnsdist -C /etc/dnsdist/dnsdist.conf --check-config" modules/slipstream.sh
grep -q -- "--dns-listen-host 127.0.0.1 --dns-listen-port 5300" modules/slipstream.sh

grep -q 'bootstrap_authorize_and_download' install.sh
grep -q 'HEXTUNNEL_DISTRIBUTION_ENDPOINT' install.sh
grep -q 'package_sha256' install.sh
grep -q 'openssl dgst -sha256 -verify' install.sh
grep -q 'HEXTUNNEL_LICENSE_PREVALIDATED=1' install.sh
grep -q '"entrypoint": "bin/hextunnel-private-install"' docs/PRIVATE_DISTRIBUTION.md
grep -q 'validar_key_hextunnel' bin/hextunnel-private-install
grep -q 'exec /usr/local/bin/menu' bin/hextunnel-private-install

grep -q 'HEXTUNNEL_BETA_ACK' beta-install.sh
grep -q 'ACEPTO_BETA_PRIVADA' beta-install.sh
grep -q 'HEXTUNNEL_BETA_REF' beta-install.sh
grep -q '\^\[0-9a-fA-F\]{40}\$' beta-install.sh
grep -q 'Gh0stDeveloper/Porno-OS' beta-install.sh
grep -q 'HEXTUNNEL_BETA_MODE=1' beta-install.sh
grep -q 'HEXTUNNEL_BETA_MODE' bin/hextunnel-beta-install
grep -q 'HEXTUNNEL_BETA_SOURCE_SHA' bin/hextunnel-beta-install
grep -q 'validar_key_hextunnel' bin/hextunnel-beta-install
grep -q 'exec /usr/local/bin/menu' bin/hextunnel-beta-install
grep -q '1.0.0-beta.1' docs/BETA.md

grep -q '^1\.0\.0-rc\.1$' VERSION
grep -q 'operation_lock_acquire' lib/rollback.sh
grep -q 'flock -n 8' lib/rollback.sh
grep -q 'hextunnel-backup restore' bin/hextunnel-backup
grep -q -- '--confirm-host' bin/hextunnel-backup
grep -q 'pre-restore-' bin/hextunnel-backup
grep -q 'RELEASE-MANIFEST.sha256' scripts/build-release.sh
grep -q 'Production readiness: OK' scripts/production-readiness.sh
grep -q 'hextunnel-backup' lib/framework.sh
grep -q '/etc/logrotate.d/hextunnel' lib/framework.sh
printf 'hardening invariants: ok\n'
