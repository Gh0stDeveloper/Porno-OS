#!/usr/bin/env python3
"""One-time, conservative migration from the monolithic installer to modules.

The generated root install.sh remains a standalone bundle for compatibility with
curl/wget | bash. Maintainers edit src/modules/*.sh and rebuild the bundle with
tools/build.py.
"""

from __future__ import annotations

import argparse
import os
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

MIN_LINES = 220
TARGET_LINES = 380
MAX_PREFERRED_LINES = 620

CHAT_RE = re.compile(r"(?m)^My_Chat_ID=(?P<quote>['\"])(?P<value>.*?)(?P=quote)\s*$")
TOKEN_RE = re.compile(r"(?m)^My_Bot_Key=(?P<quote>['\"])(?P<value>.*?)(?P=quote)\s*$")
GENERATED_MARKER = "# GENERATED FILE: edit src/modules/*.sh and run python3 tools/build.py"

HYSTERIA_EMBEDDED_TLS_RE = re.compile(
    r"(?ms)^cat\s+<<\s*EOF\s*>\s*/etc/hysteria/hysteria\.crt\s*\n"
    r".*?^EOF\s*\n\s*"
    r"^cat\s+<<\s*EOF\s*>\s*/etc/hysteria/hysteria\.key\s*\n"
    r".*?^EOF\s*\n"
)

HYSTERIA_TLS_LINKS = r'''# Reuse the per-server Xray certificate instead of a shared embedded key.
rm -f /etc/hysteria/hysteria.crt /etc/hysteria/hysteria.key
ln -s /etc/xray/xray.crt /etc/hysteria/hysteria.crt
ln -s /etc/xray/xray.key /etc/hysteria/hysteria.key
'''

RUNTIME_SAFETY = r'''# Runtime safety controls. These checks fail before the installer modifies the VPS.
HEXTUNNEL_NO_REBOOT="${HEXTUNNEL_NO_REBOOT:-0}"
for _hextunnel_arg in "$@"; do
  case "$_hextunnel_arg" in
    --no-reboot) HEXTUNNEL_NO_REBOOT=1 ;;
  esac
done
unset _hextunnel_arg

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "ERROR: Hex Tunnel debe ejecutarse como root." >&2
  exit 1
fi
if [[ ! -r /etc/os-release ]]; then
  echo "ERROR: No se pudo leer /etc/os-release." >&2
  exit 1
fi
if ! command -v systemctl >/dev/null 2>&1; then
  echo "ERROR: Este instalador requiere systemd/systemctl." >&2
  exit 1
fi

_hextunnel_free_kb="$(df -Pk / 2>/dev/null | awk 'NR==2 {print $4}')"
if [[ "$_hextunnel_free_kb" =~ ^[0-9]+$ ]] && (( _hextunnel_free_kb < 1048576 )); then
  echo "ADVERTENCIA: hay menos de 1 GiB libre en la partición raíz." >&2
fi
unset _hextunnel_free_kb
'''

FINAL_REBOOT_RE = re.compile(
    r'(?m)^echo "(?P<message>[^"\n]*reiniciar[^"\n]*|[^"\n]*reiniciará[^"\n]*)"\s*\n'
    r'sleep 10\s*\nreboot\s*$'
)

SECRET_LOADER = r'''# Telegram notification credentials are loaded from environment variables or
# a local secrets file. config/secrets.env is intentionally ignored by Git.
HEXTUNNEL_SECRETS_FILE="${HEXTUNNEL_SECRETS_FILE:-/etc/hextunnel/secrets.env}"
if [[ ! -f "$HEXTUNNEL_SECRETS_FILE" && -n "${BASH_SOURCE[0]:-}" ]]; then
  _hextunnel_source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P || true)"
  if [[ -n "$_hextunnel_source_dir" && -f "$_hextunnel_source_dir/config/secrets.env" ]]; then
    HEXTUNNEL_SECRETS_FILE="$_hextunnel_source_dir/config/secrets.env"
  fi
fi
if [[ -f "$HEXTUNNEL_SECRETS_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$HEXTUNNEL_SECRETS_FILE"
fi
My_Chat_ID="${HEXTUNNEL_TELEGRAM_CHAT_ID:-}"
My_Bot_Key="${HEXTUNNEL_TELEGRAM_BOT_TOKEN:-}"
unset _hextunnel_source_dir
'''


@dataclass(frozen=True)
class Module:
    path: Path
    content: str


def run(command: list[str], *, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def require_tool(name: str) -> None:
    if shutil.which(name) is None:
        raise RuntimeError(f"Required command not found: {name}")


def bash_syntax_ok(content: str) -> bool:
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".sh", delete=False) as handle:
        handle.write(content)
        temp_path = Path(handle.name)
    try:
        result = run(["bash", "-n", str(temp_path)])
        stderr = result.stderr.lower()
        incomplete_heredoc = "here-document" in stderr and "delimited by end-of-file" in stderr
        return result.returncode == 0 and not incomplete_heredoc
    finally:
        temp_path.unlink(missing_ok=True)


def insert_generated_marker(content: str) -> str:
    if GENERATED_MARKER in content:
        return content
    lines = content.splitlines(keepends=True)
    if lines and lines[0].startswith("#!"):
        lines.insert(1, GENERATED_MARKER + "\n")
    else:
        lines.insert(0, GENERATED_MARKER + "\n")
    return "".join(lines)


def insert_runtime_safety(content: str) -> str:
    if "HEXTUNNEL_NO_REBOOT=" in content and "Hex Tunnel debe ejecutarse como root" in content:
        return content
    marker = GENERATED_MARKER + "\n"
    position = content.find(marker)
    if position < 0:
        raise RuntimeError("Generated marker must be inserted before runtime safety controls")
    position += len(marker)
    return content[:position] + RUNTIME_SAFETY.rstrip("\n") + "\n" + content[position:]


def migrate_final_reboot(content: str) -> str:
    if "Reinicio automático omitido" in content:
        return content

    match = FINAL_REBOOT_RE.search(content)
    if not match:
        raise RuntimeError("Could not locate the final automatic reboot block")

    message = match.group("message")
    replacement = (
        'if [[ "$HEXTUNNEL_NO_REBOOT" == "1" ]]; then\n'
        '  echo "Reinicio automático omitido (--no-reboot / HEXTUNNEL_NO_REBOOT=1)."\n'
        'else\n'
        f'  echo "{message}"\n'
        '  sleep 10\n'
        '  reboot\n'
        'fi'
    )
    suffix = content[match.end() :]
    if content.endswith("\n") and not replacement.endswith("\n") and not suffix:
        replacement += "\n"
    return content[: match.start()] + replacement + suffix


def migrate_hysteria_tls(content: str) -> str:
    if "Reuse the per-server Xray certificate" in content:
        return content
    match = HYSTERIA_EMBEDDED_TLS_RE.search(content)
    if not match:
        raise RuntimeError("Could not locate the embedded Hysteria certificate and private key")
    replacement = HYSTERIA_TLS_LINKS.rstrip("\n") + "\n"
    migrated = content[: match.start()] + replacement + content[match.end() :]
    private_key_marker = "-----BEGIN " + "PRIVATE KEY-----"
    if private_key_marker in migrated:
        raise RuntimeError("A private key marker remained after Hysteria TLS migration")
    return migrated


def migrate_secrets(content: str, root: Path) -> str:
    chat_match = CHAT_RE.search(content)
    token_match = TOKEN_RE.search(content)

    if not chat_match and not token_match:
        if "HEXTUNNEL_TELEGRAM_BOT_TOKEN" in content:
            return content
        raise RuntimeError("Could not locate the Telegram credential assignments in install.sh")
    if not chat_match or not token_match:
        raise RuntimeError("Only one Telegram credential assignment was found; refusing a partial migration")

    secrets_dir = root / "config"
    secrets_dir.mkdir(parents=True, exist_ok=True)
    local_secrets = secrets_dir / "secrets.env"
    if not local_secrets.exists():
        local_secrets.write_text(
            "# Local migration copy. Do not commit this file.\n"
            f"HEXTUNNEL_TELEGRAM_CHAT_ID={shlex.quote(chat_match.group('value'))}\n"
            f"HEXTUNNEL_TELEGRAM_BOT_TOKEN={shlex.quote(token_match.group('value'))}\n",
            encoding="utf-8",
        )
        os.chmod(local_secrets, stat.S_IRUSR | stat.S_IWUSR)

    ordered = sorted((chat_match, token_match), key=lambda match: match.start())
    first, second = ordered
    migrated = (
        content[: first.start()]
        + SECRET_LOADER.rstrip("\n")
        + content[first.end() : second.start()]
        + content[second.end() :]
    )

    if chat_match.group("value") in migrated or token_match.group("value") in migrated:
        raise RuntimeError("Secret values remained in the sanitized installer")
    return migrated


def candidate_boundaries(lines: list[str]) -> list[int]:
    boundaries = {len(lines)}
    function_start = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*\s*\(\)\s*\{")
    section_comment = re.compile(r"^#\s*(?:={3,}|-{3,}|[A-Z][A-Z0-9 /&+_.()-]{5,})")

    for index in range(1, len(lines)):
        previous = lines[index - 1]
        current = lines[index]
        if previous.strip() == "":
            boundaries.add(index)
        if function_start.match(current) or section_comment.match(current):
            boundaries.add(index)
    return sorted(boundaries)


def choose_boundary(lines: list[str], start: int, candidates: list[int]) -> int:
    total = len(lines)
    if total - start <= MAX_PREFERRED_LINES:
        if not bash_syntax_ok("".join(lines[start:])):
            raise RuntimeError(f"Final fragment beginning at line {start + 1} is not valid Bash")
        return total

    target = start + TARGET_LINES
    preferred = [
        end
        for end in candidates
        if start + MIN_LINES <= end <= min(total, start + MAX_PREFERRED_LINES)
    ]
    preferred.sort(key=lambda end: (abs(end - target), end))

    for end in preferred:
        if bash_syntax_ok("".join(lines[start:end])):
            return end

    extended = [end for end in candidates if end > start + MAX_PREFERRED_LINES]
    for end in extended:
        if bash_syntax_ok("".join(lines[start:end])):
            return end

    raise RuntimeError(f"Unable to find a safe module boundary after line {start + 1}")


def module_slug(content: str, fallback_number: int) -> str:
    lowered = content.lower()
    keyword_map: list[tuple[str, tuple[str, ...]]] = [
        ("bootstrap", ("support_level", "validar_key_hextunnel", "sistemas operativos soportados")),
        ("certificates", ("letsencrypt", "certbot", "xray.crt")),
        ("packages", ("package_list", "available_packages", "apt-get install")),
        ("ssh", ("# openssh", "sshd_config", "permitrootlogin")),
        ("proxies", ("# sslh", "ws-proxy", "stunnel.conf", "squid")),
        ("xray", ("xray core", "/etc/xray/config.json", "xray-install-version")),
        ("health", ("health checks", "service_checker", "restart_after_3_fails")),
        ("slowdns", ("slowdns", "server-sldns")),
        ("slipstream", ("slipstream", "dnsdist")),
        ("hysteria", ("hysteria v1", "hysteria-server")),
        ("hysteria2", ("hysteria 2", "hysteria2-server")),
        ("udp", ("udp custom", "udp-custom")),
        ("zivpn", ("zivpn",)),
        ("accounts", ("gestión de cuentas", "add_xray", "renew_xray", "del_xray")),
        ("backup", ("backup_snapshot", "restore_snapshot", "respaldo")),
        ("menu", ("utilities_menu", "advanced_menu", "main menu", "opción:")),
        ("finalize", ("instalación completa", "reboot")),
    ]
    for slug, needles in keyword_map:
        if any(needle in lowered for needle in needles):
            return slug
    return f"section-{fallback_number:02d}"


def split_modules(content: str, root: Path) -> list[Module]:
    lines = content.splitlines(keepends=True)
    candidates = candidate_boundaries(lines)
    modules: list[Module] = []
    used_names: dict[str, int] = {}
    start = 0
    index = 0

    while start < len(lines):
        end = choose_boundary(lines, start, candidates)
        chunk = "".join(lines[start:end])
        base_slug = module_slug(chunk, index)
        occurrence = used_names.get(base_slug, 0)
        used_names[base_slug] = occurrence + 1
        slug = base_slug if occurrence == 0 else f"{base_slug}-{occurrence + 1}"
        path = root / "src" / "modules" / f"{index:02d}-{slug}.sh"
        modules.append(Module(path=path, content=chunk))
        start = end
        index += 1

    if len(modules) < 2:
        raise RuntimeError("The installer was not split into multiple modules")
    if "".join(module.content for module in modules) != content:
        raise RuntimeError("Module concatenation does not reproduce the sanitized installer")
    return modules


def write_modules(modules: Iterable[Module], root: Path) -> None:
    module_dir = root / "src" / "modules"
    if module_dir.exists():
        shutil.rmtree(module_dir)
    module_dir.mkdir(parents=True, exist_ok=True)

    manifest_lines: list[str] = []
    for module in modules:
        module.path.write_text(module.content, encoding="utf-8")
        os.chmod(module.path, 0o644)
        manifest_lines.append(module.path.relative_to(root).as_posix())

    manifest = root / "src" / "manifest.txt"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")


def create_backup(root: Path, original: str) -> None:
    backup_dir = root / ".migration-backup"
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup = backup_dir / "install.sh"
    if not backup.exists():
        backup.write_text(original, encoding="utf-8")
        os.chmod(backup, stat.S_IRUSR | stat.S_IWUSR)


def verify_gitignore(root: Path) -> None:
    gitignore = root / ".gitignore"
    if not gitignore.exists() or "config/secrets.env" not in gitignore.read_text(encoding="utf-8"):
        raise RuntimeError(".gitignore must exclude config/secrets.env before migration")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    root = args.root.resolve()
    installer = root / "install.sh"
    manifest = root / "src" / "manifest.txt"

    require_tool("bash")
    verify_gitignore(root)

    if manifest.exists() and not args.force:
        result = run([sys.executable, str(root / "tools" / "build.py"), "--check", "--root", str(root)])
        if result.returncode == 0:
            print("Repository is already modularized; build is reproducible.")
            return 0
        raise RuntimeError(result.stderr or result.stdout or "Existing modular build is inconsistent")

    if not installer.exists():
        raise RuntimeError(f"Installer not found: {installer}")

    original = installer.read_text(encoding="utf-8")
    if not bash_syntax_ok(original):
        raise RuntimeError("The original install.sh does not pass bash -n; refusing migration")

    create_backup(root, original)
    sanitized = migrate_secrets(original, root)
    sanitized = migrate_hysteria_tls(sanitized)
    sanitized = insert_generated_marker(sanitized)
    sanitized = insert_runtime_safety(sanitized)
    sanitized = migrate_final_reboot(sanitized)
    if not bash_syntax_ok(sanitized):
        raise RuntimeError("The sanitized installer does not pass bash -n")

    modules = split_modules(sanitized, root)
    write_modules(modules, root)

    build_result = run([sys.executable, str(root / "tools" / "build.py"), "--root", str(root)])
    if build_result.returncode != 0:
        raise RuntimeError(build_result.stderr or build_result.stdout or "Build failed")

    check_result = run([sys.executable, str(root / "tools" / "build.py"), "--check", "--root", str(root)])
    if check_result.returncode != 0:
        raise RuntimeError(check_result.stderr or check_result.stdout or "Reproducibility check failed")

    scan_result = run([sys.executable, str(root / "tools" / "secret_scan.py"), "--root", str(root)])
    if scan_result.returncode != 0:
        raise RuntimeError(scan_result.stderr or scan_result.stdout or "Secret scan failed")

    print(f"Created {len(modules)} modules under src/modules/.")
    print("Migrated Telegram values to ignored config/secrets.env with mode 600.")
    print("Regenerated standalone install.sh from the modular source.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
