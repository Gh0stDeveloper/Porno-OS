#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ -s VERSION ]] || fail "falta VERSION"
VERSION="$(tr -d '\r\n' < VERSION)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || fail "VERSION inválida"

required=(
  install.sh beta-install.sh
  bin/hextunnel bin/hextunnel-account bin/hextunnel-backup bin/hextunnel-doctor
  bin/hextunnel-health bin/hextunnel-nat bin/hextunnel-update
  bin/hextunnel-legacy-preflight bin/hextunnel-finalize-install
  bin/hextunnel-private-install bin/hextunnel-private-upgrade bin/hextunnel-beta-install
  bin/hextunnel-license bin/hextunnel-install-license-runtime
  bin/hextunnel-install-locked-component bin/hextunnel-slipstream-compat
  docs/ARCHITECTURE.md docs/BETA.md docs/OPERATIONS.md docs/RECOVERY.md docs/PRIVATE_DISTRIBUTION.md
  scripts/build-release.sh scripts/resolve-component-lock.sh scripts/prepare-legacy-runtime.sh
  SECURITY.md CHANGELOG.md VERSION
)
for path in "${required[@]}"; do
  [[ -s "$path" ]] || fail "falta archivo requerido: $path"
done

if [[ "${HEXTUNNEL_RELEASE_BUILD:-0}" == 1 ]]; then
  [[ -s config/component-lock.env ]] || fail "falta config/component-lock.env para construir una release"
  bash -n config/component-lock.env
  grep -q '^HEXTUNNEL_COMPONENT_LOCK_VERSION=1$' config/component-lock.env \
    || fail "component-lock.env es incompatible"
  for variable in \
    HEXTUNNEL_UDP_CUSTOM_SHA256 HEXTUNNEL_SLOWDNS_SHA256 HEXTUNNEL_BADVPN_SHA256 \
    HEXTUNNEL_SINGBOX_SHA256 HEXTUNNEL_ZIVPN_SHA256; do
    grep -Eq "^${variable}=.*[0-9a-f]{64}" config/component-lock.env \
      || fail "falta SHA-256 bloqueado para $variable"
  done
fi

while IFS= read -r -d '' file; do
  bash -n "$file"
done < <(find install.sh beta-install.sh bin lib modules scripts tests legacy -type f \( -name '*.sh' -o -path 'bin/*' \) -print0)

if command -v shellcheck >/dev/null 2>&1; then
  mapfile -d '' shell_files < <(
    find install.sh beta-install.sh bin lib modules scripts tests \
      -type f \( -name '*.sh' -o -path 'bin/*' \) -print0
  )
  shellcheck --severity=error -x "${shell_files[@]}"
fi

bash tests/security/test-hardening.sh
bash tests/security/test-current-tree.sh
bash tests/unit/test-core.sh
bash tests/unit/test-module-contract.sh
bash tests/unit/test-production-operations.sh
bash tests/unit/test-license-runtime.sh
bash tests/unit/test-legacy-runtime.sh
bash tests/integration/test-syntax.sh
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  bash tests/integration/test-dry-run.sh
elif command -v sudo >/dev/null 2>&1; then
  root_lock="$(mktemp /tmp/hextunnel-component-lock.XXXXXX.env)"
  trap 'sudo rm -f "${root_lock:-}"; rm -rf "${DIST:-}"' EXIT
  sudo install -m 600 -o root -g root config/component-lock.env "$root_lock"
  sudo -E env HEXTUNNEL_COMPONENT_LOCK_FILE="$root_lock" \
    bash tests/integration/test-dry-run.sh
  sudo rm -f "$root_lock"
  root_lock=""
else
  fail "test-dry-run requiere root o sudo"
fi

DIST="$(mktemp -d /tmp/hextunnel-release-gate.XXXXXX)"
trap 'rm -rf "${DIST:-}"' EXIT
SOURCE_DATE_EPOCH=1700000000 bash scripts/build-release.sh "$DIST"
ARCHIVE="$DIST/hextunnel-$VERSION.tar.gz"
[[ -s "$ARCHIVE" && -s "$ARCHIVE.sha256" ]] || fail "no se generó el paquete de release"
(
  cd "$DIST"
  sha256sum -c "$(basename "$ARCHIVE.sha256")"
)
archive_listing="$DIST/hextunnel-$VERSION.archive-list.txt"
tar -tzf "$ARCHIVE" > "$archive_listing"
grep -Fqx "hextunnel-$VERSION/RELEASE-MANIFEST.sha256" "$archive_listing" \
  || fail "el paquete no contiene RELEASE-MANIFEST.sha256"
grep -Fqx "hextunnel-$VERSION/bin/hextunnel-license" "$archive_listing" \
  || fail "el paquete no contiene hextunnel-license"
grep -Fqx "hextunnel-$VERSION/bin/hextunnel-private-upgrade" "$archive_listing" \
  || fail "el paquete no contiene el actualizador privado"
grep -Fqx "hextunnel-$VERSION/bin/hextunnel-install-license-runtime" "$archive_listing" \
  || fail "el paquete no contiene el runtime de licencia"

printf 'Production readiness: OK (%s)\n' "$VERSION"
