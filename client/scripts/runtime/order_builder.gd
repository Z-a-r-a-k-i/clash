@tool
class_name OrderBuilder
extends RefCounted

# Group-order fan-out. Each method takes a list of entity ids plus the
# per-order parameters and returns N EntityOrder instances — one per id.
# The orders are independent EntityOrder instances, so the resolver's
# read-only-post-submission contract holds even if a caller mutates
# something inside one of the returned orders.
#
# BUILD / TRAIN / RESEARCH are intentionally not here — those are
# single-producer orders, not group fan-out. Plan node 05 owns the
# issuance helpers when production logic lands.


static func fan_out_move(entity_ids: Array[int], target_tile: Vector2i) -> Array[EntityOrder]:
	var out: Array[EntityOrder] = []
	for id in entity_ids:
		var o := EntityOrder.new()
		o.type = EntityOrder.Type.MOVE
		o.entity_id = id
		o.target_tile = target_tile
		out.append(o)
	return out


static func fan_out_attack_move(
	entity_ids: Array[int], target_tile: Vector2i, target_priority_chain: Array[int] = []
) -> Array[EntityOrder]:
	var out: Array[EntityOrder] = []
	for id in entity_ids:
		var o := EntityOrder.new()
		o.type = EntityOrder.Type.ATTACK_MOVE
		o.entity_id = id
		o.target_tile = target_tile
		# Duplicate the chain per order so callers mutating one entity's
		# chain post-submission can't leak into another's.
		o.target_priority_chain = target_priority_chain.duplicate()
		out.append(o)
	return out


static func fan_out_attack(
	entity_ids: Array[int], target_priority_chain: Array[int]
) -> Array[EntityOrder]:
	var out: Array[EntityOrder] = []
	for id in entity_ids:
		var o := EntityOrder.new()
		o.type = EntityOrder.Type.ATTACK
		o.entity_id = id
		o.target_priority_chain = target_priority_chain.duplicate()
		out.append(o)
	return out


static func fan_out_hold_fire_toggle(entity_ids: Array[int], hold_fire: bool) -> Array[EntityOrder]:
	var out: Array[EntityOrder] = []
	for id in entity_ids:
		var o := EntityOrder.new()
		o.type = EntityOrder.Type.HOLD_FIRE_TOGGLE
		o.entity_id = id
		o.hold_fire = hold_fire
		out.append(o)
	return out


static func fan_out_cancel(entity_ids: Array[int], cancel_index: int = -1) -> Array[EntityOrder]:
	var out: Array[EntityOrder] = []
	for id in entity_ids:
		var o := EntityOrder.new()
		o.type = EntityOrder.Type.CANCEL
		o.entity_id = id
		o.cancel_index = cancel_index
		out.append(o)
	return out


static func fan_out_gather(entity_ids: Array[int], target_entity_id: int) -> Array[EntityOrder]:
	var out: Array[EntityOrder] = []
	for id in entity_ids:
		var o := EntityOrder.new()
		o.type = EntityOrder.Type.GATHER
		o.entity_id = id
		o.target_entity_id = target_entity_id
		out.append(o)
	return out
