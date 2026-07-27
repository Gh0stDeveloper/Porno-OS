#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$ROOT"
if grep -RIE --exclude-dir=.git --exclude='*.example' --exclude='test-current-tree.sh' \
  '[0-9]{8,12}:[A-Za-z0-9_-]{30,}' .; then
  echo 'Telegram token embedded in current tree' >&2
  exit 1
fi
if grep -RIE --exclude-dir=.git --exclude='test-current-tree.sh' -- \
  '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' .; then
  echo 'Private key embedded in current tree' >&2
  exit 1
fi
if find . -path './legacy' -prune -o -type f -name '*.py' -print | grep -q .; then
  echo 'Python generators are not allowed in the maintained architecture' >&2
  exit 1
fi
printf 'current-tree security checks: ok\n'
