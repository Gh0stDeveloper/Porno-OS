#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

expires_at="$(date -u -d '+2 days' +%Y-%m-%dT%H:%M:%SZ)"
lease_at="$(date -u -d '+6 hours' +%Y-%m-%dT%H:%M:%SZ)"
cat > "$TMP/license-state.env" <<EOF
HEXTUNNEL_LICENSE_EXPIRES_AT='$expires_at'
HEXTUNNEL_LEASE_EXPIRES_AT='$lease_at'
HEXTUNNEL_LICENSE_SUBJECT='203.0.113.10'
HEXTUNNEL_INSTALLED_VERSION='1.0.0-rc.3'
HEXTUNNEL_LAST_OPERATION='install'
EOF
printf 'test-activation-token\n' > "$TMP/activation.token"
chmod 600 "$TMP/license-state.env" "$TMP/activation.token"

status_output="$(HEXTUNNEL_LICENSE_STATE_DIR="$TMP" bash "$ROOT/bin/hextunnel-license" status)"
grep -Fq '1.0.0-rc.3' <<< "$status_output"
grep -Fq '203.0.113.10' <<< "$status_output"
grep -Fq '@Gh0stDeveloper y @Jotchua_DevzZ' <<< "$status_output"

remaining_output="$(HEXTUNNEL_LICENSE_STATE_DIR="$TMP" bash "$ROOT/bin/hextunnel-license" remaining)"
grep -Eq '^[0-9]+d [0-9]{2}h [0-9]{2}m$' <<< "$remaining_output"

for file in \
  "$ROOT/bin/hextunnel-license" \
  "$ROOT/bin/hextunnel-install-license-runtime" \
  "$ROOT/bin/hextunnel-private-install" \
  "$ROOT/bin/hextunnel-private-upgrade"; do
  bash -n "$file"
done

license_runtime="$ROOT/bin/hextunnel-license"
grep -Fq 'flock -w 30 9' "$license_runtime"
grep -Fq 'atomic_update_lease' "$license_runtime"
grep -Fq 'PUBLIC_KEY_FILE=' "$license_runtime"
grep -Fq 'verify_public_key "$PUBLIC_KEY_FILE"' "$license_runtime"
grep -Fq -- '--data-binary "@$request_file"' "$license_runtime"
grep -Fq 'La API rechazó la renovación:' "$license_runtime"

# Exercise a real signed lease renewal with a local cached key. The mock curl
# must never be asked to download the public key.
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$TMP/private.pem" >/dev/null 2>&1
openssl pkey -in "$TMP/private.pem" -pubout -out "$TMP/license-public.pem" >/dev/null 2>&1
public_sha="$(sha256sum "$TMP/license-public.pem" | awk '{print $1}')"
new_lease="$(date -u -d '+12 hours' +%Y-%m-%dT%H:%M:%SZ)"
activation_id='11111111-2222-3333-4444-555555555555'
cat > "$TMP/lease.payload" <<EOF
status=active
lease_expires_at=$new_lease
subject=203.0.113.10
product=hextunnel
activation_id=$activation_id
EOF
openssl dgst -sha256 -sign "$TMP/private.pem" -out "$TMP/lease.sig" "$TMP/lease.payload"
signature="$(base64 -w0 "$TMP/lease.sig")"
jq -n \
  --arg lease "$new_lease" \
  --arg activation_id "$activation_id" \
  --arg signature "$signature" \
  '{status:"active",lease_expires_at:$lease,subject:"203.0.113.10",product:"hextunnel",activation_id:$activation_id,signature:$signature}' \
  > "$TMP/lease-response.json"

mkdir -p "$TMP/mock-bin"
cat > "$TMP/mock-bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%q ' "$@" >> "$MOCK_CURL_LOG"
printf '\n' >> "$MOCK_CURL_LOG"
url="${!#}"
if [[ "$url" == https://api.ipify.org ]]; then
  printf '203.0.113.10'
  exit 0
fi
if [[ "$url" == https://license.test/lease ]]; then
  output=""
  previous=""
  for argument in "$@"; do
    if [[ "$previous" == -o ]]; then output="$argument"; fi
    previous="$argument"
  done
  [[ -n "$output" ]]
  cp "$MOCK_LEASE_RESPONSE" "$output"
  printf '200'
  exit 0
fi
echo "unexpected curl URL: $url" >&2
exit 70
MOCK
chmod 700 "$TMP/mock-bin/curl"
: > "$TMP/curl.log"

renew_env=(
  PATH="$TMP/mock-bin:$PATH"
  MOCK_CURL_LOG="$TMP/curl.log"
  MOCK_LEASE_RESPONSE="$TMP/lease-response.json"
  HEXTUNNEL_LICENSE_STATE_DIR="$TMP"
  HEXTUNNEL_LICENSE_PUBLIC_KEY_FILE="$TMP/license-public.pem"
  HEXTUNNEL_LICENSE_PUBLIC_KEY_SHA256="$public_sha"
  HEXTUNNEL_LICENSE_LOCK_FILE="$TMP/license.lock"
  HEXTUNNEL_LEASE_ENDPOINT=https://license.test/lease
  HEXTUNNEL_LICENSE_PUBLIC_KEY_URL=https://keys.test/public.pem
)
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  env "${renew_env[@]}" bash "$license_runtime" renew --quiet
else
  command -v sudo >/dev/null 2>&1
  sudo -E env "${renew_env[@]}" bash "$license_runtime" renew --quiet
fi

grep -Fq "HEXTUNNEL_LEASE_EXPIRES_AT=$new_lease" "$TMP/license-state.env"
[[ "$(grep -c '^HEXTUNNEL_LEASE_EXPIRES_AT=' "$TMP/license-state.env")" == 1 ]]
grep -Fq "HEXTUNNEL_LICENSE_EXPIRES_AT='$expires_at'" "$TMP/license-state.env"
[[ "$(stat -c '%a' "$TMP/license-state.env")" == 600 ]]
grep -Fq 'https://license.test/lease' "$TMP/curl.log"
! grep -Fq 'https://keys.test/public.pem' "$TMP/curl.log"

runtime_installer="$ROOT/bin/hextunnel-install-license-runtime"
grep -Fq 'hextunnel-license-renew.timer' "$runtime_installer"
grep -Fq 'https://ghostdeveloper.duckdns.org/install.sh' "$runtime_installer"
grep -Fq 'HEXTUNNEL_BRANDED_MENU=1' "$runtime_installer"
grep -Fq 'hextunnel-arm64-menu' "$runtime_installer"
grep -Fq '/usr/local/bin/menu.new' "$runtime_installer"
grep -Fq 'bash -n "$tmp"' "$runtime_installer"
grep -Fq '@Gh0stDeveloper' "$runtime_installer"
grep -Fq '@Jotchua_DevzZ' "$runtime_installer"
grep -Fq 'HEXTUNNEL_OPERATION:-install' "$ROOT/bin/hextunnel-private-install"

upgrade="$ROOT/bin/hextunnel-private-upgrade"
grep -Fq 'transaction_begin licensed-framework-upgrade' "$upgrade"
grep -Fq 'backup_paths' "$upgrade"
grep -Fq '/usr/local/bin/menu' "$upgrade"
grep -Fq 'install_framework' "$upgrade"
grep -Fq 'hextunnel-install-license-runtime' "$upgrade"
grep -Fq 'module_validate "$module"' "$upgrade"
grep -Fq 'hextunnel-license status' "$upgrade"
grep -Fq 'systemctl is-active --quiet hextunnel-license-renew.timer' "$upgrade"
commit_line="$(grep -nF 'transaction_commit' "$upgrade" | cut -d: -f1)"
validation_line="$(grep -nF 'module_validate "$module"' "$upgrade" | cut -d: -f1)"
runtime_line="$(grep -nF 'hextunnel-install-license-runtime' "$upgrade" | tail -n1 | cut -d: -f1)"
[[ "$commit_line" -gt "$validation_line" && "$commit_line" -gt "$runtime_line" ]]
! grep -Eq 'install_selected_modules|legacy/install-all' "$upgrade"

[[ "$(tr -d '\r\n' < "$ROOT/VERSION")" == '1.0.0-rc.3' ]]
echo 'license runtime: ok'
