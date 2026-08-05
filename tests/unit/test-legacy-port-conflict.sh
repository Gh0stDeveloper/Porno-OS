#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck disable=SC1091
source "$ROOT/modules/legacy-all.sh"

sshd_owner='LISTEN 0 4096 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=2761,fd=3))'
systemd_owner='LISTEN 0 4096 0.0.0.0:22 0.0.0.0:* users:(("systemd",pid=1,fd=100))'
combined_owner='LISTEN 0 4096 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=2761,fd=3),("systemd",pid=1,fd=100))'
resolved_owner='UNCONN 0 0 127.0.0.53:53 0.0.0.0:* users:(("systemd-resolve",pid=738,fd=14))
UNCONN 0 0 127.0.0.54:53 0.0.0.0:* users:(("systemd-resolve",pid=738,fd=16))'

legacy_all_allow_port_conflict tcp 22 "$sshd_owner"
legacy_all_allow_port_conflict tcp 22 "$systemd_owner"
legacy_all_allow_port_conflict tcp 22 "$combined_owner"
legacy_all_allow_port_conflict tcp 299 "$sshd_owner"
legacy_all_allow_port_conflict udp 53 "$resolved_owner"

if legacy_all_allow_port_conflict tcp 22 'users:(("nginx",pid=10,fd=3))'; then
  echo 'tcp/22 no debe aceptarse cuando el propietario no es OpenSSH/systemd' >&2
  exit 1
fi

mixed_ssh_owner="$sshd_owner
LISTEN 0 4096 127.0.0.1:22 0.0.0.0:* users:((\"nginx\",pid=10,fd=3))"
if legacy_all_allow_port_conflict tcp 22 "$mixed_ssh_owner"; then
  echo 'tcp/22 no debe ocultar un listener ajeno detrás de OpenSSH' >&2
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

if legacy_all_allow_port_conflict udp 53 'UNCONN 0 0 0.0.0.0:53 0.0.0.0:* users:(("systemd-resolve",pid=738,fd=14))'; then
  echo 'udp/53 wildcard no debe aceptarse aunque pertenezca a systemd-resolved' >&2
  exit 1
fi

if legacy_all_allow_port_conflict udp 53 'UNCONN 0 0 127.0.0.53:53 0.0.0.0:* users:(("dnsmasq",pid=900,fd=5))'; then
  echo 'udp/53 loopback no debe aceptarse para procesos ajenos a systemd-resolved' >&2
  exit 1
fi

mixed_dns_owner="$resolved_owner
UNCONN 0 0 10.0.0.121:53 0.0.0.0:* users:((\"dnsmasq\",pid=900,fd=5))"
if legacy_all_allow_port_conflict udp 53 "$mixed_dns_owner"; then
  echo 'udp/53 no debe ocultar un listener público ajeno detrás de systemd-resolved' >&2
  exit 1
fi

printf 'legacy OpenSSH and systemd-resolved port conflicts: ok\n'
