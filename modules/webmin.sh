#!/usr/bin/env bash

webmin_ports() {
  [[ "${HEXTUNNEL_WEBMIN_PUBLIC:-0}" == 1 ]] \
    && printf 'tcp %s %s public\n' "${HEXTUNNEL_WEBMIN_PORT:-10000}" "${HEXTUNNEL_ADMIN_IP:-0.0.0.0/0}"
}
webmin_dependencies() { :; }

webmin_install_repository() {
  local key_url="${HEXTUNNEL_WEBMIN_KEY_URL:-https://download.webmin.com/developers-key.asc}"
  local expected_key_id="${HEXTUNNEL_WEBMIN_KEY_ID:-2D223B918916F2A2}"
  local keyring=/usr/share/keyrings/hextunnel-webmin-developers.gpg
  local repo_file=/etc/apt/sources.list.d/hextunnel-webmin.list
  local tmp key_ids
  run_cmd apt-get update
  run_cmd apt-get install -y ca-certificates curl gnupg perl
  backup_paths "$keyring" "$repo_file" /etc/apt/sources.list.d/webmin.list /usr/share/keyrings/webmin.gpg
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]]; then
    log_dry "instalar clave Webmin Developers y repositorio APT firmado"
    return 0
  fi
  tmp="$(mktemp /tmp/webmin-developers-key.XXXXXX)"
  run_cmd curl -fL --retry 3 --connect-timeout 10 -o "$tmp" "$key_url"
  key_ids="$(gpg --batch --show-keys --with-colons "$tmp" 2>/dev/null | awk -F: '$1=="pub" || $1=="sub" {print toupper($5)}' || true)"
  grep -Fqx "${expected_key_id^^}" <<< "$key_ids" \
    || { rm -f "$tmp"; die "La clave oficial de Webmin no contiene el identificador esperado $expected_key_id."; }
  gpg --batch --yes --dearmor -o "$keyring" "$tmp"
  chmod 644 "$keyring"
  rm -f "$tmp"
  rm -f /etc/apt/sources.list.d/webmin.list /usr/share/keyrings/webmin.gpg
  cat > "$repo_file" <<EOF
deb [signed-by=$keyring] https://download.webmin.com/download/newkey/repository stable contrib
EOF
  chmod 644 "$repo_file"
  run_cmd apt-get clean
  run_cmd apt-get update
  run_cmd apt-get install -y --install-recommends webmin
}

webmin_set_config_value() {
  local key="$1" value="$2" file=/etc/webmin/miniserv.conf
  backup_path "$file"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && { log_dry "webmin $key=$value"; return 0; }
  if grep -q "^${key}=" "$file"; then
    sed -i -E "s#^${key}=.*#${key}=${value}#" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

webmin_wait_ready() {
  local port="${HEXTUNNEL_WEBMIN_PORT:-10000}" attempt
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  for attempt in $(seq 1 30); do
    if systemctl is-active --quiet webmin \
      && port_is_listening tcp "$port" any \
      && curl -kfsS --connect-timeout 2 --max-time 4 -o /dev/null "https://127.0.0.1:${port}/"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

webmin_install() {
  local port="${HEXTUNNEL_WEBMIN_PORT:-10000}"
  [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]] || die "Puerto Webmin inválido: $port"
  webmin_install_repository
  backup_paths /etc/webmin/miniserv.conf /etc/webmin/config
  webmin_set_config_value ssl 1
  webmin_set_config_value port "$port"
  if [[ "${HEXTUNNEL_WEBMIN_PUBLIC:-0}" == 1 ]]; then
    webmin_set_config_value bind ""
    if [[ -n "${HEXTUNNEL_ADMIN_IP:-}" ]]; then
      webmin_set_config_value allow "${HEXTUNNEL_ADMIN_IP%/32}"
    else
      log_warn "Webmin público sin HEXTUNNEL_ADMIN_IP; el firewall permitirá cualquier IP."
    fi
  else
    webmin_set_config_value bind 127.0.0.1
  fi
  webmin_set_config_value passdelay 3
  webmin_set_config_value blockhost_failures 5
  webmin_set_config_value blockhost_time 300
  safe_restart_service webmin "perl -c /usr/share/webmin/miniserv.pl >/dev/null && grep -q '^ssl=1$' /etc/webmin/miniserv.conf"
  webmin_wait_ready || die "Webmin no abrió su listener TLS en 127.0.0.1:$port."
}

webmin_uninstall() {
  local keyring=/usr/share/keyrings/hextunnel-webmin-developers.gpg
  local repo_file=/etc/apt/sources.list.d/hextunnel-webmin.list
  safe_stop_disable_service webmin
  backup_paths /etc/webmin "$repo_file" "$keyring" /etc/apt/sources.list.d/webmin.list /usr/share/keyrings/webmin.gpg
  run_cmd apt-get purge -y webmin
  run_cmd rm -rf /etc/webmin
  run_cmd rm -f "$repo_file" "$keyring" /etc/apt/sources.list.d/webmin.list /usr/share/keyrings/webmin.gpg
  firewall_close_port tcp "${HEXTUNNEL_WEBMIN_PORT:-10000}"
}

webmin_validate() {
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  local port="${HEXTUNNEL_WEBMIN_PORT:-10000}"
  [[ -s /etc/webmin/miniserv.conf ]] || die "Falta miniserv.conf de Webmin."
  grep -q '^ssl=1$' /etc/webmin/miniserv.conf || die "Webmin no tiene TLS habilitado."
  grep -q "^port=$port$" /etc/webmin/miniserv.conf || die "Webmin no usa el puerto configurado $port."
  if [[ "${HEXTUNNEL_WEBMIN_PUBLIC:-0}" != 1 ]]; then
    grep -q '^bind=127.0.0.1$' /etc/webmin/miniserv.conf || die "Webmin no está restringido a loopback."
  fi
  perl -c /usr/share/webmin/miniserv.pl >/dev/null || die "miniserv.pl no supera perl -c."
  webmin_wait_ready || die "Webmin no responde mediante TLS en 127.0.0.1:$port."
}

webmin_doctor() {
  local failed=0 port="${HEXTUNNEL_WEBMIN_PORT:-10000}" tls=disabled bind=""
  systemctl is-active --quiet webmin || failed=1
  if grep -q '^ssl=1$' /etc/webmin/miniserv.conf 2>/dev/null; then tls=enabled; else failed=1; fi
  bind="$(awk -F= '$1=="bind"{print $2}' /etc/webmin/miniserv.conf 2>/dev/null | tail -n1)"
  printf 'service=%s tls=%s bind=%s port=' "$(systemctl is-active webmin 2>/dev/null || true)" "$tls" "$bind"
  if port_is_listening tcp "$port" any; then printf open; else printf closed; failed=1; fi
  printf '\n'
  return "$failed"
}
