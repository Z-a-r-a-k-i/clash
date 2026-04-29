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
# At least one attack per turn for combat-capable units; clamp to >=1.
@export var attacks_per_turn: int = 1:
	set(value):
		attacks_per_turn = max(1, value)
