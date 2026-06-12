@tool
class_name StatusEffect
extends Resource

# A status currently applied to an entity (plan node 14). Statuses are
# runtime MODIFIERS over resolver mechanics: they can block shooting or
# movement, scale stats, override combat data (siege), add end-of-turn
# damage or healing, and grant initiative. MechanicsSystem is the single
# query layer that combines an entity's def with its active statuses —
# resolver systems must not read these fields directly.
#
# Duration is a property of any status: > 0 counts down at end of turn
# and the status expires at 0; INDEFINITE stays until explicitly cleared.
#
# Multipliers are integer percents (100 = unchanged) so the resolver
# stays free of float math (ADR 0013 determinism).
#
# Resource for save/load round-trips; clone() stays explicit for the
# resolver's pure-function contract.

const INDEFINITE := -1

# -1 = inherit the def's value (used by the attack-window overrides).
const OVERRIDE_INHERIT := -1
const OVERRIDE_OFF := 0
const OVERRIDE_ON := 1

@export var status_id: String = ""
@export var source_ability_id: String = ""
@export var duration_turns: int = INDEFINITE

# Blocking statuses.
@export var blocks_move: bool = false
@export var blocks_attack: bool = false

# Mechanics modifiers.
@export var speed_mult_pct: int = 100
@export var damage_mult_pct: int = 100
@export var grants_initiative: bool = false
@export var override_attacks_before_movement: int = OVERRIDE_INHERIT
@export var override_attacks_after_movement: int = OVERRIDE_INHERIT

# Combat data overrides; -1 = inherit from CombatDef.
@export var damage_override: int = -1
@export var attack_range_override: int = -1

# Splash: attacks by an entity carrying this status also damage every
# entity (any owner — friendly fire) whose rect lies within
# `splash_radius` tiles of the target's rect, for `splash_falloff_pct`
# percent of the attack damage. 0 = no splash.
@export var splash_radius: int = 0
@export var splash_falloff_pct: int = 50

# Turn-hook: applied at end of turn. Negative = damage (can destroy),
# positive = regeneration (capped at max HP).
@export var end_of_turn_hp_delta: int = 0

# ---- Presentation hints (renderer-only; simulation MUST NOT read) ----
@export var sprite_key: String = ""
@export var overlay_keys: Array[String] = []


func clone() -> StatusEffect:
	var c := StatusEffect.new()
	c.status_id = status_id
	c.source_ability_id = source_ability_id
	c.duration_turns = duration_turns
	c.blocks_move = blocks_move
	c.blocks_attack = blocks_attack
	c.speed_mult_pct = speed_mult_pct
	c.damage_mult_pct = damage_mult_pct
	c.grants_initiative = grants_initiative
	c.override_attacks_before_movement = override_attacks_before_movement
	c.override_attacks_after_movement = override_attacks_after_movement
	c.damage_override = damage_override
	c.attack_range_override = attack_range_override
	c.splash_radius = splash_radius
	c.splash_falloff_pct = splash_falloff_pct
	c.end_of_turn_hp_delta = end_of_turn_hp_delta
	c.sprite_key = sprite_key
	c.overlay_keys = overlay_keys.duplicate()
	return c
