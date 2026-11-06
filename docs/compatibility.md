# Compatibility

## Tested setup

| Component | Verified configuration |
|---|---|
| Game | Steam Windows 2.2.0.6, build 16736575 |
| Engine supplied by the game | GodotSteam 4.1.1 |
| Headset and controllers | Meta Quest 3 and Quest controllers |
| Connection and runtime | Virtual Desktop / VirtualDesktopXR |
| Development GPU | NVIDIA RTX 4070 Ti |
| Loader | BRMLNeo at the revision pinned in compatibility.json |

Headset testing covered menu selection, walking, both door kicks, seated interaction, items, shotgun turns, cuffs, dialogue, impact effects and the restored Dealer shading. Automated tests cover additional camera, input and ending conditions. The release cleanup was checked with the original Godot fixture and the installed retail executable. It still needs reports from other physical headsets.

## Other headsets

The mod uses OpenXR controller actions supplied by the game's Godot 4.1.1 engine. It has no headset-vendor allowlist. The engine includes Touch, Index, Vive, Pico Neo3, Cosmos, Focus 3 and other interaction profiles. Matching profiles are a starting point for compatibility.

| Setup | Status |
|---|---|
| Quest 3 with Virtual Desktop | Tested |
| Quest with Meta Link / Air Link | OpenXR path available, untested |
| Index, Vive and other SteamVR OpenXR setups | Untested |
| Pico with a PC OpenXR connection | Untested |
| Standalone headset installation | Unsupported |
| Hand tracking without controllers | Unsupported |

Movement uses the profile's primary stick or trackpad. Grip actions require a squeeze input. Index profiles have a left-stick-click pause fallback because runtimes may capture the system button. Report the actual profile printed in the log when a control behaves differently.

## Scope and known limits

- Single-player menu, bathroom/club traversal and table gameplay are adapted. Multiplayer uses an experimental fixed virtual screen. Its local adapters are tested; online play and multiplayer headset usability remain unverified. [Multiplayer scope](multiplayer.md).
- Smooth movement and smooth turning are the current controls. The ending retains the case pan and uses a steady VR seat in the car with live head tracking.
- The heaven scene after a final story defeat has no VR adapter. Use the monitor to choose Retry or Exit there. The ordinary death scene redirects to the main game automatically.
- The title options and readable gameplay text use the game's content. The added VR pause labels are English.
- Layouts and asset references are pinned to Steam 2.2.0.6. Later updates and modified game files are rejected by the installer.
- Other mods, other stores, localization combinations and every endless-mode edge case have not been exhaustively tested.

Version 1.0.3's car stabilization, additional haptics and multiplayer screen passed automated retail checks. They have not yet received the next physical Quest pass.

[Installation and troubleshooting](install.md) · [Testing details](testing.md)
