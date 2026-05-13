@tool
class_name DevTurnInput
extends RefCounted

# Dev-only turn input state for plan 07b2. Owns selection and pending
# SubmitTurn resources; it does not mutate MatchState or call the resolver.

var _state: MatchState = null
var _registry: EntityRegistry = null
var _active_player_id: int = 0
var _selected_entity_id: int = -1
var _submissions: Dictionary[int, SubmitTurn] = {}
var _status_message: String = ""


func _init() -> void:
	clear_submissions()


func bind_context(state: MatchState, registry: EntityRegistry) -> void:
	_state = state
	_registry = registry
	_ensure_submit_turn(0)
	_ensure_submit_turn(1)
	if _selected_entity_id >= 0 and not _is_selectable(_selected_entity_id):
		_selected_entity_id = -1


func set_active_player_id(player_id: int) -> void:
	_active_player_id = player_id
	_ensure_submit_turn(player_id)
	if _selected_entity_id >= 0 and not _is_selectable(_selected_entity_id):
		_selected_entity_id = -1


func active_player_id() -> int:
	return _active_player_id


func selected_entity_id() -> int:
	return _selected_entity_id


func status_message() -> String:
	return _status_message


func select_entity(entity_id: int) -> bool:
	if not _is_selectable(entity_id):
		_selected_entity_id = -1
		_status_message = "Select an active P%d entity." % _active_player_id
		return false
	_selected_entity_id = entity_id
	var entity := _state.get_entity_by_id(entity_id)
	_status_message = "Selected %s #%d" % [_def_id_for_entity(entity), entity_id]
	return true


func clear_selection() -> void:
	_selected_entity_id = -1


func issue_move(target_tile: Vector2i) -> bool:
	var actor := _selected_entity()
	if actor == null:
		_status_message = "Select a unit before issuing MOVE."
		return false
	if _state == null or _state.tile_grid == null or not _state.tile_grid.is_in_bounds(target_tile):
		_status_message = "MOVE target is outside the map."
		return false
	var def := _def_for_entity(actor)
	if def == null or def.movement == null or def.movement.speed_tiles_per_turn <= 0:
		_status_message = "%s cannot move." % _def_id_for_entity(actor)
		return false
	var order := EntityOrder.new()
	order.type = EntityOrder.Type.MOVE
	order.entity_id = actor.id
	order.target_tile = target_tile
	_append_order(order)
	_status_message = "Queued MOVE for #%d to %s." % [actor.id, str(target_tile)]
	return true


func issue_attack(target_entity_id: int) -> bool:
	var actor := _selected_entity()
	if actor == null:
		_status_message = "Select a unit before issuing ATTACK."
		return false
	var target := _live_entity(target_entity_id)
	if target == null or target.owner_player_id < 0 or target.owner_player_id == _active_player_id:
		_status_message = "ATTACK needs a live enemy target."
		return false
	var def := _def_for_entity(actor)
	if def == null or def.combat == null or def.combat.damage <= 0:
		_status_message = "%s cannot attack." % _def_id_for_entity(actor)
		return false
	var order := EntityOrder.new()
	order.type = EntityOrder.Type.ATTACK
	order.entity_id = actor.id
	order.target_priority_chain = [target_entity_id]
	_append_order(order)
	_status_message = "Queued ATTACK for #%d against #%d." % [actor.id, target_entity_id]
	return true


func issue_gather(target_entity_id: int) -> bool:
	var actor := _selected_entity()
	if actor == null:
		_status_message = "Select a worker before issuing GATHER."
		return false
	var actor_def := _def_for_entity(actor)
	if actor_def == null or actor_def.gather == null or actor.gather_state == null:
		_status_message = "%s cannot gather." % _def_id_for_entity(actor)
		return false
	var target := _live_entity(target_entity_id)
	var target_def := _def_for_entity(target)
	if target == null or not _is_gather_target(target, target_def):
		_status_message = "GATHER needs a resource source or refinery target."
		return false
	var order := EntityOrder.new()
	order.type = EntityOrder.Type.GATHER
	order.entity_id = actor.id
	order.target_entity_id = target_entity_id
	_append_order(order)
	_status_message = "Queued GATHER for #%d from #%d." % [actor.id, target_entity_id]
	return true


func surrender_active_player() -> void:
	_submission_for(_active_player_id).surrender = true
	_status_message = "P%d will surrender on resolve." % _active_player_id


func clear_submissions() -> void:
	_submissions.clear()
	_submissions[0] = SubmitTurn.new()
	_submissions[1] = SubmitTurn.new()
	_status_message = "Queues cleared."


func submit_for_player(player_id: int) -> SubmitTurn:
	return _submission_for(player_id)


func queued_order_count(player_id: int) -> int:
	return _submission_for(player_id).orders.size()


func _append_order(order: EntityOrder) -> void:
	_submission_for(_active_player_id).orders.append(order)


func _submission_for(player_id: int) -> SubmitTurn:
	_ensure_submit_turn(player_id)
	return _submissions[player_id]


func _ensure_submit_turn(player_id: int) -> void:
	if not _submissions.has(player_id) or _submissions[player_id] == null:
		_submissions[player_id] = SubmitTurn.new()


func _selected_entity() -> Entity:
	if _selected_entity_id < 0 or not _is_selectable(_selected_entity_id):
		return null
	return _state.get_entity_by_id(_selected_entity_id)


func _is_selectable(entity_id: int) -> bool:
	var entity := _live_entity(entity_id)
	return entity != null and entity.owner_player_id == _active_player_id


func _live_entity(entity_id: int) -> Entity:
	if _state == null:
		return null
	var entity := _state.get_entity_by_id(entity_id)
	if entity == null or entity.current_hp <= 0:
		return null
	return entity


func _def_for_entity(entity: Entity) -> EntityDef:
	if entity == null or _registry == null:
		return null
	return _registry.get_by_id(_def_id_for_entity(entity))


func _def_id_for_entity(entity: Entity) -> String:
	if entity == null:
		return ""
	return entity.current_def_id if entity.current_def_id != "" else entity.def_id


func _is_gather_target(target: Entity, target_def: EntityDef) -> bool:
	if target == null or target_def == null:
		return false
	if target_def.resource_source != null:
		return true
	return target_def.tags.has("refinery")
