# Release audit

Reviewed on 6 November 2026 against the Quest-tested development build and the Steam 2.2.0.6 executable.

## Changes

- Removed the practice hub, its startup override, scenario loader and production pause/input branches.
- Consolidated keypad contact and case-latch grips into the main mod. Removed the separate experimental add-on and remaining magnifier/item-deal visual proxies.
- Kept pointer-based item use and shotgun targeting, visual cuffs, dealer grading and feedback.
- Removed per-trigger and per-world-click logs. Startup, runtime profile and layout-failure messages remain available for diagnosis.
- Made the ending's continue input accept the aim pose when a grip pose is unavailable.
- Replaced machine-specific staging commands with a Windows installer, pinned dependency manifest, release allowlists and reproducible archives.
- Reworked retail tests to use disposable offline installations without an interactive practice dependency.

## Verification

The standalone Godot input fixture, nine packaging/installer tests and nine retail suites passed for this source. Retail suites cover walking, direct keys/latches, pause, ending, dealer impact, player impact, haptics, presentation and heartbeat timing.

A separate clean install exercised Steam-library discovery and downloaded the pinned BRMLNeo archive. Its installed executable passed opt-in and unavailable-OpenXR startup checks. Package inspection confirmed that the playable archive contains only the installer, original mod code, release metadata and documentation.

Physical headset observations belong to the tested development build. The cleanup's behavior is covered by automated checks, with additional headset and runtime coverage welcome.

## Limits

The heaven scene after a final story defeat still requires the monitor for Retry or Exit. Ordinary death redirects to the main scene automatically. Multiplayer and other game versions remain outside this release's support. Other OpenXR headsets require hardware testing. [Compatibility](compatibility.md).
