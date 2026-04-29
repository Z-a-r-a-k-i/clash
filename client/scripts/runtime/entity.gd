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

# Optional capability-paired state — null unless def has the matching capability.
var production_state: ProductionState
var gather_state: GatherState
