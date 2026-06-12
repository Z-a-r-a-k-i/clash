@tool
class_name StatusApplyEffect
extends Effect

# Applies `status` (cloned) to the ability's target through the
# resolver-owned StatusSystem application path. Re-applying a status with
# the same status_id replaces the existing instance (refreshes duration).

@export var status: StatusEffect
