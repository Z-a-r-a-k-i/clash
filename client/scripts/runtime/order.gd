class_name EntityOrder
extends RefCounted

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

enum Type {
	MOVE,
	ATTACK_MOVE,
	ATTACK,
	HOLD_FIRE_TOGGLE,
	BUILD,
	TRAIN,
	RESEARCH,
	CANCEL,
	SURRENDER,
}

var type: Type

# Common — owner of this order. -1 for player-level orders (e.g. SURRENDER).
var entity_id: int = -1

# MOVE / ATTACK_MOVE / BUILD — destination tile.
var target_tile: Vector2i = Vector2i.ZERO

# ATTACK — primary target id.
var target_entity_id: int = -1

# ATTACK — priority chain (fall back to closest enemy if exhausted and not on hold-fire).
var target_priority_chain: Array[int] = []

# HOLD_FIRE_TOGGLE — desired hold-fire state.
var hold_fire: bool = false

# BUILD / TRAIN / RESEARCH — what to produce, by string id.
var def_id: String = ""

# CANCEL — index into the entity's order_queue, or -1 to cancel persistent_order.
var cancel_index: int = -1
