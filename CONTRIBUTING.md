# Contributing

Bug reports and hardware compatibility reports are welcome. Include the mod/game versions, runtime, headset and controller profile. Explain the sequence that causes the problem and the expected result. Share a trimmed log with personal paths removed.

## Build and run

Use Python 3.11+ for the build and Godot 4.1.1 for the standalone fixture.

```sh
python tools/build.py
python -m unittest discover -s tests -p "test_*.py"
```

Extract `dist/Buckshot-Roulette-VR.zip` and run its installer on a machine with the supported game. For local iteration, close the private VR copy and replace its `mods/TableVR-Bootstrap.zip` with the generated ZIP of that name. Keep the installed game outside your checkout.

## Add an interaction

1. Trace the native branch, its permission flags and the existing dispatcher in the owner's local build.
2. Add input translation to `near_input.gd` or `world_pointer.gd`. Query the actual collider again at commit time and recheck the branch's permission.
3. Let the original callback consume the item, resolve a shot and advance the turn.
4. Give one input method ownership of an action. Cancel pending input on tracking/focus loss, pause and scene exit.
5. Test an allowed use, a rejected use, held input, tracking loss and the next turn. Compare the resulting native state to the ordinary pointer path.

For presentation changes, build an adapter with explicit attach and teardown. Save only the properties you change, then restore them on detach. Read resources from the installed game rather than exporting copies into the mod.

## Add headset support

Start with the controller profile recorded in the log. Verify aim and grip poses, trigger, grip, primary stick/trackpad, pause and haptics separately. The mod uses the engine's OpenXR action map. A new profile or remap requires a real headset pass as well as the simulated input tests.

## Change the supported game version

Update `compatibility.json` only after inspecting the new executable, engine and loader behavior. Recheck scene paths, exported references, animation tracks, interaction aliases and camera ownership. Then run the relevant local retail suites and a complete headset round. A matching version string alone is insufficient.

## Send changes

Keep changes focused and include the reason for them, verification performed and any untested hardware behavior. Follow [AGENTS.md](AGENTS.md) for source, test and release boundaries. See [architecture](docs/architecture.md) and [test commands](docs/testing.md).
