"""Run the fixture and fail on engine script errors, even after a success marker."""

from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
result = subprocess.run(
    [sys.argv[1], "--path", str(root), "--headless", "--xr-mode", "off",
     "--quit-after", "90", "--", "--test-input"],
    capture_output=True, timeout=30,
)
log = (result.stdout + result.stderr).decode("utf-8", errors="replace")
print(log)
sys.exit(0 if result.returncode == 0 and "TABLEVR_TEST_RESULT failures=0" in log
         and "SCRIPT ERROR:" not in log else 1)
