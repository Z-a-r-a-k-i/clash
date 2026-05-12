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
	ATTACK_MOVE,
	ATTACK,
	HOLD_FIRE_TOGGLE,
	BUILD,
	TRAIN,
	RESEARCH,
	CANCEL,
	GATHER,
}

@export var type: Type = Type.INVALID

# Owner of this order; the resolver validates it against the submitting
# player's id and drops orders that don't match.
@export var entity_id: int = -1

# MOVE / ATTACK_MOVE / BUILD — destination tile.
@export var target_tile: Vector2i = Vector2i.ZERO

# ATTACK — priority list. Resolver fires at the first live entity in this
# list; if all are dead and unit isn't on hold-fire, falls back to closest
# enemy in range. Primary target lives at index 0; the chain is a single
# list per plan/m0/02-tick-based-resolver.md "Target chain resolution".
@export var target_priority_chain: Array[int] = []

# HOLD_FIRE_TOGGLE — desired hold-fire state.
@export var hold_fire: bool = false

# BUILD / TRAIN / RESEARCH — what to produce, by string id.
@export var def_id: String = ""

# CANCEL — index into the entity's order_queue, or -1 to cancel persistent_order.
@export var cancel_index: int = -1

# GATHER — entity to gather from. Can be a ResourceSource (mineral patch /
# geyser) or a refinery (the resolver translates to the underlying geyser).
# -1 = unset.
@export var target_entity_id: int = -1


func clone() -> EntityOrder:
	var c := EntityOrder.new()
	c.type = type
	c.entity_id = entity_id
	c.target_tile = target_tile
	# Duplicate the chain — primitive ints, but the array itself must be
	# independent so a caller mutating the clone's chain doesn't leak into
	# the original.
	c.target_priority_chain = target_priority_chain.duplicate()
	c.hold_fire = hold_fire
	c.def_id = def_id
	c.cancel_index = cancel_index
	c.target_entity_id = target_entity_id
	return c
