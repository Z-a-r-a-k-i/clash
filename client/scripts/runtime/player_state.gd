@tool
class_name PlayerState
extends Resource

# Per-player runtime state. Two players per match at MVP.
#
# Resource (not RefCounted) so a MatchState save via ResourceSaver
# round-trips player resources, pop, and unlocked_researches without
# a mirror class.

@export var player_id: int = 0
@export var minerals: int = 0
@export var gas: int = 0
@export var pop_used: int = 0
@export var pop_cap: int = 0
@export var has_surrendered: bool = false

# Set of completed research def_ids. Append-only at M0 (no research can
# be unlearned). Read by future ability-gating code (plan node wires
# USE_ABILITY); written by ProductionSystem on RESEARCH completion.
@export var unlocked_researches: Array[String] = []


func clone() -> PlayerState:
	var c := PlayerState.new()
	c.player_id = player_id
	c.minerals = minerals
	c.gas = gas
	c.pop_used = pop_used
	c.pop_cap = pop_cap
	c.has_surrendered = has_surrendered
	c.unlocked_researches = unlocked_researches.duplicate()
	return c
