#!/usr/bin/env bash

install_framework() {
  local source_root="$HEXTUNNEL_ROOT"
  ensure_dir 755 /usr/local/bin
  ensure_dir 700 "$HEXTUNNEL_ETC"
  ensure_dir 700 "$HEXTUNNEL_STATE"
  ensure_dir 750 "$HEXTUNNEL_LOG_DIR"

  if [[ "$source_root" != "$HEXTUNNEL_INSTALL_DIR" ]]; then
    backup_path "$HEXTUNNEL_INSTALL_DIR"
    if [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]]; then
      log_dry "copiar framework a $HEXTUNNEL_INSTALL_DIR"
    else
      rm -rf "$HEXTUNNEL_INSTALL_DIR"
      install -d -m 755 "$HEXTUNNEL_INSTALL_DIR"
      tar -C "$source_root" --exclude=.git --exclude='*.log' -cf - . | tar -C "$HEXTUNNEL_INSTALL_DIR" -xf -
      find "$HEXTUNNEL_INSTALL_DIR" -type d -exec chmod 755 {} +
      find "$HEXTUNNEL_INSTALL_DIR" -type f -name '*.sh' -exec chmod 644 {} +
      chmod 755 \
        "$HEXTUNNEL_INSTALL_DIR/install.sh" \
        "$HEXTUNNEL_INSTALL_DIR"/bin/* \
        "$HEXTUNNEL_INSTALL_DIR/legacy/install-all.sh"
    fi
  fi

  local command
  for command in hextunnel hextunnel-doctor hextunnel-account hextunnel-update hextunnel-health; do
    [[ -f "$HEXTUNNEL_INSTALL_DIR/bin/$command" || "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || continue
    backup_path "/usr/local/bin/$command"
    if [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]]; then
      log_dry "enlazar /usr/local/bin/$command"
    else
      ln -sfn "$HEXTUNNEL_INSTALL_DIR/bin/$command" "/usr/local/bin/$command"
    fi
  done

  if [[ ! -f "$HEXTUNNEL_CONFIG_FILE" ]]; then
    if [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]]; then
      log_dry "instalar ejemplo en $HEXTUNNEL_CONFIG_FILE con modo 600"
    elif [[ -f "$HEXTUNNEL_INSTALL_DIR/config/hextunnel.env.example" ]]; then
      install -m 600 "$HEXTUNNEL_INSTALL_DIR/config/hextunnel.env.example" "$HEXTUNNEL_CONFIG_FILE"
    fi
  fi
  if [[ ! -f "$HEXTUNNEL_SECRETS_FILE" ]]; then
    if [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]]; then
      log_dry "instalar ejemplo en $HEXTUNNEL_SECRETS_FILE con modo 600"
    elif [[ -f "$HEXTUNNEL_INSTALL_DIR/config/secrets.env.example" ]]; then
      install -m 600 "$HEXTUNNEL_INSTALL_DIR/config/secrets.env.example" "$HEXTUNNEL_SECRETS_FILE"
    fi
  fi

  install_systemd_unit hextunnel-health.service 644 <<'EOF'
[Unit]
Description=Hex Tunnel health audit
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hextunnel-health
User=root
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=full
ReadOnlyPaths=/opt/hextunnel /etc/hextunnel
ReadWritePaths=/var/log/hextunnel /var/lib/hextunnel
EOF
  install_systemd_unit hextunnel-health.timer 644 <<'EOF'
[Unit]
Description=Run Hex Tunnel health audit periodically

[Timer]
OnBootSec=3min
OnUnitActiveSec=5min
RandomizedDelaySec=30s
Persistent=true

[Install]
WantedBy=timers.target
EOF
  safe_restart_service hextunnel-health.timer
}
