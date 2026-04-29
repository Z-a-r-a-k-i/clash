class_name MatchState
extends RefCounted

# Top-level mutable state container for a single match. Passed to the
# resolver each turn; the resolver returns a new MatchState (or mutates
# in place — TBD during resolver implementation).
#
# Holds:
# - turn counter and seeded RNG seed (RNG unused at M0 per ADR 0013)
# - per-player state (resources, pop, surrender flag)
# - all entities on the field (units, buildings, neutrals)
# - tile grid (terrain, occupancy) — populated by TileGrid (plan node 01)
# - per-player visibility mask — populated by VisionSystem; deferred until
#   plan node 02 / 06 implementation

var turn_index: int = 0
var rng_seed: int = 0  # reserved; unused at M0

var players: Array[PlayerState] = []
var entities: Array[Entity] = []
var next_entity_id: int = 1  # monotonic id allocator

var tile_grid: TileGrid  # populated at scenario load; null until then.

var winner_player_id: int = -1  # -1 = ongoing; >=0 = match over
var match_over: bool = false


func get_entity_by_id(id: int) -> Entity:
	# Linear scan is fine at M0 (~50 entities). Promote to a Dictionary
	# index if profiling shows this hot.
	for e in entities:
		if e != null and e.id == id:
			return e
	return null


func get_player(player_id: int) -> PlayerState:
	for p in players:
		if p != null and p.player_id == player_id:
			return p
	return null


func allocate_entity_id() -> int:
	var id := next_entity_id
	next_entity_id += 1
	return id


func entities_sorted_by_id() -> Array[Entity]:
	# Stable iteration order for the resolver (per ADR 0013). Insertion order
	# of `entities` happens to equal id order today (allocator is monotonic
	# and removals don't reorder), but we don't want determinism to depend
	# on that invariant — so we sort explicitly.
	var out: Array[Entity] = entities.duplicate()
	out.sort_custom(func(a: Entity, b: Entity) -> bool: return a.id < b.id)
	return out
