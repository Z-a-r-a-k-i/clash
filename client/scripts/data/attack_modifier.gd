@tool
class_name AttackModifier
extends Resource

@export_placeholder("light, heavy, biological, mechanical, ...") var target_tag: String = ""
# Integer percent (100 = unchanged, 150 = +50%). Integer math keeps the
# resolver deterministic across platforms (ADR 0013). Negative values
# would heal targets — out of scope; clamp at 0.
@export var damage_mult_pct: int = 100:
	set(value):
		damage_mult_pct = maxi(0, value)
