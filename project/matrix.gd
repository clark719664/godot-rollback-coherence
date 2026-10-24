extends SceneTree

const CoherentStep = preload("coherent_step.gd")
const DELTA := 1.0 / 60.0
const CYCLES := 20
var actor: Node2D
var body: StaticBody2D
var sentinel: RigidBody2D
var manager: StateManager2D
var world: World2D
var space: RID
var steps := 0
var suite_failures := 0
var cached_sentinel: Transform2D
var cached_velocity: Vector2
var cached_hitbox: Transform2D
var restore_checks := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	world = root.world_2d
	space = world.space
	PhysicsServer2D.space_set_active(space, false)
	var container := Node2D.new()
	container.name = "Simulation"
	root.add_child(container)
	actor = Node2D.new()
	actor.name = "Player"
	container.add_child(actor)
	body = StaticBody2D.new()
	body.name = "Hitbox"
	body.collision_layer = 4
	body.collision_mask = 0
	actor.add_child(body)
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(16, 16)
	collision.shape = rectangle
	body.add_child(collision)
	sentinel = RigidBody2D.new()
	sentinel.name = "ClockSentinel"
	sentinel.gravity_scale = 0
	sentinel.linear_damp = 0
	sentinel.linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	sentinel.can_sleep = false
	sentinel.collision_layer = 0
	container.add_child(sentinel)
	sentinel.position = Vector2(1000, 1000)
	sentinel.linear_velocity = Vector2(60, 0)
	var sentinel_shape := CollisionShape2D.new()
	sentinel_shape.shape = rectangle
	sentinel.add_child(sentinel_shape)
	manager = StateManager2D.new()
	manager.root_node = container
	root.add_child(manager)
	actor.position = Vector2(300, 0)
	await process_frame
	step("coherent")
	cached_sentinel = PhysicsServer2D.body_get_state(sentinel.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM)
	cached_velocity = PhysicsServer2D.body_get_state(sentinel.get_rid(), PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	cached_hitbox = PhysicsServer2D.body_get_state(body.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM)
	manager.cache_state(space, 0)
	if manager.ordered_cache_tags().size() != 1:
		push_error("Real Rapier cache was not created")
		quit(2)
		return
	var output: Array = []
	for delay_ms in [0, 100, 200]:
		for depth in [1, 6, 12, 24]:
			for mode in ["baseline", "force_only", "flush_only", "mode_toggle", "coherent", "direct"]:
				var result := run_case(delay_ms, depth, mode)
				if result.has("error"):
					print("RESTORE_ERROR=" + JSON.stringify(result))
					quit(1)
					return
				output.append(result)
	print("RESULTS_JSON=" + JSON.stringify(output))
	print("RESTORE_CHECKS=" + str(restore_checks))
	print("SUITE_FAILURES=" + str(suite_failures))
	quit(0 if suite_failures == 0 else 1)

func run_case(delay_ms: int, depth: int, mode: String) -> Dictionary:
	var misses := 0
	var false_hits := 0
	var transform_mismatches := 0
	var health_mismatches := 0
	var clock_mismatches := 0
	var query_count := 0
	var expected_steps := 0
	var started := Time.get_ticks_usec()
	for cycle in CYCLES:
		# A deterministic late-input scheduler: arrival is delayed by 0/6/12
		# simulation ticks; history depth is independently stress-tested.
		if not restore_checked():
			suite_failures += 1
			return {"error": "cache restore failed"}
		actor.position = Vector2(300, 0)
		body.force_update_transform()
		for waiting_tick in maxi(1, roundi(delay_ms / (1000.0 / 60.0))):
			actor.position = Vector2(300 + 16 * (waiting_tick + 1), 0)
			step("coherent")
		# Prediction must really advance the independent rigid body before restore.
		var predicted: Transform2D = PhysicsServer2D.body_get_state(sentinel.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM)
		if predicted.is_equal_approx(cached_sentinel):
			return {"error": "prediction did not advance sentinel"}
		# Real input arrives and restores the actual cached physics snapshot.
		if not restore_checked():
			suite_failures += 1
			return {"error": "cache restore failed"}
		actor.position = Vector2(300, 0)
		var start_transform: Transform2D = PhysicsServer2D.body_get_state(sentinel.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM)
		var reference_health := 10000
		var actual_health := 10000
		var before_steps := steps
		for replay_tick in depth:
			# Both directions matter: stale positions can miss or invent damage.
			var expected_hit := (replay_tick + cycle) % 2 == 0
			actor.position = Vector2.ZERO if expected_hit else Vector2(300, 0)
			step(mode)
			var hit := bomb_hit()
			query_count += 1
			if expected_hit:
				reference_health -= 10
			if hit:
				actual_health -= 10
			if expected_hit and not hit:
				misses += 1
			if not expected_hit and hit:
				false_hits += 1
			var server: Transform2D = PhysicsServer2D.body_get_state(body.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM)
			if server != body.global_transform:
				transform_mismatches += 1
		if reference_health != actual_health:
			health_mismatches += 1
		var end_transform: Transform2D = PhysicsServer2D.body_get_state(sentinel.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM)
		if steps - before_steps != depth or absf(end_transform.origin.x - start_transform.origin.x - depth) > 0.02:
			clock_mismatches += 1
		expected_steps += depth
	var fixed := mode in ["coherent", "direct"]
	if fixed and (misses + false_hits + transform_mismatches + health_mismatches + clock_mismatches) != 0:
		suite_failures += 1
	# Negative controls must expose the original stale-query behavior.
	if not fixed and misses + false_hits == 0:
		suite_failures += 1
	return {"input_delay_ms": delay_ms, "rollback_depth": depth, "cycles": CYCLES, "mode": mode,
		"queries": query_count, "missed_hits": misses, "false_hits": false_hits,
		"transform_mismatches": transform_mismatches, "health_mismatches": health_mismatches,
		"clock_mismatches": clock_mismatches, "replay_steps": expected_steps,
		"elapsed_usec": Time.get_ticks_usec() - started}

func step(mode: String) -> void:
	if mode == "coherent":
		CoherentStep.step_with_hitboxes(space, DELTA, [body])
	else:
		if mode == "direct":
			PhysicsServer2D.body_set_state(body.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, body.global_transform)
		RapierPhysicsServer2D.space_step(space, DELTA)
		RapierPhysicsServer2D.space_flush_queries(space)
		if mode == "force_only":
			body.force_update_transform()
		if mode == "mode_toggle":
			var original_mode := PhysicsServer2D.body_get_mode(body.get_rid())
			PhysicsServer2D.body_set_mode(body.get_rid(), PhysicsServer2D.BODY_MODE_STATIC)
			PhysicsServer2D.body_set_state(body.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, body.global_transform)
			PhysicsServer2D.body_set_mode(body.get_rid(), original_mode)
		if mode == "flush_only":
			body.force_update_transform()
			RapierPhysicsServer2D.space_flush_queries(space)
	steps += 1

func bomb_hit() -> bool:
	var circle := CircleShape2D.new()
	circle.radius = 100
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.collision_mask = 4
	for result in world.direct_space_state.intersect_shape(query):
		if result.rid == body.get_rid():
			return true
	return false

func step_count_guard() -> void:
	# Deliberately no clock reset: manager restores the real Rapier snapshot.
	pass



func restore_checked() -> bool:
	# This fault-injection option proves that a true-but-no-op importer fails.
	if not "--simulate-noop-restore" in OS.get_cmdline_user_args():
		if not manager.load_cached_state(space, 0):
			return false
	var restored: Transform2D = PhysicsServer2D.body_get_state(sentinel.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM)
	var velocity: Vector2 = PhysicsServer2D.body_get_state(sentinel.get_rid(), PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
	var hitbox: Transform2D = PhysicsServer2D.body_get_state(body.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM)
	restore_checks += 1
	return restored.is_equal_approx(cached_sentinel) and velocity.is_equal_approx(cached_velocity) and hitbox.is_equal_approx(cached_hitbox)
