@tool
class_name AttackModifier
extends Resource

@export_placeholder("light, heavy, biological, mechanical, ...") var target_tag: String = ""
# Negative multipliers would heal targets — out of scope at M0. Clamp.
@export var damage_mult: float = 1.0:
	set(value):
		damage_mult = max(0.0, value)
