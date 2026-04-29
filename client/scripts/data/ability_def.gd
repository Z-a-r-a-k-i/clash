class_name AbilityDef
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export_enum("self", "ally", "enemy", "tile", "area") var target_type: String = "self"
@export var target_range: int = 0
@export var costs: Array[AbilityCost] = []
@export var cooldown_turns: int = 0
@export var cast_time_turns: int = 0
@export var effect: Effect
