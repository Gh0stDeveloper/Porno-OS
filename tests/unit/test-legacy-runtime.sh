#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
WORK="$(mktemp -d /tmp/hextunnel-legacy-runtime-test.XXXXXX)"
trap 'rm -rf "${WORK:-}"' EXIT

for mode in beta licensed; do
  output="$WORK/install-${mode}.sh"
  bash "$ROOT/scripts/prepare-legacy-runtime.sh" \
    "$ROOT/legacy/install-all.sh" "$output" "$mode" >/dev/null
  bash -n "$output"
  grep -q 'hextunnel-install-locked-component.*slowdns' "$output"
  grep -q 'hextunnel-install-locked-component.*badvpn' "$output"
  grep -q 'hextunnel-install-locked-component.*udp-custom' "$output"
  grep -q 'hextunnel-install-locked-component.*zivpn' "$output"
  grep -q 'hextunnel-install-locked-component.*sing-box' "$output"
  grep -q 'hextunnel-slipstream-compat' "$output"
  grep -q 'PermitRootLogin prohibit-password' "$output"
  grep -q 'X11Forwarding no' "$output"
  grep -q 'LogLevel INFO' "$output"
  grep -q 'systemd-resolved se conserva activo' "$output"
  grep -q 'Se conserva /root/.profile' "$output"
  grep -q '^hextunnel_dns_listen_address()' "$output"
  grep -Fq 'SlowDNS_Listen="$(hextunnel_dns_listen_address):53"' "$output"
  grep -Fq 'setLocal("$(hextunnel_dns_listen_address):53")' "$output"
  grep -Fq 'hextunnel-cloudflare-warp" cleanup' "$output"
  grep -Fq 'hextunnel-cloudflare-warp" install || exit $?' "$output"
  grep -Fq 'Instalando paquetes necesarios (esto tarda unos minutos)' "$output"
  grep -Fq 'if [[ -e /var/log/syslog ]]; then chown syslog:adm /var/log/syslog; chmod 640 /var/log/syslog; fi' "$output"

  if grep -Eq 'apt-get upgrade|chmod 777|ssl=0|raw\.githubusercontent\.com/.*/main/|sh\.rustup\.rs.*\|.*sh|dropbox\.com/.*/badvpn|SlowDNS_Listen=":53"|setLocal\("0\.0\.0\.0:53"\)|pkg\.cloudflareclient\.com/pubkey\.gpg|warp-cli --accept-tos|chown root:root /var/log; chmod 755 /var/log; chown syslog:adm /var/log/syslog|>&3' "$output"; then
    echo "runtime $mode conserva un patrón prohibido" >&2
    exit 1
  fi
done

grep -q 'HEXTUNNEL_BETA_MODE' "$WORK/install-beta.sh"
grep -q 'HEXTUNNEL_LICENSE_PREVALIDATED' "$WORK/install-licensed.sh"
printf 'legacy runtime sanitization, DNS binding, WARP recovery and syslog guard: ok\n'
