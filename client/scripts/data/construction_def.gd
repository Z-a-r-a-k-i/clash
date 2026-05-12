@tool
class_name ConstructionDef
extends Resource

@export var build_time_turns: int = 1
@export var mineral_cost: int = 0
@export var gas_cost: int = 0
@export_placeholder("worker, barracks, factory, ...") var built_by_tag: String = ""
@export_placeholder("optional, e.g. gas_geyser") var requires_target_tag: String = ""
