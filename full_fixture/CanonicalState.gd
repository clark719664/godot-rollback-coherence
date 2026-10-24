extends RefCounted
## Delta's native hasher observes dictionary insertion order. Scene groups can
## reorder during a rollback/spawn, so give it stable keys without changing values.
static func ordered(value):
	if value is Dictionary:
		var result := {}
		var keys: Array = value.keys()
		keys.sort_custom(func(a, b): return str(a) < str(b))
		for key in keys: result[key] = ordered(value[key])
		return result
	if value is Array:
		var result := []
		for item in value: result.append(ordered(item))
		return result
	return value
