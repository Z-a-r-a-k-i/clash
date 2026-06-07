@tool
extends Node

const CODEC_PATH := "res://scripts/network/network_v0_codec.gd"
const HUB_PATH := "res://scripts/network/network_match_hub.gd"
const CLIENT_CONTROLLER_PATH := "res://scripts/network/network_client_controller.gd"
const NETWORK_PLAY_MODE_PATH := "res://scripts/network/network_play_mode.gd"
const COMBAT_SCENARIO_PATH := "res://data/scenarios/combat_marines_vs_tanks.tres"
const REGISTRY_PATH := "res://data/entity_registry.tres"
const TUNABLES_PATH := "res://data/tunables.tres"
const TEST_REPLAY_DIR := "user://tmp/network_replays_test"


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	_run_all()


func _run_all() -> int:
	var passed: int = 0
	var failed: int = 0
	var fail_names: Array[String] = []
	for test_pair: Array in _all_tests():
		var test_name: String = test_pair[0]
		var fn: Callable = test_pair[1]
		var ok: bool = fn.call() as bool
		if ok:
			passed += 1
		else:
			failed += 1
			fail_names.append(test_name)
	print("[test_network_multiplayer] %d passed, %d failed" % [passed, failed])
	for test_name in fail_names:
		push_error("  failed: %s" % test_name)
	return failed


func _all_tests() -> Array[Array]:
	return [
		["codec_round_trips_submit_state_and_events", _test_codec_round_trip],
		["hub_create_join_validate_submit_resolve_and_journal", _test_hub_turn_flow],
		["client_controller_rejects_wrong_player_orders", _test_client_submit_guard],
		["network_play_mode_uses_shared_surface_without_dev_controls", _test_network_ui_surface],
	]


func _test_codec_round_trip() -> bool:
	var codec: Object = _new_script_instance(CODEC_PATH)
	if codec == null:
		return false
	var loaded: LoadedScenario = _load_combat()
	if loaded == null:
		return false
	var submit_a: SubmitTurn = _submit_attack(loaded.state, 0)
	var submit_b: SubmitTurn = SubmitTurn.new()
	var result: ResolveResult = Resolver.resolve(
		loaded.state, submit_a, submit_b, loaded.registry, _load_tunables()
	)
	if result == null or result.new_state == null:
		push_error("direct resolver result should be available for codec test")
		return false
	var message: Dictionary = {
		"kind": "turn_resolved",
		"payload":
		{
			"submit": submit_a,
			"match_state": result.new_state,
			"events": result.events,
		},
	}
	var encoded: PackedByteArray = codec.call("encode", message)
	if encoded.is_empty():
		push_error("codec should return non-empty bytes")
		return false
	var decoded: Dictionary = codec.call("decode", encoded)
	var payload: Dictionary = decoded.get("payload", {})
	var decoded_submit: SubmitTurn = payload.get("submit") as SubmitTurn
	var decoded_state: MatchState = payload.get("match_state") as MatchState
	var decoded_events: Array = payload.get("events", [])
	var ok: bool = true
	if decoded.get("kind", "") != "turn_resolved":
		push_error("decoded message kind should round-trip")
		ok = false
	if _submit_signature(decoded_submit) != _submit_signature(submit_a):
		push_error("SubmitTurn should round-trip through v0 codec")
		ok = false
	if _state_signature(decoded_state) != _state_signature(result.new_state):
		push_error("MatchState should round-trip through v0 codec")
		ok = false
	if _events_signature(decoded_events) != _events_signature(result.events):
		push_error("Resolver events should round-trip through v0 codec")
		ok = false
	return ok


func _test_hub_turn_flow() -> bool:
	var hub: Object = _new_script_instance(HUB_PATH)
	if hub == null:
		return false
	hub.call("configure", COMBAT_SCENARIO_PATH, REGISTRY_PATH, TUNABLES_PATH, TEST_REPLAY_DIR)
	var created: Dictionary = hub.call("create_match", 101)
	if not created.get("ok", false):
		push_error("create_match should succeed: %s" % str(created))
		return false
	var code: String = created.get("code", "")
	if code.length() < 4:
		push_error("create_match should return a short invite code")
		return false
	if created.get("slot", -1) != 0:
		push_error("creator should be assigned slot 0")
		return false
	var invalid_join: Dictionary = hub.call("join_match", 303, "missing")
	if invalid_join.get("ok", true) or invalid_join.get("error", "") != "invalid_code":
		push_error("invalid join should report invalid_code")
		return false
	var joined: Dictionary = hub.call("join_match", 202, code)
	if not joined.get("ok", false) or joined.get("slot", -1) != 1:
		push_error("second peer should join as slot 1: %s" % str(joined))
		return false
	var start_state: MatchState = hub.call("match_state_for_code", code)
	var loaded: LoadedScenario = _load_combat()
	var submit_a: SubmitTurn = _submit_attack(start_state, 0)
	var submit_b: SubmitTurn = _submit_attack(start_state, 1)
	var wrong_submit: SubmitTurn = _submit_attack(start_state, 1)
	var wrong: Dictionary = hub.call("submit_turn", 101, code, wrong_submit)
	if wrong.get("ok", true) or wrong.get("error", "") != "wrong_player_order":
		push_error("hub should reject orders for entities not owned by the peer slot")
		return false
	var first: Dictionary = hub.call("submit_turn", 101, code, submit_a)
	if not first.get("ok", false) or first.get("resolved", true):
		push_error("first valid submit should be accepted without resolving")
		return false
	var duplicate: Dictionary = hub.call("submit_turn", 101, code, submit_a)
	if duplicate.get("ok", true) or duplicate.get("error", "") != "already_submitted":
		push_error("duplicate submit should be rejected")
		return false
	var second: Dictionary = hub.call("submit_turn", 202, code, submit_b)
	if not second.get("ok", false) or not second.get("resolved", false):
		push_error("second valid submit should resolve the turn")
		return false
	var resolved_state: MatchState = hub.call("match_state_for_code", code)
	var direct: ResolveResult = Resolver.resolve(
		loaded.state, submit_a, submit_b, loaded.registry, _load_tunables()
	)
	var ok: bool = true
	if _state_signature(resolved_state) != _state_signature(direct.new_state):
		push_error("network session result should match direct local resolver output")
		ok = false
	var messages_by_peer: Dictionary = second.get("messages_by_peer", {})
	if not _peer_has_message_kind(messages_by_peer, 101, "turn_resolved"):
		push_error("creator should receive authoritative turn_resolved")
		ok = false
	if not _peer_has_message_kind(messages_by_peer, 202, "turn_resolved"):
		push_error("joiner should receive authoritative turn_resolved")
		ok = false
	var replay_path: String = hub.call("match_replay_path", code)
	if replay_path == "" or not FileAccess.file_exists(replay_path):
		push_error("network match should save a replay journal after resolution")
		ok = false
	else:
		var replay: MatchReplay = (
			ResourceLoader.load(replay_path, "MatchReplay", ResourceLoader.CACHE_MODE_IGNORE)
			as MatchReplay
		)
		if replay == null or replay.frames.size() != 1:
			push_error("network replay journal should contain the resolved turn frame")
			ok = false
	var disconnected: Dictionary = hub.call("disconnect_peer", 202)
	var disconnect_messages: Dictionary = disconnected.get("messages_by_peer", {})
	if not _peer_has_message_kind(disconnect_messages, 101, "disconnect_notice"):
		push_error("remaining peer should receive disconnect_notice")
		ok = false
	return ok


func _test_client_submit_guard() -> bool:
	var controller: Object = _new_script_instance(CLIENT_CONTROLLER_PATH)
	if controller == null:
		return false
	var loaded: LoadedScenario = _load_combat()
	if loaded == null:
		return false
	controller.call("bind_authoritative_state", loaded.state, loaded.registry, 0)
	var own_submit: SubmitTurn = _submit_attack(loaded.state, 0)
	var wrong_submit: SubmitTurn = _submit_attack(loaded.state, 1)
	var ok: bool = true
	if not controller.call("can_submit_turn", own_submit):
		push_error("client slot 0 should allow its own orders")
		ok = false
	if controller.call("can_submit_turn", wrong_submit):
		push_error("client slot 0 should reject slot 1 entity orders")
		ok = false
	controller.call("mark_submit_pending", true)
	if controller.call("can_submit_turn", own_submit):
		push_error("client should block duplicate submit while ack is pending")
		ok = false
	return ok


func _test_network_ui_surface() -> bool:
	var script: Script = load(NETWORK_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % NETWORK_PLAY_MODE_PATH)
		return false
	var mode: Node = script.new()
	add_child(mode)
	mode.call("_ready")
	var ok: bool = true
	if mode.get_node_or_null("MatchPlaySurface") == null:
		push_error("network play mode should create a shared MatchPlaySurface")
		ok = false
	if mode.get_node_or_null("DevHUD") != null:
		push_error("network play mode should not show dev HUD controls")
		ok = false
	if mode.find_child("ReplayPanel", true, false) != null:
		push_error("network play mode should not expose replay controls")
		ok = false
	if mode.find_child("SnapshotLoadDialog", true, false) != null:
		push_error("network play mode should not expose snapshot controls")
		ok = false
	if not mode.has_method("bind_authoritative_snapshot"):
		push_error("network play mode should bind authoritative state snapshots")
		ok = false
	remove_child(mode)
	mode.queue_free()
	return ok


func _new_script_instance(path: String) -> Object:
	var script: Script = load(path) as Script
	if script == null:
		push_error("could not load %s" % path)
		return null
	return script.new()


func _load_combat() -> LoadedScenario:
	var scenario: ScenarioDef = load(COMBAT_SCENARIO_PATH) as ScenarioDef
	var registry: EntityRegistry = load(REGISTRY_PATH) as EntityRegistry
	var tunables: Tunables = _load_tunables()
	if scenario == null or registry == null or tunables == null:
		push_error("network tests require combat scenario, registry, and tunables")
		return null
	return ScenarioLoader.load(scenario, registry, tunables)


func _load_tunables() -> Tunables:
	return load(TUNABLES_PATH) as Tunables


func _submit_attack(state: MatchState, owner: int) -> SubmitTurn:
	var submit: SubmitTurn = SubmitTurn.new()
	var actor_id: int = _first_entity_id(state, owner)
	var target_id: int = _first_enemy_entity_id(state, owner)
	if actor_id < 0:
		return submit
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.ATTACK
	order.entity_id = actor_id
	if target_id >= 0:
		order.target_priority_chain = [target_id]
	submit.orders.append(order)
	return submit


func _first_entity_id(state: MatchState, owner: int) -> int:
	if state == null:
		return -1
	for entity: Entity in state.entities_sorted_by_id():
		if entity != null and entity.owner_player_id == owner and entity.current_hp > 0:
			return entity.id
	return -1


func _first_enemy_entity_id(state: MatchState, owner: int) -> int:
	if state == null:
		return -1
	for entity: Entity in state.entities_sorted_by_id():
		if (
			entity != null
			and entity.owner_player_id >= 0
			and entity.owner_player_id != owner
			and entity.current_hp > 0
		):
			return entity.id
	return -1


func _peer_has_message_kind(messages_by_peer: Dictionary, peer_id: int, kind: String) -> bool:
	var messages: Array = messages_by_peer.get(peer_id, [])
	for message: Dictionary in messages:
		if message.get("kind", "") == kind:
			return true
	return false


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
					"over": state.match_over,
					"winner": state.winner_player_id,
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
					}
				)
			)
	return {
		"turn": state.turn_index,
		"next_entity_id": state.next_entity_id,
		"players": players,
		"entities": entities,
	}


func _submit_signature(submit: SubmitTurn) -> Dictionary:
	if submit == null:
		return {}
	var orders: Array[Dictionary] = []
	for order: EntityOrder in submit.orders:
		if order == null:
			orders.append({})
		else:
			(
				orders
				. append(
					{
						"type": order.type,
						"entity": order.entity_id,
						"tile": order.target_tile,
						"chain": order.target_priority_chain.duplicate(),
						"halt": order.halt_on_sight,
						"def": order.def_id,
						"cancel": order.cancel_index,
						"target": order.target_entity_id,
					}
				)
			)
	return {"orders": orders, "surrender": submit.surrender}


func _events_signature(events: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: Variant in events:
		var event: ResolverEvent = item as ResolverEvent
		if event == null:
			out.append({})
		else:
			(
				out
				. append(
					{
						"type": event.type,
						"actor": event.actor_id,
						"target": event.target_id,
						"from": event.from_origin,
						"to": event.to_origin,
						"damage": event.damage,
						"hp_after": event.hp_after,
						"def": event.def_id,
						"winner": event.winner_player_id,
						"amount": event.amount,
					}
				)
			)
	return out
