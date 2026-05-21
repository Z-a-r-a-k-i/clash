@tool
class_name MovementDef
extends Resource

@export var speed_tiles_per_turn: int = 0:
	set(value):
		speed_tiles_per_turn = max(0, value)
@export_range(0.0, 1.0, 0.05) var post_shot_move_fraction: float = 0.5:
	set(value):
		post_shot_move_fraction = clampf(value, 0.0, 1.0)
@export_placeholder("ground, flying, burrowed") var default_layer: String = "ground"
@export var pathable_terrain_tags: Array[String] = []
@export var impassable_terrain_tags: Array[String] = []
