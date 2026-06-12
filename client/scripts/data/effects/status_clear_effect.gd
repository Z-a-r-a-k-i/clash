@tool
class_name StatusClearEffect
extends Effect

# Clears the status with `status_id` from the ability's target (e.g.
# unsiege removes "sieged"). Clearing a status that isn't present is a
# no-op, not an error.

@export var status_id: String = ""
