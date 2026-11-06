# Testing

## Portable checks

Use Python 3.11+.

```sh
python tools/build.py
python -m unittest discover -s tests -p "test_*.py"
```

The package checks enforce exact membership, deterministic output, matching versions and checksums, document links and removal of private paths and abandoned feature references. On Windows, the installer tests use small original fixture files to exercise install/reinstall/update, settings preservation, retry after download failure, integrity checks, destination ownership and ZIP path traversal.

Run the independent input fixture with the official Godot 4.1.1 editor.

```powershell
python tests/fixture.py 'C:\Tools\Godot_v4.1.1-stable_win64_console.exe'
```

The wrapper requires a success marker and rejects script errors. The fixture verifies camera ownership, tracked poses, pointer direction, input rearming, GUI cancellation, turning, scaling and teardown. It uses original geometry and synthetic trackers.

## Local retail checks

These tests require Windows and the owner's unmodified Steam game. They create disposable copies outside the repository, disable Steam startup and use suite-specific QA profiles. The public installer and actual retail executable run during each suite. Test scenarios arrange local game state to reach the behavior under test.

```powershell
$game = 'D:\SteamLibrary\steamapps\common\Buckshot Roulette\Buckshot Roulette_windows'
python tests/retail.py $game --suite walk
python tests/retail.py $game --suite near
python tests/retail.py $game --suite pause
python tests/retail.py $game --suite ending
python tests/retail.py $game --suite dealer
python tests/retail.py $game --suite player
python tests/retail.py $game --suite feedback
python tests/retail.py $game --suite presentation
python tests/retail.py $game --suite heartbeat
```

Use `--loader-zip <archive>` with the pinned BRMLNeo download to avoid fetching it for each suite. Avoid concurrent runs of the same suite because each name owns one QA profile. Profiles use `%APPDATA%\BuckshotVR-QA-<suite>`. They can be removed after testing.

## Headset acceptance

1. From a fresh installation, use Options, Back and Start through the right pointer.
2. Move the head and each controller independently. Lose and restore runtime focus while holding a trigger. A fresh squeeze must be required.
3. Walk through both doors and enter the room. Verify the glide and seated reach. Ordinary item/shotgun camera sockets should keep the desk base steady.
4. Poke waiver keys with a closed grip and extended index. Resting on a key must produce one letter. Test pointer fallback.
5. Use an item, pick up the shotgun and select both targets across eligible turns. Test a blank and a live round.
6. Check readable dialogue, Dealer grading, hover/action haptics, hit effects, blackout and revival heartbeat.
7. Let the dealer use cuffs. Head tracking must continue through restraint and release.
8. Open the two case latches. Confirm the pan, car scale, payout, fresh-trigger continuation and first-win unlock text.
9. Open pause with left Menu, change volume, resume and return to the title. Check the runtime-specific fallback where applicable.

Record the headset, runtime and controller profile with results. Automated tests establish engine behavior. They do not certify comfort, stereo rendering or haptic strength on untested hardware.
