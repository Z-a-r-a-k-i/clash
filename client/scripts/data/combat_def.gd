class_name CombatDef
extends Resource

@export var damage: int = 0
@export var attack_range: int = 0
@export_placeholder("ground, flying, burrowed, ...") var target_layers: Array[String] = []
@export var attack_modifiers: Array[AttackModifier] = []
@export var attacks_per_turn: int = 1
