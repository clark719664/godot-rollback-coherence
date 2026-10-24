# Godot coherent rollback: executable milestone

A reduced, real-engine reproduction confirms a SceneTree/physics synchronization boundary from Rapier issue #534. Restoring a Node2D player's parent transform leaves its child StaticBody2D at the old PhysicsServer transform. Updating the child alone updates the server transform but does not refresh the query broadphase until a physics step.

## Run

From this folder in PowerShell:

```powershell
./prepare.ps1                 # only needed if downloaded dependencies are absent
./run.ps1 -Version original
./run.ps1 -Version latest
```

The preparation script downloads pinned Windows x64 dependencies into this checkout's ignored work/dependencies folder. Supply -DependencyPath to prepare.ps1 and -GodotPath/-AddonPath/-RunPath to run.ps1 to use other locations. prepare.ps1 checks the pinned SHA256 archive hashes in dependencies.json. No native binaries are bundled in this deliverable. First extension import can request an engine restart; the runner retries import once and requires a successful import plus actual runtime measurements.

## Implemented fix

project/coherent_step.gd is a small GDScript synchronization boundary for explicitly registered, Node2D-driven static hitboxes:

1. Apply all gameplay and restored transforms.
2. Call force_update_transform() on each registered hitbox.
3. Perform exactly one regular fixed-delta Rapier step and flush.
4. Run bomb queries and commit health changes after that step.

The harness calls the same helper. The alternative direct body_set_state before the normal step also passes. No extra zero-time steps are used. Do not apply this helper indiscriminately to dynamic RigidBodies, whose simulation owns their transforms. In the original project's scheduler, bomb timer callbacks run in _network_process while physics steps in _network_postprocess: move authoritative bomb hit queries to an explicit phase after the driver step. This release provides the tested boundary helper, not an unverified full-game integration patch.

## Measured results

Official Godot 4.7.2, Windows x64, headless. Both Rapier packages: 72 cases each, 144 total, 20 repeated rollback cycles per case, with two checked snapshot restores per cycle. Each case separately tests synthetic input arrival delay 0/100/200ms (0/6/12 nominal ticks) and rollback history depth 1/6/12/24. Even the zero-delay case deliberately injects a rollback; it is not a no-rollback network control. At least one prediction tick runs in each case so a real snapshot rewind can be verified.

Per plugin, each mode executes 2,580 real shape queries:

- Baseline: 1,290 missed hits; 210 final-health mismatches across 240 cycles.
- Transform-only after step, transform+flush after step, and static mode-toggle adaptation: each 1,290 missed hits, 1,170 false hits, 120 final-health mismatches.
- Coherent boundary: zero missed/false hits, transform mismatches, health mismatches, or clock mismatches.
- Direct server transform before regular step: also zero mismatches.

All 144 cases return SUITE_FAILURES=0, meaning fixed modes pass and negative controls still demonstrate the bug. The runner separately requires baseline exit1 and normal-frame control exit0. A moving, undamped rigid body verifies that replay advances exactly depth fixed ticks. Each restore checks actual PhysicsServer sentinel transform, velocity, and hitbox transform against the original snapshot before resetting application state. Prediction must move the sentinel. A deliberately disabled snapshot importer must fail with RESTORE_ERROR; both fault-injection logs record exit1. Each successful suite records 2,880 checked restores. Actual JSON measurements and raw engine logs are in results/; timings are local microbenchmarks, not representative game performance claims.

## Scope and outstanding work

This is a deterministic delayed-input scheduler and same-frame rollback burst, not two ENet peers, operating-system latency injection, or a complete replay of issue534's bomb game. The original v3 project was downloaded and relevant scripts inspected. Real Rapier cache_state/load_cached_state, real CollisionShape2D/StaticBody2D, real rigid-body motion, real shape queries and numerical health mutations are exercised. No mock physics is used. We establish an application ordering fix; this does not establish an engine defect or cross-platform determinism.

The netfox documentation's body-mode workaround targets kinematic bodies with GodotPhysics3D/Jolt. We tested its 2D static-hitbox adaptation here; it does not fix this Rapier case when called after the normal step. That is not a verdict on the documented 3D workaround. Godot PR76462 remains open at head5b59c337ae899b12fafa057d5ea805fd6c759918 and is not in the official engine; it requires a separate custom native build and has not been tested. Rapier's existing manual stepping APIs suffice for this milestone. Animated shapes, CharacterBody floor caches, Area signals, spawning/despawning, and two-peer scheduling remain further integration work.

## Pins, provenance and licensing

- Engine: official Godot4.7.2-stable, runtime ed1daf0bf, https://github.com/godotengine/godot/releases/tag/4.7.2-stable . Godot uses the MIT license; see https://godotengine.org/license/ .
- Original requested plugin asset: v0.8.36, https://github.com/appsinacup/godot-rapier-physics/releases/download/v0.8.36/godot-rapier-2d-single-enhanced-determinism.zip . Its embedded plugin version/runtime is0.8.35; compatibility_minimum=4.7. Thus the issue's requested Godot4.6.2 is incompatible without modifying the package. We preserved the package and tested with4.7.2.
- Original source clone: tagv0.8.36, commitcaf638431121a524685bd1a3d0e380937aa04b99. src/nodes/state_manager.rs documents why an extra zero-step was disabled: it increments internal bookkeeping ticks.
- Current plugin asset: v0.36.0, https://github.com/appsinacup/godot-rapier-physics/releases/download/v0.36.0/godot-rapier-2d-single.zip . This release has no separately named enhanced-determinism asset; tests establish local repeatability only.
- Godot Rapier's MIT license and third-party notices remain in downloaded addon folders. https://github.com/appsinacup/godot-rapier-physics/blob/v0.8.36/LICENSE . Archive hashes are in dependencies.json and results/archive-hashes.json.
- Issue: https://github.com/appsinacup/godot-rapier-physics/issues/534 ; fixture: https://github.com/user-attachments/files/29163702/rollback-rapier-test-v3.zip . The fixture is not redistributed here; its licensing is not inferred.
- netfox caveats: https://foxssake.github.io/netfox/latest/netfox/tutorials/rollback-caveats/ . Manual stepping PR: https://github.com/godotengine/godot/pull/76462 .


The authored reduced harness and runner are MIT licensed (LICENSE). Engine/addon binaries and the original issue fixture are not bundled; their upstream licenses continue to apply to downloads. The results/archive-hashes.json paths are reduced to archive filenames for publication; hashes are unchanged.

A manual GitHub Actions workflow reproduces the pinned research checks. It has not been run on GitHub at initial publication; the recorded results above came from local runs.
