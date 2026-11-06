# Multiplayer status and next steps

Version 1.0.3 provides an experimental fixed virtual screen for the existing multiplayer game. This prevents the previous black-screen transition, supports original UI clicks and projects controller input into the active player's native view. It is not an immersive multiplayer implementation.

## What was verified

The local Steam 2.2.0.6 scripts and runtime have a separate multiplayer scene family: lobby, buffer and main match. The old bootstrap only recognized the single-player menu and main scene, so it detached the XR rig on entering the lobby.

Multiplayer spawns a separate player instance with its own camera, interaction manager, inventory, permissions, death effects and UI. Input is routed through native requests and host verification. A single-player adapter cannot safely be attached to those objects without handling their lifecycle and permission gates.

The compatibility screen keeps those systems intact. Tests run on an offline disposable installation and cover the native lobby popup, scene transitions, local player camera selection, projected mouse ray, permission preservation, non-pausing match menu and return to the immersive title. Vulkan rendering checks inspect the captured native canvas. No public lobby is created by tests.

**Still unverified:** physical headset use of this mode, a real host/client match, reconnection, full-round progression, Steam overlay invites, and multiplayer-specific item combinations. Normal desktop players should not need this mod because it changes local presentation and input only; that compatibility remains an inference until a two-player test succeeds. It sends no tracked-hand data to other players.

## Controls

- Aim the right controller and pull its trigger to click the screen.
- Left Menu opens the native match player/disconnect menu. Index bindings can use left-stick click. Network simulation keeps running.
- Hold right grip and move the pointer for native free look when the game permits it.
- Steam overlay invitations and clipboard lobby IDs may need the desktop. No VR keyboard is supplied.

## Immersive implementation plan

1. Bind to the active local player after it spawns. Use the native seat socket for a stable XR anchor and track ownership changes, spectators and reconnects.
2. Feed a controller world ray into that player's native hover and interaction path. Preserve major permissions, branch permissions, turn ownership and host-validated requests. Never write inventory, damage or turn state from the adapter.
3. Present local HUD, item descriptions, opponent selection, jammer choices, death/revival and match results in stereo. Keep camera shake off the XR base. Map the native match menu without pausing the tree.
4. Observe local shot/item/revival events for haptics. Keep tracked hands cosmetic and local initially. Remote hand synchronization would be a separate protocol feature.
5. Test a modded host with an ordinary desktop client, then a modded client with an ordinary host. Cover all seat positions, player counts, denied actions, death/spectating, disconnects and a complete match before claiming immersive multiplayer support.

## Other VR improvements worth testing

- A recenter control and small seated height/reach adjustments in the pause menu.
- Optional snap turning and a comfort fade for forced story camera transitions.
- In-game haptic strength, with separate impact and interaction levels.
- A stereo retry/exit adapter for the final-defeat heaven scene.
- Optional assistance for small pointer targets, with fresh-ray and native permission checks retained.

Keep pointer-based item and shotgun interactions as the default. The accepted near interactions are keypad pokes and case latches; physical item grabbing is outside the current scope.
