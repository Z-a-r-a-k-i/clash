@tool
class_name AbilityCost
extends Resource

@export_enum("hp", "minerals", "gas") var type: String = "hp"
# Clamp via setter — the resolver assumes amount >= 0; negatives would
# resemble a refund and the cost-payment math doesn't support that.
@export var amount: int = 0:
	set(value):
		amount = max(0, value)
