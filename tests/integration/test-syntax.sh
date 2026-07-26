#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
while IFS= read -r -d '' file; do
  bash -n "$file"
done < <(find "$ROOT" -type f -name '*.sh' -print0)
printf 'bash syntax: ok\n'
