#!/usr/bin/env bash
[[ -n "${HEXTUNNEL_NETWORK_POLICY_LOADED:-}" ]] && return 0
HEXTUNNEL_NETWORK_POLICY_LOADED=1

network_json_temp_file() {
  local label="${1:-hextunnel-network-config}"
  mktemp --suffix=.json "/tmp/${label}.XXXXXX"
}

# Override the base helper from install-runtime with protocol-aware rewrites.
# The files are backed up by the active transaction before modification.
network_prepare_ipv4_only_configs() {
  local tmp
  local xray_config="${HEXTUNNEL_XRAY_CONFIG:-/etc/xray/config.json}"
  local xray_binary="${HEXTUNNEL_XRAY_BINARY:-/usr/local/bin/xray}"
  local hysteria1_config="${HEXTUNNEL_HYSTERIA1_CONFIG:-/etc/hysteria1/config.json}"
  local singbox_binary="${HEXTUNNEL_SINGBOX_BINARY:-/usr/local/bin/sing-box-hextunnel}"
  local hysteria2_config="${HEXTUNNEL_HYSTERIA2_CONFIG:-/etc/hysteria2/config.yaml}"
  local zivpn_config="${HEXTUNNEL_ZIVPN_CONFIG:-/etc/zivpn/config.json}"

  if [[ -s "$xray_config" ]]; then
    backup_path "$xray_config"
    tmp="$(network_json_temp_file hextunnel-xray-ipv4)"
    jq '
      (.inbounds[] |
        select(.tag == "vless-tls-dispatcher" or .tag == "vless-plain-public") |
        .listen) = "0.0.0.0"
    ' "$xray_config" > "$tmp"
    "$xray_binary" run -test -config "$tmp"
    install -m 600 "$tmp" "$xray_config"
    rm -f "$tmp"
  fi

  if [[ -s "$hysteria1_config" ]]; then
    backup_path "$hysteria1_config"
    tmp="$(network_json_temp_file hextunnel-hysteria-ipv4)"
    jq '(.inbounds[] | select(.tag == "hy1-inbound") | .listen)="0.0.0.0"' \
      "$hysteria1_config" > "$tmp"
    "$singbox_binary" check -c "$tmp"
    install -m 640 -o root -g hextunnel-hysteria "$tmp" "$hysteria1_config"
    rm -f "$tmp"
  fi

  if [[ -s "$hysteria2_config" ]]; then
    backup_path "$hysteria2_config"
    sed -i -E 's|^listen:.*|listen: 0.0.0.0:36713|' "$hysteria2_config"
  fi

  if [[ -s "$zivpn_config" ]]; then
    backup_path "$zivpn_config"
    tmp="$(network_json_temp_file hextunnel-zivpn-ipv4)"
    jq '.listen="0.0.0.0:5667"' "$zivpn_config" > "$tmp"
    jq empty "$tmp"
    install -m 600 "$tmp" "$zivpn_config"
    rm -f "$tmp"
  fi
}
