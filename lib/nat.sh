#!/usr/bin/env bash

nat_primary_interface() {
  ip -4 route show default 2>/dev/null | awk 'NR==1 {print $5}'
}

nat_profile_values() {
  local profile="$1"
  case "$profile" in
    zivpn) printf '%s\n' '6000 19999 5667 ' ;;
    hysteria1) printf '%s\n' '20000 50000 36712 36713' ;;
    *) die "Perfil NAT desconocido: $profile" ;;
  esac
}

nat_rule_tag() {
  printf 'hextunnel-nat:%s' "$1"
}

nat_apply() {
  local profile="$1" start end target exempt interface backend tag
  read -r start end target exempt < <(nat_profile_values "$profile")
  interface="$(nat_primary_interface)"
  [[ -n "$interface" ]] || die "No se pudo determinar la interfaz pública para NAT."
  backend="$(firewall_backend)"
  tag="$(nat_rule_tag "$profile")"
  log_info "NAT $profile: UDP $start-$end -> $target mediante $backend"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  case "$backend" in
    nft)
      nft list table inet hextunnel_nat >/dev/null 2>&1 || nft add table inet hextunnel_nat
      nft list chain inet hextunnel_nat prerouting >/dev/null 2>&1 \
        || nft 'add chain inet hextunnel_nat prerouting { type nat hook prerouting priority dstnat; policy accept; }'
      if [[ -n "$exempt" ]] && ! nft -a list chain inet hextunnel_nat prerouting | grep -Fq "comment \"${tag}:exempt\""; then
        nft add rule inet hextunnel_nat prerouting iifname "$interface" udp dport "$exempt" return comment "${tag}:exempt"
      fi
      nft -a list chain inet hextunnel_nat prerouting | grep -Fq "comment \"$tag\"" \
        || nft add rule inet hextunnel_nat prerouting iifname "$interface" udp dport "$start-$end" dnat to ":$target" comment "$tag"
      ;;
    ufw|iptables)
      if [[ -n "$exempt" ]]; then
        iptables -t nat -C PREROUTING -i "$interface" -p udp --dport "$exempt" -m comment --comment "${tag}:exempt" -j RETURN 2>/dev/null \
          || iptables -t nat -I PREROUTING 1 -i "$interface" -p udp --dport "$exempt" -m comment --comment "${tag}:exempt" -j RETURN
      fi
      iptables -t nat -C PREROUTING -i "$interface" -p udp --dport "$start:$end" -m comment --comment "$tag" -j DNAT --to-destination ":$target" 2>/dev/null \
        || iptables -t nat -A PREROUTING -i "$interface" -p udp --dport "$start:$end" -m comment --comment "$tag" -j DNAT --to-destination ":$target"
      ;;
  esac
}

nat_remove() {
  local profile="$1" start end target exempt interface backend tag handle
  read -r start end target exempt < <(nat_profile_values "$profile")
  interface="$(nat_primary_interface)"
  backend="$(firewall_backend)"
  tag="$(nat_rule_tag "$profile")"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && { log_dry "eliminar NAT $profile"; return 0; }
  case "$backend" in
    nft)
      while read -r handle; do
        [[ "$handle" =~ ^[0-9]+$ ]] || continue
        nft delete rule inet hextunnel_nat prerouting handle "$handle" >/dev/null 2>&1 || true
      done < <(nft -a list chain inet hextunnel_nat prerouting 2>/dev/null | grep -F "comment \"$tag" | sed -n 's/.* handle \([0-9][0-9]*\)$/\1/p')
      ;;
    ufw|iptables)
      while iptables -t nat -C PREROUTING -i "$interface" -p udp --dport "$start:$end" -m comment --comment "$tag" -j DNAT --to-destination ":$target" 2>/dev/null; do
        iptables -t nat -D PREROUTING -i "$interface" -p udp --dport "$start:$end" -m comment --comment "$tag" -j DNAT --to-destination ":$target"
      done
      if [[ -n "$exempt" ]]; then
        while iptables -t nat -C PREROUTING -i "$interface" -p udp --dport "$exempt" -m comment --comment "${tag}:exempt" -j RETURN 2>/dev/null; do
          iptables -t nat -D PREROUTING -i "$interface" -p udp --dport "$exempt" -m comment --comment "${tag}:exempt" -j RETURN
        done
      fi
      ;;
  esac
}

nat_is_present() {
  local profile="$1" tag backend
  tag="$(nat_rule_tag "$profile")"
  backend="$(firewall_backend)"
  case "$backend" in
    nft) nft -a list chain inet hextunnel_nat prerouting 2>/dev/null | grep -Fq "comment \"$tag\"" ;;
    ufw|iptables) iptables-save -t nat 2>/dev/null | grep -Fq -- "--comment $tag" ;;
  esac
}
