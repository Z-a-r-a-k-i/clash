@tool
class_name Entity
extends Resource

# Per-instance runtime state for one entity on the field. Distinct from
# EntityDef (the immutable type definition). Many entities share the same
# def; each gets its own Entity record with mutable per-instance state.
#
# Optional state fields parallel the def's optional capabilities:
# `production_state` is non-null only if def.production != null, etc.
#
# Resource (not RefCounted) so MatchState save/load round-trips every
# field via ResourceSaver. Each runtime field is @export. clone() stays
# explicit for the resolver's pure-function contract; Resource.duplicate
# semantics differ in subtle ways (cache-mode interactions) we don't want
# in the hot path.

@export var id: int = -1  # unique runtime id (not def_id). -1 = unallocated; MatchState.allocate_entity_id() starts at 1.
@export var def_id: String = ""  # canonical EntityDef id
@export var current_def_id: String = ""  # == def_id unless TransformEffect swapped
@export var owner_player_id: int = 0
@export var origin: Vector2i = Vector2i.ZERO
@export var current_layer: String = ""  # may differ from def.movement.default_layer
@export var current_hp: int = 0

@export var order_queue: Array[EntityOrder] = []  # orders queued for this turn
# Deprecated compatibility field for older save snapshots. The resolver clears
# and ignores it; long-range move assistance lives in the input layer.
@export var persistent_order: EntityOrder
@export var focus_target_entity_id: int = -1  # preferred attack target; -1 = auto-acquire

@export var ability_cooldowns: Dictionary = {}  # { ability_id: turns_remaining }
@export var active_buffs: Array[ActiveBuff] = []
@export var ability_cast: AbilityCastState
@export var is_hidden: bool = false  # recomputed each turn
@export var halt_on_sight: bool = false  # toggled by HALT_ON_SIGHT_TOGGLE order

# Per-turn move budget. Reset to 0 at end-of-turn; incremented by the
# movement system on each successful step. Compared against
# def.movement.speed_tiles_per_turn to gate further movement this turn.
@export var moves_used_this_turn: int = 0

# Per-instance remaining capacity for ResourceSource entities (mineral
# patches, gas geysers). -1 = infinite or N/A (non-source entities). The
# scenario loader / spawner seeds this from def.resource_source.capacity
# when the entity is created. The gather system decrements it on each
# yield tick.
@export var current_resource_amount: int = -1

# Construction lifecycle (plan node 05). Buildings only.
# `is_constructing` is set to true at BUILD distribution and cleared on
# completion. While true, the building blocks pathing and is vulnerable
# but doesn't function (no production / no pop_provides).
@export var is_constructing: bool = false
# Turns until completion. -1 = N/A (not under construction).
@export var construction_turns_remaining: int = -1
# Worker currently locked to this build. -1 = paused (worker dead/missing
# or never assigned). When non-(-1) and that worker is alive + adjacent,
# construction_turns_remaining ticks each turn.
@export var construction_worker_id: int = -1

# Worker side of the lock. -1 = free. While non-(-1), the worker rejects
# new MOVE / ATTACK / GATHER orders — it's committed to constructing the
# referenced building.
@export var locked_to_building_id: int = -1

# Optional capability-paired state — null unless def has the matching capability.
@export var production_state: ProductionState
@export var gather_state: GatherState


func clone() -> Entity:
	var c := Entity.new()
	c.id = id
	c.def_id = def_id
	c.current_def_id = current_def_id
	c.owner_player_id = owner_player_id
	c.origin = origin
	c.current_layer = current_layer
	c.current_hp = current_hp

	# Deep-clone every EntityOrder so the cloned MatchState's orders never
	# alias the input state's. Cheap at M0 scale (< handful of orders per
	# entity per turn) and removes the "read-only by convention" footgun.
	c.order_queue = []
	for o in order_queue:
		if o != null:
			c.order_queue.append(o.clone())
		else:
			c.order_queue.append(null)
	c.persistent_order = persistent_order.clone() if persistent_order != null else null
	c.focus_target_entity_id = focus_target_entity_id

	c.ability_cooldowns = ability_cooldowns.duplicate()
	c.active_buffs = []
	for b in active_buffs:
		if b != null:
			c.active_buffs.append(b.clone())
	c.ability_cast = ability_cast.clone() if ability_cast != null else null
	c.is_hidden = is_hidden
	c.halt_on_sight = halt_on_sight
	c.moves_used_this_turn = moves_used_this_turn
	c.current_resource_amount = current_resource_amount
	c.is_constructing = is_constructing
	c.construction_turns_remaining = construction_turns_remaining
	c.construction_worker_id = construction_worker_id
	c.locked_to_building_id = locked_to_building_id

	if production_state != null:
		c.production_state = production_state.clone()
	if gather_state != null:
		c.gather_state = gather_state.clone()

	return c
