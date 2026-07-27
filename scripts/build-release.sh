#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
VERSION_FILE="$ROOT/VERSION"
[[ -s "$VERSION_FILE" ]] || { echo "ERROR: falta VERSION" >&2; exit 1; }
VERSION="$(tr -d '\r\n' < "$VERSION_FILE")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || {
  echo "ERROR: versión inválida: $VERSION" >&2
  exit 1
}

OUTPUT_DIR="${1:-$ROOT/dist}"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null || date +%s)}"
PACKAGE_NAME="hextunnel-$VERSION"
WORK="$(mktemp -d /tmp/hextunnel-release.XXXXXX)"
trap 'rm -rf "${WORK:-}"' EXIT
STAGE="$WORK/$PACKAGE_NAME"
mkdir -p "$STAGE" "$OUTPUT_DIR"

copy_paths=(
  VERSION CHANGELOG.md README.md SECURITY.md
  install.sh beta-install.sh bin config docs legacy lib modules templates tests scripts
)
for path in "${copy_paths[@]}"; do
  [[ -e "$ROOT/$path" ]] || { echo "ERROR: falta $path" >&2; exit 1; }
  cp -a "$ROOT/$path" "$STAGE/"
done

find "$STAGE" -type d -exec chmod 755 {} +
find "$STAGE" -type f -exec chmod 644 {} +
chmod 755 "$STAGE/install.sh" "$STAGE/beta-install.sh" "$STAGE"/bin/* "$STAGE"/scripts/*.sh "$STAGE/legacy/install-all.sh"

while IFS= read -r -d '' file; do
  bash -n "$file"
done < <(find "$STAGE" -type f \( -name '*.sh' -o -path '*/bin/*' \) -print0)

MANIFEST="$STAGE/RELEASE-MANIFEST.sha256"
(
  cd "$STAGE"
  find . -type f ! -name RELEASE-MANIFEST.sha256 -print0 \
    | sort -z \
    | xargs -0 sha256sum
) > "$MANIFEST"
chmod 644 "$MANIFEST"

ARCHIVE="$OUTPUT_DIR/$PACKAGE_NAME.tar.gz"
SBOM="$OUTPUT_DIR/$PACKAGE_NAME.files.txt"
CHECKSUM="$ARCHIVE.sha256"

(
  cd "$WORK"
  tar --sort=name \
    --mtime="@$SOURCE_DATE_EPOCH" \
    --owner=0 --group=0 --numeric-owner \
    -czf "$ARCHIVE" "$PACKAGE_NAME"
)

tar -tzf "$ARCHIVE" > "$SBOM"
sha256sum "$ARCHIVE" > "$CHECKSUM"
chmod 644 "$ARCHIVE" "$SBOM" "$CHECKSUM"

printf 'Versión: %s\n' "$VERSION"
printf 'Paquete: %s\n' "$ARCHIVE"
printf 'SHA-256: %s\n' "$(awk '{print $1}' "$CHECKSUM")"
