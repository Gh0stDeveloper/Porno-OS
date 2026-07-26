#!/usr/bin/env bash
systemd_reload() { run_cmd systemctl daemon-reload; }
safe_restart_service() { local service="$1" validator="${2:-}"; record_service_state "$service"; if [[ -n "$validator" ]]; then log_info "Validando configuración antes de reiniciar $service"; bash -c "$validator" || die "Configuración inválida para $service."; fi; run_cmd systemctl enable "$service"; run_cmd systemctl restart "$service" || return 1; if [[ "${HEXTUNNEL_DRY_RUN:-0}" != 1 ]] && ! systemctl is-active --quiet "$service"; then log_error "$service no quedó activo."; return 1; fi; }
safe_stop_disable_service() { local service="$1"; record_service_state "$service"; run_cmd systemctl stop "$service" || true; run_cmd systemctl disable "$service" || true; }
install_systemd_unit() { local service="$1" mode="${2:-644}"; write_file "/etc/systemd/system/$service" "$mode"; systemd_reload; }
