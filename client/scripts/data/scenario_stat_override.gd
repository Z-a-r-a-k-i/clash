@tool
class_name ScenarioStatOverride
extends Resource

# Overrides a single field of a single entity def for one match, without
# mutating the canonical .tres. Polymorphic value via three typed slots —
# pick the one matching the field's type. The `value_kind` discriminator
# tells the consumer (the scenario loader) which slot to read; it must be
# set explicitly because GDScript has no native sum-type encoding.
@export var entity_def_id: String = ""
@export_placeholder("health, combat, movement, ...") var capability: String = ""
@export var field: String = ""

@export_enum("int", "float", "string") var value_kind: String = "int"
@export var value_int: int = 0
@export var value_float: float = 0.0
@export var value_string: String = ""
