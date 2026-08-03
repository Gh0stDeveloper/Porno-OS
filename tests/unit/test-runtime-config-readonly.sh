#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
WORK="$(mktemp -d /tmp/hextunnel-runtime-config.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

export HEXTUNNEL_ROOT="$ROOT"
export HEXTUNNEL_ETC="$WORK/existing-etc"
export HEXTUNNEL_CONFIG_FILE="$HEXTUNNEL_ETC/hextunnel.env"
export HEXTUNNEL_COMPONENT_LOCK_FILE="$WORK/missing-component-lock.env"
export HEXTUNNEL_DRY_RUN=0

mkdir -p "$HEXTUNNEL_ETC"
printf '%s\n' 'HEXTUNNEL_TEST_READONLY_CONFIG=loaded' > "$HEXTUNNEL_CONFIG_FILE"
chmod 700 "$HEXTUNNEL_ETC"
chmod 600 "$HEXTUNNEL_CONFIG_FILE"

# shellcheck disable=SC1091
source "$ROOT/lib/common.sh"
# shellcheck disable=SC1091
source "$ROOT/lib/logging.sh"

ensure_dir() {
  printf 'ERROR: load_runtime_config intentó modificar un directorio existente.\n' >&2
  return 91
}

load_runtime_config
[[ "${HEXTUNNEL_TEST_READONLY_CONFIG:-}" == loaded ]]

unset HEXTUNNEL_TEST_READONLY_CONFIG
HEXTUNNEL_ETC="$WORK/missing-etc"
HEXTUNNEL_CONFIG_FILE="$HEXTUNNEL_ETC/hextunnel.env"
ensure_called=0
ensure_dir() {
  local mode="$1" path="$2"
  [[ "$mode" == 700 ]]
  ensure_called=1
  mkdir -p "$path"
}

load_runtime_config
[[ "$ensure_called" == 1 && -d "$HEXTUNNEL_ETC" ]]

printf 'runtime config read-only loading: ok\n'
