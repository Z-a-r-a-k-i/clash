class_name EntityRegistry
extends Resource

# Manually-maintained list of all game data defs. Loaded once at match
# start; the resolver looks up defs through it by string id.
#
# `entities` and `researches` are kept as separate exports so the editor
# UI groups them naturally. Both indexes are lazily built on first lookup.

@export var entities: Array[EntityDef] = []
@export var researches: Array[ResearchDef] = []

var _by_id: Dictionary = {}
var _research_by_id: Dictionary = {}
var _indexes_built: bool = false


func get_by_id(id: String) -> EntityDef:
	if not _indexes_built:
		_build_indexes()
	return _by_id.get(id)


func get_research_by_id(id: String) -> ResearchDef:
	if not _indexes_built:
		_build_indexes()
	return _research_by_id.get(id)


func _build_indexes() -> void:
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
	_research_by_id.clear()
	for r in researches:
		if r == null or r.id == "":
			continue
		if _research_by_id.has(r.id):
			push_error(
				(
					"EntityRegistry: duplicate research id '%s' (path: %s vs %s)"
					% [r.id, _research_by_id[r.id].resource_path, r.resource_path]
				)
			)
			continue
		_research_by_id[r.id] = r
	_indexes_built = true
