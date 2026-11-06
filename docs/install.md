# Install Buckshot Roulette VR

## Requirements

- Windows, an installed Steam copy of Buckshot Roulette **2.2.0.6**, and a Vulkan-capable PC VR setup.
- A working PC OpenXR runtime and two tracked controllers.
- Internet access during setup to fetch the pinned BRMLNeo loader.
- About 1 GB of free space per installed version.

Quest 3 with Virtual Desktop is the tested setup. Select the OpenXR runtime for your headset before starting the mod. Other headsets and connection methods need hardware testing.

## First installation

1. Extract every file from **Buckshot-Roulette-VR.zip** into a folder.
2. Close the game, then double-click **Install.cmd**.
3. The installer searches your Steam libraries. If selection is needed, choose `Buckshot Roulette.exe` under `Buckshot Roulette_windows`.
4. Connect the headset to PC VR, wake both controllers, and use the **Buckshot Roulette VR** desktop shortcut.

The default installation is `%LOCALAPPDATA%\BuckshotRouletteVR`. Each release lives under `versions\<version>`. The installer copies your own game files there and downloads the hash-checked loader. It refuses an unsupported game executable. Use the main download from GitHub Releases when installing to play.

The **Start Buckshot VR.cmd** launcher in the installation folder starts the installed VR version. Steam's usual Play button starts the game in the Steam library.

## Saves

VR uses `%APPDATA%\BuckshotRouletteVR` for local saves and logs. Your first VR launch starts with its own profile. The normal release runs the game's Steam integration, including its normal achievement calls. Automated integration tests use a separate profile with Steam disabled.

The development builds used a different profile. Existing testers can close both copies and copy their `buckshotroulette_*.shell` files from their development profile into this release's save folder after backing up the destination. Use only saves from the same game version.

## Updates

Close the VR game. Extract the new release and run **Install.cmd** again.

The installer verifies the new version before switching the launcher. It carries forward world size and haptic strength and uses the same save profile. Earlier versions stay under `versions` so you can remove them after checking the update, or launch an earlier executable from its folder with the arguments below.

Reinstalling the same release verifies its files. If verification reports modified or damaged files, choose a fresh destination or remove that version folder after closing the game. Third-party mods and their configuration need separate compatibility testing.

## Settings

Close the VR game and edit `versions\<version>\override.cfg` inside the installation folder.

```ini
[buckshot_vr]
world_size=0.88
haptic_strength=1.0
```

`world_size` supports **0.80–1.20**. Smaller numbers make the table and props appear smaller. Hand size stays physically consistent. `haptic_strength` supports **0.0–1.0**, with zero disabling vibration.

Session volume in the VR pause menu affects the current run. Other game settings are available from the original title menu. Smooth walking and turning are the release defaults.

## Multiplayer screen mode

Multiplayer opens on a fixed virtual screen in the headset. Point with the right hand and use the right trigger to click. In a match, left Menu opens the original player/disconnect menu without pausing the match. Hold right grip while moving the pointer for native free look. Index profiles use the same left-stick-click menu fallback as single player.

This mode is experimental and is not immersive multiplayer VR. The local UI and camera paths have automated checks, but an online match with another player has not been tested. Steam invites and clipboard lobby codes may require the desktop.

## Manual setup options

From PowerShell in the extracted release directory, specify the game's folder and an empty installation directory when automatic detection is unsuitable.

```powershell
.\Install.ps1 -GamePath 'D:\SteamLibrary\steamapps\common\Buckshot Roulette\Buckshot Roulette_windows' -Destination 'D:\VR Games\BuckshotRouletteVR'
```

`-NoShortcut` skips the desktop shortcut. `-LoaderArchive <zip>` uses an offline copy of the exact pinned loader archive. Its SHA-256 must match `release.json`. For a process-local script-policy override, use the included `Install.cmd` with the same arguments.

To launch a version manually, use its working directory and these arguments.

```text
"Buckshot Roulette.exe" --xr-mode on -- --buckshot-vr
```

## Uninstall

Close the VR game and remove the **Buckshot Roulette VR** desktop shortcut and `%LOCALAPPDATA%\BuckshotRouletteVR` installation directory. Keep `%APPDATA%\BuckshotRouletteVR` to preserve your VR saves, or remove it if you want to erase that profile.

## Troubleshooting

- **The installer rejects the game.** This release pins Steam 2.2.0.6 by executable and DLL hashes. Modified files, other store builds and later game updates need a separate audit. Verify Steam's game files and check the supported version.
- **The game opens on the monitor but VR stays blank.** Connect the headset to the active PC OpenXR runtime before launching, then fully close and relaunch the game. `XR_ERROR_FORM_FACTOR_UNAVAILABLE` means the runtime could not supply the headset at startup.
- **Left Menu opens the streaming overlay.** Virtual Desktop can present Index bindings. With that profile, click the left stick for the game's pause menu.
- **Position feels wrong.** Face forward before launch. Use your runtime's recenter function, then keep your head in the desired seated position while tracking resumes.
- **Download fails.** Check access to `codeload.github.com` and run the installer again. A failed download leaves the current launcher usable.

Logs are under `%APPDATA%\BuckshotRouletteVR\logs\godot.log`. Include `[TableVR]`, OpenXR and script-error lines in a bug report. [Repository and support](https://github.com/KMielnik/Buckshot-Roulette-VR-Mod).
