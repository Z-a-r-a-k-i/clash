class_name NetworkClientController
extends RefCounted

var _state: MatchState = null
var _registry: EntityRegistry = null
var _player_slot: int = -1
var _submit_pending := false
var _last_error := ""


func bind_authoritative_state(
	state: MatchState, registry: EntityRegistry, player_slot: int
) -> void:
	_state = state
	_registry = registry
	_player_slot = player_slot
	_submit_pending = false
	_last_error = ""


func player_slot() -> int:
	return _player_slot


func mark_submit_pending(pending: bool) -> void:
	_submit_pending = pending


func submit_pending() -> bool:
	return _submit_pending


func validation_error() -> String:
	return _last_error


func can_submit_turn(submit: SubmitTurn) -> bool:
	_last_error = ""
	if _submit_pending:
		_last_error = "submit_pending"
		return false
	if _state == null:
		_last_error = "missing_state"
		return false
	if submit == null:
		_last_error = "missing_submit"
		return false
	if _player_slot < 0:
		_last_error = "missing_player_slot"
		return false
	for order in submit.orders:
		if order == null:
			_last_error = "invalid_order"
			return false
		var entity: Entity = _state.get_entity_by_id(order.entity_id)
		if entity == null or entity.current_hp <= 0:
			_last_error = "invalid_order_entity"
			return false
		if entity.owner_player_id != _player_slot:
			_last_error = "wrong_player_order"
			return false
	return true


func submit_from_input(input: DevTurnInput) -> SubmitTurn:
	if input == null:
		_last_error = "missing_input"
		return null
	var submit: SubmitTurn = input.submit_for_player(_player_slot)
	if not can_submit_turn(submit):
		return null
	_submit_pending = true
	return submit.clone()
