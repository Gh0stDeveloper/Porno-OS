#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

run_step() {
  local label="$1"
  shift
  printf '\n=== GATE: %s ===\n' "$label"
  "$@" || fail "falló la etapa: $label"
}

[[ -s VERSION ]] || fail "falta VERSION"
VERSION="$(tr -d '\r\n' < VERSION)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || fail "VERSION inválida"

required=(
  install.sh beta-install.sh
  bin/hextunnel bin/hextunnel-account bin/hextunnel-arm64-menu
  bin/hextunnel-backup bin/hextunnel-doctor bin/hextunnel-health bin/hextunnel-nat bin/hextunnel-update
  bin/hextunnel-legacy-preflight bin/hextunnel-finalize-install
  bin/hextunnel-private-install bin/hextunnel-private-upgrade bin/hextunnel-beta-install
  bin/hextunnel-license bin/hextunnel-install-license-runtime
  bin/hextunnel-install-locked-component bin/hextunnel-slipstream-compat
  lib/install-runtime.sh lib/install-runtime-guards.sh lib/network-policy.sh
  lib/account-display.sh lib/account-runtime-guards.sh
  docs/ARCHITECTURE.md docs/BETA.md docs/OPERATIONS.md docs/RECOVERY.md docs/PRIVATE_DISTRIBUTION.md
  scripts/build-release.sh scripts/resolve-component-lock.sh scripts/prepare-legacy-runtime.sh
  tests/unit/test-runtime-config-readonly.sh tests/unit/test-package-manager-lock.sh
  tests/unit/test-install-runtime-network.sh tests/unit/test-rollback-service-quiesce.sh
  tests/unit/test-network-policy-config-format.sh tests/unit/test-menu-parity.sh
  tests/unit/test-legacy-port-conflict.sh
  SECURITY.md CHANGELOG.md VERSION
)
for path in "${required[@]}"; do
  [[ -s "$path" ]] || fail "falta archivo requerido: $path"
done

if [[ "${HEXTUNNEL_RELEASE_BUILD:-0}" == 1 ]]; then
  printf '\n=== GATE: component-lock ===\n'
  [[ -s config/component-lock.env ]] || fail "falta config/component-lock.env para construir una release"
  bash -n config/component-lock.env
  grep -q '^HEXTUNNEL_COMPONENT_LOCK_VERSION=1$' config/component-lock.env \
    || fail "component-lock.env es incompatible"
  for variable in \
    HEXTUNNEL_UDP_CUSTOM_SHA256 HEXTUNNEL_SLOWDNS_SHA256 HEXTUNNEL_BADVPN_SHA256 \
    HEXTUNNEL_SINGBOX_SHA256 HEXTUNNEL_ZIVPN_SHA256 \
    HEXTUNNEL_ZIVPN_AMD64_SHA256 HEXTUNNEL_ZIVPN_ARM64_SHA256; do
    grep -Eq "^${variable}=.*[0-9a-f]{64}" config/component-lock.env \
      || fail "falta SHA-256 bloqueado para $variable"
  done
  for variable in HEXTUNNEL_ZIVPN_AMD64_BINARY_URL HEXTUNNEL_ZIVPN_ARM64_BINARY_URL; do
    grep -Eq "^${variable}=.+" config/component-lock.env \
      || fail "falta URL bloqueada para $variable"
  done
fi

printf '\n=== GATE: bash-syntax ===\n'
while IFS= read -r -d '' file; do
  bash -n "$file" || fail "sintaxis Bash inválida: $file"
done < <(find install.sh beta-install.sh bin lib modules scripts tests legacy -type f \( -name '*.sh' -o -path 'bin/*' \) -print0)

if command -v shellcheck >/dev/null 2>&1; then
  printf '\n=== GATE: shellcheck ===\n'
  mapfile -d '' shell_files < <(
    find install.sh beta-install.sh bin lib modules scripts tests \
      -type f \( -name '*.sh' -o -path 'bin/*' \) -print0
  )
  shellcheck --severity=error -x "${shell_files[@]}" \
    || fail "ShellCheck detectó errores"
fi

run_step hardening bash tests/security/test-hardening.sh
run_step current-tree bash tests/security/test-current-tree.sh
run_step core bash tests/unit/test-core.sh
run_step runtime-config-readonly bash tests/unit/test-runtime-config-readonly.sh
run_step package-manager-lock bash tests/unit/test-package-manager-lock.sh
run_step legacy-port-conflict bash tests/unit/test-legacy-port-conflict.sh
run_step install-runtime-network bash tests/unit/test-install-runtime-network.sh
run_step rollback-service-quiesce bash tests/unit/test-rollback-service-quiesce.sh
run_step network-policy-config-format bash tests/unit/test-network-policy-config-format.sh
run_step menu-parity bash tests/unit/test-menu-parity.sh
run_step module-contract bash tests/unit/test-module-contract.sh
run_step production-operations bash tests/unit/test-production-operations.sh
run_step license-runtime bash tests/unit/test-license-runtime.sh
run_step legacy-runtime bash tests/unit/test-legacy-runtime.sh
run_step integration-syntax bash tests/integration/test-syntax.sh

printf '\n=== GATE: integration-dry-run ===\n'
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  bash tests/integration/test-dry-run.sh \
    || fail "falló la etapa: integration-dry-run"
elif command -v sudo >/dev/null 2>&1; then
  root_lock="$(mktemp /tmp/hextunnel-component-lock.XXXXXX.env)"
  trap 'sudo rm -f "${root_lock:-}"; rm -rf "${DIST:-}"' EXIT
  sudo install -m 600 -o root -g root config/component-lock.env "$root_lock"
  sudo -E env HEXTUNNEL_COMPONENT_LOCK_FILE="$root_lock" \
    bash tests/integration/test-dry-run.sh \
    || fail "falló la etapa: integration-dry-run"
  sudo rm -f "$root_lock"
  root_lock=""
else
  fail "test-dry-run requiere root o sudo"
fi

printf '\n=== GATE: reproducible-package ===\n'
DIST="$(mktemp -d /tmp/hextunnel-release-gate.XXXXXX)"
trap 'rm -rf "${DIST:-}"' EXIT
SOURCE_DATE_EPOCH=1700000000 bash scripts/build-release.sh "$DIST" \
  || fail "no se pudo construir el paquete reproducible"
ARCHIVE="$DIST/hextunnel-$VERSION.tar.gz"
[[ -s "$ARCHIVE" && -s "$ARCHIVE.sha256" ]] || fail "no se generó el paquete de release"
(
  cd "$DIST"
  sha256sum -c "$(basename "$ARCHIVE.sha256")"
) || fail "falló la verificación SHA-256 del paquete"
archive_listing="$DIST/hextunnel-$VERSION.archive-list.txt"
tar -tzf "$ARCHIVE" > "$archive_listing"
grep -Fqx "hextunnel-$VERSION/RELEASE-MANIFEST.sha256" "$archive_listing" \
  || fail "el paquete no contiene RELEASE-MANIFEST.sha256"
if [[ "${HEXTUNNEL_RELEASE_BUILD:-0}" == 1 ]]; then
  grep -Fqx "hextunnel-$VERSION/config/component-lock.env" "$archive_listing" \
    || fail "el paquete no contiene config/component-lock.env"
fi
for packaged in \
  bin/hextunnel-license \
  bin/hextunnel-private-upgrade \
  bin/hextunnel-install-license-runtime \
  bin/hextunnel-arm64-menu \
  lib/install-runtime-guards.sh \
  lib/network-policy.sh \
  lib/account-display.sh \
  lib/account-runtime-guards.sh; do
  grep -Fqx "hextunnel-$VERSION/$packaged" "$archive_listing" \
    || fail "el paquete no contiene $packaged"
done

printf '\nProduction readiness: OK (%s)\n' "$VERSION"
