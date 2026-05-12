@tool
class_name ProductionDef
extends Resource

# Lists are by string id (looked up via EntityRegistry / future ResearchRegistry
# at runtime). String ids avoid GDScript's circular class_name resolution and
# serialize cleanly to any wire format.
@export var produces: Array[String] = []  # entity ids the building can train
@export var researches: Array[String] = []  # research ids the building can run
# Queue must accept at least one item; clamp to >=1.
@export var queue_capacity: int = 1:
	set(value):
		queue_capacity = max(1, value)
@export var rally_offset: Vector2i = Vector2i(0, 1)
