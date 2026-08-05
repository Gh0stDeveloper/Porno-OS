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

grep -Fq 'Contraseña SSH (visible):' "$ROOT/lib/account-runtime-guards.sh"
grep -Fq 'HEXTUNNEL_ACCOUNT_SECRET' "$ROOT/lib/account-runtime-guards.sh"
grep -Fq 'account_ensure_ssh_ingress' "$ROOT/lib/account-runtime-guards.sh"
grep -Fq 'firewall_open_port tcp "$port" 0.0.0.0/0' "$ROOT/lib/account-runtime-guards.sh"
grep -Fq "account_display_compact 'SSH'" "$ROOT/lib/account-display.sh"
grep -Fq 'HEXTUNNEL_PUBLIC_IPV4' "$ROOT/lib/account-display.sh"
grep -Fq 'HEXTUNNEL_LICENSE_SUBJECT' "$ROOT/lib/account-display.sh"
grep -Fq 'Security List o NSG' "$ROOT/lib/account-display.sh"

# shellcheck disable=SC1091
source "$ROOT/lib/account-runtime-guards.sh"
tmp="$(account_xray_temp_file)"
[[ "$tmp" == *.json ]]
rm -f "$tmp"

secret="$(HEXTUNNEL_ACCOUNT_SECRET='abc123' account_read_ssh_password)"
[[ "$secret" == 'abc123' ]]

# shellcheck disable=SC1091
source "$ROOT/lib/account-display.sh"
account_is_public_ipv4 149.130.209.224
! account_is_public_ipv4 10.0.0.121
! account_is_public_ipv4 172.16.0.10
! account_is_public_ipv4 192.168.1.20
[[ "$(HEXTUNNEL_PUBLIC_IPV4=149.130.209.224 account_public_ipv4)" == 149.130.209.224 ]]

printf 'optimized administration menu, public IPv4 and SSH credential delivery: ok\n'
