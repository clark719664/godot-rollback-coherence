extends Node
## Automation only: the fixture's ENet, SyncManager, spawn manager and physics run unchanged.
var game: Node
var role := "server"
var port := 25341
var result_path := ""
var elapsed := 0.0
var rollbacks := 0
var replayed_ticks := 0
var mismatches := 0
var samples := {}
var spawn_names := {}
var observed_animated := false
var last_complete := 0
var query_checks := 0
var query_mismatches := 0
var hashes := {}
var initial_types := []
var observed_blasts: Array = []
const TARGET := 240

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() != 2: continue
		match pair[0]:
			"role": role = pair[1]
			"port": port = int(pair[1])
			"result": result_path = pair[1]
	SyncManager.state_loaded.connect(func(count): rollbacks += 1; replayed_ticks += count)
	SyncManager.remote_state_mismatch.connect(func(_tick, _peer, _local, _remote): mismatches += 1)
	SyncManager.sync_error.connect(func(msg): finish("sync_error: " + msg))
	call_deferred("begin")

func begin() -> void:
	game = get_tree().current_scene
	SyncManager.max_buffer_size = 120
	SyncManager.max_state_mismatch_count = 10000
	SyncManager.debug_physics_process_msecs = 0
	SyncManager.debug_process_msecs = 0
	SyncManager.interpolation = false
	game.port_field.text = str(port)
	# An actual NetworkAnimationPlayer moves the nested hitbox relative to its player.
	for player in [game.get_node("ServerPlayer"), game.get_node("ClientPlayer")]:
		var animation := Animation.new()
		animation.length = 0.5
		animation.loop_mode = Animation.LOOP_LINEAR
		var track := animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(track, NodePath("StaticBody2D:position"))
		animation.track_insert_key(track, 0.0, Vector2(-80, 0))
		animation.track_insert_key(track, 0.25, Vector2(80, 0))
		animation.track_insert_key(track, 0.5, Vector2(-80, 0))
		var library := AnimationLibrary.new()
		library.add_animation("Hitbox", animation)
		var animator := NetworkAnimationPlayer.new()
		animator.name = "HitboxAnimation"
		player.add_child(animator)
		animator.add_animation_library("", library)
		animator.play("Hitbox")
	if role == "server": game._on_server_button_pressed()
	else: game._on_client_button_pressed()

func scripted_input(player: Node) -> Dictionary:
	var tick: int = SyncManager.input_tick
	var input := {}
	# Converge, repeatedly reverse, drop bombs while moving through their blast areas.
	if tick <= 22:
		input.input_vector = Vector2.RIGHT if player.name == "ServerPlayer" else Vector2.LEFT
	elif tick < 175:
		input.input_vector = Vector2.RIGHT if (tick / 7) % 2 == 0 else Vector2.LEFT
	if tick in [8, 14, 27, 48, 71, 96, 121, 146]: input.drop_bomb = true
	return input

func normalize(value):
	if value is Dictionary:
		var result := {}
		var keys: Array = value.keys()
		keys.sort_custom(func(a, b): return str(a) < str(b))
		for key in keys: result[str(key)] = normalize(value[key])
		return result
	if value is Array:
		var result := []
		for item in value: result.append(normalize(item))
		return result
	if value is Vector2: return [value.x, value.y]
	if value is Transform2D: return [normalize(value.x), normalize(value.y), normalize(value.origin)]
	if value is NodePath or value is StringName: return str(value)
	return value

func typed(value):
	if value is Dictionary:
		var result := []
		for key in value:
			if key != "$": result.append([str(key), typeof(key), typed(value[key])])
		return result
	if value is Array:
		return value.map(func(item): return typed(item))
	return str(typeof(value)) + ":" + var_to_bytes(value).hex_encode()

func check_blast(center: Vector2, radius: float, actual: Array) -> void:
	query_checks += 1
	var expected: Array = []
	for rid in SyncManager.bodies:
		var player: Node = SyncManager.bodies[rid]
		var body: Node2D = player.get_node("StaticBody2D")
		var local: Vector2 = body.to_local(center)
		var nearest := local.clamp(Vector2(-64, -64), Vector2(64, 64))
		if local.distance_squared_to(nearest) <= radius * radius: expected.append(rid)
	if expected.size() != actual.size(): query_mismatches += 1; return
	for rid in expected:
		if rid not in actual: query_mismatches += 1; return

func observe_blast(center: Vector2, radius: float, actual: Array) -> void:
	observed_blasts.append([center, radius, actual.duplicate()])

func verify_observed_blasts() -> void:
	# Evaluate the original timer's results at the authoritative post-movement
	# boundary, matching the fixed driver's phase and independent rectangle oracle.
	for blast in observed_blasts: check_blast(blast[0], blast[1], blast[2])
	observed_blasts.clear()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed > 35.0: finish("timeout"); return
	if not is_instance_valid(game) or not SyncManager.started: return
	for child in game.get_children():
		if str(child.name).begins_with("Bomb") or str(child.name).begins_with("Explosion"):
			spawn_names[str(child.name)] = true
	if abs(game.get_node("ServerPlayer/StaticBody2D").position.x) > 1.0: observed_animated = true
	var complete: int = min(SyncManager._state_complete_tick, TARGET)
	while last_complete < complete:
		last_complete += 1
		var frame = SyncManager._get_state_frame(last_complete)
		if frame == null: finish("missing complete frame"); return
		# Every serialized gameplay state, including timers, RNG, animation and spawn state.
		samples[str(last_complete)] = normalize(frame.data)
		hashes[str(last_complete)] = {"cached": frame.data.get("$"), "fresh": SyncManager.sync_booster.hash_special_dict(frame.data)}
		if last_complete == 1: initial_types = typed(frame.data)
	if complete >= TARGET and SyncManager.current_tick >= TARGET + 18:
		finish("")

func finish(error: String) -> void:
	set_process(false)
	var final_state: Dictionary = samples.get(str(TARGET), {})
	var players := {}
	for key in final_state:
		if key.ends_with("/ServerPlayer") or key.ends_with("/ClientPlayer"): players[key] = final_state[key]
	var result := {"error": error, "role": role, "rollbacks": rollbacks,
		"replayed_ticks": replayed_ticks, "state_mismatches": mismatches,
		"animated_hitbox": observed_animated, "observed_spawns": spawn_names.keys(),
		"complete_tick": last_complete, "players": players, "samples": samples}
	result.query_checks = query_checks
	result.query_mismatches = query_mismatches
	result.hashes = hashes
	result.initial_types = initial_types
	var driver = game.get_node("PhysicsDriver") if is_instance_valid(game) else null
	if driver and "successful_restores" in driver:
		result.successful_restores = driver.successful_restores
		result.restore_checks = driver.restore_checks
		result.observed_rewinds = driver.observed_rewinds
	var file := FileAccess.open(result_path, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(result, "", true, true))
	print("FULL_FIXTURE_RESULT=" + JSON.stringify({"error": error, "role": role,
		"rollbacks": rollbacks, "mismatches": mismatches, "players": players}))
	get_tree().quit(0 if error.is_empty() else 1)
