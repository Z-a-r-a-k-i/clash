@tool
class_name ResourceSourceDef
extends Resource

@export_enum("minerals", "gas") var resource_type: String = "minerals"
@export var yield_per_worker_per_turn: int = 1
@export var capacity: int = -1  # -1 = infinite
@export var requires_extractor: bool = false
