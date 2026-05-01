class_name Entity
extends RefCounted

# Per-instance runtime state for one entity on the field. Distinct from
# EntityDef (the immutable type definition). Many entities share the same
# def; each gets its own Entity record with mutable per-instance state.
#
# Optional state fields parallel the def's optional capabilities:
# `production_state` is non-null only if def.production != null, etc.

var id: int = -1  # unique runtime id (not def_id). -1 = unallocated; MatchState.allocate_entity_id() starts at 1.
var def_id: String = ""  # canonical EntityDef id
var current_def_id: String = ""  # == def_id unless TransformEffect swapped
var owner_player_id: int = 0
var origin: Vector2i = Vector2i.ZERO
var current_layer: String = ""  # may differ from def.movement.default_layer
var current_hp: int = 0

var order_queue: Array[EntityOrder] = []  # orders queued for this turn
var persistent_order: EntityOrder  # move/attack-move that persists across turns

var ability_cooldowns: Dictionary = {}  # { ability_id: turns_remaining }
var active_buffs: Array[ActiveBuff] = []
var is_hidden: bool = false  # recomputed each turn
var hold_fire: bool = false  # toggled by HOLD_FIRE_TOGGLE order

# Per-turn move budget. Reset to 0 at end-of-turn; incremented by the
# movement system on each successful step. Compared against
# def.movement.speed_tiles_per_turn to gate further movement this turn.
var moves_used_this_turn: int = 0

# Optional capability-paired state — null unless def has the matching capability.
var production_state: ProductionState
var gather_state: GatherState


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

	c.ability_cooldowns = ability_cooldowns.duplicate()
	c.active_buffs = []
	for b in active_buffs:
		if b != null:
			c.active_buffs.append(b.clone())
	c.is_hidden = is_hidden
	c.hold_fire = hold_fire
	c.moves_used_this_turn = moves_used_this_turn

	if production_state != null:
		c.production_state = production_state.clone()
	if gather_state != null:
		c.gather_state = gather_state.clone()

	return c
