class_name NetworkMatchHub
extends RefCounted

const MESSAGE := preload("res://scripts/network/network_message.gd")
const DEFAULT_SCENARIO_PATH := "res://data/scenarios/mvp_map.tres"
const DEFAULT_REGISTRY_PATH := "res://data/entity_registry.tres"
const DEFAULT_TUNABLES_PATH := "res://data/tunables.tres"
const DEFAULT_REPLAY_DIR := "user://tmp/network_replays"

var _scenario_path: String = DEFAULT_SCENARIO_PATH
var _registry_path: String = DEFAULT_REGISTRY_PATH
var _tunables_path: String = DEFAULT_TUNABLES_PATH
var _replay_dir: String = DEFAULT_REPLAY_DIR
var _matches_by_code: Dictionary = {}
var _match_code_by_peer: Dictionary[int, String] = {}
var _next_code_index: int = 1


func configure(
	scenario_path: String = DEFAULT_SCENARIO_PATH,
	registry_path: String = DEFAULT_REGISTRY_PATH,
	tunables_path: String = DEFAULT_TUNABLES_PATH,
	replay_dir: String = DEFAULT_REPLAY_DIR
) -> void:
	_scenario_path = scenario_path
	_registry_path = registry_path
	_tunables_path = tunables_path
	_replay_dir = replay_dir


func create_match(peer_id: int) -> Dictionary:
	if _match_code_by_peer.has(peer_id):
		return _failure("already_in_match")
	var loaded: LoadedScenario = _load_scenario()
	var tunables: Tunables = load(_tunables_path) as Tunables
	if loaded == null or tunables == null:
		return _failure("load_failed")
	var code: String = _allocate_code()
	var replay: MatchReplay = MatchReplay.new()
	replay.initial_session = _make_session(loaded.state, loaded.registry)
	replay.frames = []
	var peers_by_slot: Dictionary[int, int] = {0: peer_id}
	var slot_by_peer: Dictionary[int, int] = {peer_id: 0}
	var match_data: Dictionary = {
		"code": code,
		"state": loaded.state,
		"registry": loaded.registry,
		"tunables": tunables,
		"peers_by_slot": peers_by_slot,
		"slot_by_peer": slot_by_peer,
		"pending": {},
		"replay": replay,
		"replay_path": _new_replay_path(code),
	}
	_matches_by_code[code] = match_data
	_match_code_by_peer[peer_id] = code
	return {
		"ok": true,
		"code": code,
		"slot": 0,
		"messages": [_match_joined_message(code, 0, 1)],
	}


func join_match(peer_id: int, code: String) -> Dictionary:
	code = code.strip_edges().to_upper()
	if not _matches_by_code.has(code):
		return _failure("invalid_code")
	if _match_code_by_peer.has(peer_id):
		return _failure("already_in_match")
	var match_data: Dictionary = _matches_by_code[code]
	var peers_by_slot: Dictionary = match_data.get("peers_by_slot", {})
	if peers_by_slot.has(1):
		return _failure("match_full")
	if not peers_by_slot.has(0):
		return _failure("match_orphaned")
	peers_by_slot[1] = peer_id
	var slot_by_peer: Dictionary = match_data.get("slot_by_peer", {})
	slot_by_peer[peer_id] = 1
	match_data["peers_by_slot"] = peers_by_slot
	match_data["slot_by_peer"] = slot_by_peer
	_matches_by_code[code] = match_data
	_match_code_by_peer[peer_id] = code
	var messages_by_peer: Dictionary[int, Array] = {}
	var turn_started: Dictionary = _turn_started_message(match_data, true)
	messages_by_peer[peers_by_slot[0]] = [turn_started]
	messages_by_peer[peer_id] = [_match_joined_message(code, 1, 2), turn_started]
	return {
		"ok": true,
		"code": code,
		"slot": 1,
		"messages_by_peer": messages_by_peer,
	}


func submit_turn(peer_id: int, code: String, submit: SubmitTurn) -> Dictionary:
	code = _resolve_code(peer_id, code)
	if code == "" or not _matches_by_code.has(code):
		return _failure("invalid_code")
	var match_data: Dictionary = _matches_by_code[code]
	var slot_by_peer: Dictionary = match_data.get("slot_by_peer", {})
	if not slot_by_peer.has(peer_id):
		return _failure("peer_not_in_match")
	var slot: int = slot_by_peer[peer_id]
	var peers_by_slot: Dictionary = match_data.get("peers_by_slot", {})
	if not peers_by_slot.has(0) or not peers_by_slot.has(1):
		return _failure("waiting_for_player")
	var validation_error: String = _validate_submit(match_data, slot, submit)
	if validation_error != "":
		return _failure(validation_error)
	var pending: Dictionary = match_data.get("pending", {})
	if pending.has(slot):
		return _failure("already_submitted")
	pending[slot] = submit.clone() if submit != null else SubmitTurn.new()
	match_data["pending"] = pending
	if pending.size() < 2:
		_matches_by_code[code] = match_data
		return {"ok": true, "resolved": false, "slot": slot}
	var turn_before: int = (match_data.get("state") as MatchState).turn_index
	var submit_a: SubmitTurn = pending.get(0, SubmitTurn.new())
	var submit_b: SubmitTurn = pending.get(1, SubmitTurn.new())
	var result: ResolveResult = Resolver.resolve(
		match_data.get("state") as MatchState,
		submit_a,
		submit_b,
		match_data.get("registry") as EntityRegistry,
		match_data.get("tunables") as Tunables
	)
	if result == null or result.new_state == null:
		return _failure("resolve_failed")
	_append_replay_frame(match_data, turn_before, submit_a, submit_b)
	match_data["state"] = result.new_state
	match_data["pending"] = {}
	_save_replay(match_data)
	_matches_by_code[code] = match_data
	var messages_by_peer: Dictionary[int, Array] = {}
	var resolved_message: Dictionary = _turn_resolved_message(result)
	var next_turn_message: Dictionary = _turn_started_message(match_data, false)
	for peer in slot_by_peer.keys():
		var target_peer: int = int(peer)
		messages_by_peer[target_peer] = [resolved_message, next_turn_message]
	return {
		"ok": true,
		"resolved": true,
		"slot": slot,
		"messages_by_peer": messages_by_peer,
	}


func cancel_submit_turn(peer_id: int, code: String) -> Dictionary:
	code = _resolve_code(peer_id, code)
	if code == "" or not _matches_by_code.has(code):
		return _failure("invalid_code")
	var match_data: Dictionary = _matches_by_code[code]
	var slot_by_peer: Dictionary = match_data.get("slot_by_peer", {})
	if not slot_by_peer.has(peer_id):
		return _failure("peer_not_in_match")
	var slot: int = slot_by_peer[peer_id]
	var pending: Dictionary = match_data.get("pending", {})
	if not pending.has(slot):
		return _failure("not_submitted")
	pending.erase(slot)
	match_data["pending"] = pending
	_matches_by_code[code] = match_data
	return {"ok": true, "resolved": false, "slot": slot}


func disconnect_peer(peer_id: int) -> Dictionary:
	if not _match_code_by_peer.has(peer_id):
		return {"ok": true, "messages_by_peer": {}}
	var code: String = _match_code_by_peer[peer_id]
	_match_code_by_peer.erase(peer_id)
	if not _matches_by_code.has(code):
		return {"ok": true, "messages_by_peer": {}}
	var match_data: Dictionary = _matches_by_code[code]
	var slot_by_peer: Dictionary = match_data.get("slot_by_peer", {})
	var slot: int = slot_by_peer.get(peer_id, -1)
	var peers_by_slot: Dictionary = match_data.get("peers_by_slot", {})
	var was_active_match: bool = peers_by_slot.has(0) and peers_by_slot.has(1)
	slot_by_peer.erase(peer_id)
	if slot >= 0:
		peers_by_slot.erase(slot)
		var pending: Dictionary = match_data.get("pending", {})
		pending.erase(slot)
		match_data["pending"] = pending
	match_data["slot_by_peer"] = slot_by_peer
	match_data["peers_by_slot"] = peers_by_slot
	var forfeit_message: Dictionary = {}
	if was_active_match and slot >= 0:
		forfeit_message = _resolve_forfeit(match_data, slot)
	_matches_by_code[code] = match_data
	var messages_by_peer: Dictionary[int, Array] = {}
	for peer in slot_by_peer.keys():
		var target_peer: int = int(peer)
		var messages: Array = []
		if not forfeit_message.is_empty():
			messages.append(forfeit_message)
		(
			messages
			. append(
				(
					MESSAGE
					. make(
						MESSAGE.DISCONNECT_NOTICE,
						{
							"code": code,
							"slot": slot,
							"peer_id": peer_id,
						}
					)
				)
			)
		)
		messages_by_peer[target_peer] = messages
	return {"ok": true, "messages_by_peer": messages_by_peer}


func match_state_for_code(code: String) -> MatchState:
	code = code.strip_edges().to_upper()
	if not _matches_by_code.has(code):
		return null
	var state: MatchState = _matches_by_code[code].get("state") as MatchState
	return state.clone() if state != null else null


func match_registry_for_code(code: String) -> EntityRegistry:
	code = code.strip_edges().to_upper()
	if not _matches_by_code.has(code):
		return null
	return _matches_by_code[code].get("registry") as EntityRegistry


func match_replay_path(code: String) -> String:
	code = code.strip_edges().to_upper()
	if not _matches_by_code.has(code):
		return ""
	return _matches_by_code[code].get("replay_path", "")


func _resolve_forfeit(match_data: Dictionary, forfeiting_slot: int) -> Dictionary:
	var state: MatchState = match_data.get("state") as MatchState
	if state == null or state.match_over:
		return {}
	var submit_a: SubmitTurn = SubmitTurn.new()
	var submit_b: SubmitTurn = SubmitTurn.new()
	if forfeiting_slot == 0:
		submit_a.surrender = true
	elif forfeiting_slot == 1:
		submit_b.surrender = true
	else:
		return {}
	var turn_before: int = state.turn_index
	var result: ResolveResult = Resolver.resolve(
		state,
		submit_a,
		submit_b,
		match_data.get("registry") as EntityRegistry,
		match_data.get("tunables") as Tunables
	)
	if result == null or result.new_state == null:
		return {}
	_append_replay_frame(match_data, turn_before, submit_a, submit_b)
	match_data["state"] = result.new_state
	match_data["pending"] = {}
	_save_replay(match_data)
	return _turn_resolved_message(result)


func _load_scenario() -> LoadedScenario:
	var scenario: ScenarioDef = load(_scenario_path) as ScenarioDef
	var registry: EntityRegistry = load(_registry_path) as EntityRegistry
	var tunables: Tunables = load(_tunables_path) as Tunables
	if scenario == null or registry == null or tunables == null:
		return null
	return ScenarioLoader.load(scenario, registry, tunables)


func _allocate_code() -> String:
	var code: String = ""
	while code == "" or _matches_by_code.has(code):
		code = "CL%04d" % _next_code_index
		_next_code_index += 1
	return code


func _new_replay_path(code: String) -> String:
	var stamp: String = Time.get_datetime_string_from_system()
	stamp = stamp.replace(":", "").replace("-", "").replace("T", "_")
	return _replay_dir.path_join("network_%s_%s.tres" % [code, stamp])


func _make_session(state: MatchState, registry: EntityRegistry) -> SavedSession:
	var session: SavedSession = SavedSession.new()
	session.state = state.clone() if state != null else null
	session.registry = registry
	session.input_snapshot = null
	return session


func _append_replay_frame(
	match_data: Dictionary, turn_index: int, submit_a: SubmitTurn, submit_b: SubmitTurn
) -> void:
	var replay: MatchReplay = match_data.get("replay") as MatchReplay
	if replay == null:
		replay = MatchReplay.new()
		replay.initial_session = _make_session(
			match_data.get("state") as MatchState, match_data.get("registry") as EntityRegistry
		)
		replay.frames = []
		match_data["replay"] = replay
	var frame: ReplayTurnFrame = ReplayTurnFrame.new()
	frame.turn_index = turn_index
	frame.submit_a = submit_a.clone() if submit_a != null else SubmitTurn.new()
	frame.submit_b = submit_b.clone() if submit_b != null else SubmitTurn.new()
	replay.frames.append(frame)


func _save_replay(match_data: Dictionary) -> bool:
	var replay: MatchReplay = match_data.get("replay") as MatchReplay
	var path: String = match_data.get("replay_path", "")
	if replay == null or path == "":
		return false
	var absolute_dir: String = ProjectSettings.globalize_path(path).get_base_dir()
	if absolute_dir != "":
		var dir_err: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
		if dir_err != OK:
			push_warning("NetworkMatchHub: could not create replay dir: %d" % dir_err)
			return false
	var err: Error = ResourceSaver.save(replay, path)
	if err != OK:
		push_warning("NetworkMatchHub: replay save failed for %s: %d" % [path, err])
		return false
	return true


func _resolve_code(peer_id: int, code: String) -> String:
	var normalized: String = code.strip_edges().to_upper()
	if normalized != "":
		return normalized
	return _match_code_by_peer.get(peer_id, "")


func _validate_submit(match_data: Dictionary, slot: int, submit: SubmitTurn) -> String:
	if submit == null:
		return "invalid_submit"
	var state: MatchState = match_data.get("state") as MatchState
	if state == null:
		return "missing_state"
	for order_index in range(submit.orders.size()):
		var order: EntityOrder = submit.orders[order_index]
		if order == null:
			return "invalid_order"
		var entity: Entity = state.get_entity_by_id(order.entity_id)
		if entity == null or entity.current_hp <= 0:
			_log_submit_validation_failure(
				match_data, slot, order_index, "invalid_order_entity", order, entity
			)
			return "invalid_order_entity"
		if entity.owner_player_id != slot:
			return "wrong_player_order"
	return ""


func _match_joined_message(code: String, slot: int, player_count: int) -> Dictionary:
	return (
		MESSAGE
		. make(
			MESSAGE.MATCH_JOINED,
			{
				"code": code,
				"player_slot": slot,
				"player_count": player_count,
			}
		)
	)


func _turn_started_message(match_data: Dictionary, include_snapshot: bool = true) -> Dictionary:
	var state: MatchState = match_data.get("state") as MatchState
	var registry: EntityRegistry = match_data.get("registry") as EntityRegistry
	var payload: Dictionary = {
		"code": match_data.get("code", ""),
		"turn_index": state.turn_index if state != null else -1,
	}
	if include_snapshot:
		payload["match_state"] = state.clone() if state != null else null
		payload["registry"] = registry
	return MESSAGE.make(MESSAGE.TURN_STARTED, payload)


func _turn_resolved_message(result: ResolveResult) -> Dictionary:
	return (
		MESSAGE
		. make(
			MESSAGE.TURN_RESOLVED,
			{
				"turn_index": result.new_state.turn_index,
				"match_state": result.new_state.clone(),
				"events": result.events.duplicate(),
			}
		)
	)


func _failure(error_code: String) -> Dictionary:
	return {
		"ok": false,
		"error": error_code,
		"messages": [MESSAGE.error(error_code, error_code)],
	}


func _log_submit_validation_failure(
	match_data: Dictionary,
	slot: int,
	order_index: int,
	error_code: String,
	order: EntityOrder,
	entity: Entity
) -> void:
	var state: MatchState = match_data.get("state") as MatchState
	var turn_index: int = state.turn_index if state != null else -1
	var entity_id: int = order.entity_id if order != null else -1
	var order_type: int = order.type if order != null else -1
	var entity_owner: int = entity.owner_player_id if entity != null else -1
	var entity_hp: int = entity.current_hp if entity != null else -1
	push_warning(
		(
			(
				"NetworkMatchHub: submit rejected code=%s turn=%d slot=%d order=%d "
				+ "error=%s type=%d entity=%d entity_owner=%d entity_hp=%d"
			)
			% [
				match_data.get("code", ""),
				turn_index,
				slot,
				order_index,
				error_code,
				order_type,
				entity_id,
				entity_owner,
				entity_hp,
			]
		)
	)
