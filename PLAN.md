# Godot coherent rollback milestone

## Spec
Reproduce child StaticBody2D hitbox transforms lagging behind a restored Node2D parent during a same-frame rollback burst. Use official Godot and real Rapier, pinned versions. Record SceneTree transform, PhysicsServer body transform, and actual shape-query results. Compare baseline, force_update_transform, and explicit body_set_state synchronization for 0/100/200 ms simulated input delay and rollback depths. A successful mitigation must fix actual query/hit health outcomes, not only log parsing.

## Plan
1. Fetch issue #534 v3 fixture and pinned prebuilt engine/plugin, inspect relevant scripts.
2. Build a small headless reproduction from the real fixture's parent/child collision setup; verify failure before writing mitigation.
3. Test transform-flush and explicit server synchronization independently; add focused implementation only after evidence.
4. Run matrix, package source harness, measurements, exact versions and limitations.

## Ledger
- Local llm wrapper/Ollama unavailable, confirmed by parent; mechanical work proceeds directly.
- Upstream latest observed: Rapier v0.36.0. Original fixture requests v0.8.36 and Godot 4.6.2. Test original pins first.
- Upstream discussion explicitly distinguishes Godot node cached transforms from Rapier server state. Engine defect remains unproven.

## Completed ledger
- Downloaded original fixture, original plugin asset, current plugin asset, official Godot4.6.2 and4.7.2. Original plugin requires4.7; tests use4.7.2, no minimum-version edits.
- Reproduced real stale server transform and stale broadphase query before mitigation. Baseline exit1. Normal-frame control exit0.
- Added explicit transform synchronization before one normal physics step; no zero-step or engine modifications.
- Added matrix modes baseline/force_only/flush_only/mode_toggle/coherent/direct. Added sixth mode after first summary, so final count72/plugin144total.
- Both packaged runner suites pass, including2,880verified restore checks/plugin, no-op restore fault injection failing as expected, and independent rigid-body clock guard.
- Full issue networking, netfox3D workaround and custom manual-stepping engine fork remain untested; no engine defect asserted.
