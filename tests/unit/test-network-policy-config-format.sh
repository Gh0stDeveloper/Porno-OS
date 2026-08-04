#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TMP="$(mktemp -d /tmp/hextunnel-network-policy-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

backup_path() { :; }

mkdir -p "$TMP/bin"
cat > "$TMP/bin/xray" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
config="${*: -1}"
[[ "$config" == *.json ]] || {
  printf 'Xray test received a config without .json suffix: %s\n' "$config" >&2
  exit 23
}
jq empty "$config"
printf '%s\n' "$config" > "$MOCK_XRAY_CONFIG_LOG"
EOF
chmod 700 "$TMP/bin/xray"

cat > "$TMP/xray.json" <<'EOF'
{
  "inbounds": [
    {"tag": "vless-tls-dispatcher", "listen": "::"},
    {"tag": "vless-plain-public", "listen": "::"},
    {"tag": "internal-only", "listen": "127.0.0.1"}
  ]
}
EOF

export MOCK_XRAY_CONFIG_LOG="$TMP/xray-tested-path"
export HEXTUNNEL_XRAY_CONFIG="$TMP/xray.json"
export HEXTUNNEL_XRAY_BINARY="$TMP/bin/xray"
export HEXTUNNEL_HYSTERIA1_CONFIG="$TMP/missing-hysteria1.json"
export HEXTUNNEL_HYSTERIA2_CONFIG="$TMP/missing-hysteria2.yaml"
export HEXTUNNEL_ZIVPN_CONFIG="$TMP/missing-zivpn.json"

# shellcheck disable=SC1091
source "$ROOT/lib/network-policy.sh"

sample="$(network_json_temp_file hextunnel-format-probe)"
[[ "$sample" == *.json ]]
rm -f "$sample"

network_prepare_ipv4_only_configs

tested_path="$(cat "$MOCK_XRAY_CONFIG_LOG")"
[[ "$tested_path" == *.json ]]
[[ ! -e "$tested_path" ]]

jq -e '
  (.inbounds[] | select(.tag == "vless-tls-dispatcher") | .listen) == "0.0.0.0" and
  (.inbounds[] | select(.tag == "vless-plain-public") | .listen) == "0.0.0.0" and
  (.inbounds[] | select(.tag == "internal-only") | .listen) == "127.0.0.1"
' "$HEXTUNNEL_XRAY_CONFIG" >/dev/null

printf 'network policy config format validation: ok\n'
