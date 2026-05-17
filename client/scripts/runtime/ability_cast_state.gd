@tool
class_name AbilityCastState
extends Resource

# Runtime state for an in-progress delayed ability cast.

@export var ability_id: String = ""
@export var turns_remaining: int = 0:
	set(value):
		turns_remaining = max(0, value)


func clone() -> AbilityCastState:
	var c: AbilityCastState = AbilityCastState.new()
	c.ability_id = ability_id
	c.turns_remaining = turns_remaining
	return c
