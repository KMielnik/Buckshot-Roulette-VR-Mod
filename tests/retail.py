"""Run a suite on a disposable, offline copy of the owner's installed game."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from build import MOD, build_release

SUITES = {
    "walk": ("retail_walk.gd", "WALK_QA"),
    "dealer": ("retail_dealer.gd", "DEALER_QA"),
    "player": ("retail_player_impact.gd", "PLAYER_QA"),
    "feedback": ("retail_feedback.gd", "FEEDBACK_QA"),
    "presentation": ("retail_presentation.gd", "UI_QA"),
    "heartbeat": ("retail_heartbeat.gd", "HEART_QA"),
    "ending": ("retail_finale.gd", "FINALE_QA"),
    "pause": ("retail_pause.gd", "PAUSE_QA"),
    "near": ("retail_near.gd", "NEAR_QA"),
}


def run(game, loader, suite):
    if os.name != "nt":
        raise SystemExit("Local retail testing requires Windows.")
    script, marker = SUITES[suite]
    with tempfile.TemporaryDirectory(prefix=f"BuckshotVR-{suite}-") as scratch:
        scratch = Path(scratch)
        build_release(scratch / "dist")
        release = scratch / "release"
        with zipfile.ZipFile(scratch / "dist/Buckshot-Roulette-VR.zip") as package:
            package.extractall(release)
        destination = scratch / "installed"
        command = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
                   "-File", str(release / "Install.ps1"), "-GamePath", str(game),
                   "-Destination", str(destination), "-NoShortcut"]
        if loader:
            command.extend(["-LoaderArchive", str(loader.resolve())])
        # Match Install.cmd's Windows PowerShell environment even when this
        # Python process was launched from PowerShell 7.
        environment = {key: value for key, value in os.environ.items() if key.upper() != "PSMODULEPATH"}
        installed = subprocess.run(command, capture_output=True, timeout=150, env=environment)
        if installed.returncode:
            print(installed.stdout.decode(errors="replace"))
            print(installed.stderr.decode(errors="replace"))
            return False
        version = (ROOT / "VERSION").read_text().strip()
        stage = destination / "versions" / version
        config = stage / "override.cfg"
        settings = config.read_text(encoding="utf-8").replace(
            'config/custom_user_dir_name="BuckshotRouletteVR"',
            f'config/custom_user_dir_name="BuckshotVR-QA-{suite}"')
        settings = settings.replace(
            '[autoload]', '[autoload]\nGlobalSteam="*res://tests/offline_steam.gd"')
        config.write_text(settings, encoding="utf-8")
        manifest = json.loads((ROOT / "mods-unpacked" / MOD / "manifest.json").read_text())
        manifest.update(namespace="Local", name="RetailQA", dependencies=[MOD])
        with zipfile.ZipFile(stage / "mods/Local-RetailQA.zip", "w") as probe:
            probe.writestr("mods-unpacked/Local-RetailQA/manifest.json", json.dumps(manifest))
            probe.write(ROOT / "tests" / script, "mods-unpacked/Local-RetailQA/mod_main.gd")
        # Autoloads resolve before the mod loader mounts ZIPs.
        (stage / "tests").mkdir()
        (stage / "tests/offline_steam.gd").write_bytes((ROOT / "tests/offline_steam.gd").read_bytes())
        proc = subprocess.run(
            [str(stage / "Buckshot Roulette.exe"), "--headless", "--xr-mode", "off",
             *(["--max-fps", "120"] if suite == "heartbeat" else ["--fixed-fps", "90"]),
             "--quit-after", "9000", "--", "--buckshot-vr"], cwd=stage,
            capture_output=True, timeout=100,
        )
        log = (proc.stdout + proc.stderr).decode("utf-8", errors="replace")
        for line in log.splitlines():
            if line.startswith((marker + " ", "SCRIPT ERROR:", "SHADER ERROR:")):
                print(line)
        passed = proc.returncode == 0 and marker + " failures=0" in log and "SCRIPT ERROR:" not in log
        if not passed and marker not in log:
            print(log[-4000:])
        return passed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game_dir", type=Path)
    parser.add_argument("--loader-zip", type=Path)
    parser.add_argument("--suite", choices=SUITES, default="walk")
    args = parser.parse_args()
    sys.exit(0 if run(args.game_dir, args.loader_zip, args.suite) else 1)
