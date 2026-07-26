#!/usr/bin/env bash

HEXTUNNEL_ACCOUNTS_DB="${HEXTUNNEL_ACCOUNTS_DB:-/etc/hextunnel/accounts.tsv}"
HEXTUNNEL_ACCOUNTS_AUDIT="${HEXTUNNEL_ACCOUNTS_AUDIT:-/var/log/hextunnel/accounts-audit.log}"
HEXTUNNEL_CREDENTIALS_DIR="${HEXTUNNEL_CREDENTIALS_DIR:-/etc/hextunnel/credentials}"

accounts_init() {
  ensure_dir 700 /etc/hextunnel
  ensure_dir 700 "$HEXTUNNEL_CREDENTIALS_DIR"
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

account_validate_protocol() {
  case "$1" in ssh|vless|vmess|trojan|hysteria|hysteria2|zivpn) ;; *) die "Protocolo de cuenta no soportado: $1" ;; esac
}

account_validate_date() {
  local normalized
  normalized="$(date -d "$1" +%Y-%m-%d 2>/dev/null)" || die "Fecha inválida: $1"
  [[ "$normalized" == "$1" ]] || die "Usa el formato YYYY-MM-DD."
}

account_validate_limits() {
  local max_sessions="$1" quota_mb="$2" speed_kbps="$3"
  [[ "$max_sessions" =~ ^[1-9][0-9]*$ ]] || die "max_sessions debe ser mayor que cero."
  [[ "$quota_mb" =~ ^[0-9]+$ && "$speed_kbps" =~ ^[0-9]+$ ]] || die "Cuota y velocidad deben ser números enteros."
  if ((quota_mb > 0 || speed_kbps > 0)); then
    die "Cuotas y velocidad todavía no tienen un contador fiable; usa 0 para no prometer límites que no se aplicarían."
  fi
}

account_audit() {
  local action="$1" protocol="$2" username="$3"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  printf '%s\taction=%s\tprotocol=%s\tuser=%s\tactor=%s\n' \
    "$(date -Is)" "$action" "$protocol" "$username" "${SUDO_USER:-root}" >> "$HEXTUNNEL_ACCOUNTS_AUDIT"
}

account_get_row() {
  local protocol="$1" username="$2"
  awk -F '\t' -v p="$protocol" -v u="$username" '$1==p && $2==u {print; exit}' "$HEXTUNNEL_ACCOUNTS_DB" 2>/dev/null
}

account_exists() {
  [[ -n "$(account_get_row "$1" "$2")" ]]
}

account_db_upsert() {
  local protocol="$1" username="$2" expires="$3" status="$4" max_sessions="$5" quota_mb="$6" speed_kbps="$7" tmp
  accounts_init
  backup_path "$HEXTUNNEL_ACCOUNTS_DB"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
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

account_credential_file() {
  local protocol="$1" username="$2"
  printf '%s/%s/%s.env' "$HEXTUNNEL_CREDENTIALS_DIR" "$protocol" "$username"
}

account_store_credential() {
  local protocol="$1" username="$2" secret="$3" expires="$4" path directory
  path="$(account_credential_file "$protocol" "$username")"
  directory="$(dirname "$path")"
  ensure_dir 700 "$directory"
  backup_path "$path"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  {
    printf 'ACCOUNT_PROTOCOL=%q\n' "$protocol"
    printf 'ACCOUNT_USERNAME=%q\n' "$username"
    printf 'ACCOUNT_SECRET=%q\n' "$secret"
    printf 'ACCOUNT_EXPIRES=%q\n' "$expires"
  } > "$path"
  chmod 600 "$path"
}

account_load_credential() {
  local protocol="$1" username="$2" path
  path="$(account_credential_file "$protocol" "$username")"
  [[ -f "$path" ]] || die "No existe la credencial privada de $protocol/$username."
  validate_private_env_file "$path"
  unset ACCOUNT_PROTOCOL ACCOUNT_USERNAME ACCOUNT_SECRET ACCOUNT_EXPIRES
  # shellcheck disable=SC1090
  source "$path"
  [[ "$ACCOUNT_PROTOCOL" == "$protocol" && "$ACCOUNT_USERNAME" == "$username" && -n "$ACCOUNT_SECRET" ]] || die "El archivo de credencial no coincide con la cuenta."
}

account_delete_credential() {
  local path
  path="$(account_credential_file "$1" "$2")"
  backup_path "$path"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || rm -f "$path"
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
    jq --arg secret "$secret" --arg user "$username" --argjson tags "$tags" '
      (.inbounds[] | select(.tag as $tag | $tags | index($tag)) | .settings.clients) |=
        ([.[] | select(.email != $user)] + [{"password":$secret,"email":$user}])
    ' "$config" > "$tmp"
  elif [[ "$protocol" == vmess ]]; then
    jq --arg secret "$secret" --arg user "$username" --argjson tags "$tags" '
      (.inbounds[] | select(.tag as $tag | $tags | index($tag)) | .settings.clients) |=
        ([.[] | select(.email != $user)] + [{"id":$secret,"alterId":0,"email":$user}])
    ' "$config" > "$tmp"
  else
    jq --arg secret "$secret" --arg user "$username" --argjson tags "$tags" '
      (.inbounds[] | select(.tag as $tag | $tags | index($tag)) | .settings.clients) |=
        ([.[] | select(.email != $user)] + [{"id":$secret,"email":$user}])
    ' "$config" > "$tmp"
  fi
  /usr/local/bin/xray run -test -config "$tmp"
  install -m 600 "$tmp" "$config"
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]]; then
    touch "/etc/xray/${protocol}.txt"
    sed -i -E "/^${username//./\\.} /d" "/etc/xray/${protocol}.txt"
    printf '%s %s %s\n' "$username" "$secret" "$expires" >> "/etc/xray/${protocol}.txt"
    chmod 600 "/etc/xray/${protocol}.txt"
  fi
  safe_restart_service xray "/usr/local/bin/xray run -test -config /etc/xray/config.json"
  rm -f "$tmp"
}

account_xray_remove_runtime() {
  local protocol="$1" username="$2" config=/etc/xray/config.json tags tmp
  [[ -s "$config" ]] || return 0
  tags="$(xray_protocol_tags "$protocol")" || die "Protocolo Xray inválido."
  backup_paths "$config" "/etc/xray/${protocol}.txt"
  tmp="$(mktemp /tmp/hextunnel-xray-account.XXXXXX)"
  jq --arg user "$username" --argjson tags "$tags" '
    (.inbounds[] | select(.tag as $tag | $tags | index($tag)) | .settings.clients) |= map(select(.email != $user))
  ' "$config" > "$tmp"
  /usr/local/bin/xray run -test -config "$tmp"
  install -m 600 "$tmp" "$config"
  [[ -f "/etc/xray/${protocol}.txt" && "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]] && sed -i -E "/^${username//./\\.} /d" "/etc/xray/${protocol}.txt"
  safe_restart_service xray "/usr/local/bin/xray run -test -config /etc/xray/config.json"
  rm -f "$tmp"
}

account_hysteria_add() {
  local username="$1" token="$2" expires="$3"
  [[ -s /etc/hysteria1/config.json ]] || die "Hysteria v1 no está instalado."
  backup_paths /etc/hysteria1/users.txt /etc/hysteria1/config.json
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || {
    touch /etc/hysteria1/users.txt
    sed -i -E "/^${username//./\\.} /d" /etc/hysteria1/users.txt
    printf '%s %s %s\n' "$username" "$token" "$expires" >> /etc/hysteria1/users.txt
    chmod 600 /etc/hysteria1/users.txt
    hysteria_rebuild_users
  }
  safe_restart_service hextunnel-hysteria "/usr/local/bin/sing-box-hextunnel check -c /etc/hysteria1/config.json"
}

account_hysteria_remove_runtime() {
  local username="$1" tmp
  [[ -f /etc/hysteria1/users.txt ]] || return 0
  backup_paths /etc/hysteria1/users.txt /etc/hysteria1/config.json
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  tmp="$(mktemp /tmp/hextunnel-hysteria-account.XXXXXX)"
  awk -v user="$username" '$1 != user' /etc/hysteria1/users.txt > "$tmp"
  install -m 600 "$tmp" /etc/hysteria1/users.txt
  rm -f "$tmp"
  hysteria_rebuild_users
  safe_restart_service hextunnel-hysteria "/usr/local/bin/sing-box-hextunnel check -c /etc/hysteria1/config.json"
}

account_hysteria2_add() {
  local username="$1" token="$2" expires="$3"
  [[ -s /etc/hysteria2/users.txt ]] || die "Hysteria 2 no está instalado."
  backup_path /etc/hysteria2/users.txt
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || {
    sed -i -E "/^${username//./\\.} /d" /etc/hysteria2/users.txt
    printf '%s %s %s\n' "$username" "$token" "$expires" >> /etc/hysteria2/users.txt
    chmod 600 /etc/hysteria2/users.txt
  }
}

account_hysteria2_remove_runtime() {
  local username="$1" tmp
  [[ -f /etc/hysteria2/users.txt ]] || return 0
  backup_path /etc/hysteria2/users.txt
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  tmp="$(mktemp /tmp/hextunnel-hysteria2-account.XXXXXX)"
  awk -v user="$username" '$1 != user' /etc/hysteria2/users.txt > "$tmp"
  install -m 600 "$tmp" /etc/hysteria2/users.txt
  rm -f "$tmp"
}

account_zivpn_rebuild_config() {
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  zivpn_rebuild_config_passwords
  safe_restart_service zivpn "jq empty /etc/zivpn/config.json"
}

account_zivpn_add() {
  local username="$1" password="$2" expires="$3"
  [[ -s /etc/zivpn/config.json ]] || die "ZiVPN no está instalado."
  backup_paths /etc/zivpn/users.txt /etc/zivpn/config.json
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || {
    sed -i -E "/^${username//./\\.} /d" /etc/zivpn/users.txt
    printf '%s %s %s\n' "$username" "$password" "$expires" >> /etc/zivpn/users.txt
    chmod 600 /etc/zivpn/users.txt
  }
  account_zivpn_rebuild_config
}

account_zivpn_remove_runtime() {
  local username="$1" tmp
  [[ -f /etc/zivpn/users.txt ]] || return 0
  backup_paths /etc/zivpn/users.txt /etc/zivpn/config.json
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  tmp="$(mktemp /tmp/hextunnel-zivpn-account.XXXXXX)"
  awk -v user="$username" '$1 != user' /etc/zivpn/users.txt > "$tmp"
  install -m 600 "$tmp" /etc/zivpn/users.txt
  rm -f "$tmp"
  account_zivpn_rebuild_config
}

account_ssh_add() {
  local username="$1" password="$2" expires="$3" max_sessions="$4" shell="${HEXTUNNEL_SSH_ACCOUNT_SHELL:-/bin/false}"
  if id "$username" >/dev/null 2>&1; then
    run_cmd usermod -U -e "$expires" "$username"
  else
    run_cmd useradd --create-home --shell "$shell" --expiredate "$expires" "$username"
  fi
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || printf '%s:%s\n' "$username" "$password" | chpasswd
  ensure_dir 700 /etc/hextunnel
  backup_path /etc/hextunnel/ssh-limits.tsv
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]]; then
    touch /etc/hextunnel/ssh-limits.tsv
    sed -i -E "/^${username//./\\.}[[:space:]]/d" /etc/hextunnel/ssh-limits.tsv
    printf '%s\t%s\n' "$username" "$max_sessions" >> /etc/hextunnel/ssh-limits.tsv
    chmod 600 /etc/hextunnel/ssh-limits.tsv
  fi
}

account_runtime_add() {
  local protocol="$1" username="$2" secret="$3" expires="$4" max_sessions="$5"
  case "$protocol" in
    vless|vmess|trojan) account_xray_add "$protocol" "$username" "$secret" "$expires" ;;
    hysteria) account_hysteria_add "$username" "$secret" "$expires" ;;
    hysteria2) account_hysteria2_add "$username" "$secret" "$expires" ;;
    zivpn) account_zivpn_add "$username" "$secret" "$expires" ;;
    ssh) account_ssh_add "$username" "$secret" "$expires" "$max_sessions" ;;
  esac
}

account_runtime_remove() {
  local protocol="$1" username="$2"
  case "$protocol" in
    vless|vmess|trojan) account_xray_remove_runtime "$protocol" "$username" ;;
    hysteria) account_hysteria_remove_runtime "$username" ;;
    hysteria2) account_hysteria2_remove_runtime "$username" ;;
    zivpn) account_zivpn_remove_runtime "$username" ;;
    ssh) run_cmd usermod -L "$username" ;;
  esac
}

account_create() {
  local protocol="$1" username="$2" expires="$3" max_sessions="${4:-1}" quota_mb="${5:-0}" speed_kbps="${6:-0}" secret
  require_root
  accounts_init
  account_validate_protocol "$protocol"
  account_validate_username "$username"
  account_validate_date "$expires"
  account_validate_limits "$max_sessions" "$quota_mb" "$speed_kbps"
  account_lock
  account_exists "$protocol" "$username" && die "La cuenta ya existe."
  case "$protocol" in
    vless|vmess) secret="$(cat /proc/sys/kernel/random/uuid)" ;;
    *) secret="$(random_secret "$([[ "$protocol" == ssh ]] && printf 20 || printf 32)")" ;;
  esac
  account_store_credential "$protocol" "$username" "$secret" "$expires"
  account_runtime_add "$protocol" "$username" "$secret" "$expires" "$max_sessions"
  account_db_upsert "$protocol" "$username" "$expires" active "$max_sessions" "$quota_mb" "$speed_kbps"
  account_audit create "$protocol" "$username"
  printf 'Usuario: %s\nProtocolo: %s\nExpira: %s\nCredencial: %s\n' "$username" "$protocol" "$expires" "$secret"
}

account_suspend() {
  local protocol="$1" username="$2" row expires status max_sessions quota speed
  require_root
  accounts_init
  account_validate_protocol "$protocol"
  account_lock
  row="$(account_get_row "$protocol" "$username")"
  [[ -n "$row" ]] || die "Cuenta no registrada."
  IFS=$'\t' read -r _ _ expires status max_sessions quota speed <<< "$row"
  [[ "$status" != suspended ]] || return 0
  account_load_credential "$protocol" "$username"
  account_runtime_remove "$protocol" "$username"
  account_db_upsert "$protocol" "$username" "$expires" suspended "$max_sessions" "$quota" "$speed"
  account_audit suspend "$protocol" "$username"
}

account_resume() {
  local protocol="$1" username="$2" row expires status max_sessions quota speed
  require_root
  accounts_init
  account_validate_protocol "$protocol"
  account_lock
  row="$(account_get_row "$protocol" "$username")"
  [[ -n "$row" ]] || die "Cuenta no registrada."
  IFS=$'\t' read -r _ _ expires status max_sessions quota speed <<< "$row"
  [[ "$status" == suspended ]] || die "La cuenta no está suspendida."
  [[ "$expires" > "$(date +%Y-%m-%d)" || "$expires" == "$(date +%Y-%m-%d)" ]] || die "La cuenta está expirada; renuévala antes de reanudar."
  account_load_credential "$protocol" "$username"
  account_runtime_add "$protocol" "$username" "$ACCOUNT_SECRET" "$expires" "$max_sessions"
  account_db_upsert "$protocol" "$username" "$expires" active "$max_sessions" "$quota" "$speed"
  account_audit resume "$protocol" "$username"
}

account_delete() {
  local protocol="$1" username="$2" row status
  require_root
  accounts_init
  account_validate_protocol "$protocol"
  account_lock
  row="$(account_get_row "$protocol" "$username")"
  [[ -n "$row" ]] || die "Cuenta no registrada."
  status="$(awk -F '\t' '{print $4}' <<< "$row")"
  [[ "$status" == suspended ]] || account_runtime_remove "$protocol" "$username"
  if [[ "$protocol" == ssh ]]; then
    run_cmd userdel -r "$username" || true
    if [[ "${HEXTUNNEL_DRY_RUN:-0}" != 1 && -f /etc/hextunnel/ssh-limits.tsv ]]; then
      sed -i -E "/^${username//./\\.}[[:space:]]/d" /etc/hextunnel/ssh-limits.tsv
    fi
  fi
  account_delete_credential "$protocol" "$username"
  account_db_delete "$protocol" "$username"
  account_audit delete "$protocol" "$username"
}

account_update_runtime_expiry() {
  local protocol="$1" username="$2" expires="$3"
  case "$protocol" in
    ssh) run_cmd chage -E "$expires" "$username" ;;
    vless|vmess|trojan)
      [[ -f "/etc/xray/${protocol}.txt" && "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]] && sed -i -E "s#^(${username//./\\.} [^ ]+) [^ ]+#\\1 $expires#" "/etc/xray/${protocol}.txt"
      ;;
    hysteria)
      [[ -f /etc/hysteria1/users.txt && "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]] && sed -i -E "s#^(${username//./\\.} [^ ]+) [^ ]+#\\1 $expires#" /etc/hysteria1/users.txt
      ;;
    hysteria2)
      [[ -f /etc/hysteria2/users.txt && "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]] && sed -i -E "s#^(${username//./\\.} [^ ]+) [^ ]+#\\1 $expires#" /etc/hysteria2/users.txt
      ;;
    zivpn)
      [[ -f /etc/zivpn/users.txt && "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]] && sed -i -E "s#^(${username//./\\.} [^ ]+) [^ ]+#\\1 $expires#" /etc/zivpn/users.txt
      ;;
  esac
}

account_renew() {
  local protocol="$1" username="$2" expires="$3" row status max_sessions quota speed
  require_root
  accounts_init
  account_validate_protocol "$protocol"
  account_validate_date "$expires"
  account_lock
  row="$(account_get_row "$protocol" "$username")"
  [[ -n "$row" ]] || die "Cuenta no registrada."
  IFS=$'\t' read -r _ _ _ status max_sessions quota speed <<< "$row"
  account_load_credential "$protocol" "$username"
  account_store_credential "$protocol" "$username" "$ACCOUNT_SECRET" "$expires"
  account_db_upsert "$protocol" "$username" "$expires" "$status" "$max_sessions" "$quota" "$speed"
  [[ "$status" == active ]] && account_update_runtime_expiry "$protocol" "$username" "$expires"
  account_audit renew "$protocol" "$username"
}

account_list() {
  accounts_init
  column -t -s $'\t' "$HEXTUNNEL_ACCOUNTS_DB" 2>/dev/null || cat "$HEXTUNNEL_ACCOUNTS_DB"
}
