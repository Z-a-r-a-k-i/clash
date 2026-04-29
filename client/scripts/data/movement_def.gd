class_name MovementDef
extends Resource

@export var speed_tiles_per_turn: int = 0
@export_placeholder("ground, flying, burrowed") var default_layer: String = "ground"
@export var pathable_terrain_tags: Array[String] = []
@export var impassable_terrain_tags: Array[String] = []
