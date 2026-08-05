#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck disable=SC1091
source "$ROOT/modules/legacy-all.sh"

sshd_owner='LISTEN 0 4096 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=2761,fd=3))'
systemd_owner='LISTEN 0 4096 0.0.0.0:22 0.0.0.0:* users:(("systemd",pid=1,fd=100))'
combined_owner='LISTEN 0 4096 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=2761,fd=3),("systemd",pid=1,fd=100))'

legacy_all_allow_port_conflict tcp 22 "$sshd_owner"
legacy_all_allow_port_conflict tcp 22 "$systemd_owner"
legacy_all_allow_port_conflict tcp 22 "$combined_owner"
legacy_all_allow_port_conflict tcp 299 "$sshd_owner"

if legacy_all_allow_port_conflict tcp 22 'users:(("nginx",pid=10,fd=3))'; then
  echo 'tcp/22 no debe aceptarse cuando el propietario no es OpenSSH/systemd' >&2
  exit 1
fi

if legacy_all_allow_port_conflict tcp 443 "$sshd_owner"; then
  echo 'la excepción no debe aplicarse a tcp/443' >&2
  exit 1
fi

if legacy_all_allow_port_conflict udp 22 "$sshd_owner"; then
  echo 'la excepción no debe aplicarse a udp/22' >&2
  exit 1
fi

printf 'legacy OpenSSH port conflict: ok\n'
