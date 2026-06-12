@tool
extends Node

signal finished(failed: int)

const NETWORK_PLAY_MODE_PATH := "res://scripts/network/network_play_mode.gd"
const TEST_PORT: int = 19087
const TEST_TIMEOUT_MSEC: int = 5000
const TEST_REPLAY_DIR := "user://tmp/network_live_replays_test"
const TEST_SERVER_URL_CONFIG_PREFIX := "user://tmp/network_live_server_url"


func _run_all_async() -> void:
	var passed: int = 0
	var failed: int = 0
	var fail_names: Array[String] = []
	for test_pair: Array in _all_tests():
		var test_name: String = test_pair[0]
		var fn: Callable = test_pair[1]
		var ok: bool = await fn.call()
		if ok:
			passed += 1
		else:
			failed += 1
			fail_names.append(test_name)
	print("[test_network_live] %d passed, %d failed" % [passed, failed])
	for test_name in fail_names:
		push_error("  failed: %s" % test_name)
	finished.emit(failed)


func _all_tests() -> Array[Array]:
	return [
		["live_two_client_move_resolves_and_applies", _test_live_move_resolves_and_applies],
		["live_two_client_train_resolves_and_applies", _test_live_train_resolves_and_applies],
	]


func _test_live_move_resolves_and_applies() -> bool:
	var match_data: Dictionary = await _start_live_match("move")
	if match_data.is_empty():
		return false
	var p0: Node = match_data.get("p0") as Node
	var p1: Node = match_data.get("p1") as Node
	var state: MatchState = _current_state(p0)
	var registry: EntityRegistry = _current_registry(p0)
	var actor_id: int = _first_movable_entity_id(state, registry, 0)
	var target_tile: Vector2i = _first_open_neighbor(state, actor_id)
	if actor_id < 0 or target_tile == Vector2i(-1, -1):
		push_error("live move test requires a P0 movable entity and an open target tile")
		_cleanup_live_match(match_data)
		return false
	var start_origin: Vector2i = state.get_entity_by_id(actor_id).origin
	if not bool(p0.call("select_entity_id", actor_id)):
		push_error("live move test could not select P0 entity %d" % actor_id)
		_cleanup_live_match(match_data)
		return false
	if not bool(p0.call("issue_move_selected", target_tile, false)):
		push_error("live move test could not queue Move for entity %d" % actor_id)
		_cleanup_live_match(match_data)
		return false
	var p1_state: MatchState = _current_state(p1)
	var p1_registry: EntityRegistry = _current_registry(p1)
	var p1_actor_id: int = _first_movable_entity_id(p1_state, p1_registry, 1)
	var p1_target_tile: Vector2i = _first_open_neighbor(p1_state, p1_actor_id)
	if p1_actor_id < 0 or p1_target_tile == Vector2i(-1, -1):
		push_error("live move test requires a P1 movable entity and an open target tile")
		_cleanup_live_match(match_data)
		return false
	var p1_start_origin: Vector2i = p1_state.get_entity_by_id(p1_actor_id).origin
	if not bool(p1.call("select_entity_id", p1_actor_id)):
		push_error("live move test could not select P1 entity %d" % p1_actor_id)
		_cleanup_live_match(match_data)
		return false
	if not bool(p1.call("issue_move_selected", p1_target_tile, false)):
		push_error("live move test could not queue P1 Move for entity %d" % p1_actor_id)
		_cleanup_live_match(match_data)
		return false
	var previous_turn: int = state.turn_index
	var ok: bool = await _submit_both_and_wait(match_data, previous_turn, "live move resolve")
	var resolved_state: MatchState = _current_state(p0)
	var moved: Entity = (
		resolved_state.get_entity_by_id(actor_id) if resolved_state != null else null
	)
	if moved == null or moved.origin == start_origin:
		push_error("live network Move did not change the authoritative unit position")
		ok = false
	var p1_moved: Entity = (
		resolved_state.get_entity_by_id(p1_actor_id) if resolved_state != null else null
	)
	if p1_moved == null or p1_moved.origin == p1_start_origin:
		push_error("live network P1 Move did not change the authoritative unit position")
		ok = false
	if not _client_states_match(p0, p1):
		push_error("live network Move left clients on different authoritative states")
		ok = false
	_cleanup_live_match(match_data)
	return ok


func _test_live_train_resolves_and_applies() -> bool:
	var match_data: Dictionary = await _start_live_match("train")
	if match_data.is_empty():
		return false
	var p0: Node = match_data.get("p0") as Node
	var p1: Node = match_data.get("p1") as Node
	var state: MatchState = _current_state(p0)
	var registry: EntityRegistry = _current_registry(p0)
	var producer_id: int = _first_producer_entity_id(state, registry, 0)
	if producer_id < 0:
		push_error("live train test requires a P0 producer")
		_cleanup_live_match(match_data)
		return false
	if not bool(p0.call("select_entity_id", producer_id)):
		push_error("live train test could not select producer %d" % producer_id)
		_cleanup_live_match(match_data)
		return false
	var input: DevTurnInput = p0.call("input_model") as DevTurnInput
	var train_ids: Array[String] = input.train_option_ids() if input != null else []
	if train_ids.is_empty():
		push_error("live train test requires a train option")
		_cleanup_live_match(match_data)
		return false
	var train_def_id: String = train_ids[0]
	var before_count: int = _entity_count_by_def_and_owner(state, train_def_id, 0)
	if not bool(p0.call("issue_train_selected", train_def_id)):
		push_error("live train test could not queue TRAIN %s" % train_def_id)
		_cleanup_live_match(match_data)
		return false
	var previous_turn: int = state.turn_index
	var ok: bool = await _submit_both_and_wait(match_data, previous_turn, "live train start")
	state = _current_state(p0)
	var producer: Entity = state.get_entity_by_id(producer_id) if state != null else null
	var after_first_count: int = _entity_count_by_def_and_owner(state, train_def_id, 0)
	if (
		after_first_count == before_count
		and (
			producer == null
			or producer.production_state == null
			or producer.production_state.active.is_empty()
		)
	):
		push_error("live network TRAIN neither started production nor completed immediately")
		ok = false
	for _turn: int in range(6):
		state = _current_state(p0)
		if _entity_count_by_def_and_owner(state, train_def_id, 0) > before_count:
			break
		previous_turn = state.turn_index if state != null else previous_turn
		if not await _submit_both_and_wait(match_data, previous_turn, "live train follow-up"):
			ok = false
			break
	state = _current_state(p0)
	if _entity_count_by_def_and_owner(state, train_def_id, 0) <= before_count:
		push_error("live network TRAIN never completed after follow-up turns")
		ok = false
	if not _client_states_match(p0, p1):
		push_error("live network TRAIN left clients on different authoritative states")
		ok = false
	_cleanup_live_match(match_data)
	return ok


func _start_live_match(test_name: String) -> Dictionary:
	var server: NetworkMatchServer = NetworkMatchServer.new()
	server.name = "LiveNetworkServer%s" % test_name.capitalize()
	server.port = TEST_PORT
	server.replay_dir = TEST_REPLAY_DIR.path_join(test_name)
	add_child(server)
	var err: Error = server.start()
	if err != OK:
		push_error("live network server failed to start on port %d: %d" % [TEST_PORT, err])
		_cleanup_live_match({"server": server})
		return {}
	var url: String = "ws://127.0.0.1:%d" % TEST_PORT
	var p0: Node = _new_network_mode("%sP0" % test_name, url)
	var p1: Node = _new_network_mode("%sP1" % test_name, url)
	if p0 == null or p1 == null:
		_cleanup_live_match({"server": server, "p0": p0, "p1": p1})
		return {}
	p0.call("_connect_pressed")
	p1.call("_connect_pressed")
	if not await _wait_until(
		func() -> bool: return _client_is_open(p0) and _client_is_open(p1),
		TEST_TIMEOUT_MSEC,
		"%s clients connected" % test_name
	):
		_cleanup_live_match({"server": server, "p0": p0, "p1": p1})
		return {}
	p0.call("_create_pressed")
	if not await _wait_until(
		func() -> bool: return int(p0.call("player_slot")) == 0 and _match_code(p0) != "",
		TEST_TIMEOUT_MSEC,
		"%s match created" % test_name
	):
		push_error("P0 status after create timeout: %s" % _status_text(p0))
		_cleanup_live_match({"server": server, "p0": p0, "p1": p1})
		return {}
	var code: String = _match_code(p0)
	var p1_code_edit: LineEdit = p1.find_child("JoinCode", true, false) as LineEdit
	if p1_code_edit == null:
		push_error("network mode missing JoinCode field")
		_cleanup_live_match({"server": server, "p0": p0, "p1": p1})
		return {}
	p1_code_edit.text = code
	p1.call("_join_pressed")
	if not await _wait_until(
		func() -> bool: return _mode_ready(p0, 0) and _mode_ready(p1, 1),
		TEST_TIMEOUT_MSEC,
		"%s match started" % test_name
	):
		push_error("P0 status after join timeout: %s" % _status_text(p0))
		push_error("P1 status after join timeout: %s" % _status_text(p1))
		_cleanup_live_match({"server": server, "p0": p0, "p1": p1})
		return {}
	return {
		"server": server,
		"p0": p0,
		"p1": p1,
		"code": code,
	}


func _new_network_mode(name_prefix: String, url: String) -> Node:
	var script: Script = load(NETWORK_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % NETWORK_PLAY_MODE_PATH)
		return null
	var mode: Node = script.new()
	mode.name = "LiveNetworkMode%s" % name_prefix.capitalize()
	add_child(mode)
	mode.call("ensure_initialized")
	mode.call(
		"set_server_url_config_path", "%s_%s.cfg" % [TEST_SERVER_URL_CONFIG_PREFIX, name_prefix]
	)
	var url_edit: LineEdit = mode.find_child("ServerUrl", true, false) as LineEdit
	if url_edit == null:
		push_error("network mode missing ServerUrl field")
		remove_child(mode)
		mode.queue_free()
		return null
	url_edit.text = url
	return mode


func _submit_both_and_wait(match_data: Dictionary, previous_turn: int, label: String) -> bool:
	var p0: Node = match_data.get("p0") as Node
	var p1: Node = match_data.get("p1") as Node
	if not bool(p0.call("submit_queued_turn")):
		push_error("P0 submit failed for %s: %s" % [label, _status_text(p0)])
		return false
	if not _submit_button_is_pending(p0):
		push_error("P0 submit button did not enter pending state before server ack")
		return false
	var status_label: Label = p0.find_child("Status", true, false) as Label
	if status_label == null or status_label.text.find("Submit: sending") == -1:
		push_error("P0 shared cockpit status should show the pre-ack sending state")
		return false
	if not await _wait_until(
		func() -> bool:
			var status: String = _status_text(p0)
			return status.contains("Submitted") and status.contains("Waiting"),
		TEST_TIMEOUT_MSEC,
		"P0 submit accepted for %s" % label
	):
		push_error("P0 status after accepted-submit timeout: %s" % _status_text(p0))
		return false
	if not bool(p1.call("submit_queued_turn")):
		push_error("P1 submit failed for %s: %s" % [label, _status_text(p1)])
		return false
	var resolved: bool = await _wait_until(
		func() -> bool:
			var state_a: MatchState = _current_state(p0)
			var state_b: MatchState = _current_state(p1)
			return (
				state_a != null
				and state_b != null
				and state_a.turn_index > previous_turn
				and state_b.turn_index == state_a.turn_index
			),
		TEST_TIMEOUT_MSEC,
		label
	)
	if not resolved:
		push_error("P0 status after submit timeout: %s" % _status_text(p0))
		push_error("P1 status after submit timeout: %s" % _status_text(p1))
		return false
	return true


func _wait_until(condition: Callable, timeout_msec: int, label: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if bool(condition.call()):
			return true
	push_error("timed out waiting for %s" % label)
	return false


func _cleanup_live_match(match_data: Dictionary) -> void:
	var p0: Node = match_data.get("p0") as Node
	var p1: Node = match_data.get("p1") as Node
	var server: NetworkMatchServer = match_data.get("server") as NetworkMatchServer
	for mode: Node in [p0, p1]:
		if mode == null:
			continue
		if mode.has_method("_leave_match_pressed"):
			mode.call("_leave_match_pressed")
		if mode.get_parent() != null:
			mode.get_parent().remove_child(mode)
		mode.queue_free()
	if server != null:
		server.stop()
		if server.get_parent() != null:
			server.get_parent().remove_child(server)
		server.queue_free()


func _client_is_open(mode: Node) -> bool:
	if mode == null:
		return false
	var client: NetworkClient = mode.find_child("NetworkClient", true, false) as NetworkClient
	if client == null:
		return false
	var peer: WebSocketPeer = client.get("_peer") as WebSocketPeer
	return peer != null and peer.get_ready_state() == WebSocketPeer.STATE_OPEN


func _mode_ready(mode: Node, slot: int) -> bool:
	if mode == null or int(mode.call("player_slot")) != slot:
		return false
	var surface: MatchPlaySurface = (
		mode.find_child("MatchPlaySurface", true, false) as MatchPlaySurface
	)
	return surface != null and surface.current_state() != null and surface.registry() != null


func _current_state(mode: Node) -> MatchState:
	var surface: MatchPlaySurface = (
		mode.find_child("MatchPlaySurface", true, false) as MatchPlaySurface
		if mode != null
		else null
	)
	return surface.current_state() if surface != null else null


func _current_registry(mode: Node) -> EntityRegistry:
	var surface: MatchPlaySurface = (
		mode.find_child("MatchPlaySurface", true, false) as MatchPlaySurface
		if mode != null
		else null
	)
	return surface.registry() if surface != null else null


func _match_code(mode: Node) -> String:
	var code_edit: LineEdit = mode.find_child("JoinCode", true, false) as LineEdit
	if code_edit == null:
		return ""
	return code_edit.text.strip_edges().to_upper()


func _status_text(mode: Node) -> String:
	var cockpit_status: Label = mode.find_child("Status", true, false) as Label
	if cockpit_status != null and cockpit_status.text != "":
		return cockpit_status.text
	var lobby_status: Label = mode.find_child("LobbyStatus", true, false) as Label
	return lobby_status.text if lobby_status != null else ""


func _client_states_match(p0: Node, p1: Node) -> bool:
	return _state_signature(_current_state(p0)) == _state_signature(_current_state(p1))


func _submit_button_is_pending(mode: Node) -> bool:
	var submit_button: Button = mode.find_child("Resolve", true, false) as Button
	return (
		submit_button != null
		and submit_button.button_pressed
		and submit_button.text == "Cancel Submit"
	)


func _first_movable_entity_id(state: MatchState, registry: EntityRegistry, owner: int) -> int:
	if state == null or registry == null:
		return -1
	var input: DevTurnInput = DevTurnInput.new()
	input.bind_context(state, registry)
	input.set_active_player_id(owner)
	for entity: Entity in state.entities_sorted_by_id():
		if entity == null or entity.owner_player_id != owner or entity.current_hp <= 0:
			continue
		if input.select_entity(entity.id) and input.can_issue_move():
			return entity.id
	return -1


func _first_producer_entity_id(state: MatchState, registry: EntityRegistry, owner: int) -> int:
	if state == null or registry == null:
		return -1
	var input: DevTurnInput = DevTurnInput.new()
	input.bind_context(state, registry)
	input.set_active_player_id(owner)
	for entity: Entity in state.entities_sorted_by_id():
		if entity == null or entity.owner_player_id != owner or entity.current_hp <= 0:
			continue
		if not input.select_entity(entity.id):
			continue
		if not input.train_option_ids().is_empty():
			return entity.id
	return -1


func _first_open_neighbor(state: MatchState, entity_id: int) -> Vector2i:
	if state == null or state.tile_grid == null or entity_id < 0:
		return Vector2i(-1, -1)
	var entity: Entity = state.get_entity_by_id(entity_id)
	if entity == null:
		return Vector2i(-1, -1)
	var offsets: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
	]
	for offset: Vector2i in offsets:
		var tile: Vector2i = entity.origin + offset
		if state.tile_grid.is_in_bounds(tile) and state.tile_grid.entity_at(tile) < 0:
			return tile
	return Vector2i(-1, -1)


func _entity_count_by_def_and_owner(state: MatchState, def_id: String, owner_player_id: int) -> int:
	if state == null:
		return 0
	var count: int = 0
	for entity: Entity in state.entities_sorted_by_id():
		if entity != null and entity.def_id == def_id and entity.owner_player_id == owner_player_id:
			count += 1
	return count


func _state_signature(state: MatchState) -> Dictionary:
	if state == null:
		return {}
	var entities: Array[Dictionary] = []
	for entity: Entity in state.entities_sorted_by_id():
		(
			entities
			. append(
				{
					"id": entity.id,
					"def": entity.def_id,
					"current_def": entity.current_def_id,
					"owner": entity.owner_player_id,
					"origin": entity.origin,
					"hp": entity.current_hp,
					"focus": entity.focus_target_entity_id,
					"order_queue": _orders_signature(entity.order_queue),
					"persistent_order": _order_signature(entity.persistent_order),
					"ability_cooldowns": entity.ability_cooldowns.duplicate(true),
					"active_buffs": _active_buffs_signature(entity.active_buffs),
					"ability_cast": _ability_cast_signature(entity.ability_cast),
					"is_hidden": entity.is_hidden,
					"moves_used": entity.moves_used_this_turn,
					"resource_amount": entity.current_resource_amount,
					"is_constructing": entity.is_constructing,
					"construction_turns": entity.construction_turns_remaining,
					"construction_worker": entity.construction_worker_id,
					"locked_to_building": entity.locked_to_building_id,
					"pending_build_def": entity.pending_build_def_id,
					"pending_build_tile": entity.pending_build_target_tile,
					"pending_build_target": entity.pending_build_target_entity_id,
					"production": _production_signature(entity.production_state),
					"gather": _gather_signature(entity.gather_state),
				}
			)
		)
	var players: Array[Dictionary] = []
	for player: PlayerState in state.players:
		if player == null:
			players.append({})
		else:
			(
				players
				. append(
					{
						"id": player.player_id,
						"minerals": player.minerals,
						"gas": player.gas,
						"pop_used": player.pop_used,
						"pop_cap": player.pop_cap,
						"surrendered": player.has_surrendered,
						"research": player.unlocked_researches.duplicate(),
					}
				)
			)
	return {
		"turn": state.turn_index,
		"next_entity_id": state.next_entity_id,
		"match_over": state.match_over,
		"winner": state.winner_player_id,
		"players": players,
		"entities": entities,
		"tile_grid": _tile_grid_signature(state.tile_grid),
	}


func _orders_signature(orders: Array[EntityOrder]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for order: EntityOrder in orders:
		out.append(_order_signature(order))
	return out


func _order_signature(order: EntityOrder) -> Dictionary:
	if order == null:
		return {}
	return {
		"type": order.type,
		"entity": order.entity_id,
		"tile": order.target_tile,
		"chain": order.target_priority_chain.duplicate(),
		"def": order.def_id,
		"cancel": order.cancel_index,
		"target": order.target_entity_id,
		"mode": order.mode,
		"enabled": order.enabled,
	}


func _active_buffs_signature(active_buffs: Array[ActiveBuff]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for buff: ActiveBuff in active_buffs:
		if buff == null:
			out.append({})
		else:
			(
				out
				. append(
					{
						"source": buff.source_ability_id,
						"turns": buff.turns_remaining,
						"damage": buff.damage_mult,
						"speed": buff.speed_mult,
					}
				)
			)
	return out


func _ability_cast_signature(cast_state: AbilityCastState) -> Dictionary:
	if cast_state == null:
		return {}
	return {
		"ability": cast_state.ability_id,
		"turns": cast_state.turns_remaining,
	}


func _production_signature(production: ProductionState) -> Dictionary:
	if production == null:
		return {}
	var queue: Array[Dictionary] = []
	for item: Dictionary in production.queue:
		queue.append(item.duplicate(true))
	return {
		"active": production.active.duplicate(true),
		"queue": queue,
		"repeat": production.repeat_train_enabled,
		"repeat_def": production.repeat_train_def_id,
		"rally_mode": production.rally_mode,
		"rally_tile": production.rally_target_tile,
		"rally_target": production.rally_target_entity_id,
	}


func _gather_signature(gather: GatherState) -> Dictionary:
	if gather == null:
		return {}
	return {
		"source": gather.assigned_source_entity_id,
		"resource": gather.carrying_resource_type,
		"amount": gather.carrying_amount,
		"phase": gather.phase,
	}


func _tile_grid_signature(tile_grid: TileGrid) -> Dictionary:
	if tile_grid == null:
		return {}
	var rects: Array[Dictionary] = []
	for entity_id: int in tile_grid.all_placed_entity_ids():
		rects.append({"entity": entity_id, "rect": tile_grid.entity_rect(entity_id)})
	var occupants: Array[Dictionary] = []
	for y: int in range(tile_grid.height):
		for x: int in range(tile_grid.width):
			var tile: Vector2i = Vector2i(x, y)
			var entities: Array[int] = tile_grid.entities_at(tile)
			if not entities.is_empty():
				occupants.append({"tile": tile, "entities": entities})
	var terrain: Array[Dictionary] = []
	for y: int in range(tile_grid.height):
		for x: int in range(tile_grid.width):
			var tile: Vector2i = Vector2i(x, y)
			var tags: Array[String] = tile_grid.tile_terrain_tags(tile)
			if not tags.is_empty():
				terrain.append({"tile": tile, "tags": tags})
	return {
		"width": tile_grid.width,
		"height": tile_grid.height,
		"rects": rects,
		"occupants": occupants,
		"terrain": terrain,
	}
