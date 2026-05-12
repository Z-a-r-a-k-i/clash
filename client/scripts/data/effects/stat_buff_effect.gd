@tool
class_name StatBuffEffect
extends Effect

# Applies stat overrides to the target for N turns.
# When AbilityDef.target_type == "self" this is a buff; "enemy" makes it a debuff.

@export var duration_turns: int = 0
@export var damage_mult: float = 1.0
@export var speed_mult: float = 1.0
