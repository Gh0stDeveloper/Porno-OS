#!/usr/bin/env python3
"""Build or verify the standalone installer from src/manifest.txt."""

from __future__ import annotations

import argparse
import os
import sys
import tempfile
from pathlib import Path


def load_bundle(root: Path) -> str:
    manifest = root / "src" / "manifest.txt"
    if not manifest.exists():
        raise RuntimeError(f"Manifest not found: {manifest}")

    paths = [line.strip() for line in manifest.read_text(encoding="utf-8").splitlines() if line.strip()]
    if not paths:
        raise RuntimeError("Module manifest is empty")

    chunks: list[str] = []
    for relative in paths:
        path = (root / relative).resolve()
        try:
            path.relative_to(root.resolve())
        except ValueError as exc:
            raise RuntimeError(f"Manifest path escapes repository: {relative}") from exc
        if not path.is_file():
            raise RuntimeError(f"Module not found: {relative}")
        chunks.append(path.read_text(encoding="utf-8"))
    return "".join(chunks)


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp_name, 0o755)
        os.replace(temp_name, path)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    root = args.root.resolve()
    output = (args.output or (root / "install.sh")).resolve()
    bundle = load_bundle(root)

    if args.check:
        if not output.exists():
            print(f"Generated installer missing: {output}", file=sys.stderr)
            return 1
        existing = output.read_text(encoding="utf-8")
        if existing != bundle:
            print("install.sh is out of date; run python3 tools/build.py", file=sys.stderr)
            return 1
        print("install.sh matches src/modules.")
        return 0

    atomic_write(output, bundle)
    print(f"Built {output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
