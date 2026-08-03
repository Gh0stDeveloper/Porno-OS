#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$ROOT"
maintained=(
  install.sh beta-install.sh bin lib modules templates config
  scripts/build-release.sh scripts/production-readiness.sh scripts/resolve-component-lock.sh
)

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

if grep -RIE --exclude='*.example' 'chmod[[:space:]]+755[^\n]*(\.key|key\.pem|server\.key)' modules lib bin install.sh beta-install.sh; then
  echo 'private key permissions cannot be executable/world-readable' >&2
  exit 1
fi

if grep -q 'codeload.github.com' install.sh; then
  echo 'the production bootstrap must not download the project from GitHub before license authorization' >&2
  exit 1
fi

if grep -RIE 'raw\.githubusercontent\.com/.*/main/' modules config; then
  echo 'mutable raw GitHub main URLs are forbidden in production dependencies' >&2
  exit 1
fi

component_override_pattern='^[[:space:]]*HEXTUNNEL_(UDP_CUSTOM_(REF|BINARY_URL|SHA256)|BADVPN_(REF|SOURCE_URL|SHA256)|SLOWDNS_(REF|BINARY_URL|SHA256)|SINGBOX_(VERSION|BINARY_URL|SHA256)|ZIVPN_(VERSION|BINARY_URL|SHA256|AMD64_(BINARY_URL|SHA256)|ARM64_(BINARY_URL|SHA256)))=""'
if grep -Eq "$component_override_pattern" config/hextunnel.env.example; then
  echo 'empty component overrides must not erase release lock values' >&2
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
grep -q 'bash "$PREFLIGHT"' bin/hextunnel-private-install
grep -q 'bash "$PREPARER".*licensed' bin/hextunnel-private-install
grep -q 'bash "$FINALIZER"' bin/hextunnel-private-install
grep -q 'exec /usr/local/bin/menu' bin/hextunnel-private-install
grep -q 'HEXTUNNEL_OPERATION:-install' bin/hextunnel-private-install
grep -q 'Arquitectura ARM64 detectada' bin/hextunnel-private-install
grep -q -- '--modules=ssh,xray,hysteria,hysteria2,zivpn,webmin' bin/hextunnel-private-install
grep -q 'hextunnel-arm64-menu' bin/hextunnel-private-install
grep -q 'install_framework' bin/hextunnel-private-upgrade
grep -q 'hextunnel-license-renew.timer' bin/hextunnel-install-license-runtime
grep -q 'https://ghostdeveloper.duckdns.org/install.sh' bin/hextunnel-install-license-runtime
grep -q 'bash -n "$tmp"' bin/hextunnel-install-license-runtime
grep -q 'hextunnel-arm64-menu' bin/hextunnel-install-license-runtime
grep -q '/usr/local/bin/menu.new' bin/hextunnel-install-license-runtime
grep -q 'Activación: permanente' bin/hextunnel-install-license-runtime
grep -q 'hextunnel-license reseller' bin/hextunnel-install-license-runtime
grep -q 'openssl dgst -sha256 -verify' bin/hextunnel-license
grep -q 'HEXTUNNEL_INSTALLATION_PERMANENT' bin/hextunnel-license
grep -q 'show_reseller' bin/hextunnel-license
grep -q '@Gh0stDeveloper' bin/hextunnel-install-license-runtime
grep -q '@Jotchua_DevzZ' bin/hextunnel-install-license-runtime

grep -q 'HEXTUNNEL_BETA_ACK' beta-install.sh
grep -q 'ACEPTO_BETA_PRIVADA' beta-install.sh
grep -q 'HEXTUNNEL_BETA_REF' beta-install.sh
grep -q '\^\[0-9a-fA-F\]{40}\$' beta-install.sh
grep -q 'Gh0stDeveloper/Porno-OS' beta-install.sh
grep -q HEXTUNNEL_BETA_MODE=1 beta-install.sh
grep -q HEXTUNNEL_BETA_MODE bin/hextunnel-beta-install
grep -q HEXTUNNEL_BETA_SOURCE_SHA bin/hextunnel-beta-install
grep -q 'bash "$PREFLIGHT"' bin/hextunnel-beta-install
grep -q 'bash "$PREPARER".*beta' bin/hextunnel-beta-install
grep -q 'bash "$FINALIZER"' bin/hextunnel-beta-install
grep -q 'exec /usr/local/bin/menu' bin/hextunnel-beta-install
grep -q '1.0.0-rc.6' docs/BETA.md

grep -q '^1\.0\.0-rc\.6$' VERSION
grep -q 'debian:12|ubuntu:22.04|ubuntu:24.04' lib/validation.sh
grep -q 'amd64|arm64' lib/validation.sh
grep -q 'aarch64|arm64' lib/validation.sh
grep -q 'udp_custom_supported_architectures.*amd64' lib/architecture.sh
grep -q 'slowdns_supported_architectures.*amd64' lib/architecture.sh
grep -q 'legacy_all_supported_architectures.*amd64' lib/architecture.sh
grep -q 'unset HEXTUNNEL_SINGBOX_SHA256' lib/architecture.sh
grep -q 'HEXTUNNEL_ZIVPN_ARM64_SHA256' lib/architecture.sh
grep -q 'HEXTUNNEL_ZIVPN_ARM64_BINARY_URL' lib/architecture.sh
grep -q 'HEXTUNNEL_ZIVPN_SHA256="${HEXTUNNEL_ZIVPN_ARM64_SHA256,,}"' lib/architecture.sh
grep -q 'HEXTUNNEL_ZIVPN_AMD64_SHA256' scripts/resolve-component-lock.sh
grep -q 'HEXTUNNEL_ZIVPN_ARM64_SHA256' scripts/resolve-component-lock.sh
grep -Fq '[[ -d "$HEXTUNNEL_ETC" ]] || ensure_dir 700 "$HEXTUNNEL_ETC"' lib/common.sh
grep -q 'test-runtime-config-readonly.sh' scripts/production-readiness.sh
grep -q 'systemctl reset-failed' lib/rollback.sh
grep -q 'operation_lock_acquire' lib/rollback.sh
grep -q HEXTUNNEL_OPERATION_LOCK_FILE lib/common.sh
grep -q /run/lock/hextunnel-operation.lock lib/common.sh
grep -q 'flock -n 8' lib/rollback.sh
grep -q 'hextunnel-backup restore' bin/hextunnel-backup
grep -q -- '--confirm-host' bin/hextunnel-backup
grep -q 'pre-restore-' bin/hextunnel-backup
grep -q '^etc/deekayvpn$' bin/hextunnel-backup
grep -q '^home/vps/public_html$' bin/hextunnel-backup
grep -q '^usr/local/bin/menu$' bin/hextunnel-backup
grep -q 'module_validate legacy-all' bin/hextunnel-finalize-install
grep -q 'module_install webmin' bin/hextunnel-finalize-install
grep -q 'module_install slipstream' bin/hextunnel-finalize-install
grep -q 'install_framework' bin/hextunnel-finalize-install
grep -q 'preflight_all legacy-all' bin/hextunnel-legacy-preflight
grep -q 'prepare-legacy-runtime.sh' scripts/production-readiness.sh
grep -q 'Runtime heredado saneado' scripts/prepare-legacy-runtime.sh
grep -q 'hextunnel-install-locked-component' scripts/prepare-legacy-runtime.sh
grep -q 'hextunnel-slipstream-compat' scripts/prepare-legacy-runtime.sh
grep -q 'locked_download' bin/hextunnel-install-locked-component
grep -q 'module_install slipstream' bin/hextunnel-slipstream-compat
grep -q RELEASE-MANIFEST.sha256 scripts/build-release.sh
grep -q resolve-component-lock.sh .github/workflows/release-candidate.yml
grep -q HEXTUNNEL_COMPONENT_LOCK_FILE lib/common.sh
grep -q HEXTUNNEL_COMPONENT_LOCK_VERSION scripts/resolve-component-lock.sh
grep -q d7bb82abb6b36f1320bc349f36c0746b335a9ff9 modules/udp-custom.sh
grep -q b667b0d15be0589cd89cd2f997873296ceb07ce2 modules/slowdns.sh
grep -q 'Production readiness: OK' scripts/production-readiness.sh
grep -q hextunnel-backup lib/framework.sh
grep -q hextunnel-slipstream-compat lib/framework.sh
grep -q /etc/logrotate.d/hextunnel lib/framework.sh
printf 'hardening invariants: ok\n'
