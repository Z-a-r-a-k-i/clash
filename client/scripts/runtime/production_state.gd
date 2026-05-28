@tool
class_name ProductionState
extends Resource

# Per-entity runtime state for entities with a ProductionDef capability.
# Two-part shape introduced in plan node 05:
#
#   `active` is the slot currently paying & ticking. Empty Dict = idle.
#   `queue`  is an ordered list of unpaid declarations.
#
# Lazy-deduct: TRAIN/RESEARCH orders append to `queue` without deducting
# cost. Cost is deducted when the slot transitions — i.e., when `active`
# becomes empty and the queue head is affordable. This lets a player
# declare a long production plan up front without sinking minerals.
#
# Active slot keys: KEY_DEF_ID, KEY_KIND, KEY_TURNS_REMAINING, plus the
# per-slot KEY_PAID_* fields recording exactly what was deducted (so
# cancel-active can refund symmetrically and partial-pop refunds work).
#
# Queue items keep only KEY_DEF_ID and KEY_KIND. Cost lookup happens at
# install time via the EntityRegistry — keeping the queue lean.
#
# All accesses to dict entries should use these constants — never raw
# string literals — to prevent typos and keep the schema centralised.

# Dictionary keys for items in `active` and `queue`.
const KEY_DEF_ID := "def_id"
const KEY_KIND := "kind"
const KEY_TURNS_REMAINING := "turns_remaining"

# Active-only keys — recorded at install time so cancel-active can refund
# the exact amount that was paid.
const KEY_PAID_MINERALS := "paid_minerals"
const KEY_PAID_GAS := "paid_gas"
const KEY_PAID_POP := "paid_pop"

# Values for `KEY_KIND` — distinguishes whether `def_id` refers to an
# EntityDef (unit/building to spawn) or a ResearchDef (effect to apply).
const KIND_UNIT := "unit"
const KIND_RESEARCH := "research"

@export var active: Dictionary = {}
@export var queue: Array[Dictionary] = []
@export var repeat_train_enabled: bool = false
@export var repeat_train_def_id: String = ""


func clone() -> ProductionState:
	var c := ProductionState.new()
	c.active = active.duplicate()  # primitive values; shallow duplicate is enough
	c.queue = []
	for item in queue:
		c.queue.append(item.duplicate())
	c.repeat_train_enabled = repeat_train_enabled
	c.repeat_train_def_id = repeat_train_def_id
	return c
