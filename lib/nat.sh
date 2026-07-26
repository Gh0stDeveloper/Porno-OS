#!/usr/bin/env bash

nat_primary_interface() {
  ip -4 route show default 2>/dev/null | awk 'NR==1 {print $5}'
}

nat_profile_values() {
  local profile="$1"
  case "$profile" in
    zivpn)
      printf '%s %s %s %s\n' \
        "${HEXTUNNEL_ZIVPN_NAT_START:-6000}" \
        "${HEXTUNNEL_ZIVPN_NAT_END:-19999}" \
        "${HEXTUNNEL_ZIVPN_PORT:-5667}" \
        "${HEXTUNNEL_ZIVPN_NAT_EXEMPT:-}"
      ;;
    hysteria1)
      printf '%s %s %s %s\n' \
        "${HEXTUNNEL_HYSTERIA1_NAT_START:-20000}" \
        "${HEXTUNNEL_HYSTERIA1_NAT_END:-50000}" \
        "${HEXTUNNEL_HYSTERIA1_PORT:-36712}" \
        "${HEXTUNNEL_HYSTERIA1_NAT_EXEMPT:-36713}"
      ;;
    *) die "Perfil NAT desconocido: $profile" ;;
  esac
}

nat_validate_values() {
  local start="$1" end="$2" target="$3" exempt="${4:-}"
  [[ "$start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ && "$target" =~ ^[0-9]+$ ]] || die "El perfil NAT contiene puertos no numéricos."
  ((start >= 1 && start <= 65535 && end >= start && end <= 65535 && target >= 1 && target <= 65535)) \
    || die "El rango o destino NAT está fuera de límites."
  [[ -z "$exempt" || "$exempt" =~ ^[0-9]+$ ]] || die "El puerto exento NAT no es numérico."
  [[ -z "$exempt" || ( "$exempt" -ge 1 && "$exempt" -le 65535 ) ]] || die "El puerto exento NAT está fuera de límites."
}

nat_rule_tag() {
  printf 'hextunnel-nat:%s' "$1"
}

nat_apply() {
  local profile="$1" start end target exempt interface backend tag
  read -r start end target exempt < <(nat_profile_values "$profile")
  nat_validate_values "$start" "$end" "$target" "$exempt"
  interface="$(nat_primary_interface)"
  [[ -n "$interface" ]] || die "No se pudo determinar la interfaz pública para NAT."
  backend="$(firewall_backend)" || die "No existe un backend de firewall preparado."
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
      if ! nft -a list chain inet hextunnel_nat prerouting | grep -Fq "comment \"$tag\""; then
        nft add rule inet hextunnel_nat prerouting iifname "$interface" udp dport "$start-$end" dnat to ":$target" comment "$tag"
      fi
      ;;
    ufw|iptables)
      if [[ -n "$exempt" ]] && ! iptables -t nat -C PREROUTING -i "$interface" -p udp --dport "$exempt" -m comment --comment "${tag}:exempt" -j RETURN 2>/dev/null; then
        iptables -t nat -I PREROUTING 1 -i "$interface" -p udp --dport "$exempt" -m comment --comment "${tag}:exempt" -j RETURN
      fi
      if ! iptables -t nat -C PREROUTING -i "$interface" -p udp --dport "$start:$end" -m comment --comment "$tag" -j DNAT --to-destination ":$target" 2>/dev/null; then
        iptables -t nat -A PREROUTING -i "$interface" -p udp --dport "$start:$end" -m comment --comment "$tag" -j DNAT --to-destination ":$target"
      fi
      ;;
  esac
}

nat_remove() {
  local profile="$1" start end target exempt interface backend tag handle
  read -r start end target exempt < <(nat_profile_values "$profile")
  nat_validate_values "$start" "$end" "$target" "$exempt"
  interface="$(nat_primary_interface)"
  backend="$(firewall_backend)" || return 0
  tag="$(nat_rule_tag "$profile")"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && { log_dry "eliminar NAT $profile"; return 0; }
  case "$backend" in
    nft)
      while read -r handle; do
        [[ "$handle" =~ ^[0-9]+$ ]] || continue
        nft delete rule inet hextunnel_nat prerouting handle "$handle" >/dev/null 2>&1 || true
      done < <({ nft -a list chain inet hextunnel_nat prerouting 2>/dev/null | grep -F "comment \"$tag" | sed -n 's/.* handle \([0-9][0-9]*\)$/\1/p'; } || true)
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
  local profile="$1" tag backend output
  tag="$(nat_rule_tag "$profile")"
  backend="$(firewall_backend 2>/dev/null)" || return 1
  case "$backend" in
    nft)
      output="$(nft -a list chain inet hextunnel_nat prerouting 2>/dev/null || true)"
      if grep -Fq "comment \"$tag\"" <<< "$output"; then return 0; fi
      ;;
    ufw|iptables)
      output="$(iptables-save -t nat 2>/dev/null || true)"
      if grep -Fq -- "--comment $tag" <<< "$output"; then return 0; fi
      ;;
  esac
  return 1
}
