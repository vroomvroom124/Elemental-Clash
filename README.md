# Elemental Clash — R15 Combat Animation Prototype

This package upgrades your existing working **v0.2/v0.3 Roblox Studio place**. It does not contain the base game installers, older client/config scripts, or a `.rbxl` place, so it cannot create the game in a blank place.

The cosmetic animation client supports legacy `Motor6D` joints, newer R15 `AnimationConstraint` joints, and a basic R6 fallback. All combat actions and damage remain server-authoritative. No published animation assets are required.

## Update an existing animation client

1. Stop Play in Studio.
2. Open the current [CombatAnimationClient.lua](https://raw.githubusercontent.com/vroomvroom124/Elemental-Clash/main/CombatAnimationClient.lua) and copy all its source.
3. In Explorer open **StarterPlayer → StarterPlayerScripts → CombatAnimationClient**.
4. Replace that LocalScript's entire source in **Edit mode**, rather than pasting it into the Command Bar.
5. Press Play. Hold F and try the three-hit LMB combo, RMB heavy, Q dodge, and E boulder. Stop, then start Play again to confirm the edit persisted.

This client-only update preserves any Studio-specific server modifications. The existing servers must already broadcast through `CombatAnimationRemote` for it to work.

## Install the upgrade onto an existing v0.2 place

1. Back up the place with **File → Save to File**.
2. Extract `Elemental-Clash_R15_Polish.zip`.
3. Open `INSTALL_ANIMATIONS_v0.3.lua` in a text editor and copy its complete contents.
4. Open your working place in **Edit mode**, with Play stopped.
5. Open Studio's **Command Bar**, paste the installer, and run it. Use Studio search for Command Bar if its menu location differs in your version.
6. Confirm Output reports `[Elemental Clash] v0.3 installed`.
7. In Explorer confirm:
   - `ReplicatedStorage/CombatAnimationRemote` is a RemoteEvent.
   - `ServerScriptService/CombatServer` and `BoulderServer` are Scripts.
   - `StarterPlayer/StarterPlayerScripts/CombatAnimationClient` is an enabled LocalScript.
   - `ServerScriptService/ElementalClashBackups` contains the original server source backups.

The full installer replaces both server sources with the supplied v0.3 versions. Compare any Studio-only server modifications first. Existing `CombatServer_v0.2_Source` and `BoulderServer_v0.2_Source` backups are kept; an existing animation client is backed up once as `CombatAnimationClient_PrePolish_Source`. Reruns reuse scripts/remotes and preserve those backups.

## Animation behavior

- Jab, cross, and heavy use forward arm extension, compact elbow positions, an inward rear-hand guard, and reduced torso twisting.
- Strikes have a short anticipation, fast extension, brief contact hold, and a quick return to guard. The timed poses are applied without a second per-frame smoothing pass after a short entry blend.
- A **0.30-second cosmetic ready stance** follows melee recovery to bridge combo hits. It does not block damage or change the server's action timings. Blocking, boulder stance, dodge, hit/stun reactions, and death override or clear it as appropriate.
- The kick chambers forward at the hip and folds backward at the knee before extension. Boulder poses push forward with both hands.
- F guard, block recoil, parry, dodge, and hit/stun reactions use the same server-confirmed event stream.
- Punches leave walking legs under the Animator. Joint overrides are removed before the next animation update; untargeted joints stay under normal animation control.
- Existing strike contact timestamps and total clip durations are retained. Intermediate visual keyframes were added. The existing `CombatConfig` still determines gameplay timing.

## Controls

- LMB: light three-hit combo. RMB: heavy.
- Hold F: block; timing controls parry. Q: dodge.
- Hold E: raise a boulder; RMB charges; LMB launches; release E stops steering.
- Existing camera/input/HUD scripts remain in your place.

## Validation and limits

Read [PLAYTEST_R15.md](PLAYTEST_R15.md) for exact installation, two-player, R6, upgraded-joint, and visual regression checks. Roblox Studio is required to confirm visual quality, avatar proportions, retargeting, and network behavior. Headless checks do not establish that the poses look polished on your avatar.

From this folder, with Python 3 and the official Luau compiler/CLI available:

```sh
python tests/check.py --luau-dir /path/to/luau
```

The suite compiles all four Lua files, checks embedded installer sources, and runs mock tests for joint ownership, forward hand geometry, inward guard geometry, contact holds at 30/60/120 FPS, combo transitions, recovery, interruptions, R6 fallback, upgraded R15 joints, and installer reruns/backups. The mock rotation interpolation is not Roblox's quaternion interpolation and does not reproduce physical simulation or visual retargeting.

This remains a procedural prototype. For production-quality martial arts motion, author and publish R15 animations in Studio Animation Editor under an account/group permitted for the experience, then replace the pose clips with Animator-loaded tracks. Do not invent asset IDs or move hit validation to client markers.

Server-confirmed events add latency to visual startup. Mid-block join reconciliation remains absent; held boulder state can reconcile through the existing attribute. The v0.1 training dummy is not an articulated rig. Use a second player for reaction tests.

Roblox's current joint API: [AnimationConstraint documentation](https://create.roblox.com/docs/reference/engine/classes/AnimationConstraint).

## Files

- `CombatAnimationClient.lua`: cosmetic multi-character procedural animation client.
- `CombatServer_v0.3.lua` and `BoulderServer_v0.3.lua`: supplied authoritative servers, unchanged by animation polish.
- `INSTALL_ANIMATIONS_v0.3.lua`: Command Bar installer with matching embedded source.
- `AGENTS.md`: development instructions.
- `PLAYTEST_R15.md`: manual multiplayer and visual checks.
- `tests/`: mock runtime and validation runner.
