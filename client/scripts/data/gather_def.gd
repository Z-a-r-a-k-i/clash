class_name GatherDef
extends Resource

@export var gather_per_turn: int = 1
@export var carry_amount: int = 5
@export_placeholder("minerals, gas") var accepts_resource_types: Array[String] = []
