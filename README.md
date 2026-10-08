# Elemental Clash v0.3 — R15 Procedural Animation Polish

**Requires your working v0.2 Roblox Studio place.** This upgrade builds on the working three-hit combat, blocking, parrying, dodging, and floating Earth boulder. It does not overwrite your arena or input/HUD scripts.

## Install (Roblox Studio)

1. **Back up your Roblox place** first (File → Save to File).
2. Download/extract `Elemental-Clash_R15_Polish.zip`.
3. Open `INSTALL_ANIMATIONS_v0.3.lua` in a text editor; select/copy all its contents.
4. Open your **v0.2** place in Roblox Studio, in **Edit** mode (not playing).
5. Open **Command Bar** (View → Command Bar, or Studio's Command Bar search) and paste the full installer script; press Enter.
6. Verify in Explorer:
   - `ReplicatedStorage/CombatAnimationRemote` (RemoteEvent)
   - `ServerScriptService/CombatServer` and `BoulderServer` (both upgraded)
   - `StarterPlayer/StarterPlayerScripts/CombatAnimationClient` (new LocalScript)
   - `ServerScriptService/ElementalClashBackups/CombatServer_v0.2_Source` and `BoulderServer_v0.2_Source`
7. Press **Play** to test. Use Roblox Studio's **Start Server / Start Player** multiplayer test for replication and player versus player.

## New features

- Procedurally animated jab/cross combo with bent-elbow recovery and a chamber → extension → re-chamber third-hit front kick.
- Wind-up and follow-through poses for a heavier martial attack.
- Bent-elbow guard; blocked hits play recoil and return to the held guard. Parry gets a quick defensive snap and a golden flash.
- Dodge dips torso and adjusts leg posture; stun/hit reactions play after validated hits.
- Holding a boulder extends both hands; launching it triggers a martial-arts push pose.
- Every client sees the same action start for *other players*; server only broadcasts successful/accepted moves.
- R15 elbow/knee articulation with graceful R6 fallback, no published animation assets required.
- Smooth keyframe interpolation and frame-rate-independent blending. Punches leave legs under the default Animator; prior overrides are removed before the next animation update.
- The installer preserves an existing animation client in `ElementalClashBackups/CombatAnimationClient_PrePolish_Source` once and reuses existing script/remote instances on reruns.

## Controls (unchanged)

- Left Click: light combo. Right Click: heavy attack.
- Hold F: block / parry at the right instant. Q: dodge.
- Hold E: raise boulder; RMB charges; LMB launches; release E stops control.
- Aim with third-person mouse/camera.

## Important limitations

- **Animation system is an early procedural prototype** manipulating character Motor6D joints. It is not a set of hand-authored / uploaded Roblox animation assets. Movements are intentionally rough placeholders until you create polished keyframed R15 animations in Roblox's Animation Editor.
- Combat damage, projectile behavior, movement, and game balance stay on v0.2 logic; v0.3 is an animation/presentation layer.
- Animation start times are server-confirmed; high latency will delay visuals slightly. Later, use client prediction for local attack startup and synchronize server acceptance.
- Original animation scripts can interfere with some custom character rigs or advanced avatars. Use default R15 avatars for initial tests.
- Client-side procedural poses are intentionally broadcast to each player rather than relied upon to replicate Motor6D.Transform. Players who join in the middle of a *held boulder* can see the pose through the replicated attribute, but mid-block join reconciliation is not included.
- Replacing your v0.2 server scripts also overwrites any manual modifications made to those scripts; the installer backs up their prior source before upgrading.
- The basic training dummy from v0.1 is not an articulated rig; its health reacts, but it won't play joint animations. Test attack reactions against a second player.
- **Not run/tested inside Roblox Studio** from this environment. Installer contents were checked statically; test in Play and multiplayer.

## For polished animation assets (later)

In Studio's Animation Editor, insert an R15 rig, animate punches/kicks/parry/boulder pose, choose **Publish to Roblox**, and use the generated animation asset IDs. Replace the procedural client poses with `Animator:LoadAnimation()` tracks. Do not invent asset IDs; animations must be published under an account/group with permission to use them.

## For Codex

Open the extracted project folder in VS Code or use Codex CLI. Codex can update the `.lua` source files, create tests and regenerate the paste installer, but Studio is still needed to playtest. Long term, use a Rojo-based filesystem project and Git for easier source syncing and history.

## Contents

- `CombatAnimationClient.lua`: client-side multi-character pose player and FX
- `CombatServer_v0.3.lua`: v0.2 server with animation broadcasts after accepted combat actions
- `BoulderServer_v0.3.lua`: v0.2 server with start/launch/end animation broadcasts
- `INSTALL_ANIMATIONS_v0.3.lua`: one-paste Roblox Studio installer
- `AGENTS.md`: setup and guardrails for Codex
- `tests/`: Luau mock runtime checks and a Python test runner.
- `PLAYTEST_R15.md`: exact Studio multiplayer regression steps and animation authoring guidance.

The attached files did not include `Reference_Source/`, the v0.1/v0.2 installers, or a `.rbxl` place. This package requires your existing working v0.2/v0.3 place; it cannot create that base game by itself.

## Local validation

With Python 3 and the official Luau CLI/compiler available, run from this folder:

```sh
python tests/check.py --luau-dir /path/to/luau
```

The runner compiles all four scripts, compares each embedded installer source with its standalone file, and exercises animation state/joint ownership plus installer reruns in a mock runtime. These checks do not simulate Roblox physics, networking, or visual joint orientation. No server source, remote format, damage tuning, input, camera, or HUD code was changed in this polish pass.

## Newer R15 joint compatibility

The animation client supports both legacy `Motor6D` joints and upgraded R15 `AnimationConstraint` joints. Roblox's Avatar Joint Upgrade can spawn R15 characters with AnimationConstraints, which the first client version skipped. Both use the documented `Transform` property; no avatar settings, attachments, combat servers, or physics settings are changed.

For an already installed copy, stop Play and open `StarterPlayer/StarterPlayerScripts/CombatAnimationClient`. Replace:

```lua
if descendant:IsA("Motor6D") then motors[descendant.Name] = descendant end
```

with:

```lua
if descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint") then motors[descendant.Name] = descendant end
```

Then press Play and hold F or attack. The downloadable installer already includes this change.

Reference: [Roblox AnimationConstraint documentation](https://create.roblox.com/docs/reference/engine/classes/AnimationConstraint).

## Guard direction correction

The guard's shoulder and elbow pitch signs now bring standard R15 arms forward rather than behind the torso. Parry and block recoil use the same defensive convention. In an existing Studio client, replace the `local blockPose = ...` line with:

```lua
local blockPose = {RightShoulder=R(35,-12,25), LeftShoulder=R(35,12,-25), RightElbow=R(110,0,0), LeftElbow=R(110,0,0), Waist=R(6,0,0)}
```

Stop Play first, edit the source under StarterPlayerScripts, then restart Play and hold F. Check from the side that forearms and hands are in front of the torso. The downloadable full client/installer also includes the defensive reaction corrections. Custom joint axes still require Studio visual checks.

## Forward punch correction

Jab, cross, and heavy now use forward shoulder pitch, positive elbow flexion, compact recovery, and a guarded rear hand. The same reversed limb convention was corrected in the front kick and boulder poses. Existing keyframe times, action events, server combat, and damage windows remain unchanged. The mock suite checks forward hand extension/retraction using standard R15 joint axes; body proportions, retargeting, and visual quality still need Studio playtesting.

For an existing installation, stop Play, copy the full current `CombatAnimationClient.lua`, and replace the source of `StarterPlayer/StarterPlayerScripts/CombatAnimationClient`. Updating only this LocalScript preserves any Studio-specific server changes. Replace the source in Edit mode so it persists after restarting Play. You do not need to rerun the full installer or add animation assets.
