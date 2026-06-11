@tool
class_name CombatDef
extends Resource

@export var damage: int = 0:
	set(value):
		damage = max(0, value)
@export var attack_range: int = 0:
	set(value):
		attack_range = max(0, value)
@export_placeholder("ground, flying, burrowed, ...") var target_layers: Array[String] = []
@export var attack_modifiers: Array[AttackModifier] = []
@export var attacks_before_movement: bool = true
@export var attacks_after_movement: bool = false
@export var has_initiative: bool = false
