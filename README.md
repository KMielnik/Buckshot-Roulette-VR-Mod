# Buckshot Roulette VR

An unofficial OpenXR mod that brings **Buckshot Roulette** to PC VR with tracked controllers, walking, fingertip buttons and a steady seated view of the table.

Walk out of the bathroom, kick the doors open and take your place opposite the Dealer. Point to use items and choose shotgun targets. Read the original dialogue in VR, feel recoil, item actions and revival heartbeats, and watch your wrists get cuffed to the rail.

**Tested with Quest 3, Quest controllers and Virtual Desktop on Windows.** Other PC OpenXR headsets use the same controller actions but need hardware testing. Requires the **Steam Windows version 2.2.0.6**. Single-player support. [Compatibility and troubleshooting](docs/compatibility.md).

## Install

1. Install Buckshot Roulette from Steam. Connect your headset to your PC VR runtime and wake both controllers.
2. Download **[Buckshot-Roulette-VR.zip](https://github.com/KMielnik/Buckshot-Roulette-VR-Mod/releases/latest/download/Buckshot-Roulette-VR.zip)** from the [latest release](https://github.com/KMielnik/Buckshot-Roulette-VR-Mod/releases/latest).
3. Extract the ZIP, then double-click **Install.cmd**. The installer finds Steam libraries, verifies the game, downloads the pinned BRMLNeo loader and prepares a separate VR installation. If asked, select the game's executable.
4. Start **Buckshot Roulette VR** from the desktop shortcut. Face forward as the game opens.

Setup uses the PowerShell included with Windows and needs internet access. Allow about 1 GB for each installed version. The installer creates a separate local save profile. [Install, update, settings and uninstall details](docs/install.md).

## Controls

| Action | Control |
|---|---|
| Point and interact | Aim the right index finger, then pull the **right trigger**. Use this for menus, items, shotgun pickup and self/Dealer selection. |
| Walk before reaching the table | **Left stick**. Move close to each door to kick it open. Walk farther into the room to glide to the desk. |
| Turn | **Right stick** left or right for smooth turning. At the table, look and lean physically. |
| Sign the waiver | Click with the pointer or poke a key with the extended **right index**. You can hold the side grip while poking. Withdraw before pressing again. |
| Cash case | Click each latch, or squeeze a side grip near it. The right grip can also operate a latch at pointer distance. Opening both latches starts the ending. |
| Continue after winning | Pull the **right trigger** when the score prompt appears. |
| Pause | **Left Menu / Options** button. With an Index controller profile, **left-stick click** also works. Point and click to resume, change session volume, return to the title or quit. |

The original game decides when actions are allowed. Cuffs temporarily hold the visible hands at the table. The ending follows the case pan, then holds a steady seat and score panel in the car. Head tracking stays active throughout.

## Multiplayer

Version 1.0.3 adds **experimental virtual-screen mode** for multiplayer. The original lobby and match appear on a fixed screen inside the headset. Aim and click with the right trigger. In a match, left Menu opens the native player/disconnect menu; hold right grip and move the pointer for the game's free look. Multiplayer is not paused by that menu.

This is a flat-screen compatibility mode, not immersive multiplayer VR. Local scene, UI, camera and input tests pass; **an online match with a second player has not been verified**. Steam invitations and clipboard lobby codes may still need desktop interaction. See the [multiplayer audit and implementation plan](docs/multiplayer.md).

## Settings and support

World size and vibration strength can be adjusted in the installed version's `override.cfg`. The defaults are `world_size=0.88` and `haptic_strength=1.0`. The full game options are available from the title menu. [Settings](docs/install.md#settings).

For a bug report, include the mod version, game version, headset, controller profile, runtime and steps to reproduce. Attach the relevant part of the log after removing personal paths. Hardware reports from other headsets are welcome. [Report a bug](https://github.com/KMielnik/Buckshot-Roulette-VR-Mod/issues/new?template=bug_report.yml).

## Develop

Use Python 3.11+ to build the release.

```sh
python tools/build.py
python -m unittest discover -s tests -p "test_*.py"
```

Edit `mods-unpacked/TableVR-Bootstrap/`, then rebuild. The Windows installer ZIP is written to `dist/`. The repository also includes a standalone Godot 4.1.1 input fixture and integration tests for an owner's local game copy. Start with [CONTRIBUTING.md](CONTRIBUTING.md), [architecture](docs/architecture.md) and [AGENTS.md](AGENTS.md).

## License and credits

[MIT](LICENSE) for the original mod code and documentation. Buckshot Roulette belongs to Mike Klubnika and its respective rights holders. BRMLNeo and Godot retain their own licenses. This community project is unofficial, unaffiliated and substantially AI-generated, with hands-on testing on Quest 3. [Notices and upstream credits](NOTICE.md).
