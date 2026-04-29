class_name TransformEffect
extends Effect

# Replaces the target's current_def_id with another EntityDef (e.g. tank → siege_tank).
# Used for SC2-style mode transitions; modes are different EntityDefs sharing the
# capability composition shape.
#
# We store the target by string id (looked up via EntityRegistry) instead of a
# typed EntityDef reference to avoid the circular class_name dependency
# EntityDef → AbilitiesDef → AbilityDef → Effect → TransformEffect → EntityDef.

@export var to_def_id: String = ""
