#!/usr/bin/env bash

transaction_begin() {
  require_root
  ensure_dir 700 "$HEXTUNNEL_STATE"
  ensure_dir 700 "$HEXTUNNEL_STATE/transactions"
  local label="${1:-change}" id
  id="$(date +%Y%m%d-%H%M%S)-$$-${label//[^A-Za-z0-9_.-]/_}"
  HEXTUNNEL_TRANSACTION_DIR="$HEXTUNNEL_STATE/transactions/$id"
  export HEXTUNNEL_TRANSACTION_DIR
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]]; then
    mkdir -p "$HEXTUNNEL_TRANSACTION_DIR/files"
    : > "$HEXTUNNEL_TRANSACTION_DIR/files.manifest"
    : > "$HEXTUNNEL_TRANSACTION_DIR/services.manifest"
    printf '%s\n' RUNNING > "$HEXTUNNEL_TRANSACTION_DIR/status"
  fi
  log_info "Transacción iniciada: $id"
}

record_service_state() {
  local service="$1" enabled=disabled active=inactive
  [[ -n "${HEXTUNNEL_TRANSACTION_DIR:-}" && "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]] || return 0
  grep -Fq "|$service|" "$HEXTUNNEL_TRANSACTION_DIR/services.manifest" 2>/dev/null && return 0
  systemctl is-enabled --quiet "$service" 2>/dev/null && enabled=enabled
  systemctl is-active --quiet "$service" 2>/dev/null && active=active
  printf 'SERVICE|%s|%s|%s\n' "$service" "$enabled" "$active" >> "$HEXTUNNEL_TRANSACTION_DIR/services.manifest"
}

restore_transaction_files() {
  local dir="$1" status path key backup
  [[ -f "$dir/files.manifest" ]] || return 0
  tac "$dir/files.manifest" | while IFS='|' read -r status path key; do
    [[ -n "$path" ]] || continue
    if [[ "$status" == EXISTS ]]; then
      backup="$dir/files/$key"
      rm -rf -- "$path"
      mkdir -p "$(dirname "$path")"
      cp -a -- "$backup" "$path"
    else
      rm -rf -- "$path"
    fi
  done
}

restore_transaction_services() {
  local dir="$1" marker service enabled active
  [[ -f "$dir/services.manifest" ]] || return 0
  systemctl daemon-reload >/dev/null 2>&1 || true
  while IFS='|' read -r marker service enabled active; do
    [[ "$marker" == SERVICE ]] || continue
    if [[ "$enabled" == enabled ]]; then
      systemctl enable "$service" >/dev/null 2>&1 || log_warn "No se pudo restaurar enable de $service"
    else
      systemctl disable "$service" >/dev/null 2>&1 || true
    fi
    if [[ "$active" == active ]]; then
      systemctl restart "$service" >/dev/null 2>&1 || log_warn "No se pudo restaurar el estado activo de $service"
    else
      systemctl stop "$service" >/dev/null 2>&1 || true
    fi
  done < "$dir/services.manifest"
}

rollback_transaction() {
  require_root
  local id="${1:-}" dir
  if [[ -z "$id" ]]; then
    dir="$(find "$HEXTUNNEL_STATE/transactions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -n1)"
  elif [[ "$id" == /* ]]; then
    dir="$id"
  else
    dir="$HEXTUNNEL_STATE/transactions/$id"
  fi
  [[ -n "$dir" && -d "$dir" ]] || die "No se encontró la transacción solicitada."
  log_warn "Restaurando transacción: $(basename "$dir")"
  restore_transaction_files "$dir"
  firewall_restore "$dir"
  restore_transaction_services "$dir"
  printf '%s\n' ROLLED_BACK > "$dir/status"
  log_success "Rollback completado."
}

transaction_fail() {
  local code="$1" line="$2" command="$3"
  trap - ERR INT TERM
  log_error "Falló la transacción en línea $line: $command (código $code)"
  if [[ -n "${HEXTUNNEL_TRANSACTION_DIR:-}" && "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]]; then
    printf '%s\n' FAILED > "$HEXTUNNEL_TRANSACTION_DIR/status"
    printf 'line=%s command=%s code=%s\n' "$line" "$command" "$code" > "$HEXTUNNEL_TRANSACTION_DIR/error"
    rollback_transaction "$HEXTUNNEL_TRANSACTION_DIR" || true
  fi
  exit "$code"
}

transaction_commit() {
  [[ -n "${HEXTUNNEL_TRANSACTION_DIR:-}" ]] || return 0
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]]; then
    printf '%s\n' COMMITTED > "$HEXTUNNEL_TRANSACTION_DIR/status"
    ln -sfn "$HEXTUNNEL_TRANSACTION_DIR" "$HEXTUNNEL_STATE/last-successful"
  fi
  log_success "Transacción confirmada: $(basename "$HEXTUNNEL_TRANSACTION_DIR")"
}
