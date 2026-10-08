# Elemental Clash — Codex development instructions

This is a **Roblox Studio / Luau** prototype, not an Unreal Engine or native app project.
The working Roblox place was installed through the v0.1, v0.2 and v0.3 Studio Command Bar installers.
The package is intended as an editable offline source folder. Running the game still requires Roblox Studio.

## Current controls
- LMB light three-hit combo; RMB heavy; F guard/parry; Q dodge.
- Hold E to make a boulder; RMB charges while holding E; LMB launches; release E stops steering.
- Camera-relative character-facing is handled by CombatClient.

## Files
- CombatServer_v0.3.lua: authoritative melee hits, guard, parry, dodge, damage and action broadcasts.
- BoulderServer_v0.3.lua: authoritative boulder state, steering/collision/damage and animation events.
- CombatAnimationClient.lua: cosmetic procedural R15/R6 animation poses on every player's client.
- Reference_Source/: unchanged v0.2 client/config and v0.1 boulder client/config scripts for context.
- INSTALL_ANIMATIONS_v0.3.lua: source-embedded Command Bar installer for applying v0.3 to a place that already has v0.2.

## Editing requirements
1. Keep the server authoritative for combat and damage. Never accept client-submitted target or damage values.
2. Preserve BoulderRemote / CombatRemote formats unless updating both ends consistently.
3. Use CombatAnimationRemote for server-confirmed cosmetic action events only. Never trust a player to broadcast hit events.
4. Avoid overwriting the player's arena, camera controls, or existing HUD unless specifically requested.
5. Changes to any server/client file must also be copied into the matching `.Source = [====[ ... ]====]` block in INSTALL_ANIMATIONS_v0.3.lua before shipping.
6. Always keep the installer's original script backups and verify re-running installation doesn't duplicate instances.
7. Roblox Studio can't be run in a headless test here. Static checks aren't playtesting; give exact manual multiplayer testing steps.
8. Prefer R15 for visual polish. Keep R6 degradation graceful until the game formally switches to R15-only.

## Next steps
- Create polished player-owned R15 animations in Roblox Studio Animation Editor, publish each asset and store IDs in a configuration file.
- Replace rough Motor6D.Transform procedural poses with Animator-loaded tracks; optionally use animation markers for hit windows.
- Move from one-paste installers to Rojo source sync and Git when the developer is ready.
