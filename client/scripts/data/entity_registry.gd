class_name EntityRegistry
extends Resource

# Manually-maintained list of all EntityDefs in the game.
# Loaded once at match start; the resolver looks up entity defs through it
# by string id.

@export var entities: Array[EntityDef] = []

var _by_id: Dictionary = {}


func get_by_id(id: String) -> EntityDef:
	if _by_id.is_empty() and not entities.is_empty():
		for e in entities:
			if e != null and e.id != "":
				_by_id[e.id] = e
	return _by_id.get(id)
