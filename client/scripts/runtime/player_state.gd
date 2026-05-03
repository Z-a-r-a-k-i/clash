class_name PlayerState
extends RefCounted

# Per-player runtime state. Two players per match at MVP.

var player_id: int = 0
var minerals: int = 0
var gas: int = 0
var pop_used: int = 0
var pop_cap: int = 0
var has_surrendered: bool = false

# Set of completed research def_ids. Append-only at M0 (no research can
# be unlearned). Read by future ability-gating code (plan node wires
# USE_ABILITY); written by ProductionSystem on RESEARCH completion.
var unlocked_researches: Array[String] = []


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
