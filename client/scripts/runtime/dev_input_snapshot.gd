@tool
class_name DevInputSnapshot
extends Resource

# Dev-only continuation state saved alongside a MatchState snapshot or replay
# checkpoint. It intentionally mirrors DevTurnInput's private state without
# becoming a second input implementation.

@export var active_player_id: int = 0
@export var selected_entity_id: int = -1
@export var submit_a: SubmitTurn
@export var submit_b: SubmitTurn
@export var move_assists: Dictionary = {}
@export var future_orders: Dictionary = {}
@export var queue_modifier_active: bool = false
@export var status_message: String = ""


func clone() -> DevInputSnapshot:
	var c: DevInputSnapshot = DevInputSnapshot.new()
	c.active_player_id = active_player_id
	c.selected_entity_id = selected_entity_id
	c.submit_a = submit_a.clone() if submit_a != null else SubmitTurn.new()
	c.submit_b = submit_b.clone() if submit_b != null else SubmitTurn.new()
	c.move_assists = _clone_order_dictionary(move_assists)
	c.future_orders = _clone_future_order_dictionary(future_orders)
	c.queue_modifier_active = queue_modifier_active
	c.status_message = status_message
	return c


func _clone_order_dictionary(source: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not source is Dictionary:
		return out
	var source_dict: Dictionary = source
	for key in source_dict:
		var order: EntityOrder = source_dict[key]
		if order != null:
			out[int(key)] = order.clone()
	return out


func _clone_future_order_dictionary(source: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not source is Dictionary:
		return out
	var source_dict: Dictionary = source
	for key in source_dict:
		var cloned_queue: Array[EntityOrder] = []
		var raw_queue: Variant = source_dict[key]
		if not raw_queue is Array:
			continue
		var queue: Array = raw_queue
		for item in queue:
			var order: EntityOrder = item
			if order != null:
				cloned_queue.append(order.clone())
		if not cloned_queue.is_empty():
			out[int(key)] = cloned_queue
	return out
