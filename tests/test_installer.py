"""Exercise the shipped PowerShell installer using original tiny test files."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import build


@unittest.skipUnless(os.name == "nt", "Windows PowerShell installer")
class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="BuckshotVR-installer-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.game = self.root / "Steam Game"
        self.game.mkdir()
        self.destination = self.root / "VR install"
        build.build_release(self.root / "dist")
        self.release = self.root / "release"
        with zipfile.ZipFile(self.root / "dist/Buckshot-Roulette-VR.zip") as archive:
            archive.extractall(self.release)
        self.config = json.loads((self.release / "release.json").read_text())
        for name in self.config["game_files"]:
            content = ("original installer test " + name).encode()
            (self.game / name).write_bytes(content)
            self.config["game_files"][name] = hashlib.sha256(content).hexdigest()
        self.loader = self.root / "loader.zip"
        self.make_loader()

    def make_loader(self, extra=None):
        prefix = "BRMLNeo-" + self.config["loader"]["revision"] + "/"
        with zipfile.ZipFile(self.loader, "w") as archive:
            archive.writestr(prefix + "override.cfg", "[application]\n[autoload]\n")
            archive.writestr(prefix + "addons/test.gd", "# Original installer fixture\n")
            archive.writestr(prefix + "godot/uid_cache.bin", b"fixture")
            if extra:
                archive.writestr(prefix + extra, b"must not escape")
        self.config["loader"]["sha256"] = hashlib.sha256(self.loader.read_bytes()).hexdigest()
        self.write_config()

    def write_config(self):
        (self.release / "release.json").write_text(json.dumps(self.config), encoding="utf-8")

    def install(self, success=True, destination=None):
        result = subprocess.run(
            ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
             "-File", str(self.release / "Install.ps1"), "-GamePath", str(self.game),
             "-Destination", str(destination or self.destination), "-LoaderArchive", str(self.loader),
             "-NoShortcut"],
            capture_output=True, timeout=35,
            env={key: value for key, value in os.environ.items() if key.upper() != "PSMODULEPATH"},
        )
        log = (result.stdout + result.stderr).decode(errors="replace")
        self.assertEqual(result.returncode == 0, success, log)
        return log

    def test_install_repeat_and_update_preserve_settings(self):
        original = {file.name: file.read_bytes() for file in self.game.iterdir()}
        self.install()
        self.install()
        first = self.destination / "versions" / self.config["version"]
        config = first / "override.cfg"
        config.write_text(config.read_text().replace("world_size=0.88", "world_size=0.92"))
        self.config["version"] = "2.0.0"
        self.write_config()
        self.install()
        second = self.destination / "versions/2.0.0"
        self.assertIn("world_size=0.92", (second / "override.cfg").read_text())
        self.assertIn('cd /d "%~dp0versions\\2.0.0"', (self.destination / "Start Buckshot VR.cmd").read_text())
        self.assertTrue(first.exists())
        self.assertEqual(original, {file.name: file.read_bytes() for file in self.game.iterdir()})

    def test_invalid_download_can_be_retried(self):
        correct = self.loader.read_bytes()
        self.loader.write_bytes(b"bad download")
        self.install(success=False)
        self.assertFalse((self.destination / "Start Buckshot VR.cmd").exists())
        self.loader.write_bytes(correct)
        self.install()

    def test_rejects_tampered_game_and_mod(self):
        executable = self.game / "Buckshot Roulette.exe"
        original = executable.read_bytes()
        executable.write_bytes(b"unsupported game")
        self.install(success=False)
        self.assertFalse(self.destination.exists())
        executable.write_bytes(original)
        (self.release / self.config["mod_file"]).write_bytes(b"tampered mod")
        self.install(success=False)
        self.assertFalse(self.destination.exists())

    def test_rejects_game_tree_and_unowned_destination(self):
        self.install(success=False, destination=self.game / "VR")
        self.destination.mkdir()
        sentinel = self.destination / "keep.txt"
        sentinel.write_text("user data")
        self.install(success=False)
        self.assertEqual(sentinel.read_text(), "user data")

    def test_rejects_loader_path_traversal(self):
        self.make_loader("addons/../../../escaped.txt")
        self.install(success=False)
        self.assertFalse((self.root / "escaped.txt").exists())
        self.assertFalse((self.destination / "Start Buckshot VR.cmd").exists())


if __name__ == "__main__":
    unittest.main()
