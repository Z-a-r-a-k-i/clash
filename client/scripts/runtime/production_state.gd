class_name ProductionState
extends RefCounted

# Per-entity runtime state for entities with a ProductionDef capability.
# Tracks the build queue and per-item progress.
#
# Each queue item is a Dictionary { "def_id": String, "kind": String,
# "turns_remaining": int }. Kept as a Dictionary rather than a typed
# class to avoid an extra class_name file for what is essentially a small
# tagged record; we may promote to a typed ProductionItem class later
# if the dictionary access pattern becomes painful.
#
# `kind` is "unit" | "research" — distinguishes whether def_id refers to
# an EntityDef (unit/building to spawn) or a ResearchDef (effect to apply).

var queue: Array[Dictionary] = []
