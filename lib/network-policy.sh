#!/usr/bin/env bash
[[ -n "${HEXTUNNEL_NETWORK_POLICY_LOADED:-}" ]] && return 0
HEXTUNNEL_NETWORK_POLICY_LOADED=1

# Override the base helper from install-runtime with protocol-aware rewrites.
# The files are backed up by the active transaction before modification.
network_prepare_ipv4_only_configs() {
  local tmp

  if [[ -s /etc/xray/config.json ]]; then
    backup_path /etc/xray/config.json
    tmp="$(mktemp /tmp/hextunnel-xray-ipv4.XXXXXX)"
    jq '
      (.inbounds[] |
        select(.tag == "vless-tls-dispatcher" or .tag == "vless-plain-public") |
        .listen) = "0.0.0.0"
    ' /etc/xray/config.json > "$tmp"
    /usr/local/bin/xray run -test -config "$tmp"
    install -m 600 "$tmp" /etc/xray/config.json
    rm -f "$tmp"
  fi

  if [[ -s /etc/hysteria1/config.json ]]; then
    backup_path /etc/hysteria1/config.json
    tmp="$(mktemp /tmp/hextunnel-hysteria-ipv4.XXXXXX)"
    jq '(.inbounds[] | select(.tag == "hy1-inbound") | .listen)="0.0.0.0"' \
      /etc/hysteria1/config.json > "$tmp"
    /usr/local/bin/sing-box-hextunnel check -c "$tmp"
    install -m 640 -o root -g hextunnel-hysteria "$tmp" /etc/hysteria1/config.json
    rm -f "$tmp"
  fi

  if [[ -s /etc/hysteria2/config.yaml ]]; then
    backup_path /etc/hysteria2/config.yaml
    sed -i -E 's|^listen:.*|listen: 0.0.0.0:36713|' /etc/hysteria2/config.yaml
  fi

  if [[ -s /etc/zivpn/config.json ]]; then
    backup_path /etc/zivpn/config.json
    tmp="$(mktemp /tmp/hextunnel-zivpn-ipv4.XXXXXX)"
    jq '.listen="0.0.0.0:5667"' /etc/zivpn/config.json > "$tmp"
    jq empty "$tmp"
    install -m 600 "$tmp" /etc/zivpn/config.json
    rm -f "$tmp"
  fi
}
