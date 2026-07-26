#!/usr/bin/env python3
"""Security preprocessing performed before splitting the legacy installer.

The historical installer embeds one certificate/private-key pair for Hysteria v1.
This migration removes that shared private material and reuses the certificate
that the installer already generated or obtained for Xray on the target VPS.
"""

from __future__ import annotations

import argparse
import re
import subprocess
from pathlib import Path

STATIC_HYSTERIA_TLS = re.compile(
    r"(?ms)^cat << EOF > /etc/hysteria/hysteria\.crt\n.*?^EOF\n\n"
    r"cat << EOF > /etc/hysteria/hysteria\.key\n.*?^EOF\n"
)

REPLACEMENT = """# Reuse the certificate already generated or validated for Xray.
# This avoids distributing the same private key to every installed VPS.
install -m 0644 /etc/xray/xray.crt /etc/hysteria/hysteria.crt
install -m 0600 /etc/xray/xray.key /etc/hysteria/hysteria.key
"""

INSECURE_CHMOD = (
    "chmod 755 /etc/hysteria/config.json /etc/hysteria/hysteria.crt "
    "/etc/hysteria/hysteria.key"
)
SECURE_CHMOD = (
    "chmod 600 /etc/hysteria/config.json /etc/hysteria/hysteria.key\n"
    "chmod 644 /etc/hysteria/hysteria.crt"
)
MARKER = "This avoids distributing the same private key to every installed VPS."


def validate_bash(path: Path) -> None:
    result = subprocess.run(
        ["bash", "-n", str(path)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "bash -n failed")


def migrate(path: Path) -> bool:
    original = path.read_text(encoding="utf-8")
    if MARKER in original:
        validate_bash(path)
        return False

    migrated, count = STATIC_HYSTERIA_TLS.subn(REPLACEMENT, original, count=1)
    if count != 1:
        raise RuntimeError(
            "Could not locate exactly one embedded Hysteria certificate/private-key block"
        )
    if INSECURE_CHMOD not in migrated:
        raise RuntimeError("Could not locate the insecure Hysteria chmod assignment")

    migrated = migrated.replace(INSECURE_CHMOD, SECURE_CHMOD, 1)
    if "-----BEGIN PRIVATE KEY-----" in migrated:
        raise RuntimeError("A PEM private key remains embedded after preprocessing")

    path.write_text(migrated, encoding="utf-8")
    validate_bash(path)
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args()
    installer = args.root.resolve() / "install.sh"
    if not installer.is_file():
        raise RuntimeError(f"Installer not found: {installer}")

    changed = migrate(installer)
    print("Removed embedded Hysteria TLS material." if changed else "Hysteria TLS material already migrated.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=__import__("sys").stderr)
        raise SystemExit(1)
