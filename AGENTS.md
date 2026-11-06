# Working in this repository

Read README.md, CONTRIBUTING.md and docs/architecture.md before changing runtime behavior.

## Commands

- Python 3.11+ builds the release with `python tools/build.py`.
- Run portable packaging tests with `python -m unittest discover -s tests -p "test_*.py"`.
- Run the original-geometry fixture with Godot 4.1.1 using `--path . --headless --xr-mode off --quit-after 90 -- --test-input`.
- Retail suites require the owner's installed Steam build and Windows. Follow docs/testing.md.
- Edit `mods-unpacked/TableVR-Bootstrap/`. Release archives under `dist/` are generated and ignored.

## Runtime boundaries

- Preserve the native interaction permissions, inventory, shell sequence, damage, turn order, save ownership and story progression.
- Route user actions through the existing dispatcher. The runtime owns VR presentation, tracking and input translation.
- Keep head tracking independent of hands. Require a fresh input after focus loss, tracking loss, pause or a scene transition.
- Restore every camera, canvas mask, material, process flag and simulation clock that the mod takes over.
- The accepted direct interactions are keypad pokes and case latches. Items and shotgun decisions use the pointer.
- Keep pause and world input mutually exclusive. The first-time unlock UI must render above the ending fade.
- Use Godot 4.1.1 APIs. Verify engine or game assumptions against pinned sources or local retail evidence before changing them.
- Keep startup, unsupported-host and layout-failure logs useful. Avoid per-frame or per-trigger logging in production.

## Repository boundaries

- Never commit game files, recovered source, extracted assets, runtime logs, credentials, local profiles or absolute machine paths.
- Keep proprietary recovery and disposable game installations outside this repository and outside every Git worktree.
- Runtime assets come from the installed game. The standalone fixture contains original geometry.
- Tests may arrange local game state in disposable offline copies. Test entry points and Steam stubs must stay out of the release archive.
- Use the release allowlists in tools/build.py. Add every runtime file there deliberately and verify archive membership.
- Distinguish fixture tests, retail automation and physical headset testing. Quest 3 / Virtual Desktop is the tested hardware configuration.
- Avoid expanding compatibility claims to multiplayer, other game builds or untested headsets.

## Release

Update VERSION and the manifest together. Build, run the relevant tests, audit the archive and update CHANGELOG.md. Publish a matching tag and GitHub release when requested. Release assets are Buckshot-Roulette-VR.zip and SHA256SUMS.txt. Verify their public download hashes after publishing.
