extends Node
class_name PhysicsDriver
## Fixture integration: transforms/animation -> one normal step -> damage queries.
@export var state_manager: StateManager2D
var space: RID
var physics_tick_time: float
var pending_blasts: Array = []
var successful_restores := 0
var restore_checks := 0
var observed_rewinds := 0

func _init() -> void:
	add_to_group("network_sync")

func _ready() -> void:
	space = get_viewport().world_2d.space
	PhysicsServer2D.space_set_active(space, false)
	SyncManager.sync_stopped.connect(func(): state_manager.clear_cache())
	SyncManager.sync_started.connect(func(): physics_tick_time = SyncManager.tick_time)

func queue_blast(center: Vector2, radius: float, damage: int) -> void:
	# Copy values: the spawn manager despawns the bomb before this phase runs.
	pending_blasts.append({"center": center, "radius": radius, "damage": damage})

func _network_postprocess(_input: Dictionary) -> void:
	# The registry is the fixture's explicit player-hitbox registry. Discovering it
	# each tick also avoids keeping freed bodies alive after spawn/despawn.
	for rid in SyncManager.bodies:
		var owner: Node = SyncManager.bodies[rid]
		if is_instance_valid(owner) and owner.is_inside_tree():
			owner.get_node("StaticBody2D").force_update_transform()
	RapierPhysicsServer2D.space_step(space, physics_tick_time)
	RapierPhysicsServer2D.space_flush_queries(space)
	_apply_blasts()

func _apply_blasts() -> void:
	for blast in pending_blasts:
		var circle := CircleShape2D.new()
		circle.radius = blast.radius
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = circle
		query.transform = Transform2D(0.0, blast.center)
		query.collision_mask = 1 << 2
		var hits: Array = get_viewport().world_2d.direct_space_state.intersect_shape(query)
		if has_node("/root/TestRig"):
			get_node("/root/TestRig").check_blast(blast.center, blast.radius, hits.map(func(hit): return hit.rid))
		for result in hits:
			var owner = SyncManager.bodies.get(result.rid)
			if is_instance_valid(owner) and owner.is_inside_tree(): owner.hurt(blast.damage)
	pending_blasts.clear()

func _save_state() -> Dictionary:
	state_manager.cache_state(space, SyncManager.current_tick)
	var state := {"_tick": SyncManager.current_tick}
	for rid in SyncManager.bodies:
		var owner: Node = SyncManager.bodies[rid]
		if is_instance_valid(owner) and owner.is_inside_tree():
			state[str(owner.get_path())] = {
				"t": PhysicsServer2D.body_get_state(rid, PhysicsServer2D.BODY_STATE_TRANSFORM),
				"lv": PhysicsServer2D.body_get_state(rid, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY),
				"av": PhysicsServer2D.body_get_state(rid, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY)}
	return state

func _load_state(state: Dictionary) -> void:
	pending_blasts.clear()
	var tick: int = state.get("_tick")
	var tags: Array = state_manager.ordered_cache_tags()
	for i in range(tags.size() - 1, -1, -1):
		if tags[i] == tick:
			var before := {}
			for rid in SyncManager.bodies:
				before[rid] = PhysicsServer2D.body_get_state(rid, PhysicsServer2D.BODY_STATE_TRANSFORM)
			if not state_manager.load_cached_state(space, i):
				_restore_failed("native cache load failed for tick %s" % tick)
				return
			RapierPhysicsServer2D.space_flush_queries(space)
			for rid in SyncManager.bodies:
				var owner: Node = SyncManager.bodies[rid]
				if not is_instance_valid(owner) or not owner.is_inside_tree(): continue
				var expected: Dictionary = state.get(str(owner.get_path()), {})
				if expected.is_empty():
					_restore_failed("missing saved hitbox for tick %s" % tick)
					return
				var actual: Transform2D = PhysicsServer2D.body_get_state(rid, PhysicsServer2D.BODY_STATE_TRANSFORM)
				var velocity: Vector2 = PhysicsServer2D.body_get_state(rid, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
				var angular: float = PhysicsServer2D.body_get_state(rid, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY)
				if actual != expected.t or velocity != expected.lv or angular != expected.av:
					_restore_failed("restored hitbox transform/velocity mismatch for tick %s" % tick)
					return
				restore_checks += 1
				if before[rid] != actual: observed_rewinds += 1
			successful_restores += 1
			return
	_restore_failed("missing cached state for tick %s" % tick)

func _restore_failed(message: String) -> void:
	# A failed import must stop rollback; replaying from the future is invalid.
	SyncManager._handle_fatal_error("RESTORE_ERROR: " + message)
