"""Build reproducible, allowlisted mod and Windows installer archives."""

import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MOD = "TableVR-Bootstrap"
RUNTIME_FILES = (
    "manifest.json", "mod_main.gd", "rig.tscn", "hand.gd", "glove.gd",
    "retail_hand.gd", "view_station.gd", "walk_area.gd", "menu_panel.gd",
    "world_pointer.gd", "near_input.gd", "dealer_impact.gd", "player_impact.gd",
    "haptics.gd", "action_feedback.gd", "cuffs.gd", "table_text.gd", "menu_bullets.gd",
    "retail_grade.gd", "finale.gd", "pause_menu.gd", "screen_mode.gd",
)
RELEASE_FILES = {
    "Install.cmd": "installer/Install.cmd",
    "Install.ps1": "installer/Install.ps1",
    "README.md": "docs/install.md",
    "LICENSE": "LICENSE",
    "NOTICE.md": "NOTICE.md",
}


def source_bytes(path):
    text = path.read_text(encoding="utf-8")
    if path.suffix in {".cmd", ".ps1"}:
        text = text.replace("\n", "\r\n")
    return text.encode("utf-8")


def archive_bytes(files):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, content in sorted(files.items()):
            info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            info.external_attr = 0o100644 << 16
            archive.writestr(info, content, compress_type=zipfile.ZIP_DEFLATED)
    return buffer.getvalue()


def build_mod():
    source = ROOT / "mods-unpacked" / MOD
    actual = {path.name for path in source.iterdir() if path.is_file()}
    if actual != set(RUNTIME_FILES):
        raise ValueError("Runtime files differ from the package allowlist.")
    version = (ROOT / "VERSION").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("VERSION must be a release version such as 1.0.2.")
    if json.loads((source / "manifest.json").read_text())["version_number"] != version:
        raise ValueError("VERSION and the mod manifest disagree.")
    return archive_bytes({
        f"mods-unpacked/{MOD}/{name}": source_bytes(source / name)
        for name in RUNTIME_FILES
    })


def build_release(output):
    output.mkdir(parents=True, exist_ok=True)
    mod = build_mod()
    config = json.loads((ROOT / "compatibility.json").read_text())
    config.update(
        version=(ROOT / "VERSION").read_text().strip(),
        mod_file=f"{MOD}.zip",
        mod_sha256=hashlib.sha256(mod).hexdigest(),
    )
    files = {name: source_bytes(ROOT / path) for name, path in RELEASE_FILES.items()}
    files[f"{MOD}.zip"] = mod
    files["release.json"] = (json.dumps(config, indent=2) + "\n").encode()
    release = output / "Buckshot-Roulette-VR.zip"
    release.write_bytes(archive_bytes(files))
    (output / f"{MOD}.zip").write_bytes(mod)
    checksum = hashlib.sha256(release.read_bytes()).hexdigest()
    (output / "SHA256SUMS.txt").write_text(f"{checksum}  {release.name}\n", encoding="ascii")
    print(f"Built {release.name} for {config['version']} with {len(RUNTIME_FILES)} runtime files.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    build_release(args.output)
