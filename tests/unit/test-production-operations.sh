#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
WORK="$(mktemp -d /tmp/hextunnel-production-test.XXXXXX)"
trap 'rm -rf "${WORK:-}"' EXIT

mkdir -p "$WORK/source/etc/hextunnel" "$WORK/runtime/etc" "$WORK/runtime/state" "$WORK/runtime/log"
printf 'sample=true\n' > "$WORK/source/etc/hextunnel/sample.env"
tar -C "$WORK/source" -czf "$WORK/valid.tar.gz" etc/hextunnel/sample.env
(
  cd "$WORK"
  sha256sum valid.tar.gz > valid.tar.gz.sha256
)

env \
  HEXTUNNEL_ROOT="$ROOT" \
  HEXTUNNEL_INSTALL_DIR="$ROOT" \
  HEXTUNNEL_ETC="$WORK/runtime/etc" \
  HEXTUNNEL_STATE="$WORK/runtime/state" \
  HEXTUNNEL_LOG_DIR="$WORK/runtime/log" \
  HEXTUNNEL_CONFIG_FILE="$WORK/runtime/etc/hextunnel.env" \
  bash "$ROOT/bin/hextunnel-backup" verify "$WORK/valid.tar.gz" \
  | grep -q 'Respaldo válido'

mkdir -p "$WORK/bad/tmp"
printf 'forbidden\n' > "$WORK/bad/tmp/not-managed"
tar -C "$WORK/bad" -czf "$WORK/invalid.tar.gz" tmp/not-managed
if env \
  HEXTUNNEL_ROOT="$ROOT" \
  HEXTUNNEL_INSTALL_DIR="$ROOT" \
  HEXTUNNEL_ETC="$WORK/runtime/etc" \
  HEXTUNNEL_STATE="$WORK/runtime/state" \
  HEXTUNNEL_LOG_DIR="$WORK/runtime/log" \
  HEXTUNNEL_CONFIG_FILE="$WORK/runtime/etc/hextunnel.env" \
  bash "$ROOT/bin/hextunnel-backup" verify "$WORK/invalid.tar.gz" >/dev/null 2>&1; then
  echo 'an archive with unmanaged paths was accepted' >&2
  exit 1
fi

SOURCE_DATE_EPOCH=1700000000 bash "$ROOT/scripts/build-release.sh" "$WORK/dist-a" >/dev/null
SOURCE_DATE_EPOCH=1700000000 bash "$ROOT/scripts/build-release.sh" "$WORK/dist-b" >/dev/null
VERSION="$(tr -d '\r\n' < "$ROOT/VERSION")"
sha_a="$(sha256sum "$WORK/dist-a/hextunnel-$VERSION.tar.gz" | awk '{print $1}')"
sha_b="$(sha256sum "$WORK/dist-b/hextunnel-$VERSION.tar.gz" | awk '{print $1}')"
[[ "$sha_a" == "$sha_b" ]] || {
  echo 'release archives are not reproducible' >&2
  exit 1
}

printf 'production operations: ok\n'
