# Verified implementation ledger

The reduced synchronization reproduction and its 144-case matrix were completed first. The continuation then used the original v3 scene, native Delta Rollback extension, ENet transport, spawn manager and timers.

1. A real two-peer baseline reproduced divergent health and stale collision decisions under actual delayed UDP transport.
2. The driver's postprocess phase now synchronizes registered moving/animated child hitboxes, runs one ordinary physics step, then processes copied blast requests.
3. A separate native hash-order bug was isolated with confirmed-frame Variant byte/type manifests. Stable dictionary ordering before hashing fixes it without hiding native hashes or normalizing values.
4. Full gameplay tests compare all 240 confirmed states against a zero-delay reference. A geometric oracle and intentional query-before-step fault establish that peer agreement alone cannot pass a broken scheduler.
5. Restore API results and saved server transforms/velocities are checked; counters require successful native imports and observed physical rewinds.
6. Both pinned plugins pass the full suite. The original/fault negative controls fail the collision oracle. The reduced no-op importer and rigid-body clock controls remain intact.
7. Fresh-clone defaults use .deps and .runs beneath the repository root. Dependency preparation, the reduced runner and full suite were exercised in an isolated copy. Manual game preparation preserves the original input/menu and passed a headless startup smoke check.

Boundaries: only the fixture's registered Node2D-driven StaticBody2D contract is supported. CharacterBody caches, Area signals, dynamic physics-body lifecycle and cross-platform determinism remain unverified. No custom engine builds or system network changes were used. The local llm wrapper/Ollama were unavailable as established by the parent session; mechanical work proceeded directly.
