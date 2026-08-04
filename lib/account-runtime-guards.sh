#!/usr/bin/env bash
[[ -n "${HEXTUNNEL_ACCOUNT_RUNTIME_GUARDS_LOADED:-}" ]] && return 0
HEXTUNNEL_ACCOUNT_RUNTIME_GUARDS_LOADED=1

account_xray_temp_file() {
  mktemp --suffix=.json /tmp/hextunnel-xray-account.XXXXXX
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
