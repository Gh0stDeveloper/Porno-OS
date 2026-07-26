#!/usr/bin/env bash

HEXTUNNEL_ACCOUNTS_DB="${HEXTUNNEL_ACCOUNTS_DB:-/etc/hextunnel/accounts.tsv}"
HEXTUNNEL_ACCOUNTS_AUDIT="${HEXTUNNEL_ACCOUNTS_AUDIT:-/var/log/hextunnel/accounts-audit.log}"

accounts_init() {
  ensure_dir 700 /etc/hextunnel
  ensure_dir 750 /var/log/hextunnel
  if [[ ! -f "$HEXTUNNEL_ACCOUNTS_DB" && "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]]; then
    printf '#protocol\tusername\texpires\tstatus\tmax_sessions\tquota_mb\tspeed_kbps\n' > "$HEXTUNNEL_ACCOUNTS_DB"
    chmod 600 "$HEXTUNNEL_ACCOUNTS_DB"
  fi
  if [[ ! -f "$HEXTUNNEL_ACCOUNTS_AUDIT" && "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]]; then
    touch "$HEXTUNNEL_ACCOUNTS_AUDIT"
    chmod 600 "$HEXTUNNEL_ACCOUNTS_AUDIT"
  fi
}

account_validate_username() {
  [[ "$1" =~ ^[A-Za-z][A-Za-z0-9_.-]{2,31}$ ]] || die "Usuario inválido; usa de 3 a 32 caracteres seguros."
}

account_validate_date() {
  date -d "$1" +%Y-%m-%d >/dev/null 2>&1 || die "Fecha inválida: $1"
}

account_audit() {
  local action="$1" protocol="$2" username="$3"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  printf '%s\taction=%s\tprotocol=%s\tuser=%s\tactor=%s\n' \
    "$(date -Is)" "$action" "$protocol" "$username" "${SUDO_USER:-root}" >> "$HEXTUNNEL_ACCOUNTS_AUDIT"
}

account_db_upsert() {
  local protocol="$1" username="$2" expires="$3" status="$4" max_sessions="$5" quota_mb="$6" speed_kbps="$7"
  accounts_init
  backup_path "$HEXTUNNEL_ACCOUNTS_DB"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  local tmp
  tmp="$(mktemp /tmp/hextunnel-accounts.XXXXXX)"
  awk -F '\t' -v p="$protocol" -v u="$username" 'BEGIN{OFS="\t"} /^#/ || !($1==p && $2==u) {print}' "$HEXTUNNEL_ACCOUNTS_DB" > "$tmp"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$protocol" "$username" "$expires" "$status" "$max_sessions" "$quota_mb" "$speed_kbps" >> "$tmp"
  install -m 600 "$tmp" "$HEXTUNNEL_ACCOUNTS_DB"
  rm -f "$tmp"
}

account_db_delete() {
  local protocol="$1" username="$2" tmp
  accounts_init
  backup_path "$HEXTUNNEL_ACCOUNTS_DB"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  tmp="$(mktemp /tmp/hextunnel-accounts.XXXXXX)"
  awk -F '\t' -v p="$protocol" -v u="$username" 'BEGIN{OFS="\t"} /^#/ || !($1==p && $2==u) {print}' "$HEXTUNNEL_ACCOUNTS_DB" > "$tmp"
  install -m 600 "$tmp" "$HEXTUNNEL_ACCOUNTS_DB"
  rm -f "$tmp"
}

account_lock() {
  ensure_dir 755 /run/lock
  exec 8>/run/lock/hextunnel-accounts.lock
  flock -w 30 8 || die "No se pudo obtener el bloqueo de cuentas."
}

xray_protocol_tags() {
  case "$1" in
    vless) printf '%s' '["vless-tls-dispatcher","vless-tcp-http","vless-plain-public","vless-ws","vless-xhttp","vless-httpupgrade","vless-grpc"]' ;;
    vmess) printf '%s' '["vmess-tcp-http","vmess-ws","vmess-xhttp","vmess-httpupgrade","vmess-grpc"]' ;;
    trojan) printf '%s' '["trojan-ws"]' ;;
    *) return 1 ;;
  esac
}

account_xray_add() {
  local protocol="$1" username="$2" secret="$3" expires="$4" config=/etc/xray/config.json tags tmp
  [[ -s "$config" && -x /usr/local/bin/xray ]] || die "Xray no está instalado."
  tags="$(xray_protocol_tags "$protocol")" || die "Protocolo Xray inválido."
  backup_paths "$config" "/etc/xray/${protocol}.txt"
  tmp="$(mktemp /tmp/hextunnel-xray-account.XXXXXX)"
  if [[ "$protocol" == trojan ]]; then
    jq --arg secret "$secret" --arg user "$username" --argjson tags "$tags" \
      '(.inbounds[] | select(.tag as $tag | $tags | index($tag)) | .settings.clients) += [{"password":$secret,"email":$user}]' "$config" > "$tmp"
  elif [[ "$protocol" == vmess ]]; then
    jq --arg secret "$secret" --arg user "$username" --argjson tags "$tags" \
      '(.inbounds[] | select(.tag as $tag | $tags | index($tag)) | .settings.clients) += [{"id":$secret,"alterId":0,"email":$user}]' "$config" > "$tmp"
  else
    jq --arg secret "$secret" --arg user "$username" --argjson tags "$tags" \
      '(.inbounds[] | select(.tag as $tag | $tags | index($tag)) | .settings.clients) += [{"id":$secret,"email":$user}]' "$config" > "$tmp"
  fi
  /usr/local/bin/xray run -test -config "$tmp"
  install -m 600 "$tmp" "$config"
  printf '%s %s %s\n' "$username" "$secret" "$expires" >> "/etc/xray/${protocol}.txt"
  chmod 600 "/etc/xray/${protocol}.txt"
  safe_restart_service xray "/usr/local/bin/xray run -test -config /etc/xray/config.json"
  rm -f "$tmp"
}

account_xray_remove_runtime() {
  local protocol="$1" username="$2" config=/etc/xray/config.json tmp
  [[ -s "$config" ]] || return 0
  backup_paths "$config" "/etc/xray/${protocol}.txt"
  tmp="$(mktemp /tmp/hextunnel-xray-account.XXXXXX)"
  jq --arg user "$username" '
    (.inbounds[] | select(((.settings.clients? // null) | type) == "array") | .settings.clients) |= map(select(.email != $user)) |
    (.inbounds[] | select(((.settings.users? // null) | type) == "array") | .settings.users) |= map(select(.email != $user))
  ' "$config" > "$tmp"
  /usr/local/bin/xray run -test -config "$tmp"
  install -m 600 "$tmp" "$config"
  [[ -f "/etc/xray/${protocol}.txt" ]] && sed -i -E "/^${username//./\.} /d" "/etc/xray/${protocol}.txt"
  safe_restart_service xray "/usr/local/bin/xray run -test -config /etc/xray/config.json"
  rm -f "$tmp"
}

account_hysteria2_add() {
  local username="$1" token="$2" expires="$3"
  [[ -s /etc/hysteria2/users.txt ]] || die "Hysteria 2 no está instalado."
  backup_path /etc/hysteria2/users.txt
  printf '%s %s %s\n' "$username" "$token" "$expires" >> /etc/hysteria2/users.txt
  chmod 600 /etc/hysteria2/users.txt
}

account_hysteria2_remove_runtime() {
  local username="$1" tmp
  [[ -f /etc/hysteria2/users.txt ]] || return 0
  backup_path /etc/hysteria2/users.txt
  tmp="$(mktemp /tmp/hextunnel-hysteria2-account.XXXXXX)"
  awk -v user="$username" '$1 != user' /etc/hysteria2/users.txt > "$tmp"
  install -m 600 "$tmp" /etc/hysteria2/users.txt
  rm -f "$tmp"
}

account_zivpn_rebuild_config() {
  local tmp
  tmp="$(mktemp /tmp/hextunnel-zivpn-account.XXXXXX)"
  jq --argjson passwords "$(awk '{print $2}' /etc/zivpn/users.txt | jq -R . | jq -s .)" '.auth.config=$passwords' /etc/zivpn/config.json > "$tmp"
  jq empty "$tmp"
  install -m 600 "$tmp" /etc/zivpn/config.json
  rm -f "$tmp"
  safe_restart_service zivpn "jq empty /etc/zivpn/config.json"
}

account_zivpn_add() {
  local username="$1" password="$2" expires="$3"
  [[ -s /etc/zivpn/config.json ]] || die "ZiVPN no está instalado."
  backup_paths /etc/zivpn/users.txt /etc/zivpn/config.json
  printf '%s %s %s\n' "$username" "$password" "$expires" >> /etc/zivpn/users.txt
  chmod 600 /etc/zivpn/users.txt
  account_zivpn_rebuild_config
}

account_zivpn_remove_runtime() {
  local username="$1" tmp
  [[ -f /etc/zivpn/users.txt ]] || return 0
  backup_paths /etc/zivpn/users.txt /etc/zivpn/config.json
  tmp="$(mktemp /tmp/hextunnel-zivpn-account.XXXXXX)"
  awk -v user="$username" '$1 != user' /etc/zivpn/users.txt > "$tmp"
  install -m 600 "$tmp" /etc/zivpn/users.txt
  rm -f "$tmp"
  account_zivpn_rebuild_config
}

account_ssh_add() {
  local username="$1" password="$2" expires="$3" max_sessions="$4"
  id "$username" >/dev/null 2>&1 && die "El usuario SSH ya existe."
  run_cmd useradd --create-home --shell /bin/false --expiredate "$expires" "$username"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || printf '%s:%s\n' "$username" "$password" | chpasswd
  ensure_dir 700 /etc/hextunnel
  backup_path /etc/hextunnel/ssh-limits.tsv
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || printf '%s\t%s\n' "$username" "$max_sessions" >> /etc/hextunnel/ssh-limits.tsv
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || chmod 600 /etc/hextunnel/ssh-limits.tsv
}

account_create() {
  local protocol="$1" username="$2" expires="$3" max_sessions="${4:-1}" quota_mb="${5:-0}" speed_kbps="${6:-0}" secret
  require_root; accounts_init; account_validate_username "$username"; account_validate_date "$expires"; account_lock
  grep -Fq $'\n'"$protocol"$'\t'"$username"$'\t' "$HEXTUNNEL_ACCOUNTS_DB" 2>/dev/null && die "La cuenta ya existe."
  case "$protocol" in
    vless|vmess) secret="$(cat /proc/sys/kernel/random/uuid)"; account_xray_add "$protocol" "$username" "$secret" "$expires" ;;
    trojan) secret="$(random_secret 32)"; account_xray_add trojan "$username" "$secret" "$expires" ;;
    hysteria2) secret="$(random_secret 32)"; account_hysteria2_add "$username" "$secret" "$expires" ;;
    zivpn) secret="$(random_secret 32)"; account_zivpn_add "$username" "$secret" "$expires" ;;
    ssh) secret="$(random_secret 20)"; account_ssh_add "$username" "$secret" "$expires" "$max_sessions" ;;
    *) die "Protocolo de cuenta no soportado: $protocol" ;;
  esac
  account_db_upsert "$protocol" "$username" "$expires" active "$max_sessions" "$quota_mb" "$speed_kbps"
  account_audit create "$protocol" "$username"
  printf 'Usuario: %s\nProtocolo: %s\nExpira: %s\nCredencial: %s\n' "$username" "$protocol" "$expires" "$secret"
}

account_suspend() {
  local protocol="$1" username="$2"
  require_root; accounts_init; account_lock
  case "$protocol" in vless|vmess|trojan) account_xray_remove_runtime "$protocol" "$username" ;; hysteria2) account_hysteria2_remove_runtime "$username" ;; zivpn) account_zivpn_remove_runtime "$username" ;; ssh) run_cmd usermod -L "$username" ;; *) die "Protocolo no soportado." ;; esac
  local row
  row="$(awk -F '\t' -v p="$protocol" -v u="$username" '$1==p && $2==u {print; exit}' "$HEXTUNNEL_ACCOUNTS_DB")"
  [[ -n "$row" ]] || die "Cuenta no registrada."
  IFS=$'\t' read -r _ _ expires _ max_sessions quota speed <<< "$row"
  account_db_upsert "$protocol" "$username" "$expires" suspended "$max_sessions" "$quota" "$speed"
  account_audit suspend "$protocol" "$username"
}

account_delete() {
  local protocol="$1" username="$2"
  account_suspend "$protocol" "$username" || true
  [[ "$protocol" == ssh ]] && run_cmd userdel -r "$username" || true
  account_db_delete "$protocol" "$username"
  account_audit delete "$protocol" "$username"
}

account_renew() {
  local protocol="$1" username="$2" expires="$3" row
  require_root; accounts_init; account_validate_date "$expires"
  row="$(awk -F '\t' -v p="$protocol" -v u="$username" '$1==p && $2==u {print; exit}' "$HEXTUNNEL_ACCOUNTS_DB")"
  [[ -n "$row" ]] || die "Cuenta no registrada."
  IFS=$'\t' read -r _ _ _ status max_sessions quota speed <<< "$row"
  account_db_upsert "$protocol" "$username" "$expires" "$status" "$max_sessions" "$quota" "$speed"
  case "$protocol" in
    ssh) run_cmd chage -E "$expires" "$username" ;;
    vless|vmess|trojan) [[ -f "/etc/xray/${protocol}.txt" ]] && sed -i -E "s#^(${username//./\.} [^ ]+) [^ ]+#\\1 $expires#" "/etc/xray/${protocol}.txt" ;;
    hysteria2) sed -i -E "s#^(${username//./\.} [^ ]+) [^ ]+#\\1 $expires#" /etc/hysteria2/users.txt ;;
    zivpn) sed -i -E "s#^(${username//./\.} [^ ]+) [^ ]+#\\1 $expires#" /etc/zivpn/users.txt ;;
  esac
  account_audit renew "$protocol" "$username"
}

account_list() {
  accounts_init
  column -t -s $'\t' "$HEXTUNNEL_ACCOUNTS_DB" 2>/dev/null || cat "$HEXTUNNEL_ACCOUNTS_DB"
}
