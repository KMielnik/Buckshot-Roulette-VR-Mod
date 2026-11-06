"""Public package boundaries, version consistency and reproducibility."""

import hashlib
import io
import json
from pathlib import Path
import re
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import build


class ReleaseTests(unittest.TestCase):
    def test_reproducible_mod_and_exact_membership(self):
        first = build.build_mod()
        self.assertEqual(first, build.build_mod())
        with zipfile.ZipFile(io.BytesIO(first)) as archive:
            expected = {f"mods-unpacked/{build.MOD}/{name}" for name in build.RUNTIME_FILES}
            self.assertEqual(set(archive.namelist()), expected)
            self.assertIsNone(archive.testzip())
            for name in archive.namelist():
                self.assertEqual(archive.read(name), build.source_bytes(ROOT / name))

    def test_installer_archive_and_checksum(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            build.build_release(output)
            first = (output / "Buckshot-Roulette-VR.zip").read_bytes()
            build.build_release(output)
            self.assertEqual(first, (output / "Buckshot-Roulette-VR.zip").read_bytes())
            with zipfile.ZipFile(io.BytesIO(first)) as archive:
                expected = set(build.RELEASE_FILES) | {"release.json", "TableVR-Bootstrap.zip"}
                self.assertEqual(set(archive.namelist()), expected)
                manifest = json.loads(archive.read("release.json"))
                self.assertEqual(manifest["version"], (ROOT / "VERSION").read_text().strip())
                self.assertEqual(hashlib.sha256(archive.read(manifest["mod_file"])).hexdigest(),
                                 manifest["mod_sha256"])
                self.assertEqual(archive.read(manifest["mod_file"]), build.build_mod())
            self.assertTrue((output / "SHA256SUMS.txt").read_text().startswith(hashlib.sha256(first).hexdigest()))

    def test_no_removed_feature_paths_or_private_data(self):
        runtime = ROOT / "mods-unpacked" / build.MOD
        for path in runtime.iterdir():
            text = path.read_text(encoding="utf-8")
            self.assertNotRegex(text.lower(), r"playground|buckshot-hands-on|tablevr-handson")
            self.assertNotRegex(text, r"(?i)[a-z]:[\\/]Users[\\/]|github_pat_|ghp_[A-Za-z0-9]{20}")
        self.assertTrue(all(Path(name).suffix in {".gd", ".tscn", ".json"} for name in build.RUNTIME_FILES))

    def test_local_document_links_exist(self):
        for page in [ROOT / "README.md", ROOT / "CONTRIBUTING.md", *list((ROOT / "docs").glob("*.md"))]:
            for link in re.findall(r"\]\(([^)]+)\)", page.read_text(encoding="utf-8")):
                if "://" in link or link.startswith("#"):
                    continue
                target = link.split("#")[0]
                self.assertTrue((page.parent / target).exists(), f"{page.name}: {link}")


if __name__ == "__main__":
    unittest.main()
