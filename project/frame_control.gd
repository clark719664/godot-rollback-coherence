extends SceneTree

var actor: Node2D
var body: StaticBody2D
var world: World2D
var space: RID

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	world = root.world_2d
	space = world.space
	PhysicsServer2D.space_set_active(space, false)
	actor = Node2D.new()
	root.add_child(actor)
	body = StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	actor.add_child(body)
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(16, 16)
	collision.shape = rectangle
	body.add_child(collision)
	actor.position = Vector2(300, 0)
	await process_frame
	RapierPhysicsServer2D.space_step(space, 1.0 / 60)
	RapierPhysicsServer2D.space_flush_queries(space)
	var before := sample("predicted_outside")
	actor.position = Vector2.ZERO
	var restored := sample("restored_parent")
	await process_frame
	RapierPhysicsServer2D.space_step(space, 1.0 / 60)
	RapierPhysicsServer2D.space_flush_queries(space)
	var stepped := sample("after_step_flush")
	print(JSON.stringify({"before": before, "restored": restored, "stepped": stepped}))
	quit(0 if stepped.hit else 1)

func sample(label: String) -> Dictionary:
	var circle := CircleShape2D.new()
	circle.radius = 100
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.collision_mask = 4
	var results := world.direct_space_state.intersect_shape(query)
	var server: Transform2D = PhysicsServer2D.body_get_state(body.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM)
	return {"phase": label, "node_x": body.global_position.x, "server_x": server.origin.x, "hit": not results.is_empty()}
