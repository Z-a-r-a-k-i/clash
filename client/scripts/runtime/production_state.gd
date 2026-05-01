class_name ProductionState
extends RefCounted

# Per-entity runtime state for entities with a ProductionDef capability.
# Tracks the build queue and per-item progress.
#
# Each queue item is a Dictionary keyed by KEY_*; values for KEY_KIND are
# one of the KIND_* constants. Kept as a Dictionary rather than a typed
# class to avoid an extra class_name file for what is essentially a small
# tagged record; we may promote to a typed ProductionItem class later
# if the dictionary access pattern becomes painful.
#
# All accesses to queue entries should use these constants — never raw
# string literals — to prevent typos and keep the schema centralised.

# Dictionary keys for items in `queue`.
const KEY_DEF_ID := "def_id"
const KEY_KIND := "kind"
const KEY_TURNS_REMAINING := "turns_remaining"

# Values for `KEY_KIND` — distinguishes whether `def_id` refers to an
# EntityDef (unit/building to spawn) or a ResearchDef (effect to apply).
const KIND_UNIT := "unit"
const KIND_RESEARCH := "research"

var queue: Array[Dictionary] = []


func clone() -> ProductionState:
	var c := ProductionState.new()
	c.queue = []
	for item in queue:
		# Dictionaries hold primitive values; .duplicate() is sufficient.
		c.queue.append(item.duplicate())
	return c
