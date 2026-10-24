# Coherent Rapier rollback in Godot

A working integration and regression suite for the original [Rapier issue #534 bomb game](https://github.com/appsinacup/godot-rapier-physics/issues/534). It runs two real headless Godot peers over ENet, injects latency into actual loopback UDP datagrams, and checks every confirmed gameplay tick against a zero-delay reference. A smaller physics matrix isolates the original synchronization bug.

## Run from a fresh clone

Requires Windows x64, PowerShell, and Python 3. No Godot installation, native build, administrator privileges, firewall changes, or Python packages are needed.

```powershell
./prepare.ps1
./run-full.ps1 -Version original
./run-full.ps1 -Version latest
./run.ps1 -Version original
./run.ps1 -Version latest
```

The first command downloads SHA256-pinned archives into `.deps/`. The fixture is downloaded from its author's original attachment; it is not redistributed. Runners create isolated projects and logs in `.runs/`. Use `-DependencyPath`, `-PythonPath`, `-RunPath`, and (for the network suite) `-Port` to override defaults. The reduced runner also accepts `-GodotPath` and `-AddonPath`. A fresh folder with no surrounding workspace was tested using these defaults.

For the original game with its manual menu and keyboard controls:

```powershell
./make-game.ps1
./.deps/engine472/Godot_v4.7.2-stable_win64_console.exe --path ./.runs/game
```

The manual preparation preserves the original controls and connection menu. The automated runs add deterministic input and an actual NetworkAnimationPlayer that moves each nested hitbox. Those additions are test scaffolding. Both paths apply the same production driver and hash ordering fix. Archived scene UID metadata can emit diagnostics on initial editor import; the automated runner separately rejects runtime script/engine errors and requires actual gameplay results.

## What changed

The original bomb timer queried collisions during `_network_process`, before the driver's physics step in `_network_postprocess`. A rollback restores physics and scene state on different schedules, so a query could use an older hitbox location. The integration queues a copy of each blast's position, radius and damage, flushes each explicitly registered player hitbox after all movement and animation, performs exactly one regular fixed-delta Rapier step, then executes damage queries. There are no extra zero-time steps.

`full_fixture/PhysicsDriver.gd` retains real Rapier snapshots. Each load must return success, and restored PhysicsServer transforms and linear/angular velocities must equal the saved state. Missing or incorrect restores stop synchronization. Counters distinguish attempted rollbacks, successful native restores, verified bodies, and observed physical rewinds.

A second fixture issue appeared in real peer tests: the native Delta Rollback hasher observes Dictionary insertion order. Rollback and spawning can reorder scene groups. Initial confirmed frames had identical Variant types and byte values but different root-key order and different native hashes, until the first spawn alphabetized the scene. `CanonicalState.gd` orders dictionary keys for hashing while preserving the original values and types. The test still requires equality of the native `$` hashes and zero remote hash mismatches.

`run_full.py` patches the downloaded fixture using exact anchors and refuses an unexpected source layout. It preserves the original ENet adapter, native Delta Rollback extension, spawn manager, timers, RNG, scene, player health, and Rapier physics. Only the test scaffold scripts and the integration changes are redistributed here.

## Full gameplay regression

Each plugin runs four cases: original scheduling with delay, patched zero-delay reference, patched delayed peers, and an intentional regression that executes the patched blast queue before transform synchronization/stepping.

- Two separate Godot processes exchange actual ENet packets through a loopback UDP relay. The relay delays datagrams in both directions by 100ms plus deterministic jitter from -20 to +20ms. Recorded receive-to-send delay was approximately 93–125ms on this Windows machine. This is network transport delay; the reduced matrix's synthetic tick delay is a separate test.
- All 240 completed input ticks are compared with full float precision, including player health/positions, native physics transforms/velocities, timer states, RNG, animation, spawn records and native hashes. Predictions and unequal local clocks are not compared.
- Patched delayed peers match each other and the zero-delay reference at every checked tick. Both perform genuine rollback imports and physical rewinds. All authoritative shape queries also match an independent circle-versus-axis-aligned-rectangle oracle at the post-movement boundary.
- Each match creates and logically despawns 16 bombs and 16 explosions. The test checks their counters and that any retained spawn records are waiting for removal after despawn; delayed physical node disposal is the original spawn manager's rollback retention policy.
- Original scheduling and the explicit query-before-step regression must fail the geometric oracle. Comparing peers alone would be insufficient: two peers can make the same wrong query. The original run also produced wrong final health relative to the reference; the latest-plugin original run diverged between peers.

Measured logs, summary JSON, and compressed full-precision peer traces are in `results/full-original/` and `results/full-latest/`. Exact rollback/query counts depend on packet timing and are reported per run, rather than hardcoded as a required count. Final patched health is ServerPlayer -30 and ClientPlayer -40 on both peers for the scripted scenario; the original game allows health below zero.

## Reduced physics controls

`project/coherent_step.gd` is the minimal synchronization boundary. The reduced suite runs 72 cases per plugin, 144 total, across synthetic input arrival delay 0/100/200ms and rollback depth 1/6/12/24. Per plugin, each mode executes 2,580 shape queries. Baseline misses 1,290 hits; the coherent boundary and direct server-transform-before-step mode have zero missed/false hits, health mismatches, transform mismatches or clock mismatches.

Each successful suite verifies 2,880 snapshot restores. A deliberately disabled snapshot importer must fail with RESTORE_ERROR. A moving undamped rigid-body sentinel checks replay advances exactly the intended number of fixed ticks. The runner also requires the simple baseline to fail and a normal-frame control to pass. These controls remain independent of the full-game integration.

## Supported scope

The application fix is validated for this fixture's registered StaticBody2D hitboxes driven by Node2D parents, including animated child transforms and the original bomb/explosion lifecycle. It establishes local Windows repeatability for the pinned binaries. It does not establish cross-platform determinism, CharacterBody floor-cache restoration, Area signal replay, dynamically spawned physics bodies, animated shape-resource changes, or general RigidBody transform ownership. The integration deliberately does not rewrite those unrelated contracts.

The official engine's existing Rapier stepping APIs suffice. [Godot PR #76462](https://github.com/godotengine/godot/pull/76462) is not built or claimed as fixed here. This is an application ordering/hash integration fix, not proof of an engine defect. The [netfox body-mode caveat](https://foxssake.github.io/netfox/latest/netfox/tutorials/rollback-caveats/) concerns GodotPhysics3D/Jolt kinematic bodies; the reduced matrix's 2D static adaptation is not a verdict on that workaround.

## Pins and provenance

- [Godot 4.7.2 stable](https://github.com/godotengine/godot/releases/tag/4.7.2-stable), runtime `ed1daf0bf`, Windows x64. [MIT license](https://godotengine.org/license/).
- [Original Rapier v0.8.36 enhanced-determinism asset](https://github.com/appsinacup/godot-rapier-physics/releases/download/v0.8.36/godot-rapier-2d-single-enhanced-determinism.zip). The embedded runtime reports v0.8.35 and requires Godot 4.7. The package was preserved; the issue's requested 4.6.2 engine cannot load it unchanged. Original source tag commit: `caf638431121a524685bd1a3d0e380937aa04b99`.
- [Rapier v0.36.0 single-precision asset](https://github.com/appsinacup/godot-rapier-physics/releases/download/v0.36.0/godot-rapier-2d-single.zip). This release has no separately named enhanced-determinism asset. [Rapier MIT license](https://github.com/appsinacup/godot-rapier-physics/blob/v0.8.36/LICENSE); addon archives retain their notices.
- [Original v3 fixture attachment](https://github.com/user-attachments/files/29163702/rollback-rapier-test-v3.zip), SHA256 `9350DCDB8B1C100BC6EB19180621036EE19C109C5DF5F83DCB21E913DDCCA96E`. It includes its native Delta Rollback extension; fixture licensing is not inferred. The attachment and its binaries are fetched only when the user runs preparation.
- All dependency URLs and archive hashes are recorded in `dependencies.json`. No downloaded engine/plugin/fixture binaries are checked into this deliverable.

The authored harness, integration scripts and documentation are MIT licensed (LICENSE). Downloaded fixture/addon components retain their own upstream terms; the original fixture and binaries are not redistributed here. Retained text logs replace machine-local checkout/build-cache prefixes with placeholders; numerical measurements remain unchanged.

The manual GitHub Actions workflow runs both pinned packages through the reduced controls and full two-peer integration suite.
