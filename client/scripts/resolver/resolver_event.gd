class_name ResolverEvent
extends RefCounted

# Events emitted by the resolver during a turn. Tagged-union shape matching
# EntityOrder — single class with a `type` enum and per-type fields. The
# event order in `ResolveResult.events` is significant: it's the canonical
# replay sequence and the order clients animate in.

# INVALID is a sentinel for an uninitialized event (catches bugs where
# `var e := ResolverEvent.new()` is appended without `e.type` being set).
enum Type {
	INVALID = -1,
	ENTITY_MOVED = 0,
	ENTITY_DAMAGED,
	ENTITY_DESTROYED,
	ENTITY_TRANSFORMED,
	BUILD_COMPLETED,
	MATCH_ENDED,
	WORKER_GATHERED,
	WORKER_DEPOSITED,
	RESOURCE_DEPLETED,
}

var type: Type = Type.INVALID

# Common — most events have an actor (the entity that did the thing) and
# optionally a target (the entity it acted on). -1 means "not applicable".
var actor_id: int = -1
var target_id: int = -1

# ENTITY_MOVED — origin transition (top-left tile of the entity's footprint).
var from_origin: Vector2i = Vector2i.ZERO
var to_origin: Vector2i = Vector2i.ZERO

# ENTITY_DAMAGED — damage dealt this tick + the target's HP after.
# WORKER_GATHERED / WORKER_DEPOSITED — amount field reused (ints, no unit
# conflict).
var damage: int = 0
var hp_after: int = 0

# ENTITY_TRANSFORMED — current_def_id swap (e.g. tank -> siege_tank).
var new_def_id: String = ""

# BUILD_COMPLETED — the def id that finished construction / training.
# WORKER_DEPOSITED — the resource type ("minerals" | "gas").
var def_id: String = ""

# MATCH_ENDED — winner. -1 means unknown / draw (M0 has no draws).
var winner_player_id: int = -1

# WORKER_GATHERED — yield this tick.
# WORKER_DEPOSITED — total amount deposited (= worker.gather_state.carry).
var amount: int = 0
