#!/usr/bin/env python3
"""Harden Hysteria TLS handling in an already modularized installer."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

LEGACY_LINK_BLOCK = """# Reuse the per-server Xray certificate instead of a shared embedded key.
rm -f /etc/hysteria/hysteria.crt /etc/hysteria/hysteria.key
ln -s /etc/xray/xray.crt /etc/hysteria/hysteria.crt
ln -s /etc/xray/xray.key /etc/hysteria/hysteria.key
"""

HARDENED_COPY_BLOCK = """# Reuse the per-server Xray certificate instead of a shared embedded key.
# Copies avoid permission changes propagating through symbolic links.
install -m 0644 /etc/xray/xray.crt /etc/hysteria/hysteria.crt
install -m 0600 /etc/xray/xray.key /etc/hysteria/hysteria.key
"""

INSECURE_MODE = (
    "chmod 755 /etc/hysteria/config.json /etc/hysteria/hysteria.crt "
    "/etc/hysteria/hysteria.key"
)
SECURE_MODE = (
    "chmod 600 /etc/hysteria/config.json /etc/hysteria/hysteria.key\n"
    "chmod 644 /etc/hysteria/hysteria.crt"
)


def run(command: list[str], root: Path) -> None:
    result = subprocess.run(
        command,
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())


def harden(root: Path) -> bool:
    manifest = root / "src" / "manifest.txt"
    if not manifest.is_file():
        raise RuntimeError("src/manifest.txt does not exist")

    paths = [
        root / line.strip()
        for line in manifest.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    changed = False
    link_replacements = 0
    mode_replacements = 0

    for path in paths:
        text = path.read_text(encoding="utf-8")
        if LEGACY_LINK_BLOCK in text:
            text = text.replace(LEGACY_LINK_BLOCK, HARDENED_COPY_BLOCK, 1)
            link_replacements += 1
            changed = True
        if INSECURE_MODE in text:
            text = text.replace(INSECURE_MODE, SECURE_MODE, 1)
            mode_replacements += 1
            changed = True
        path.write_text(text, encoding="utf-8")

    already_hardened = any(
        HARDENED_COPY_BLOCK in path.read_text(encoding="utf-8")
        and SECURE_MODE in path.read_text(encoding="utf-8")
        for path in paths
    )
    if not changed and already_hardened:
        return False
    if link_replacements != 1 or mode_replacements != 1:
        raise RuntimeError(
            "Expected exactly one Hysteria TLS block and one insecure permission assignment; "
            f"found links={link_replacements}, modes={mode_replacements}"
        )

    run([sys.executable, "tools/build.py", "--root", str(root)], root)
    run([sys.executable, "tools/build.py", "--check", "--root", str(root)], root)
    run(["bash", "-n", "install.sh"], root)
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args()
    root = args.root.resolve()
    changed = harden(root)
    print("Hardened generated Hysteria TLS source." if changed else "Generated Hysteria TLS source already hardened.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
