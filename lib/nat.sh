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
        "${HEXTUNNEL_HYSTERIA1_NAT_EXEMPT:-36713,36717}"
      ;;
    *) die "Perfil NAT desconocido: $profile" ;;
  esac
}

nat_exemption_ports() {
  local values="${1:-}" port
  [[ -n "$values" ]] || return 0
  IFS=',' read -r -a ports <<< "$values"
  for port in "${ports[@]}"; do
    [[ -n "$port" ]] && printf '%s\n' "$port"
  done
}

nat_validate_values() {
  local start="$1" end="$2" target="$3" exemptions="${4:-}" exempt
  [[ "$start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ && "$target" =~ ^[0-9]+$ ]] || die "El perfil NAT contiene puertos no numéricos."
  ((start >= 1 && start <= 65535 && end >= start && end <= 65535 && target >= 1 && target <= 65535)) \
    || die "El rango o destino NAT está fuera de límites."
  while read -r exempt; do
    [[ "$exempt" =~ ^[0-9]+$ ]] || die "El puerto exento NAT no es numérico: $exempt"
    ((exempt >= 1 && exempt <= 65535)) || die "El puerto exento NAT está fuera de límites: $exempt"
  done < <(nat_exemption_ports "$exemptions")
}

nat_rule_tag() {
  printf 'hextunnel-nat:%s' "$1"
}

nat_nft_chain() {
  nft -a list chain inet hextunnel_nat prerouting 2>/dev/null || true
}

nat_apply() {
  local profile="$1" start end target exemptions interface backend tag quoted_tag output exempt exempt_tag quoted_exempt
  read -r start end target exemptions < <(nat_profile_values "$profile")
  nat_validate_values "$start" "$end" "$target" "$exemptions"
  interface="$(nat_primary_interface)"
  [[ -n "$interface" ]] || die "No se pudo determinar la interfaz pública para NAT."
  backend="$(firewall_backend)" || die "No existe un backend de firewall preparado."
  tag="$(nat_rule_tag "$profile")"
  quoted_tag="\"$tag\""
  log_info "NAT $profile: UDP $start-$end -> $target mediante $backend"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  case "$backend" in
    nft)
      nft list table inet hextunnel_nat >/dev/null 2>&1 || nft add table inet hextunnel_nat
      nft list chain inet hextunnel_nat prerouting >/dev/null 2>&1 \
        || nft 'add chain inet hextunnel_nat prerouting { type nat hook prerouting priority dstnat; policy accept; }'
      output="$(nat_nft_chain)"
      while read -r exempt; do
        exempt_tag="${tag}:exempt:${exempt}"
        quoted_exempt="\"$exempt_tag\""
        if ! grep -Fq "comment \"$exempt_tag\"" <<< "$output"; then
          nft add rule inet hextunnel_nat prerouting iifname "$interface" udp dport "$exempt" return comment "$quoted_exempt"
          output="$(nat_nft_chain)"
        fi
      done < <(nat_exemption_ports "$exemptions")
      if ! grep -Fq "comment \"$tag\"" <<< "$output"; then
        nft add rule inet hextunnel_nat prerouting iifname "$interface" udp dport "$start-$end" dnat to ":$target" comment "$quoted_tag"
      fi
      ;;
    ufw|iptables)
      while read -r exempt; do
        exempt_tag="${tag}:exempt:${exempt}"
        if ! iptables -t nat -C PREROUTING -i "$interface" -p udp --dport "$exempt" -m comment --comment "$exempt_tag" -j RETURN 2>/dev/null; then
          iptables -t nat -I PREROUTING 1 -i "$interface" -p udp --dport "$exempt" -m comment --comment "$exempt_tag" -j RETURN
        fi
      done < <(nat_exemption_ports "$exemptions")
      if ! iptables -t nat -C PREROUTING -i "$interface" -p udp --dport "$start:$end" -m comment --comment "$tag" -j DNAT --to-destination ":$target" 2>/dev/null; then
        iptables -t nat -A PREROUTING -i "$interface" -p udp --dport "$start:$end" -m comment --comment "$tag" -j DNAT --to-destination ":$target"
      fi
      ;;
  esac
}

nat_remove() {
  local profile="$1" start end target exemptions interface backend tag handle exempt exempt_tag
  read -r start end target exemptions < <(nat_profile_values "$profile")
  nat_validate_values "$start" "$end" "$target" "$exemptions"
  interface="$(nat_primary_interface)"
  backend="$(firewall_backend)" || return 0
  tag="$(nat_rule_tag "$profile")"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && { log_dry "eliminar NAT $profile"; return 0; }
  case "$backend" in
    nft)
      while read -r handle; do
        [[ "$handle" =~ ^[0-9]+$ ]] || continue
        nft delete rule inet hextunnel_nat prerouting handle "$handle" >/dev/null 2>&1 || true
      done < <({ nat_nft_chain | grep -F "$tag" | sed -n 's/.* handle \([0-9][0-9]*\)$/\1/p'; } || true)
      ;;
    ufw|iptables)
      while iptables -t nat -C PREROUTING -i "$interface" -p udp --dport "$start:$end" -m comment --comment "$tag" -j DNAT --to-destination ":$target" 2>/dev/null; do
        iptables -t nat -D PREROUTING -i "$interface" -p udp --dport "$start:$end" -m comment --comment "$tag" -j DNAT --to-destination ":$target"
      done
      while read -r exempt; do
        exempt_tag="${tag}:exempt:${exempt}"
        while iptables -t nat -C PREROUTING -i "$interface" -p udp --dport "$exempt" -m comment --comment "$exempt_tag" -j RETURN 2>/dev/null; do
          iptables -t nat -D PREROUTING -i "$interface" -p udp --dport "$exempt" -m comment --comment "$exempt_tag" -j RETURN
        done
        while iptables -t nat -C PREROUTING -i "$interface" -p udp --dport "$exempt" -m comment --comment "${tag}:exempt" -j RETURN 2>/dev/null; do
          iptables -t nat -D PREROUTING -i "$interface" -p udp --dport "$exempt" -m comment --comment "${tag}:exempt" -j RETURN
        done
      done < <(nat_exemption_ports "$exemptions")
      ;;
  esac
}

nat_is_present() {
  local profile="$1" tag backend output
  tag="$(nat_rule_tag "$profile")"
  backend="$(firewall_backend 2>/dev/null)" || return 1
  case "$backend" in
    nft)
      output="$(nat_nft_chain)"
      grep -Fq "comment \"$tag\"" <<< "$output"
      ;;
    ufw|iptables)
      output="$(iptables-save -t nat 2>/dev/null || true)"
      grep -Eq -- "--comment (\"${tag}\"|${tag})([[:space:]]|$)" <<< "$output"
      ;;
  esac
}
