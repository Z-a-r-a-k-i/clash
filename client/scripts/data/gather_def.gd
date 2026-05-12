@tool
class_name GatherDef
extends Resource

@export var gather_per_turn: int = 1:
	set(value):
		gather_per_turn = max(0, value)
@export var carry_amount: int = 5:
	set(value):
		carry_amount = max(0, value)
@export_placeholder("minerals, gas") var accepts_resource_types: Array[String] = []
