from __future__ import annotations

import importlib.util
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


ROOT = Path(__file__).resolve().parents[1]
MODULARIZE = load_module("bootstrap_modularize", ROOT / "tools" / "bootstrap_modularize.py")
BUILD = load_module("build_tool", ROOT / "tools" / "build.py")


class ModularizationTests(unittest.TestCase):
    def sample_script(self) -> str:
        token = "123456789:" + "ABCDEFGHIJKLMNOPQRSTUVWXYZ" + "abcdefghi"
        body = [
            "#!/bin/bash\n",
            "set -o pipefail\n",
            "My_Chat_ID='123456789'\n",
            f"My_Bot_Key='{token}'\n",
            "\n",
            "cat << EOF > /etc/hysteria/hysteria.crt\n",
            "-----BEGIN CERTIFICATE-----\ncertificate-body\n-----END CERTIFICATE-----\nEOF\n\n",
            "cat << EOF > /etc/hysteria/hysteria.key\n",
            ("-----BEGIN " + "PRIVATE KEY-----\nprivate-body\n-----END PRIVATE KEY-----\nEOF\n\n"),
        ]
        for index in range(8):
            body.extend(
                [
                    f"section_{index}() {{\n",
                    f"  local value='{index}'\n",
                    "  cat <<'EOF_SAMPLE' >/dev/null\n",
                    "sample\n",
                    "EOF_SAMPLE\n",
                    "  if [[ -n \"$value\" ]]; then\n",
                    "    printf '%s\\n' \"$value\" >/dev/null\n",
                    "  fi\n",
                    "}\n",
                    "\n",
                ]
            )
            body.extend([f"# filler {index}-{line}\n" for line in range(75)])
            body.append("\n")
        body.extend(["section_0\n", "echo \"El servidor se reiniciará en 10 segundos\"\n", "sleep 10\n", "reboot"])
        return "".join(body)

    def prepare_root(self, temp: Path) -> None:
        (temp / "tools").mkdir(parents=True)
        (temp / "config").mkdir()
        (temp / ".gitignore").write_text("config/secrets.env\n.migration-backup/\n", encoding="utf-8")
        for source in ("bootstrap_modularize.py", "build.py", "secret_scan.py"):
            (temp / "tools" / source).write_text((ROOT / "tools" / source).read_text(encoding="utf-8"), encoding="utf-8")
        (temp / "install.sh").write_text(self.sample_script(), encoding="utf-8")

    def test_migration_splits_and_rebuilds(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            self.prepare_root(temp)
            result = subprocess.run(
                ["python3", str(temp / "tools" / "bootstrap_modularize.py"), "--root", str(temp)],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            modules = sorted((temp / "src" / "modules").glob("*.sh"))
            self.assertGreaterEqual(len(modules), 2)
            self.assertEqual(BUILD.load_bundle(temp), (temp / "install.sh").read_text(encoding="utf-8"))
            generated = (temp / "install.sh").read_text(encoding="utf-8")
            self.assertFalse(generated.endswith("\n"))
            self.assertNotIn("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghi", generated)
            self.assertIn("Hex Tunnel debe ejecutarse como root", generated)
            self.assertIn("HEXTUNNEL_NO_REBOOT", generated)
            self.assertIn("Reinicio automático omitido", generated)
            secrets = temp / "config" / "secrets.env"
            self.assertTrue(secrets.exists())
            self.assertEqual(stat.S_IMODE(secrets.stat().st_mode), 0o600)
            syntax = subprocess.run(["bash", "-n", str(temp / "install.sh")], check=False)
            self.assertEqual(syntax.returncode, 0)

    def test_embedded_hysteria_key_is_replaced(self) -> None:
        private_block = "-----BEGIN " + "PRIVATE KEY-----\nprivate-body\n-----END PRIVATE KEY-----\nEOF\n"
        original = (
            "cat << EOF > /etc/hysteria/hysteria.crt\n"
            "-----BEGIN CERTIFICATE-----\ncertificate-body\n-----END CERTIFICATE-----\nEOF\n\n"
            "cat << EOF > /etc/hysteria/hysteria.key\n"
            + private_block
        )
        migrated = MODULARIZE.migrate_hysteria_tls(original)
        self.assertNotIn("BEGIN " + "PRIVATE KEY", migrated)
        self.assertIn("ln -s /etc/xray/xray.crt", migrated)
        self.assertIn("ln -s /etc/xray/xray.key", migrated)

    def test_incomplete_heredoc_is_rejected(self) -> None:
        fragment = "cat <<'EOF_SAMPLE'\nunterminated\n"
        self.assertFalse(MODULARIZE.bash_syntax_ok(fragment))

    def test_split_fragments_are_valid_bash(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            content = MODULARIZE.insert_generated_marker(self.sample_script())
            content = MODULARIZE.migrate_secrets(content, temp)
            modules = MODULARIZE.split_modules(content, temp)
            for module in modules:
                self.assertTrue(MODULARIZE.bash_syntax_ok(module.content), module.path.name)


if __name__ == "__main__":
    unittest.main()
