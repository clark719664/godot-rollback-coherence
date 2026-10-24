extends RefCounted
## For explicitly registered Node2D-driven hitboxes. Call once after every
## gameplay transform write and before the ONE regular rollback physics step.
## Queries and health changes run only after this boundary.
static func step_with_hitboxes(space: RID, delta: float, hitboxes: Array) -> void:
	for hitbox in hitboxes:
		hitbox.force_update_transform()
	RapierPhysicsServer2D.space_step(space, delta)
	RapierPhysicsServer2D.space_flush_queries(space)
