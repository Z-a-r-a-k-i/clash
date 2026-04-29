class_name EntityRegistry
extends Resource

# Manually-maintained list of all EntityDefs in the game.
# Loaded once at match start; the resolver looks up entity defs through it
# by string id.

@export var entities: Array[EntityDef] = []

var _by_id: Dictionary = {}
var _by_id_built: bool = false


func get_by_id(id: String) -> EntityDef:
	if not _by_id_built:
		_build_index()
	return _by_id.get(id)


func _build_index() -> void:
	_by_id.clear()
	for e in entities:
		if e == null or e.id == "":
			continue
		if _by_id.has(e.id):
			# Fail loud — silently overwriting would mean two EntityDefs share
			# an id and lookups become non-deterministic. This is a content
			# error, not a runtime condition the resolver should tolerate.
			push_error(
				(
					"EntityRegistry: duplicate entity id '%s' (path: %s vs %s)"
					% [e.id, _by_id[e.id].resource_path, e.resource_path]
				)
			)
			continue
		_by_id[e.id] = e
	_by_id_built = true
