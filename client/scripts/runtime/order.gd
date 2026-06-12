@tool
class_name EntityOrder
extends Resource

# Orders are runtime queue entries describing what an entity should do.
# Tagged-union shape: a `type` enum + the relevant fields filled in. Other
# fields are unused and at their default values. Cleaner to dispatch on
# `order.type` in the resolver than to maintain a polymorphic class
# hierarchy, and serializes cleanly for replays / save-load when M2 lands.
#
# Order types correspond to plan/m0/03-action-queue-and-orders.md.
#
# Naming: EntityOrder rather than Order to avoid potential conflicts with
# Godot's internal naming. Construction is via `EntityOrder.new()` followed
# by direct field assignment — static factories were dropped because
# referencing the class_name inside the class's own static methods can fail
# during first-compile in Godot 4.6 (the parser can't always resolve a
# script's own class_name as its return type).
#
# Mutation contract: callers shouldn't mutate an EntityOrder once it's
# submitted to the resolver — by convention, not enforcement. `clone()`
# produces a fully independent deep copy (target_priority_chain is
# duplicated), so `SubmitTurn.clone()` and `Entity.clone()` use it to
# guarantee input state never aliases a cloned MatchState's orders.
#
# Note: there is no `SURRENDER` here. Surrender is a per-turn flag on
# `SubmitTurn`, not an order — see plan/m0/03-action-queue-and-orders.md.

# INVALID is the explicit sentinel for an uninitialized order. Without it,
# `var type: Type` would default to enum value 0 (MOVE), masking bugs where
# the type was never assigned.
enum Type {
	INVALID = -1,
	MOVE = 0,
	ATTACK_MOVE = 1,
	TARGET = 2,
	BUILD = 3,
	TRAIN = 4,
	RESEARCH = 5,
	CANCEL = 6,
	GATHER = 7,
	USE_ABILITY = 8,
	SET_RALLY_POINT = 9,
	REPEAT_TRAIN_TOGGLE = 10,
}

@export var type: Type = Type.INVALID

# Owner of this order; the resolver validates it against the submitting
# player's id and drops orders that don't match.
@export var entity_id: int = -1

# MOVE / ATTACK_MOVE / BUILD — destination tile.
@export var target_tile: Vector2i = Vector2i.ZERO

# TARGET / ATTACK_MOVE — priority list. Resolver fires at the first live,
# visible entity in this list; if the target is invalid or out of range, falls
# back to closest visible enemy in range. Primary target lives at index 0.
@export var target_priority_chain: Array[int] = []

# BUILD / TRAIN / RESEARCH / USE_ABILITY — what to produce or use, by string id.
@export var def_id: String = ""

# CANCEL — index into the entity's order_queue, or -1 to clear standing intent.
@export var cancel_index: int = -1

# GATHER / TARGET-generated MOVE — target entity id. For GATHER this can be a
# ResourceSource (mineral patch / geyser) or a refinery. For MOVE, non-negative
# means the input layer generated the move to reach that target's weapon range.
# -1 = unset.
@export var target_entity_id: int = -1

# SET_RALLY_POINT — ProductionState.RALLY_MODE_*.
@export var mode: String = ""

# REPEAT_TRAIN_TOGGLE and future binary standing commands.
@export var enabled: bool = false


func clone() -> EntityOrder:
	var c := EntityOrder.new()
	c.type = type
	c.entity_id = entity_id
	c.target_tile = target_tile
	# Duplicate the chain — primitive ints, but the array itself must be
	# independent so a caller mutating the clone's chain doesn't leak into
	# the original.
	c.target_priority_chain = target_priority_chain.duplicate()
	c.def_id = def_id
	c.cancel_index = cancel_index
	c.target_entity_id = target_entity_id
	c.mode = mode
	c.enabled = enabled
	return c
