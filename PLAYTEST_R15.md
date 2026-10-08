# R15 polish: Studio acceptance test

This is a procedural polish pass, not published animation assets. Keep a copy of your working place and perform the following in a duplicate. The uploaded package does not contain the base v0.1/v0.2 place or CombatConfig; existing combat settings still control damage and hit timing.

## Apply and check installer reruns

1. Open your working v0.2/v0.3 place in **Edit** mode. Copy the complete `INSTALL_ANIMATIONS_v0.3.lua` into the Studio Command Bar and execute it.
2. Confirm one `ReplicatedStorage/CombatAnimationRemote`, one `ServerScriptService/CombatServer`, one `BoulderServer`, and one `StarterPlayer/StarterPlayerScripts/CombatAnimationClient`.
3. Inspect `ServerScriptService/ElementalClashBackups`. Existing `CombatServer_v0.2_Source` and `BoulderServer_v0.2_Source` values must retain their original source. If a client existed before installation, `CombatAnimationClient_PrePolish_Source` must contain that original client source.
4. Run the same installer again in Edit mode. Confirm instance counts and backup values are unchanged. The installer replaces server source with the supplied v0.3 source; compare any Studio-only server modifications before using it. If your servers are already customized, update only the animation LocalScript manually after saving its current source.

## Test with two players

1. Set the test avatar type to **R15** through Studio's avatar/game settings. In the **Test** tab start a local server with **2 players**. Open Output on the server and both clients. Keep player B facing player A and within melee range. Use B's window to observe A's whole body as well as A's local view.
2. With A stationary, press LMB three times at the game's accepted combo cadence. Expect right jab, left cross, then right front kick: knee chambers, leg extends, knee re-chambers. Arms recover toward guard. Compare impact timing with health loss on B; record a mismatch against the actual `CombatConfig.LightWindup` values rather than changing damage windows for visual reasons.
3. Walk forward and sideways while using the first two light strikes and RMB heavy. Expect the normal walk cycle to continue on both legs during punches/heavy; the third strike intentionally poses the kicking leg. After every strike the default locomotion/idle must resume without a stuck shoulder, elbow, hip, or knee.
4. Hold F on B. Wait beyond the parry window, then strike B with A. Expect a brief guard recoil on both client views and a return to B's held bent-elbow guard. Release F; arms must smoothly return to default animation. Repeat with a correctly timed parry: expect a defensive snap/golden flash and the same server-authoritative guard/stun behavior as before.
5. Press Q on A while moving forward, sideways, and backward. Verify dodge displacement and cooldown match the prior game. Strike during/after dodge to verify existing invulnerability behavior. Animation must recover; no character-root motion is added by this client.
6. Hold E on A, charge with RMB, launch with LMB, steer, and release E. Expect held two-hand pose, a distinct push on launch, and recovery. Boulder charging, size, damage, steering, and cooldown must match the previous build. Attempt melee while holding: existing server restrictions must remain intact.
7. Hit/stun A during an animation; verify the reaction interrupts it and recovers. Reset A while guarding and while holding a boulder. A's respawn must animate normally on both clients; no stale pose should transfer to the new character. Leave/rejoin one client while the other holds a boulder: the joiner should see the held pose. Mid-block join reconciliation remains an existing limitation.
8. Repeat basic attacks, block, boulder, death, and respawn with **R6** test avatars. Missing elbows/knees must produce no errors; the original shoulder/hip fallback still animates. Restore R15 when finished.
9. Repeat on different R15 body proportions and under Studio network emulation. Compare the last saved working place for health, guard, combo/cooldown, HUD, aiming, and camera regressions. Record results and any errors from both clients and server. Visual polish and replicated behavior are not verified until this pass is completed in Studio.

## Authoring the next animation pass

Use an R15 rig matching the intended player body proportions in Studio Animation Editor. Start with a compact guard, right jab, left cross, front kick, heavy, and block recoil. Keep guard elbows bent, punches forward at chest height, the rear hand protecting the face, and feet planted except during the kick. Preview from front and side to check R15 joint axes and silhouette. The procedural values are an editable starting point, not an anatomical reference.

Keep strike peaks aligned to the real `CombatConfig` windups, and recovery within its action timings. Do not change server damage or accept client animation markers as evidence of a hit. Publish assets under the experience owner's account/group with permission for the experience, then record the real IDs and clip timings for a later Animator-track implementation. No asset IDs were invented or added here.
