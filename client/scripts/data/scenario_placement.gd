@tool
class_name ScenarioPlacement
extends Resource

# A single entity placed at scenario load time.
@export var def_id: String = ""
@export var owner_player_id: int = 0
@export var origin: Vector2i = Vector2i.ZERO
@export var current_layer: String = ""  # empty => use def's MovementDef.default_layer
@export var initial_hp_override: int = -1  # -1 => use HealthDef.max_hp
