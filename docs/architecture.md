# Architecture

## Entry and ownership

BRMLNeo mounts `mods-unpacked/TableVR-Bootstrap/` and creates `mod_main.gd`. The adapter activates only with `--buckshot-vr` and the expected engine/game version. The desktop executable initializes OpenXR through `--xr-mode on`.

On a supported scene, the mod attaches an `XROrigin3D` with an `XRCamera3D` and independent `XRController3D` nodes for aim and grip. It calibrates the head once tracking is ready. Session focus, stopping and recenter events cancel pending input or reset the anchor.

The original game retains shell order, inventory, damage, turn decisions, animations and saving. The VR layer owns camera placement, input translation and stereo presentation.

## Modules

| Module | Responsibility |
|---|---|
| mod_main.gd / rig.tscn | Scene and OpenXR lifecycle, calibration, adapter ownership |
| view_station.gd / walk_area.gd | Walking within runtime room geometry, proximity kicks, desk glide and a stable table anchor |
| hand.gd / glove.gd / retail_hand.gd | Independent aim/grip poses, trigger rearming, runtime player meshes and index alignment |
| world_pointer.gd | First-hit physics query, retail hover and guarded interaction dispatch |
| near_input.gd | Swept fingertip keys and grip-operated case latches |
| menu_panel.gd / pause_menu.gd | Original title canvas in stereo and a separate in-game pause panel |
| table_text.gd | Localized dealer dialogue and current item description |
| cuffs.gd | Visible wrists held against the retail rail through the cuff animation |
| dealer_impact.gd / player_impact.gd | Stereo hit effects, blackout, revival and heartbeat observation |
| haptics.gd / action_feedback.gd | Prioritized pulses and bounded patterns driven by native shot, shell and item events |
| screen_mode.gd | Multiplayer compatibility screen, native canvas, mouse projection and menu/free-look actions |
| menu_bullets.gd / retail_grade.gd | Continuous casing waterfall and stereo color grading |
| finale.gd | Automatic case lid, authored winning camera, car scale, native payout and unlock UI |

## Interaction contract

A trigger edge records the scene-owned pointer pose and its tracking-source revision. The physics tick performs a fresh ray query, supplies the result to the original camera interaction field and asks the original manager to resolve the branch. It rechecks tracking, cursor visibility and branch permission before calling `MainInteractionEvent`.

Fingertip and grip actions submit hits through that same dispatcher. A fingertip must leave a key before another poke. One path owns an input tick, so a poke and a simultaneous trigger cannot produce two letters.

Focus loss, controller loss, pause and detach clear pending presses. Menu input is routed to the game's actual controls. The pause panel captures input and saves/restores both tree pause state and `Engine.time_scale` because some retail timers process while the tree is paused.

## Camera and presentation

The intro derives walkable floors, door placement and kick timings from the installed scene. Entry into the room produces a short glide to the authored seated height, ten centimetres behind the original home socket. At the table, ordinary camera socket changes leave the VR base steady while physical head movement continues.

The cash-case pan explicitly takes camera ownership. The mod follows the authored transition, then captures the first car pose as a fixed anchor for both the rig and the score panel. The native looping shake continues only on the desktop camera. The car uses different geometry units, so the covered cut changes units per metre and the tracking/hand offsets by the measured 0.1335 ratio. The same case has consistent physical width before and after the cut.

Original score labels, the continue prompt and the first-win unlock label share a filtered canvas viewport. A glyph outline keeps the score readable over the car. The unlock label renders above the black exit fade.

Screen overlays and player flashes use stereo-safe presentation. Dealer shading uses a one-dimensional lookup matching the enabled retail posterization settings. Hand meshes, materials, animations and text are read from the local game.

## Feedback

`action_feedback.gd` observes the local muzzle animation, player shell ejection and selected native sound players. It does not guess damage from a click. The original aiming clip can finish before the gun fires, so shooter ownership uses the assigned animation. A player hit owns both motors and suppresses simultaneous self-shot recoil.

Audio onsets are consumed while unfocused and must be recent. Recoil, impact, door, saw and other short patterns use real-time deadlines. Focus loss clears queued beats; missing tracking discards that hand's pending beats. Higher-priority feedback suppresses incidental ticks. The existing revival audio clock still supplies the heartbeat timing.

## Multiplayer presentation

`screen_mode.gd` shares the native 2D/3D worlds with a capture viewport and follows the currently selected native camera. The headset sees only the fixed screen and VR geometry on a separate render layer. The capture excludes that layer to avoid feedback. The original multiplayer mouse ray is suspended and replaced with the capture camera's projection; native hover resolution and interaction permissions remain in charge. Left Menu sends the game's own exit-menu action, without freezing network simulation.

The implementation uses the pinned [Godot 4.1 SubViewport](https://docs.godotengine.org/en/4.1/classes/class_subviewport.html) and [Camera3D](https://docs.godotengine.org/en/4.1/classes/class_camera3d.html) APIs. See [multiplayer limitations and the immersive adapter plan](multiplayer.md).

## Cleanup

Detach restores the desktop camera, root canvas mask, original material/render layers, mouse polling, previous world scale and simulation clock. It runs when the last-added rig exits, before the native UI/cameras leave the tree, and clears the captured mouse hover. Waiting for the scene root's exit is too late for this captured GUI state in the retail Vulkan build. Each adapter disconnects its observers and releases only resources it owns. This applies on scene changes and OpenXR session stop.

## Packaging

`tools/build.py` maintains exact runtime and installer allowlists and stable ZIP timestamps. The installer downloads the hash-pinned BRMLNeo archive, checks the owner's executable and DLL, prepares a new version directory and publishes the launcher after validation. Every version uses the same dedicated save profile.

The public ZIP contains the installer, release manifest, mod ZIP, install guide and notices. Developer fixtures, test setup code and the game remain outside that archive.
