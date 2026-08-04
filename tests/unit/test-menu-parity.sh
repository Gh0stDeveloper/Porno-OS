#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
MENU="$ROOT/bin/hextunnel-arm64-menu"
ACCOUNT="$ROOT/bin/hextunnel-account"

bash -n "$MENU"
bash -n "$ACCOUNT"
bash -n "$ROOT/lib/account-display.sh"
bash -n "$ROOT/lib/account-runtime-guards.sh"

for text in \
  'MENÚ PRINCIPAL' \
  'Cuentas SSH' \
  'Cuentas Xray' \
  'Cuentas Hysteria' \
  'Cuentas Hysteria 2' \
  'Cuentas ZiVPN' \
  'Conexiones activas' \
  'Control de servicios' \
  'Backup y restaurar' \
  'Configuración avanzada' \
  'Mostrar credencial o enlaces'; do
  grep -Fq "$text" "$MENU" || {
    printf 'missing optimized menu function: %s\n' "$text" >&2
    exit 1
  }
done

grep -Fq 'hextunnel-account show <protocolo> <usuario>' "$ACCOUNT"
grep -Fq 'source "$ROOT/lib/account-runtime-guards.sh"' "$ACCOUNT"
grep -Fq 'source "$ROOT/lib/account-display.sh"' "$ACCOUNT"

# shellcheck disable=SC1091
source "$ROOT/lib/account-runtime-guards.sh"
tmp="$(account_xray_temp_file)"
[[ "$tmp" == *.json ]]
rm -f "$tmp"

printf 'optimized administration menu parity: ok\n'
