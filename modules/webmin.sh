#!/usr/bin/env bash

webmin_ports() {
  [[ "${HEXTUNNEL_WEBMIN_PUBLIC:-0}" == 1 ]] && printf '%s %s %s\n' tcp 10000 "${HEXTUNNEL_ADMIN_IP:-0.0.0.0/0}"
}
webmin_dependencies() { :; }

webmin_install_repository() {
  run_cmd apt-get update
  run_cmd apt-get install -y ca-certificates curl gnupg perl
  backup_paths /usr/share/keyrings/webmin.gpg /etc/apt/sources.list.d/webmin.list
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]]; then
    log_dry "instalar clave y repositorio APT firmado de Webmin"
    return 0
  fi
  local tmp
  tmp="$(mktemp /tmp/webmin-key.XXXXXX)"
  curl -fL --retry 3 -o "$tmp" https://download.webmin.com/jcameron-key.asc
  gpg --batch --yes --dearmor -o /usr/share/keyrings/webmin.gpg "$tmp"
  chmod 644 /usr/share/keyrings/webmin.gpg
  rm -f "$tmp"
  cat > /etc/apt/sources.list.d/webmin.list <<'EOF'
deb [signed-by=/usr/share/keyrings/webmin.gpg] https://download.webmin.com/download/newkey/repository stable contrib
EOF
  chmod 644 /etc/apt/sources.list.d/webmin.list
  apt-get update
  apt-get install -y webmin
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

webmin_install() {
  webmin_install_repository
  backup_paths /etc/webmin/miniserv.conf /etc/webmin/config
  webmin_set_config_value ssl 1
  webmin_set_config_value port 10000
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
}

webmin_uninstall() {
  safe_stop_disable_service webmin
  backup_paths /etc/webmin /etc/apt/sources.list.d/webmin.list /usr/share/keyrings/webmin.gpg
  run_cmd apt-get remove -y webmin
  run_cmd rm -f /etc/apt/sources.list.d/webmin.list /usr/share/keyrings/webmin.gpg
  firewall_close_port tcp 10000
}

webmin_validate() {
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  [[ -s /etc/webmin/miniserv.conf ]]
  grep -q '^ssl=1$' /etc/webmin/miniserv.conf
  perl -c /usr/share/webmin/miniserv.pl >/dev/null
  if [[ "${HEXTUNNEL_WEBMIN_PUBLIC:-0}" != 1 ]]; then grep -q '^bind=127.0.0.1$' /etc/webmin/miniserv.conf; fi
}

webmin_doctor() {
  printf 'service=%s tls=' "$(systemctl is-active webmin 2>/dev/null || true)"
  grep -q '^ssl=1$' /etc/webmin/miniserv.conf 2>/dev/null && printf enabled || printf disabled
  printf ' bind=%s port=' "$(awk -F= '$1=="bind"{print $2}' /etc/webmin/miniserv.conf 2>/dev/null | tail -n1)"
  port_is_listening tcp 10000 && printf open || printf closed
  printf '\n'
}
