#!/usr/bin/env python3
"""Small dependency-free secret scanner for tracked project files."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("Telegram bot token", re.compile(r"\b\d{8,12}:[A-Za-z0-9_-]{30,}\b")),
    ("GitHub token", re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b")),
    ("GitHub fine-grained token", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{40,}\b")),
    ("AWS access key", re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")),
    ("Private key", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")),
    (
        "Hardcoded Telegram assignment",
        re.compile(r"(?m)^(?:My_Bot_Key|HEXTUNNEL_TELEGRAM_BOT_TOKEN)\s*=\s*['\"][^$<{][^'\"\n]{20,}['\"]\s*$"),
    ),
)

SKIP_SUFFIXES = {".png", ".jpg", ".jpeg", ".gif", ".zip", ".gz", ".tar", ".deb", ".so"}
SKIP_NAMES = {"secrets.env", "install.sh"}  # install.sh is generated and checked through modules.


def tracked_files(root: Path) -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "-co", "--exclude-standard", "-z"],
        cwd=root,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if result.returncode == 0 and result.stdout:
        return [root / item.decode("utf-8") for item in result.stdout.split(b"\0") if item]

    ignored_parts = {".git", ".migration-backup", "__pycache__", ".pytest_cache"}
    return [
        path
        for path in root.rglob("*")
        if path.is_file() and not ignored_parts.intersection(path.relative_to(root).parts)
    ]


def line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    root = args.root.resolve()

    findings: list[str] = []
    for path in tracked_files(root):
        relative = path.relative_to(root)
        if path.name in SKIP_NAMES or path.suffix.lower() in SKIP_SUFFIXES:
            continue
        if path.name.endswith(".example") or "fixtures" in relative.parts:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for label, pattern in PATTERNS:
            for match in pattern.finditer(text):
                findings.append(f"{relative}:{line_number(text, match.start())}: {label}")

    if findings:
        print("Potential secrets detected:", file=sys.stderr)
        for finding in findings:
            print(f"  {finding}", file=sys.stderr)
        return 1

    print("No tracked secrets detected by local patterns.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
