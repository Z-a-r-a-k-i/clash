@tool
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
# Research id required to use this ability. Empty = always available.
# Forward-compat data field (plan node 05) — the gate-check consumer
# lands when USE_ABILITY is wired in a future plan node.
@export var requires_research_id: String = ""
