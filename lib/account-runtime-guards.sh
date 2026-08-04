#!/usr/bin/env bash
[[ -n "${HEXTUNNEL_ACCOUNT_RUNTIME_GUARDS_LOADED:-}" ]] && return 0
HEXTUNNEL_ACCOUNT_RUNTIME_GUARDS_LOADED=1

account_xray_temp_file() {
  mktemp --suffix=.json /tmp/hextunnel-xray-account.XXXXXX
}

account_validate_ssh_password() {
  local password="$1" length=${#1}
  ((length >= 4 && length <= 64)) \
    || die "La contraseña SSH debe contener entre 4 y 64 caracteres."
  [[ "$password" != *:* && "$password" != *@* ]] \
    || die "La contraseña SSH no puede contener ':' ni '@' porque se entrega también en formato HOST:PUERTO@USUARIO:CONTRASEÑA."
  [[ ! "$password" =~ [[:space:]] ]] \
    || die "La contraseña SSH no puede contener espacios, tabulaciones ni saltos de línea."
  [[ "$password" =~ ^[[:graph:]]+$ ]] \
    || die "La contraseña SSH contiene caracteres de control no permitidos."
}

account_read_ssh_password() {
  local password="${HEXTUNNEL_ACCOUNT_SECRET:-}" confirmation=''

  if [[ -n "$password" ]]; then
    account_validate_ssh_password "$password"
    printf '%s' "$password"
    return 0
  fi

  [[ -r /dev/tty && -w /dev/tty ]] \
    || die "No existe una terminal interactiva para introducir la contraseña SSH. Define HEXTUNNEL_ACCOUNT_SECRET para uso automatizado."

  while true; do
    printf 'Contraseña SSH (visible): ' > /dev/tty
    IFS= read -r password < /dev/tty \
      || die "No se pudo leer la contraseña SSH desde la terminal."

    if (( ${#password} < 4 || ${#password} > 64 )) \
      || [[ "$password" == *:* || "$password" == *@* || "$password" =~ [[:space:]] || ! "$password" =~ ^[[:graph:]]+$ ]]; then
      printf 'Contraseña inválida. Usa entre 4 y 64 caracteres visibles, sin espacios, dos puntos ni @.\n' > /dev/tty
      password=''
      continue
    fi

    printf 'Confirmar contraseña: ' > /dev/tty
    IFS= read -r confirmation < /dev/tty \
      || die "No se pudo confirmar la contraseña SSH."

    if [[ "$password" != "$confirmation" ]]; then
      printf 'Las contraseñas no coinciden. Intenta nuevamente.\n' > /dev/tty
      password=''
      confirmation=''
      continue
    fi

    printf 'Contraseña confirmada correctamente.\n' > /dev/tty
    printf '%s' "$password"
    return 0
  done
}

account_ensure_ssh_ingress() {
  local port
  for port in 22 299 443 4443 25 80 2082 2086 8080 8880 10080; do
    firewall_open_port tcp "$port" 0.0.0.0/0
  done
}

account_create() {
  local protocol="$1" username="$2" expires="$3"
  local max_sessions="${4:-1}" quota_mb="${5:-0}" speed_kbps="${6:-0}" secret

  require_root
  accounts_init
  account_validate_protocol "$protocol"
  account_validate_username "$username"
  account_validate_date "$expires"
  account_validate_limits "$max_sessions" "$quota_mb" "$speed_kbps"
  account_lock
  account_exists "$protocol" "$username" && die "La cuenta ya existe."

  case "$protocol" in
    ssh)
      secret="$(account_read_ssh_password)"
      ;;
    vless|vmess)
      secret="$(cat /proc/sys/kernel/random/uuid)"
      ;;
    *)
      secret="$(random_secret 32)"
      ;;
  esac

  account_store_credential "$protocol" "$username" "$secret" "$expires"
  account_runtime_add "$protocol" "$username" "$secret" "$expires" "$max_sessions"
  if [[ "$protocol" == ssh ]]; then
    account_ensure_ssh_ingress
  fi
  account_db_upsert "$protocol" "$username" "$expires" active "$max_sessions" "$quota_mb" "$speed_kbps"
  account_audit create "$protocol" "$username"
  printf 'Cuenta %s/%s creada correctamente. Expira: %s.\n' "$protocol" "$username" "$expires"
}

account_xray_add() {
  local protocol="$1" username="$2" secret="$3" expires="$4" config=/etc/xray/config.json tags tmp
  [[ -s "$config" && -x /usr/local/bin/xray ]] || die "Xray no está instalado."
  tags="$(xray_protocol_tags "$protocol")" || die "Protocolo Xray inválido."
  backup_paths "$config" "/etc/xray/${protocol}.txt"
  tmp="$(account_xray_temp_file)"
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
  tmp="$(account_xray_temp_file)"
  jq --arg user "$username" --argjson tags "$tags" '
    (.inbounds[] | select(.tag as $tag | $tags | index($tag)) | .settings.clients) |= map(select(.email != $user))
  ' "$config" > "$tmp"
  /usr/local/bin/xray run -test -config "$tmp"
  install -m 600 "$tmp" "$config"
  [[ -f "/etc/xray/${protocol}.txt" && "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]] && sed -i -E "/^${username//./\\.} /d" "/etc/xray/${protocol}.txt"
  safe_restart_service xray "/usr/local/bin/xray run -test -config /etc/xray/config.json"
  rm -f "$tmp"
}
