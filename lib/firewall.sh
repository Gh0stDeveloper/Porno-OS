#!/usr/bin/env bash

firewall_backend() {
  if command_exists ufw && ufw status 2>/dev/null | grep -qi '^Status: active'; then
    printf ufw
  elif command_exists nft; then
    printf nft
  elif command_exists iptables; then
    printf iptables
  else
    return 1
  fi
}

firewall_prepare_backend() {
  local backend
  if backend="$(firewall_backend 2>/dev/null)"; then
    log_debug "Backend de firewall disponible: $backend"
    return 0
  fi
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]]; then
    log_dry "apt-get update && apt-get install -y nftables"
    return 0
  fi
  command_exists apt-get || die "No existe un backend de firewall ni un gestor APT para instalar nftables."
  log_info "No se encontró UFW activo, nftables ni iptables; instalando nftables antes de la transacción."
  apt-get update
  apt-get install -y nftables
  command_exists nft || die "nftables no quedó disponible después de instalarlo."
}

firewall_rule_tag() {
  printf 'hextunnel:%s:%s' "$1" "$2"
}

firewall_snapshot() {
  [[ -n "${HEXTUNNEL_TRANSACTION_DIR:-}" && "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]] || return 0
  local backend
  backend="$(firewall_backend)" || die "No existe un backend de firewall preparado."
  printf '%s\n' "$backend" > "$HEXTUNNEL_TRANSACTION_DIR/firewall.backend"
  case "$backend" in
    ufw)
      backup_path /etc/ufw
      ;;
    nft)
      nft list ruleset > "$HEXTUNNEL_TRANSACTION_DIR/firewall.nft" 2>/dev/null || true
      ;;
    iptables)
      iptables-save > "$HEXTUNNEL_TRANSACTION_DIR/firewall.iptables" 2>/dev/null || true
      command_exists ip6tables-save \
        && ip6tables-save > "$HEXTUNNEL_TRANSACTION_DIR/firewall.ip6tables" 2>/dev/null \
        || true
      ;;
  esac
}

firewall_restore() {
  local dir="$1" backend
  [[ -f "$dir/firewall.backend" ]] || return 0
  backend="$(cat "$dir/firewall.backend")"
  case "$backend" in
    ufw)
      ufw reload >/dev/null 2>&1 || true
      ;;
    nft)
      if [[ -s "$dir/firewall.nft" ]]; then
        nft flush ruleset >/dev/null 2>&1 || true
        nft -f "$dir/firewall.nft" >/dev/null 2>&1 || true
      fi
      ;;
    iptables)
      [[ -s "$dir/firewall.iptables" ]] \
        && iptables-restore < "$dir/firewall.iptables" >/dev/null 2>&1 \
        || true
      [[ -s "$dir/firewall.ip6tables" ]] \
        && ip6tables-restore < "$dir/firewall.ip6tables" >/dev/null 2>&1 \
        || true
      ;;
  esac
}

firewall_open_port() {
  local protocol="$1" port="$2" source="${3:-0.0.0.0/0}" backend tag family quoted_tag
  backend="$(firewall_backend)" || die "No existe un backend de firewall preparado."
  tag="$(firewall_rule_tag "$protocol" "$port")"
  quoted_tag="\"$tag\""
  log_info "Firewall: permitir $protocol/$port desde $source mediante $backend"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0

  case "$backend" in
    ufw)
      if ufw status | grep -Fq "$tag"; then
        return 0
      fi
      if [[ "$source" == 0.0.0.0/0 || "$source" == ::/0 ]]; then
        ufw allow "$port/$protocol" comment "$tag"
      else
        ufw allow from "$source" to any port "$port" proto "$protocol" comment "$tag"
      fi
      ;;
    nft)
      nft list table inet hextunnel >/dev/null 2>&1 || nft add table inet hextunnel
      nft list chain inet hextunnel input >/dev/null 2>&1 \
        || nft 'add chain inet hextunnel input { type filter hook input priority -5; policy accept; }'
      if nft -a list chain inet hextunnel input 2>/dev/null | grep -Fq "$tag"; then
        return 0
      fi
      if [[ "$source" == 0.0.0.0/0 || "$source" == ::/0 ]]; then
        nft add rule inet hextunnel input "$protocol" dport "$port" accept comment "$quoted_tag"
      else
        family=ip
        [[ "$source" == *:* ]] && family=ip6
        nft add rule inet hextunnel input "$family" saddr "$source" "$protocol" dport "$port" accept comment "$quoted_tag"
      fi
      ;;
    iptables)
      if [[ "$source" == *:* ]]; then
        command_exists ip6tables || die "ip6tables es necesario para la fuente IPv6 $source"
        ip6tables -C INPUT -p "$protocol" -s "$source" --dport "$port" \
          -m comment --comment "$tag" -j ACCEPT 2>/dev/null \
          || ip6tables -I INPUT -p "$protocol" -s "$source" --dport "$port" \
            -m comment --comment "$tag" -j ACCEPT
      else
        iptables -C INPUT -p "$protocol" -s "$source" --dport "$port" \
          -m comment --comment "$tag" -j ACCEPT 2>/dev/null \
          || iptables -I INPUT -p "$protocol" -s "$source" --dport "$port" \
            -m comment --comment "$tag" -j ACCEPT
      fi
      ;;
  esac
}

firewall_ufw_rule_numbers() {
  local tag="$1" output
  output="$(ufw status numbered 2>/dev/null || true)"
  printf '%s\n' "$output" \
    | sed -n "/$(printf '%s' "$tag" | sed 's/[][\\.^$*+?{}|()]/\\&/g')/s/^\[ *\([0-9][0-9]*\)\].*/\1/p" \
    | sort -rn
}

firewall_nft_rule_handles() {
  local tag="$1" output
  output="$(nft -a list chain inet hextunnel input 2>/dev/null || true)"
  printf '%s\n' "$output" \
    | sed -n "/$(printf '%s' "$tag" | sed 's/[][\\.^$*+?{}|()]/\\&/g')/s/.* handle \([0-9][0-9]*\)$/\1/p"
}

firewall_close_port() {
  local protocol="$1" port="$2" backend tag number handle
  local numbers=() handles=()
  backend="$(firewall_backend)" || return 0
  tag="$(firewall_rule_tag "$protocol" "$port")"

  if [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]]; then
    log_dry "cerrar reglas etiquetadas $tag"
    return 0
  fi

  case "$backend" in
    ufw)
      mapfile -t numbers < <(firewall_ufw_rule_numbers "$tag")
      for number in "${numbers[@]}"; do
        [[ "$number" =~ ^[0-9]+$ ]] || continue
        yes | ufw delete "$number" >/dev/null 2>&1 || true
      done
      ;;
    nft)
      mapfile -t handles < <(firewall_nft_rule_handles "$tag")
      for handle in "${handles[@]}"; do
        [[ "$handle" =~ ^[0-9]+$ ]] || continue
        nft delete rule inet hextunnel input handle "$handle" >/dev/null 2>&1 || true
      done
      ;;
    iptables)
      while iptables -C INPUT -p "$protocol" --dport "$port" \
        -m comment --comment "$tag" -j ACCEPT 2>/dev/null; do
        iptables -D INPUT -p "$protocol" --dport "$port" \
          -m comment --comment "$tag" -j ACCEPT
      done
      if command_exists ip6tables; then
        while ip6tables -C INPUT -p "$protocol" --dport "$port" \
          -m comment --comment "$tag" -j ACCEPT 2>/dev/null; do
          ip6tables -D INPUT -p "$protocol" --dport "$port" \
            -m comment --comment "$tag" -j ACCEPT
        done
      fi
      ;;
  esac
  return 0
}

firewall_apply_module_ports() {
  local module="$1" protocol port source scope
  while read -r protocol port source scope; do
    [[ -n "$protocol" && -n "$port" ]] || continue
    firewall_open_port "$protocol" "$port" "${source:-0.0.0.0/0}"
  done < <(module_call "$module" ports || true)
}
