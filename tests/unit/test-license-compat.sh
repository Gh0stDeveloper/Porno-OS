#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
WORK="$(mktemp -d /tmp/hextunnel-license-test.XXXXXX)"
trap 'rm -rf "${WORK:-}"' EXIT

# shellcheck source=../../lib/license-compat.sh
source "$ROOT/lib/license-compat.sh"

endpoint='203.0.113.10:8888'
token="$(printf '%040d' 123456789)"
raw="$endpoint/$token"
encoded="$(hextunnel_legacy_key_codec "$raw")"
[[ "$(hextunnel_legacy_key_codec "$encoded")" == "$raw" ]]
key="HexGen/$encoded"

hextunnel_legacy_license_parse "$key"
[[ "$HEXTUNNEL_LEGACY_LICENSE_ENDPOINT" == "$endpoint" ]]
[[ "$HEXTUNNEL_LEGACY_LICENSE_TOKEN" == "$token" ]]
! hextunnel_legacy_license_parse 'invalid-key'
! hextunnel_legacy_license_parse 'HexGen/not-valid'

mkdir -p "$WORK/bin"
cat > "$WORK/bin/curl" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *api.ipify.org*) printf '198.51.100.77' ;;
  *'http://$endpoint/$token/HexGen/198.51.100.77'*) printf 'HexGen' ;;
  *) exit 22 ;;
esac
EOF
chmod 700 "$WORK/bin/curl"

PATH="$WORK/bin:$PATH" \
HEXTUNNEL_REQUIRE_BOT_KEY=1 \
HEXTUNNEL_ALLOW_LEGACY_HTTP_LICENSE=1 \
HEXTUNNEL_LICENSE_KEY="$key" \
HEXTUNNEL_LICENSE_STATE_DIR="$WORK/state" \
hextunnel_validate_telebotgen_key >/dev/null

[[ "${HEXTUNNEL_LICENSE_PREVALIDATED:-0}" == 1 ]]
[[ "${HEXTUNNEL_LICENSE_SUBJECT:-}" == '198.51.100.77' ]]
[[ "$(cat "$WORK/state/license.key")" == "$key" ]]
grep -q '^HEXTUNNEL_LICENSE_PROVIDER=telebotgen-compat$' "$WORK/state/license-state.env"
grep -q '^HEXTUNNEL_LICENSE_SUBJECT=198.51.100.77$' "$WORK/state/license-state.env"
[[ "$(stat -c '%a' "$WORK/state/license.key")" == 600 ]]
[[ "$(stat -c '%a' "$WORK/state/license-state.env")" == 600 ]]

printf 'license compatibility: ok\n'
