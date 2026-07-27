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
  docs/ARCHITECTURE.md docs/BETA.md docs/OPERATIONS.md docs/RECOVERY.md
  SECURITY.md CHANGELOG.md
)
for path in "${required[@]}"; do
  [[ -s "$path" ]] || fail "falta archivo requerido: $path"
done

while IFS= read -r -d '' file; do
  bash -n "$file"
done < <(find install.sh beta-install.sh bin lib modules scripts tests legacy -type f \( -name '*.sh' -o -path 'bin/*' \) -print0)

if command -v shellcheck >/dev/null 2>&1; then
  mapfile -d '' shell_files < <(find install.sh beta-install.sh bin lib modules scripts tests legacy -type f \( -name '*.sh' -o -path 'bin/*' \) -print0)
  shellcheck -x "${shell_files[@]}"
fi

bash tests/security/test-hardening.sh
bash tests/security/test-current-tree.sh
bash tests/unit/test-core.sh
bash tests/unit/test-module-contract.sh
bash tests/integration/test-syntax.sh
bash tests/integration/test-dry-run.sh

DIST="$(mktemp -d /tmp/hextunnel-release-gate.XXXXXX)"
trap 'rm -rf "${DIST:-}"' EXIT
SOURCE_DATE_EPOCH=1700000000 bash scripts/build-release.sh "$DIST"
ARCHIVE="$DIST/hextunnel-$VERSION.tar.gz"
[[ -s "$ARCHIVE" && -s "$ARCHIVE.sha256" ]] || fail "no se generó el paquete de release"
sha256sum -c "$ARCHIVE.sha256"
tar -tzf "$ARCHIVE" | grep -q "hextunnel-$VERSION/RELEASE-MANIFEST.sha256"

printf 'Production readiness: OK (%s)\n' "$VERSION"
