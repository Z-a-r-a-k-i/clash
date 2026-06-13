class_name AiMemory
extends RefCounted

# Cross-turn state for one AiPlayer (plan m1/01). Owned by the caller
# (dev play mode / simulation harness), reset on scenario load. This is
# what makes fog-honesty workable: the planner acts on what it has SEEN,
# not on the live state of hidden enemies.

# enemy entity id -> {"def_id": String, "origin": Vector2i,
# "building": bool, "turn": int (last seen)}
var enemy_last_seen: Dictionary = {}

# Mirrored guess of the enemy main's origin (static map knowledge:
# spawn positions are fixed and mirrored). Vector2i(-1, -1) = unset.
var enemy_base_guess: Vector2i = Vector2i(-1, -1)

# Next index into AiConfig.build_order.
var build_order_index: int = 0

# Producer ids that already received a rally order.
var rallied_producer_ids: Dictionary = {}

# Producer ids that already received a repeat-train toggle.
var repeat_train_producer_ids: Dictionary = {}

var attacking: bool = false
var last_enemy_seen_turn: int = -1000
var scout_unit_id: int = -1
