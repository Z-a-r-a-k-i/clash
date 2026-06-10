@tool
extends Node

const CODEC_PATH := "res://scripts/network/network_v0_codec.gd"
const HUB_PATH := "res://scripts/network/network_match_hub.gd"
const CLIENT_CONTROLLER_PATH := "res://scripts/network/network_client_controller.gd"
const NETWORK_PLAY_MODE_PATH := "res://scripts/network/network_play_mode.gd"
const ACTION_PREVIEW_BUILDER_PATH := "res://scripts/game/action_preview_builder.gd"
const MAIN_MENU_PATH := "res://scripts/ui/main_menu.gd"
const SOLO_SCENE_PATH := "res://scenes/_dev/dev_play_mode.tscn"
const NETWORK_SCENE_PATH := "res://scenes/network_lobby.tscn"
const REPLAY_SCENE_PATH := "res://scenes/replay_mode.tscn"
const COMBAT_SCENARIO_PATH := "res://data/scenarios/combat_marines_vs_tanks.tres"
const MVP_SCENARIO_PATH := "res://data/scenarios/mvp_map.tres"
const REGISTRY_PATH := "res://data/entity_registry.tres"
const TUNABLES_PATH := "res://data/tunables.tres"
const TEST_REPLAY_DIR := "user://tmp/network_replays_test"
const TEST_SERVER_URL_CONFIG := "user://tmp/network_server_url_test.cfg"


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return


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
		["entity_order_type_wire_values_are_stable", _test_entity_order_type_wire_values],
		["hub_create_join_validate_submit_resolve_and_journal", _test_hub_turn_flow],
		["client_controller_rejects_wrong_player_orders", _test_client_submit_guard],
		["network_play_mode_uses_shared_surface_without_dev_controls", _test_network_ui_surface],
		["main_menu_routes_solo_and_multiplayer", _test_main_menu_routes],
		["shared_action_preview_builder_drives_network_previews", _test_action_preview_builder],
		["network_play_mode_splits_lobby_match_and_escape_ui", _test_network_ui_flow],
		["network_order_preview_toggle_shows_all_local_orders", _test_network_order_preview_toggle],
		[
			"network_drag_box_selects_without_panning",
			_test_network_drag_box_selects_without_panning
		],
		[
			"network_escape_resets_active_selection_drag",
			_test_network_escape_resets_active_selection_drag
		],
		["network_group_right_click_fans_out", _test_network_group_orders],
		[
			"network_submit_in_flight_blocks_local_edits",
			_test_network_submit_in_flight_blocks_local_edits
		],
		[
			"network_authoritative_rebind_syncs_selection_highlights",
			_test_network_authoritative_rebind_syncs_selection_highlights
		],
		["network_lobby_remembers_last_server_url", _test_network_lobby_remembers_url],
		[
			"network_next_turn_started_preserves_queued_orders",
			_test_network_preserves_orders_after_next_turn_started
		],
		[
			"network_turn_started_resets_submit_and_allows_next_move",
			_test_network_turn_started_resets_submit_and_allows_next_move
		],
		[
			"network_submit_error_clears_pending_state",
			_test_network_submit_error_clears_pending_state
		],
		[
			"network_disconnect_resets_local_match_state",
			_test_network_disconnect_resets_local_match_state
		],
		["network_match_over_shows_outcome_overlay", _test_network_match_over_overlay],
		["network_building_selection_shows_production", _test_network_building_production],
		["network_hub_base_trains_worker", _test_network_hub_base_trains_worker],
		["network_context_actions_cover_rally_and_gather", _test_network_context_actions],
		["network_command_card_wires_pending_commands", _test_network_pending_command_buttons],
		["network_a_key_attack_mode", _test_network_a_key_attack_mode],
		[
			"network_submit_persists_repeat_rally_and_spawn_orders",
			_test_network_authoritative_producer_state
		],
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


func _test_entity_order_type_wire_values() -> bool:
	var expected: Dictionary = {
		EntityOrder.Type.INVALID: -1,
		EntityOrder.Type.MOVE: 0,
		EntityOrder.Type.ATTACK_MOVE: 1,
		EntityOrder.Type.TARGET: 2,
		EntityOrder.Type.BUILD: 3,
		EntityOrder.Type.TRAIN: 4,
		EntityOrder.Type.RESEARCH: 5,
		EntityOrder.Type.CANCEL: 6,
		EntityOrder.Type.GATHER: 7,
		EntityOrder.Type.USE_ABILITY: 8,
		EntityOrder.Type.SET_RALLY_POINT: 9,
		EntityOrder.Type.REPEAT_TRAIN_TOGGLE: 10,
	}
	for key: Variant in expected.keys():
		var actual: int = int(key)
		var wanted: int = expected[key]
		if actual != wanted:
			push_error(
				"EntityOrder.Type wire value changed: expected %d, got %d" % [wanted, actual]
			)
			return false
	return true


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
	if not _message_list_has_kind(created.get("messages", []), "match_joined"):
		push_error("creator should receive match_joined on create")
		return false
	if _message_list_has_kind(created.get("messages", []), "turn_started"):
		push_error("creator should wait for second player before turn_started")
		return false
	var invalid_join: Dictionary = hub.call("join_match", 303, "missing")
	if invalid_join.get("ok", true) or invalid_join.get("error", "") != "invalid_code":
		push_error("invalid join should report invalid_code")
		return false
	var joined: Dictionary = hub.call("join_match", 202, code)
	if not joined.get("ok", false) or joined.get("slot", -1) != 1:
		push_error("second peer should join as slot 1: %s" % str(joined))
		return false
	var joined_messages: Dictionary = joined.get("messages_by_peer", {})
	if not _peer_has_message_kind(joined_messages, 101, "turn_started"):
		push_error("creator should receive turn_started after second player joins")
		return false
	if not _peer_has_message_kind(joined_messages, 202, "turn_started"):
		push_error("joiner should receive turn_started after joining")
		return false
	var initial_turn_started: Dictionary = _message_from_list(
		joined_messages.get(101, []), "turn_started"
	)
	var initial_payload: Dictionary = initial_turn_started.get("payload", {})
	if initial_payload.get("match_state") == null or initial_payload.get("registry") == null:
		push_error("initial turn_started should include the authoritative snapshot")
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
	if not hub.has_method("cancel_submit_turn"):
		push_error("hub should support cancelling a pending submit before both players are ready")
		return false
	var cancelled: Dictionary = hub.call("cancel_submit_turn", 101, code)
	if not cancelled.get("ok", false):
		push_error("pending submit should be cancellable before resolution: %s" % str(cancelled))
		return false
	var first_after_cancel: Dictionary = hub.call("submit_turn", 202, code, submit_b)
	if not first_after_cancel.get("ok", false) or first_after_cancel.get("resolved", true):
		push_error("remaining submit should not resolve after opponent cancelled readiness")
		return false
	var resubmitted: Dictionary = hub.call("submit_turn", 101, code, submit_a)
	if not resubmitted.get("ok", false) or not resubmitted.get("resolved", false):
		push_error("resubmitting after cancel should resolve once both players are ready")
		return false
	var resolved_state: MatchState = hub.call("match_state_for_code", code)
	var direct: ResolveResult = Resolver.resolve(
		loaded.state, submit_a, submit_b, loaded.registry, _load_tunables()
	)
	var ok: bool = true
	if _state_signature(resolved_state) != _state_signature(direct.new_state):
		push_error("network session result should match direct local resolver output")
		ok = false
	var messages_by_peer: Dictionary = resubmitted.get("messages_by_peer", {})
	if not _peer_has_message_kind(messages_by_peer, 101, "turn_resolved"):
		push_error("creator should receive authoritative turn_resolved")
		ok = false
	if not _peer_has_message_kind(messages_by_peer, 202, "turn_resolved"):
		push_error("joiner should receive authoritative turn_resolved")
		ok = false
	var post_resolve_turn_started: Dictionary = _message_from_list(
		messages_by_peer.get(101, []), "turn_started"
	)
	var post_resolve_payload: Dictionary = post_resolve_turn_started.get("payload", {})
	if post_resolve_payload.has("match_state") or post_resolve_payload.has("registry"):
		push_error("post-resolve turn_started should not duplicate the authoritative snapshot")
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
	var forfeit_created: Dictionary = hub.call("create_match", 404)
	var forfeit_code: String = forfeit_created.get("code", "")
	var forfeit_joined: Dictionary = hub.call("join_match", 505, forfeit_code)
	if not forfeit_joined.get("ok", false):
		push_error("forfeit setup should join a second active match")
		ok = false
	var disconnected: Dictionary = hub.call("disconnect_peer", 505)
	var disconnect_messages: Dictionary = disconnected.get("messages_by_peer", {})
	if not _peer_has_message_kind(disconnect_messages, 404, "disconnect_notice"):
		push_error("remaining peer should receive disconnect_notice")
		ok = false
	var forfeit_message: Dictionary = _message_from_list(
		disconnect_messages.get(404, []), "turn_resolved"
	)
	var forfeit_payload: Dictionary = forfeit_message.get("payload", {})
	var forfeit_state: MatchState = forfeit_payload.get("match_state") as MatchState
	if forfeit_state == null or not forfeit_state.match_over or forfeit_state.winner_player_id != 0:
		push_error("disconnecting from an active match should make the remaining player win")
		ok = false
	var forfeit_events: Array = forfeit_payload.get("events", [])
	if not _events_include_match_winner(forfeit_events, 0):
		push_error("forfeit should broadcast a MATCH_ENDED event with the remaining player")
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
	mode.call("ensure_initialized")
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
	var lobby_panel: Control = mode.find_child("LobbyPanel", true, false) as Control
	if lobby_panel == null or not lobby_panel.visible:
		push_error("network play mode should start in a visible lobby panel")
		ok = false
	var match_hud: Control = mode.find_child("MatchHUD", true, false) as Control
	if match_hud == null or match_hud.visible:
		push_error("network play mode should keep match HUD hidden before a match starts")
		ok = false
	var submit_button: Button = mode.find_child("SubmitTurn", true, false) as Button
	if submit_button == null or not submit_button.visible or submit_button.text != "Submit Turn":
		push_error("network play mode should expose a visible Submit Turn button")
		ok = false
	elif not submit_button.toggle_mode:
		push_error("network Submit Turn should be a toggle button")
		ok = false
	var show_orders_button: BaseButton = mode.find_child("ShowAllOrders", true, false) as BaseButton
	if show_orders_button == null or not show_orders_button.toggle_mode:
		push_error("network play mode should expose a Show All Orders toggle")
		ok = false
	var interface_button: Button = mode.find_child("InterfaceToggle", true, false) as Button
	if interface_button == null:
		push_error("network play mode should expose an interface hide/show button")
		ok = false
	var loaded: LoadedScenario = _load_combat()
	if loaded == null:
		remove_child(mode)
		mode.queue_free()
		return false
	loaded.state.get_player(0).minerals = 150
	loaded.state.get_player(0).gas = 25
	mode.call("bind_authoritative_snapshot", loaded.state, loaded.registry, 0)
	var resources_label: Label = mode.find_child("Resources", true, false) as Label
	if resources_label == null:
		push_error("network match HUD should expose a named Resources label")
		ok = false
	elif (
		resources_label.text.find("Minerals: 150") == -1
		or resources_label.text.find("Gas: 25") == -1
	):
		push_error(
			"network resources label should show minerals and gas, got: %s" % resources_label.text
		)
		ok = false
	(
		mode
		. call(
			"_handle_network_message",
			{
				"kind": "match_joined",
				"payload":
				{
					"code": "CL4242",
					"player_slot": 0,
					"player_count": 1,
				},
			}
		)
	)
	var code_edit: LineEdit = mode.find_child("JoinCode", true, false) as LineEdit
	if code_edit == null or code_edit.text != "CL4242":
		push_error("network play mode should mirror invite code into the visible code field")
		ok = false
	remove_child(mode)
	mode.queue_free()
	return ok


func _test_main_menu_routes() -> bool:
	var script: Script = load(MAIN_MENU_PATH) as Script
	if script == null:
		push_error("could not load %s" % MAIN_MENU_PATH)
		return false
	var menu: Control = script.new() as Control
	if menu == null:
		push_error("main menu script should instantiate as Control")
		return false
	add_child(menu)
	menu.call("ensure_initialized")
	var ok: bool = true
	var solo_button: Button = menu.find_child("SoloButton", true, false) as Button
	if solo_button == null or solo_button.text != "Solo":
		push_error("main menu should expose a Solo button")
		ok = false
	var multiplayer_button: Button = menu.find_child("MultiplayerButton", true, false) as Button
	if multiplayer_button == null or multiplayer_button.text != "Multiplayer":
		push_error("main menu should expose a Multiplayer button")
		ok = false
	var replay_button: Button = menu.find_child("ReplayButton", true, false) as Button
	if replay_button == null or replay_button.text != "Replay":
		push_error("main menu should expose a Replay button")
		ok = false
	if menu.call("solo_scene_path") != SOLO_SCENE_PATH:
		push_error("main menu Solo route should load dev play mode")
		ok = false
	if menu.call("multiplayer_scene_path") != NETWORK_SCENE_PATH:
		push_error("main menu Multiplayer route should load the multiplayer lobby")
		ok = false
	if (
		not menu.has_method("replay_scene_path")
		or menu.call("replay_scene_path") != REPLAY_SCENE_PATH
	):
		push_error("main menu Replay route should load replay mode")
		ok = false
	remove_child(menu)
	menu.queue_free()
	return ok


func _test_action_preview_builder() -> bool:
	var builder: Object = _new_script_instance(ACTION_PREVIEW_BUILDER_PATH)
	if builder == null:
		return false
	var loaded: LoadedScenario = _load_combat()
	if loaded == null:
		return false
	var input: DevTurnInput = DevTurnInput.new()
	input.set_active_player_id(0)
	input.bind_context(loaded.state, loaded.registry)
	var actor_id: int = _first_entity_id(loaded.state, 0)
	var target_tile: Vector2i = _first_open_neighbor(loaded.state, actor_id)
	if actor_id < 0 or target_tile == Vector2i(-1, -1):
		push_error("preview test requires a movable entity with an open neighbor")
		return false
	if not input.select_entity(actor_id):
		push_error("preview test should select actor")
		return false
	if not input.issue_move(target_tile):
		push_error("preview test should queue a move order")
		return false
	var previews: Array = builder.call(
		"build", loaded.state, loaded.registry, input, 0, actor_id, false, null
	)
	if previews.is_empty():
		push_error("shared preview builder should emit queued order previews")
		return false
	var preview: Dictionary = previews[0]
	if preview.get("entity_id", -1) != actor_id or preview.get("target_tile") != target_tile:
		push_error("shared preview should identify actor and target tile")
		return false
	return true


func _test_network_ui_flow() -> bool:
	var script: Script = load(NETWORK_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % NETWORK_PLAY_MODE_PATH)
		return false
	var mode: Node = script.new()
	add_child(mode)
	mode.call("ensure_initialized")
	var loaded: LoadedScenario = _load_combat()
	var ok: bool = true
	if loaded == null:
		remove_child(mode)
		mode.queue_free()
		return false
	var lobby_panel: Control = mode.find_child("LobbyPanel", true, false) as Control
	var match_hud: Control = mode.find_child("MatchHUD", true, false) as Control
	if lobby_panel == null or match_hud == null:
		push_error("network play mode should have separate lobby and match HUD panels")
		ok = false
	mode.call("bind_authoritative_snapshot", loaded.state, loaded.registry, 0)
	if lobby_panel != null and lobby_panel.visible:
		push_error("network lobby should hide after authoritative match state binds")
		ok = false
	if match_hud == null or not match_hud.visible:
		push_error("network match HUD should show after authoritative match state binds")
		ok = false
	var escape_menu: Control = mode.find_child("EscapeMenu", true, false) as Control
	if escape_menu == null or escape_menu.visible:
		push_error("network play mode should create a hidden Escape menu")
		ok = false
	if mode.has_method("set_escape_menu_visible"):
		mode.call("set_escape_menu_visible", true)
	if escape_menu == null or not escape_menu.visible:
		push_error("network Escape menu should be showable")
		ok = false
	if not mode.has_method("set_interface_hidden"):
		push_error("network play mode should allow hiding the match interface")
		ok = false
	else:
		mode.call("set_interface_hidden", true)
		if match_hud != null and match_hud.visible:
			push_error("network match HUD should hide when the interface is hidden")
			ok = false
		mode.call("set_interface_hidden", false)
		if match_hud == null or not match_hud.visible:
			push_error("network match HUD should show again when the interface is restored")
			ok = false
	remove_child(mode)
	mode.queue_free()
	return ok


func _test_network_order_preview_toggle() -> bool:
	var script: Script = load(NETWORK_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % NETWORK_PLAY_MODE_PATH)
		return false
	var mode: Node = script.new()
	add_child(mode)
	mode.call("ensure_initialized")
	var loaded: LoadedScenario = _load_combat()
	var ok: bool = true
	if loaded == null:
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("bind_authoritative_snapshot", loaded.state, loaded.registry, 0)
	var actor_id: int = _first_entity_id(loaded.state, 0)
	var second_id: int = _nth_entity_id(loaded.state, 0, 1)
	var target_tile: Vector2i = _first_open_neighbor(loaded.state, actor_id)
	if actor_id < 0 or second_id < 0 or target_tile == Vector2i(-1, -1):
		push_error("preview toggle test requires two owned entities and an open move tile")
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("select_entity_id", actor_id)
	mode.call("issue_move_selected", target_tile)
	mode.call("select_entity_id", second_id)
	var surface: MatchPlaySurface = mode.get_node_or_null("MatchPlaySurface") as MatchPlaySurface
	var renderer: MatchRenderer = surface.renderer() if surface != null else null
	if renderer == null:
		push_error("preview toggle test requires a renderer")
		ok = false
	elif renderer.action_preview_count() != 0:
		push_error("selected-only preview should hide orders from other units")
		ok = false
	if not mode.has_method("set_show_all_orders"):
		push_error("network play mode should expose show-all-orders state")
		ok = false
	else:
		mode.call("set_show_all_orders", true)
		if renderer != null and renderer.action_preview_count() <= 0:
			push_error("show-all-orders should reveal queued orders from other units")
			ok = false
	remove_child(mode)
	mode.queue_free()
	return ok


func _test_network_drag_box_selects_without_panning() -> bool:
	var script: Script = load(NETWORK_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % NETWORK_PLAY_MODE_PATH)
		return false
	var mode: Node = script.new()
	add_child(mode)
	mode.call("ensure_initialized")
	var loaded: LoadedScenario = _load_combat()
	if loaded == null:
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("bind_authoritative_snapshot", loaded.state, loaded.registry, 0)
	var surface: MatchPlaySurface = mode.get_node_or_null("MatchPlaySurface") as MatchPlaySurface
	var renderer: MatchRenderer = surface.renderer() if surface != null else null
	var camera: Camera2D = (
		renderer.get_node_or_null("Camera2D") as Camera2D if renderer != null else null
	)
	if renderer == null or camera == null:
		push_error("selection drag test requires a renderer camera")
		remove_child(mode)
		mode.queue_free()
		return false
	var ids: Array[int] = _entity_ids_by_def_owner(loaded.state, "marine", 0)
	if ids.size() < 2:
		push_error("combat scenario should have at least two P0 marines")
		remove_child(mode)
		mode.queue_free()
		return false
	var original_position: Vector2 = camera.position
	_drag_box(mode, _world_box_for_entities(loaded.state, ids), false)
	var selected: Array[int] = _selected_ids_for_test(mode.call("input_model") as DevTurnInput)
	var ok: bool = selected == ids
	if not ok:
		push_error("network drag-box should select boxed owned movers, got %s" % str(selected))
	if camera.position != original_position:
		push_error("network left drag-box should not pan the camera")
		ok = false
	remove_child(mode)
	mode.queue_free()
	return ok


func _test_network_escape_resets_active_selection_drag() -> bool:
	var script: Script = load(NETWORK_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % NETWORK_PLAY_MODE_PATH)
		return false
	var mode: Node = script.new()
	add_child(mode)
	mode.call("ensure_initialized")
	var loaded: LoadedScenario = _load_combat()
	if loaded == null:
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("bind_authoritative_snapshot", loaded.state, loaded.registry, 0)
	var input: DevTurnInput = mode.call("input_model") as DevTurnInput
	var ids: Array[int] = _entity_ids_by_def_owner(loaded.state, "marine", 0)
	if ids.size() < 2:
		push_error("network escape drag reset test requires two P0 marines")
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("select_entity_id", ids[0])
	var box: Rect2 = _world_box_for_entities(loaded.state, [ids[1]])
	mode.call("_unhandled_input", _mouse_button(MOUSE_BUTTON_LEFT, true, box.position))
	mode.call("_unhandled_input", _mouse_motion(box.size, MOUSE_BUTTON_MASK_LEFT, box.end))
	mode.call("_unhandled_input", _key_press(KEY_ESCAPE))
	mode.call("_unhandled_input", _mouse_button(MOUSE_BUTTON_LEFT, false, box.end))
	var surface: MatchPlaySurface = mode.get_node_or_null("MatchPlaySurface") as MatchPlaySurface
	var renderer: MatchRenderer = surface.renderer() if surface != null else null
	var selected: Array[int] = _selected_ids_for_test(input)
	var ok: bool = selected == [ids[0]]
	if not ok:
		push_error("network Escape should cancel active selection drag, got %s" % str(selected))
	if renderer != null and int(renderer.call("input_highlight_count")) != 1:
		push_error("network Escape should clear the active selection box")
		ok = false
	remove_child(mode)
	mode.queue_free()
	return ok


func _test_network_group_orders() -> bool:
	var script: Script = load(NETWORK_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % NETWORK_PLAY_MODE_PATH)
		return false
	var mode: Node = script.new()
	add_child(mode)
	mode.call("ensure_initialized")
	var loaded: LoadedScenario = _load_combat()
	if loaded == null:
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("bind_authoritative_snapshot", loaded.state, loaded.registry, 0)
	var input: DevTurnInput = mode.call("input_model") as DevTurnInput
	var ids: Array[int] = _entity_ids_by_def_owner(loaded.state, "marine", 0)
	if ids.size() < 2:
		push_error("combat scenario should have at least two P0 marines")
		remove_child(mode)
		mode.queue_free()
		return false
	if not _select_entities_for_test(input, ids):
		remove_child(mode)
		mode.queue_free()
		return false
	var surface: MatchPlaySurface = mode.get_node_or_null("MatchPlaySurface") as MatchPlaySurface
	var renderer: MatchRenderer = surface.renderer() if surface != null else null
	if renderer != null:
		renderer.call("set_selected_entity_ids", ids)
	var target_tile: Vector2i = _first_empty_tile(loaded.state)
	mode.call(
		"_unhandled_input", _mouse_button(MOUSE_BUTTON_RIGHT, true, _tile_center_px(target_tile))
	)
	var ok: bool = true
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != ids.size():
		push_error("network group right-click should queue one flat order per unit")
		ok = false
	else:
		for i in orders.size():
			if not _has_move_order([orders[i]], ids[i], target_tile):
				push_error("expected MOVE for selected unit #%d" % ids[i])
				ok = false
	remove_child(mode)
	mode.queue_free()
	return ok


func _test_network_submit_in_flight_blocks_local_edits() -> bool:
	var script: Script = load(NETWORK_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % NETWORK_PLAY_MODE_PATH)
		return false
	var mode: Node = script.new()
	add_child(mode)
	mode.call("ensure_initialized")
	var loaded: LoadedScenario = _load_combat()
	if loaded == null:
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("bind_authoritative_snapshot", loaded.state, loaded.registry, 0)
	var input: DevTurnInput = mode.call("input_model") as DevTurnInput
	var actor_id: int = _first_movable_entity_id(loaded.state, loaded.registry, 0)
	var second_id: int = _nth_entity_id(loaded.state, 0, 1)
	var target_tile: Vector2i = _first_open_neighbor(loaded.state, actor_id)
	if actor_id < 0 or second_id < 0 or target_tile == Vector2i(-1, -1):
		push_error("submit in-flight edit test requires two entities and an open tile")
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("select_entity_id", actor_id)
	mode.set("_submit_in_flight", true)
	var ok: bool = true
	if bool(mode.call("select_entity_id", second_id)):
		push_error("submit in-flight should reject selection changes")
		ok = false
	if bool(mode.call("issue_move_selected", target_tile, false)):
		push_error("submit in-flight should reject new orders")
		ok = false
	mode.call("begin_target")
	if mode.call("pending_command_kind") != "":
		push_error("submit in-flight should reject pending command changes")
		ok = false
	if _selected_ids_for_test(input) != [actor_id]:
		push_error("submit in-flight should preserve existing selection")
		ok = false
	if input.submit_for_player(0).orders.size() != 0:
		push_error("submit in-flight should not mutate queued orders")
		ok = false
	mode.set("_submit_in_flight", false)
	if not bool(mode.call("issue_move_selected", target_tile, false)):
		push_error("clearing submit in-flight should allow local edits again")
		ok = false
	remove_child(mode)
	mode.queue_free()
	return ok


func _test_network_authoritative_rebind_syncs_selection_highlights() -> bool:
	var script: Script = load(NETWORK_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % NETWORK_PLAY_MODE_PATH)
		return false
	var mode: Node = script.new()
	add_child(mode)
	mode.call("ensure_initialized")
	var loaded: LoadedScenario = _load_combat()
	if loaded == null:
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("bind_authoritative_snapshot", loaded.state, loaded.registry, 0)
	var input: DevTurnInput = mode.call("input_model") as DevTurnInput
	var actor_id: int = _first_entity_id(loaded.state, 0)
	if actor_id < 0:
		push_error("selection highlight sync test requires a P0 entity")
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("select_entity_id", actor_id)
	var surface: MatchPlaySurface = mode.get_node_or_null("MatchPlaySurface") as MatchPlaySurface
	var renderer: MatchRenderer = surface.renderer() if surface != null else null
	if renderer == null:
		push_error("selection highlight sync test requires a renderer")
		remove_child(mode)
		mode.queue_free()
		return false
	if int(renderer.call("input_highlight_count")) <= 0:
		push_error("selection should create renderer highlights before authoritative rebind")
		remove_child(mode)
		mode.queue_free()
		return false
	var next_state: MatchState = loaded.state.clone()
	var selected: Entity = next_state.get_entity_by_id(actor_id)
	if selected == null:
		push_error("selection highlight sync test could not clone selected entity")
		remove_child(mode)
		mode.queue_free()
		return false
	selected.current_hp = 0
	mode.call("apply_authoritative_result", next_state, [])
	var ok: bool = true
	if not _selected_ids_for_test(input).is_empty():
		push_error("authoritative result should prune dead selected entity")
		ok = false
	if int(renderer.call("input_highlight_count")) != 0:
		push_error("authoritative result should resync cleared selection highlights")
		ok = false
	remove_child(mode)
	mode.queue_free()
	return ok


func _test_network_lobby_remembers_url() -> bool:
	var script: Script = load(NETWORK_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % NETWORK_PLAY_MODE_PATH)
		return false
	_remove_user_file(TEST_SERVER_URL_CONFIG)
	var mode: Node = script.new()
	if not mode.has_method("set_server_url_config_path"):
		push_error("network lobby should allow tests to isolate the remembered URL config")
		mode.queue_free()
		return false
	mode.call("set_server_url_config_path", TEST_SERVER_URL_CONFIG)
	add_child(mode)
	mode.call("ensure_initialized")
	var remembered_url := "ws://192.0.2.10:9999"
	var ok: bool = true
	if not mode.has_method("server_url"):
		push_error("network lobby should expose its configured server URL")
		ok = false
	elif mode.call("server_url") == "":
		push_error("network lobby should default to a websocket URL")
		ok = false
	if not mode.has_method("remember_server_url"):
		push_error("network lobby should persist the last server URL")
		ok = false
	else:
		mode.call("remember_server_url", remembered_url)
	remove_child(mode)
	mode.queue_free()
	var restored: Node = script.new()
	if not restored.has_method("set_server_url_config_path"):
		restored.queue_free()
		_remove_user_file(TEST_SERVER_URL_CONFIG)
		return false
	restored.call("set_server_url_config_path", TEST_SERVER_URL_CONFIG)
	add_child(restored)
	restored.call("ensure_initialized")
	if restored.has_method("server_url") and restored.call("server_url") != remembered_url:
		push_error("network lobby should load the remembered server URL by default")
		ok = false
	remove_child(restored)
	restored.queue_free()
	_remove_user_file(TEST_SERVER_URL_CONFIG)
	return ok


func _test_network_preserves_orders_after_next_turn_started() -> bool:
	var script: Script = load(NETWORK_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % NETWORK_PLAY_MODE_PATH)
		return false
	var mode: Node = script.new()
	add_child(mode)
	mode.call("ensure_initialized")
	var loaded: LoadedScenario = _load_combat()
	if loaded == null:
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("bind_authoritative_snapshot", loaded.state, loaded.registry, 0)
	var input: DevTurnInput = mode.call("input_model") as DevTurnInput
	var actor_id: int = _first_entity_id(loaded.state, 0)
	var far_tile: Vector2i = _far_open_tile(loaded.state, actor_id)
	var future_tile: Vector2i = _first_open_neighbor(loaded.state, actor_id)
	if actor_id < 0 or far_tile == Vector2i(-1, -1) or future_tile == Vector2i(-1, -1):
		push_error("network preserve-orders test requires a movable entity and open tiles")
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("select_entity_id", actor_id)
	if not mode.call("issue_move_selected", far_tile, false):
		push_error("expected long move order to queue for the current turn")
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("issue_move_selected", future_tile, true)
	if input.future_order_count_for_entity(actor_id) != 1:
		push_error("expected queued future order before resolve")
		remove_child(mode)
		mode.queue_free()
		return false
	var submit: SubmitTurn = input.submit_for_player(0).clone()
	var result: ResolveResult = Resolver.resolve(
		loaded.state, submit, SubmitTurn.new(), loaded.registry, _load_tunables()
	)
	if result == null or result.new_state == null:
		push_error("network preserve-orders test requires a resolve result")
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("apply_authoritative_result", result.new_state, result.events)
	var has_next_turn_orders: bool = (
		input.submit_for_player(0).orders.size() > 0
		or input.future_order_count_for_entity(actor_id) > 0
	)
	(
		mode
		. call(
			"_handle_network_message",
			{
				"kind": "turn_started",
				"payload":
				{
					"code": "CL4242",
					"turn_index": result.new_state.turn_index,
					"match_state": result.new_state,
					"registry": loaded.registry,
				},
			}
		)
	)
	var ok: bool = has_next_turn_orders
	if (
		input.submit_for_player(0).orders.is_empty()
		and input.future_order_count_for_entity(actor_id) == 0
	):
		push_error("next turn_started should not clear client-side queued follow-up orders")
		ok = false
	remove_child(mode)
	mode.queue_free()
	return ok


func _test_network_turn_started_resets_submit_and_allows_next_move() -> bool:
	var script: Script = load(NETWORK_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % NETWORK_PLAY_MODE_PATH)
		return false
	var mode: Node = script.new()
	add_child(mode)
	mode.call("ensure_initialized")
	var loaded: LoadedScenario = _load_combat()
	if loaded == null:
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("bind_authoritative_snapshot", loaded.state, loaded.registry, 0)
	(
		mode
		. call(
			"_handle_network_message",
			{
				"kind": "submit_turn",
				"payload": {"accepted": true},
			}
		)
	)
	var submit_button: Button = mode.find_child("SubmitTurn", true, false) as Button
	var ok: bool = true
	if (
		submit_button == null
		or not submit_button.button_pressed
		or submit_button.text != "Cancel Submit"
	):
		push_error("accepted submit should mark the network submit button pending")
		ok = false
	(
		mode
		. call(
			"_handle_network_message",
			{
				"kind": "turn_started",
				"payload":
				{
					"code": "CL4242",
					"turn_index": loaded.state.turn_index + 1,
					"match_state": loaded.state,
					"registry": loaded.registry,
				},
			}
		)
	)
	if submit_button == null or submit_button.button_pressed or submit_button.text != "Submit Turn":
		push_error("turn_started should reset the network submit button for the new turn")
		ok = false
	var actor_id: int = _first_movable_entity_id(loaded.state, loaded.registry, 0)
	var target_tile: Vector2i = _first_open_neighbor(loaded.state, actor_id)
	if actor_id < 0 or target_tile == Vector2i(-1, -1):
		push_error("submit reset test requires a movable entity and open tile")
		remove_child(mode)
		mode.queue_free()
		return false
	var start_origin: Vector2i = loaded.state.get_entity_by_id(actor_id).origin
	mode.call("select_entity_id", actor_id)
	if not bool(mode.call("issue_move_selected", target_tile, false)):
		push_error("network move test should queue Move after turn_started")
		ok = false
	var input: DevTurnInput = mode.call("input_model") as DevTurnInput
	var submit: SubmitTurn = input.submit_for_player(0).clone() if input != null else null
	if not bool(mode.call("can_submit_turn", submit)):
		push_error("turn_started should allow the next turn's queued Move submit")
		ok = false
	if submit != null:
		var result: ResolveResult = Resolver.resolve(
			loaded.state, submit, SubmitTurn.new(), loaded.registry, _load_tunables()
		)
		var moved: Entity = result.new_state.get_entity_by_id(actor_id) if result != null else null
		if moved == null or moved.origin == start_origin:
			push_error("authoritative network Move submit should move the selected unit")
			ok = false
	remove_child(mode)
	mode.queue_free()
	return ok


func _test_network_submit_error_clears_pending_state() -> bool:
	var script: Script = load(NETWORK_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % NETWORK_PLAY_MODE_PATH)
		return false
	var mode: Node = script.new()
	add_child(mode)
	mode.call("ensure_initialized")
	var loaded: LoadedScenario = _load_combat()
	if loaded == null:
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("bind_authoritative_snapshot", loaded.state, loaded.registry, 0)
	(
		mode
		. call(
			"_handle_network_message",
			{
				"kind": "submit_turn",
				"payload": {"accepted": true},
			}
		)
	)
	(
		mode
		. call(
			"_handle_network_message",
			{
				"kind": "match_error",
				"payload": {"code": "wrong_player_order", "message": "wrong_player_order"},
			}
		)
	)
	var submit_button: Button = mode.find_child("SubmitTurn", true, false) as Button
	var submit_label: Label = mode.find_child("SubmitState", true, false) as Label
	var status_label: Label = mode.find_child("MatchStatus", true, false) as Label
	var ok: bool = true
	if submit_button == null or submit_button.button_pressed or submit_button.text != "Submit Turn":
		push_error("server submit error should clear the pending submit button")
		ok = false
	if submit_label == null or submit_label.text != "Submit: idle":
		push_error("server submit error should clear the pending submit label")
		ok = false
	if status_label == null or status_label.text.find("wrong_player_order") == -1:
		push_error("server submit error should remain visible in match status")
		ok = false
	remove_child(mode)
	mode.queue_free()
	return ok


func _test_network_disconnect_resets_local_match_state() -> bool:
	var script: Script = load(NETWORK_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % NETWORK_PLAY_MODE_PATH)
		return false
	var mode: Node = script.new()
	add_child(mode)
	mode.call("ensure_initialized")
	var loaded: LoadedScenario = _load_combat()
	if loaded == null:
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("bind_authoritative_snapshot", loaded.state, loaded.registry, 0)
	var actor_id: int = _first_movable_entity_id(loaded.state, loaded.registry, 0)
	var target_tile: Vector2i = _first_open_neighbor(loaded.state, actor_id)
	if actor_id < 0 or target_tile == Vector2i(-1, -1):
		push_error("disconnect reset test requires a movable entity and open tile")
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("select_entity_id", actor_id)
	if not bool(mode.call("issue_move_selected", target_tile, false)):
		push_error("disconnect reset test should queue a pre-reset move")
		remove_child(mode)
		mode.queue_free()
		return false
	(
		mode
		. call(
			"_handle_network_message",
			{
				"kind": "submit_turn",
				"payload": {"accepted": true},
			}
		)
	)
	var input: DevTurnInput = mode.call("input_model") as DevTurnInput
	var stale_submit: SubmitTurn = input.submit_for_player(0).clone() if input != null else null
	mode.call("_reset_local_match_state")
	var submit_button: Button = mode.find_child("SubmitTurn", true, false) as Button
	var ok: bool = true
	if int(mode.call("player_slot")) != -1:
		push_error("disconnect reset should clear player slot")
		ok = false
	if input == null or not input.submit_for_player(0).orders.is_empty():
		push_error("disconnect reset should clear queued input")
		ok = false
	if bool(mode.call("can_submit_turn", stale_submit)):
		push_error("disconnect reset should invalidate stale submits")
		ok = false
	if submit_button == null or submit_button.button_pressed or submit_button.text != "Submit Turn":
		push_error("disconnect reset should clear submit pending HUD state")
		ok = false
	remove_child(mode)
	mode.queue_free()
	return ok


func _test_network_match_over_overlay() -> bool:
	var script: Script = load(NETWORK_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % NETWORK_PLAY_MODE_PATH)
		return false
	var mode: Node = script.new()
	add_child(mode)
	mode.call("ensure_initialized")
	var loaded: LoadedScenario = _load_combat()
	if loaded == null:
		remove_child(mode)
		mode.queue_free()
		return false
	var terminal_state: MatchState = loaded.state.clone()
	terminal_state.match_over = true
	terminal_state.winner_player_id = 0
	mode.call("bind_authoritative_snapshot", terminal_state, loaded.registry, 0)
	var overlay: Control = mode.find_child("OutcomeOverlay", true, false) as Control
	var label: Label = mode.find_child("OutcomeTitle", true, false) as Label
	var ok: bool = true
	if overlay == null or not overlay.visible:
		push_error("network match-over state should show a centered outcome overlay")
		ok = false
	if label == null or label.text != "Victory":
		push_error("network match-over overlay should show Victory for the winning player")
		ok = false
	remove_child(mode)
	mode.queue_free()
	return ok


func _test_network_building_production() -> bool:
	var script: Script = load(NETWORK_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % NETWORK_PLAY_MODE_PATH)
		return false
	var mode: Node = script.new()
	add_child(mode)
	mode.call("ensure_initialized")
	var loaded: LoadedScenario = _load_mvp()
	if loaded == null:
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("bind_authoritative_snapshot", loaded.state, loaded.registry, 0)
	var producer_id: int = _first_producer_entity_id(loaded.state, loaded.registry, 0)
	if producer_id < 0:
		push_error("network production test requires a player-owned producer")
		remove_child(mode)
		mode.queue_free()
		return false
	var expected_input := DevTurnInput.new()
	expected_input.bind_context(loaded.state, loaded.registry)
	expected_input.set_active_player_id(0)
	expected_input.select_entity(producer_id)
	var expected_train_ids: Array[String] = expected_input.train_option_ids()
	var expected_research_ids: Array[String] = expected_input.research_option_ids()
	mode.call("select_entity_id", producer_id)
	var card: CommandCard = mode.find_child("CommandCard", true, false) as CommandCard
	var ok: bool = true
	if card == null:
		push_error("network command card should exist")
		ok = false
	elif (
		card.train_option_ids() != expected_train_ids
		or card.research_option_ids() != expected_research_ids
	):
		push_error(
			(
				(
					"network command card should show building production, "
					+ "train=%s/%s research=%s/%s"
				)
				% [
					str(card.train_option_ids()),
					str(expected_train_ids),
					str(card.research_option_ids()),
					str(expected_research_ids),
				]
			)
		)
		ok = false
	if ok and not expected_train_ids.is_empty():
		card.emit_signal("train_requested", expected_train_ids[0])
		var input: DevTurnInput = mode.call("input_model") as DevTurnInput
		var orders: Array[EntityOrder] = input.submit_for_player(0).orders
		if orders.is_empty() or orders[0].type != EntityOrder.Type.TRAIN:
			push_error("network train button should queue a TRAIN order")
			ok = false
	remove_child(mode)
	mode.queue_free()
	return ok


func _test_network_hub_base_trains_worker() -> bool:
	var hub: Object = _new_script_instance(HUB_PATH)
	if hub == null:
		return false
	hub.call("configure", MVP_SCENARIO_PATH, REGISTRY_PATH, TUNABLES_PATH, TEST_REPLAY_DIR)
	var created: Dictionary = hub.call("create_match", 101)
	if not created.get("ok", false):
		push_error("worker production match create failed: %s" % str(created))
		return false
	var code: String = created.get("code", "")
	var joined: Dictionary = hub.call("join_match", 202, code)
	if not joined.get("ok", false):
		push_error("worker production match join failed: %s" % str(joined))
		return false
	var state: MatchState = hub.call("match_state_for_code", code)
	var registry: EntityRegistry = hub.call("match_registry_for_code", code)
	var producer_id: int = _first_producer_entity_id(state, registry, 0)
	if producer_id < 0:
		push_error("worker production network test requires a P0 producer")
		return false
	var before_workers: int = _entity_count_by_def_and_owner(state, "worker", 0)
	var train: EntityOrder = EntityOrder.new()
	train.type = EntityOrder.Type.TRAIN
	train.entity_id = producer_id
	train.def_id = "worker"
	var submit_a: SubmitTurn = SubmitTurn.new()
	submit_a.orders = [train] as Array[EntityOrder]
	var accepted: Dictionary = hub.call("submit_turn", 101, code, submit_a)
	if not accepted.get("ok", false) or accepted.get("resolved", true):
		push_error("first worker TRAIN submit should wait for opponent: %s" % str(accepted))
		return false
	var resolved: Dictionary = hub.call("submit_turn", 202, code, SubmitTurn.new())
	if not resolved.get("ok", false) or not resolved.get("resolved", false):
		push_error("second submit should resolve worker TRAIN: %s" % str(resolved))
		return false
	var events: Array = _events_from_peer_messages(resolved.get("messages_by_peer", {}), 101)
	if _events_have_type(events, ResolverEvent.Type.ORDER_REJECTED):
		push_error("network worker TRAIN was rejected")
		return false
	if _events_have_type(events, ResolverEvent.Type.PRODUCTION_STALLED):
		push_error("network worker TRAIN stalled")
		return false
	if not _events_have_type(events, ResolverEvent.Type.TRAIN_STARTED):
		push_error("network worker TRAIN did not start")
		return false
	var spawned_id: int = -1
	for _turn in 4:
		var p0: Dictionary = hub.call("submit_turn", 101, code, SubmitTurn.new())
		if not p0.get("ok", false) or p0.get("resolved", true):
			push_error("P0 empty follow-up submit failed: %s" % str(p0))
			return false
		var p1: Dictionary = hub.call("submit_turn", 202, code, SubmitTurn.new())
		if not p1.get("ok", false) or not p1.get("resolved", false):
			push_error("P1 empty follow-up submit failed: %s" % str(p1))
			return false
		events = _events_from_peer_messages(p1.get("messages_by_peer", {}), 101)
		if _events_have_type(events, ResolverEvent.Type.ORDER_REJECTED):
			push_error("network worker TRAIN follow-up rejected an order")
			return false
		if _events_have_type(events, ResolverEvent.Type.PRODUCTION_STALLED):
			push_error("network worker TRAIN stalled after starting")
			return false
		if _events_have_type(events, ResolverEvent.Type.SPAWN_DEFERRED):
			push_error("network worker TRAIN spawn deferred")
			return false
		spawned_id = _train_completed_target_id(events, producer_id, "worker")
		if spawned_id >= 0:
			break
	if spawned_id < 0:
		push_error("network worker TRAIN never completed")
		return false
	state = hub.call("match_state_for_code", code)
	var after_workers: int = _entity_count_by_def_and_owner(state, "worker", 0)
	if after_workers != before_workers + 1:
		push_error(
			(
				"network worker TRAIN expected %d P0 workers, got %d"
				% [before_workers + 1, after_workers]
			)
		)
		return false
	return true


func _test_network_context_actions() -> bool:
	var script: Script = load(NETWORK_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % NETWORK_PLAY_MODE_PATH)
		return false
	var mode: Node = script.new()
	add_child(mode)
	mode.call("ensure_initialized")
	var loaded: LoadedScenario = _load_mvp()
	if loaded == null:
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("bind_authoritative_snapshot", loaded.state, loaded.registry, 0)
	if not mode.has_method("issue_context_at_tile"):
		push_error("network play mode should expose solo-equivalent context actions")
		remove_child(mode)
		mode.queue_free()
		return false
	var producer_id: int = _first_producer_entity_id(loaded.state, loaded.registry, 0)
	var gatherer_id: int = _first_gatherer_entity_id(loaded.state, loaded.registry, 0)
	var resource_id: int = _first_resource_target_id_for_owner(loaded.state, loaded.registry, 0)
	if producer_id < 0 or gatherer_id < 0 or resource_id < 0:
		push_error("network context test requires producer, gatherer, and resource target")
		remove_child(mode)
		mode.queue_free()
		return false
	var producer: Entity = loaded.state.get_entity_by_id(producer_id)
	var resource: Entity = loaded.state.get_entity_by_id(resource_id)
	var rally_tile: Vector2i = _first_open_neighbor(loaded.state, producer_id)
	if producer == null or resource == null or rally_tile == Vector2i(-1, -1):
		push_error("network context test requires reachable rally/resource tiles")
		remove_child(mode)
		mode.queue_free()
		return false
	var ok: bool = true
	mode.call("select_entity_id", producer_id)
	if not bool(mode.call("issue_context_at_tile", rally_tile, false)):
		push_error("producer right-click empty tile should set a move rally in network play")
		ok = false
	if (
		producer.production_state == null
		or producer.production_state.rally_mode != ProductionState.RALLY_MODE_MOVE
		or producer.production_state.rally_target_tile != rally_tile
	):
		push_error("network producer move rally state was not stored")
		ok = false
	if not bool(mode.call("issue_context_at_tile", resource.origin, false)):
		push_error("producer right-click resource should set a gather rally in network play")
		ok = false
	if (
		producer.production_state == null
		or producer.production_state.rally_mode != ProductionState.RALLY_MODE_GATHER
		or producer.production_state.rally_target_entity_id != resource_id
	):
		push_error("network producer gather rally state was not stored")
		ok = false
	mode.call("select_entity_id", gatherer_id)
	if not bool(mode.call("issue_context_at_tile", resource.origin, false)):
		push_error("worker right-click resource should queue GATHER in network play")
		ok = false
	var input: DevTurnInput = mode.call("input_model") as DevTurnInput
	if (
		input == null
		or not _has_gather_order(input.submit_for_player(0).orders, gatherer_id, resource_id)
	):
		push_error("network resource context should append a GATHER order for the worker")
		ok = false
	remove_child(mode)
	mode.queue_free()
	return ok


func _test_network_pending_command_buttons() -> bool:
	var script: Script = load(NETWORK_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % NETWORK_PLAY_MODE_PATH)
		return false
	var mode: Node = script.new()
	add_child(mode)
	mode.call("ensure_initialized")
	var loaded: LoadedScenario = _load_mvp()
	if loaded == null:
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("bind_authoritative_snapshot", loaded.state, loaded.registry, 0)
	if not mode.has_method("confirm_pending_at_tile"):
		push_error("network play mode should confirm command-card pending actions")
		remove_child(mode)
		mode.queue_free()
		return false
	var card: CommandCard = mode.find_child("CommandCard", true, false) as CommandCard
	var input: DevTurnInput = mode.call("input_model") as DevTurnInput
	if card == null or input == null:
		push_error("network pending command test requires command card and input model")
		remove_child(mode)
		mode.queue_free()
		return false
	loaded.state.get_player(0).minerals = 10000
	loaded.state.get_player(0).gas = 10000
	loaded.state.get_player(0).pop_cap = 200
	var builder_id: int = _first_builder_entity_id(loaded.state, loaded.registry, 0)
	if builder_id < 0:
		push_error("network pending command test requires a builder")
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("select_entity_id", builder_id)
	var build_ids: Array[String] = input.build_option_ids()
	if build_ids.is_empty() or not card.build_option_ids().has(build_ids[0]):
		push_error("network command card should show selected builder build options")
		remove_child(mode)
		mode.queue_free()
		return false
	var build_tile: Vector2i = _first_valid_build_tile(input, build_ids[0], loaded.state)
	if build_tile == Vector2i(-1, -1):
		push_error("network pending command test requires a valid build tile")
		remove_child(mode)
		mode.queue_free()
		return false
	var ok: bool = true
	card.emit_signal("build_requested", build_ids[0])
	if not bool(mode.call("confirm_pending_at_tile", build_tile, false)):
		push_error("network build button should enter pending BUILD and confirm on map click")
		ok = false
	if not _has_order_type(input.submit_for_player(0).orders, builder_id, EntityOrder.Type.BUILD):
		push_error("network pending BUILD should queue a BUILD order")
		ok = false
	input.clear_submissions()
	var gatherer_id: int = _first_gatherer_entity_id(loaded.state, loaded.registry, 0)
	var resource_id: int = _first_resource_target_id_for_owner(loaded.state, loaded.registry, 0)
	var resource: Entity = loaded.state.get_entity_by_id(resource_id)
	if gatherer_id < 0 or resource == null:
		push_error("network pending command test requires gatherer and resource target")
		ok = false
	else:
		mode.call("select_entity_id", gatherer_id)
		card.emit_signal("gather_requested")
		if not bool(mode.call("confirm_pending_at_tile", resource.origin, false)):
			push_error("network gather button should enter pending GATHER and confirm on resource")
			ok = false
		if not _has_gather_order(input.submit_for_player(0).orders, gatherer_id, resource_id):
			push_error("network pending GATHER should queue a GATHER order")
			ok = false
		input.clear_submissions()
		var move_tile: Vector2i = _first_open_neighbor(loaded.state, gatherer_id)
		card.emit_signal("move_requested")
		if not bool(mode.call("confirm_pending_at_tile", move_tile, false)):
			push_error("network move button should enter pending Move")
			ok = false
		if not _has_order_type(
			input.submit_for_player(0).orders, gatherer_id, EntityOrder.Type.MOVE
		):
			push_error("network pending Move should queue a MOVE order")
			ok = false
	remove_child(mode)
	mode.queue_free()
	if not _network_pending_target_button_queues_attack_target():
		ok = false
	return ok


func _network_pending_target_button_queues_attack_target() -> bool:
	var script: Script = load(NETWORK_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % NETWORK_PLAY_MODE_PATH)
		return false
	var mode: Node = script.new()
	add_child(mode)
	mode.call("ensure_initialized")
	var loaded: LoadedScenario = _load_combat()
	if loaded == null:
		remove_child(mode)
		mode.queue_free()
		return false
	var enemy_id: int = _first_enemy_entity_id(loaded.state, 0)
	var enemy: Entity = loaded.state.get_entity_by_id(enemy_id)
	if enemy != null and loaded.state.tile_grid != null:
		var visible_enemy_origin := Vector2i(8, 10)
		if loaded.state.tile_grid.move(enemy.id, visible_enemy_origin):
			enemy.origin = visible_enemy_origin
	mode.call("bind_authoritative_snapshot", loaded.state, loaded.registry, 0)
	if not mode.has_method("confirm_pending_at_tile"):
		push_error("network play mode should confirm pending Attack")
		remove_child(mode)
		mode.queue_free()
		return false
	var actor_id: int = _first_target_capable_entity_id(loaded.state, loaded.registry, 0)
	var card: CommandCard = mode.find_child("CommandCard", true, false) as CommandCard
	var input: DevTurnInput = mode.call("input_model") as DevTurnInput
	if actor_id < 0 or enemy == null or card == null or input == null:
		push_error("network pending target test requires combat actor, enemy, card, and input")
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("select_entity_id", actor_id)
	card.emit_signal("target_requested")
	var ok: bool = true
	if not bool(mode.call("confirm_pending_at_tile", enemy.origin, false)):
		push_error("network attack button should enter pending Attack and confirm on enemy")
		ok = false
	var actor: Entity = loaded.state.get_entity_by_id(actor_id)
	if actor == null or actor.focus_target_entity_id != -1:
		push_error("network pending Attack should not mutate focus before resolve")
		ok = false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if (
		orders.size() != 1
		or orders[0].type != EntityOrder.Type.TARGET
		or orders[0].target_priority_chain != ([enemy_id] as Array[int])
		or orders[0].target_entity_id != enemy_id
		or orders[0].target_tile != enemy.origin
	):
		push_error("network pending Attack should queue TARGET")
		ok = false
	remove_child(mode)
	mode.queue_free()
	return ok


func _test_network_a_key_attack_mode() -> bool:
	var script: Script = load(NETWORK_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % NETWORK_PLAY_MODE_PATH)
		return false
	var mode: Node = script.new()
	add_child(mode)
	mode.call("ensure_initialized")
	var loaded: LoadedScenario = _load_combat()
	if loaded == null:
		remove_child(mode)
		mode.queue_free()
		return false
	var actor_id: int = _first_target_capable_entity_id(loaded.state, loaded.registry, 0)
	var enemy_id: int = _first_enemy_entity_id(loaded.state, 0)
	var enemy: Entity = loaded.state.get_entity_by_id(enemy_id)
	if enemy != null and loaded.state.tile_grid != null:
		var visible_enemy_origin := Vector2i(8, 10)
		if loaded.state.tile_grid.move(enemy.id, visible_enemy_origin):
			enemy.origin = visible_enemy_origin
	mode.call("bind_authoritative_snapshot", loaded.state, loaded.registry, 0)
	var input: DevTurnInput = mode.call("input_model") as DevTurnInput
	var move_tile: Vector2i = _first_open_neighbor(loaded.state, actor_id)
	if actor_id < 0 or enemy == null or input == null or move_tile == Vector2i(-1, -1):
		push_error("network A-key test requires combat actor, enemy, input, and move tile")
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("select_entity_id", actor_id)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	mode.call("_unhandled_input", _key_press(KEY_A))
	var ok: bool = true
	if mode.call("pending_command_kind") != "target":
		push_error("network A key should enter pending attack mode")
		ok = false
	if int(mode.call("pending_cursor_shape")) != Input.CURSOR_CROSS:
		push_error("network pending attack should use crosshair cursor")
		ok = false
	if not bool(mode.call("confirm_pending_at_tile", move_tile, false)):
		push_error("network A-key ground click should queue attack movement")
		ok = false
	var ground_orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if (
		ground_orders.size() != 1
		or ground_orders[0].type != EntityOrder.Type.ATTACK_MOVE
		or ground_orders[0].target_tile != move_tile
	):
		push_error("network A-key ground click should queue ATTACK_MOVE")
		ok = false
	if mode.call("pending_command_kind") != "":
		push_error("network A-key ground click should clear pending attack mode after queuing")
		ok = false
	input.clear_submissions()
	mode.call("_unhandled_input", _key_press(KEY_A))
	if not bool(mode.call("confirm_pending_at_tile", enemy.origin, false)):
		push_error("network A-key enemy click should queue TARGET")
		ok = false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if (
		orders.size() != 1
		or orders[0].type != EntityOrder.Type.TARGET
		or orders[0].target_priority_chain != ([enemy_id] as Array[int])
		or orders[0].target_entity_id != enemy_id
		or orders[0].target_tile != enemy.origin
	):
		push_error("network A-key enemy click should queue TARGET against the clicked enemy")
		ok = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	remove_child(mode)
	mode.queue_free()
	return ok


func _test_network_authoritative_producer_state() -> bool:
	var script: Script = load(NETWORK_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % NETWORK_PLAY_MODE_PATH)
		return false
	var mode: Node = script.new()
	add_child(mode)
	mode.call("ensure_initialized")
	var client_loaded: LoadedScenario = _load_mvp()
	var server_loaded: LoadedScenario = _load_mvp()
	if client_loaded == null or server_loaded == null:
		remove_child(mode)
		mode.queue_free()
		return false
	_give_generous_player_resources(client_loaded.state, 0)
	_give_generous_player_resources(server_loaded.state, 0)
	client_loaded.registry = _clone_registry_for_test(client_loaded.registry)
	server_loaded.registry = _clone_registry_for_test(server_loaded.registry)
	if client_loaded.registry == null or server_loaded.registry == null:
		push_error("network authoritative producer test requires cloned registries")
		remove_child(mode)
		mode.queue_free()
		return false
	var producer_id: int = _first_producer_entity_id(client_loaded.state, client_loaded.registry, 0)
	if producer_id < 0:
		push_error("network authoritative producer test requires a producer")
		remove_child(mode)
		mode.queue_free()
		return false
	if (
		not _ensure_second_train_option(client_loaded.state, client_loaded.registry, producer_id)
		or not _ensure_second_train_option(server_loaded.state, server_loaded.registry, producer_id)
	):
		push_error("network authoritative producer test requires two train options")
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("bind_authoritative_snapshot", client_loaded.state, client_loaded.registry, 0)
	var rally_tile: Vector2i = _first_open_neighbor(client_loaded.state, producer_id)
	if rally_tile == Vector2i(-1, -1):
		push_error("network authoritative producer test requires a rally tile")
		remove_child(mode)
		mode.queue_free()
		return false
	mode.call("select_entity_id", producer_id)
	var input: DevTurnInput = mode.call("input_model") as DevTurnInput
	var train_ids: Array[String] = input.train_option_ids() if input != null else []
	if train_ids.is_empty():
		push_error("network authoritative producer test requires a train option")
		remove_child(mode)
		mode.queue_free()
		return false
	var stale_repeat_def_id: String = train_ids[0]
	var train_def_id: String = train_ids[1] if train_ids.size() > 1 else train_ids[0]
	_set_repeat_train_state(client_loaded.state, producer_id, true, stale_repeat_def_id)
	_set_repeat_train_state(server_loaded.state, producer_id, true, stale_repeat_def_id)
	var ok: bool = true
	if not bool(mode.call("issue_context_at_tile", rally_tile, false)):
		push_error("network producer should accept move rally before submit")
		ok = false
	if not bool(mode.call("issue_repeat_train_selected", true)):
		push_error("network producer should accept repeat train before submit")
		ok = false
	if not bool(mode.call("issue_train_selected", train_def_id)):
		push_error("network producer should queue TRAIN before submit")
		ok = false
	if not bool(mode.call("issue_repeat_train_selected", false)):
		push_error("network producer should accept repeat train disable before submit")
		ok = false
	if not bool(mode.call("issue_repeat_train_selected", true)):
		push_error("network producer should accept repeat train re-enable before submit")
		ok = false
	var repeat_def_id: String = _repeat_train_order_def_id(
		input.submit_for_player(0).orders, producer_id
	)
	if repeat_def_id != train_def_id:
		push_error("network repeat train should target the selected train option")
		ok = false
	var submit: SubmitTurn = _round_trip_submit_turn(input.submit_for_player(0).clone())
	if submit == null:
		push_error("network authoritative producer test expected wire SubmitTurn round-trip")
		remove_child(mode)
		mode.queue_free()
		return false
	var result: ResolveResult = Resolver.resolve(
		server_loaded.state, submit, SubmitTurn.new(), server_loaded.registry, _load_tunables()
	)
	if result == null or result.new_state == null:
		push_error("network authoritative producer test expected first resolve result")
		remove_child(mode)
		mode.queue_free()
		return false
	var server_state: MatchState = result.new_state
	var server_producer: Entity = server_state.get_entity_by_id(producer_id)
	if (
		server_producer == null
		or server_producer.production_state == null
		or not server_producer.production_state.repeat_train_enabled
		or server_producer.production_state.repeat_train_def_id != train_def_id
	):
		push_error("server should preserve submitted repeat-train state")
		ok = false
	if (
		server_producer == null
		or server_producer.production_state == null
		or server_producer.production_state.rally_mode != ProductionState.RALLY_MODE_MOVE
		or server_producer.production_state.rally_target_tile != rally_tile
	):
		push_error("server should preserve submitted move-rally state")
		ok = false
	mode.call("apply_authoritative_result", server_state, result.events)
	var spawned_id: int = -1
	for turn in range(4):
		var next_submit: SubmitTurn = input.submit_for_player(0).clone()
		result = Resolver.resolve(
			server_state, next_submit, SubmitTurn.new(), server_loaded.registry, _load_tunables()
		)
		if result == null or result.new_state == null:
			push_error("network authoritative producer test expected follow-up resolve result")
			ok = false
			break
		server_state = result.new_state
		mode.call("apply_authoritative_result", server_state, result.events)
		spawned_id = _train_completed_target_id(result.events, producer_id, train_def_id)
		if spawned_id >= 0:
			break
	if spawned_id < 0:
		push_error("network authoritative producer test expected TRAIN_COMPLETED")
		ok = false
	else:
		var rally_orders: Array[EntityOrder] = input.submit_for_player(0).orders
		if not _has_move_order(rally_orders, spawned_id, rally_tile):
			push_error("client should queue spawned unit MOVE from authoritative rally state")
			ok = false
		var final_producer: Entity = server_state.get_entity_by_id(producer_id)
		if (
			final_producer == null
			or final_producer.production_state == null
			or not final_producer.production_state.repeat_train_enabled
			or final_producer.production_state.repeat_train_def_id != train_def_id
			or final_producer.production_state.active.is_empty()
		):
			push_error(
				"repeat train should remain enabled and start the next unit after completion"
			)
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


func _key_press(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _round_trip_submit_turn(submit: SubmitTurn) -> SubmitTurn:
	var codec: Object = _new_script_instance(CODEC_PATH)
	if codec == null:
		return null
	var encoded: PackedByteArray = codec.call(
		"encode", {"kind": "submit_turn", "payload": {"submit": submit}}
	)
	var decoded: Dictionary = codec.call("decode", encoded)
	var payload: Dictionary = decoded.get("payload", {})
	return payload.get("submit", null) as SubmitTurn


func _load_combat() -> LoadedScenario:
	var scenario: ScenarioDef = load(COMBAT_SCENARIO_PATH) as ScenarioDef
	var registry: EntityRegistry = load(REGISTRY_PATH) as EntityRegistry
	var tunables: Tunables = _load_tunables()
	if scenario == null or registry == null or tunables == null:
		push_error("network tests require combat scenario, registry, and tunables")
		return null
	return ScenarioLoader.load(scenario, registry, tunables)


func _load_mvp() -> LoadedScenario:
	var scenario: ScenarioDef = load(MVP_SCENARIO_PATH) as ScenarioDef
	var registry: EntityRegistry = load(REGISTRY_PATH) as EntityRegistry
	var tunables: Tunables = _load_tunables()
	if scenario == null or registry == null or tunables == null:
		push_error("network tests require MVP scenario, registry, and tunables")
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
	order.type = EntityOrder.Type.TARGET
	order.entity_id = actor_id
	if target_id >= 0:
		order.target_priority_chain = [target_id]
		order.target_entity_id = target_id
		var target: Entity = state.get_entity_by_id(target_id)
		if target != null:
			order.target_tile = target.origin
	submit.orders.append(order)
	return submit


func _first_entity_id(state: MatchState, owner: int) -> int:
	return _nth_entity_id(state, owner, 0)


func _entity_ids_by_def_owner(state: MatchState, def_id: String, owner: int) -> Array[int]:
	var out: Array[int] = []
	if state == null:
		return out
	for entity: Entity in state.entities_sorted_by_id():
		if (
			entity != null
			and entity.def_id == def_id
			and entity.owner_player_id == owner
			and entity.current_hp > 0
		):
			out.append(entity.id)
	return out


func _nth_entity_id(state: MatchState, owner: int, index: int) -> int:
	if state == null:
		return -1
	var seen: int = 0
	for entity: Entity in state.entities_sorted_by_id():
		if entity != null and entity.owner_player_id == owner and entity.current_hp > 0:
			if seen == index:
				return entity.id
			seen += 1
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
		if not input.train_option_ids().is_empty() or not input.research_option_ids().is_empty():
			return entity.id
	return -1


func _clone_registry_for_test(registry: EntityRegistry) -> EntityRegistry:
	if registry == null:
		return null
	var out: EntityRegistry = EntityRegistry.new()
	for def: EntityDef in registry.entities:
		var copied_def: EntityDef = null
		if def != null:
			copied_def = def.duplicate(true) as EntityDef
		out.entities.append(copied_def)
	for research: ResearchDef in registry.researches:
		var copied_research: ResearchDef = null
		if research != null:
			copied_research = research.duplicate(true) as ResearchDef
		out.researches.append(copied_research)
	return out


func _ensure_second_train_option(
	state: MatchState, registry: EntityRegistry, producer_id: int
) -> bool:
	if state == null or registry == null:
		return false
	var producer: Entity = state.get_entity_by_id(producer_id)
	if producer == null:
		return false
	var def_id: String = (
		producer.current_def_id if producer.current_def_id != "" else producer.def_id
	)
	var def: EntityDef = registry.get_by_id(def_id)
	if def == null or def.production == null:
		return false
	if def.production.produces.size() > 1:
		return true
	var candidates: Array[String] = ["marine", "worker", "siege_tank", "helicopter"]
	for candidate_id: String in candidates:
		if def.production.produces.has(candidate_id):
			continue
		if registry.get_by_id(candidate_id) == null:
			continue
		def.production.produces.append(candidate_id)
		return true
	return def.production.produces.size() > 1


func _set_repeat_train_state(
	state: MatchState, producer_id: int, enabled: bool, def_id: String
) -> void:
	if state == null:
		return
	var producer: Entity = state.get_entity_by_id(producer_id)
	if producer == null or producer.production_state == null:
		return
	producer.production_state.repeat_train_enabled = enabled
	producer.production_state.repeat_train_def_id = def_id


func _first_gatherer_entity_id(state: MatchState, registry: EntityRegistry, owner: int) -> int:
	if state == null or registry == null:
		return -1
	var input: DevTurnInput = DevTurnInput.new()
	input.bind_context(state, registry)
	input.set_active_player_id(owner)
	for entity: Entity in state.entities_sorted_by_id():
		if entity == null or entity.owner_player_id != owner or entity.current_hp <= 0:
			continue
		if input.select_entity(entity.id) and input.can_issue_gather():
			return entity.id
	return -1


func _first_builder_entity_id(state: MatchState, registry: EntityRegistry, owner: int) -> int:
	if state == null or registry == null:
		return -1
	var input: DevTurnInput = DevTurnInput.new()
	input.bind_context(state, registry)
	input.set_active_player_id(owner)
	for entity: Entity in state.entities_sorted_by_id():
		if entity == null or entity.owner_player_id != owner or entity.current_hp <= 0:
			continue
		if input.select_entity(entity.id) and not input.build_option_ids().is_empty():
			return entity.id
	return -1


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


func _first_target_capable_entity_id(
	state: MatchState, registry: EntityRegistry, owner: int
) -> int:
	if state == null or registry == null:
		return -1
	var input: DevTurnInput = DevTurnInput.new()
	input.bind_context(state, registry)
	input.set_active_player_id(owner)
	for entity: Entity in state.entities_sorted_by_id():
		if entity == null or entity.owner_player_id != owner or entity.current_hp <= 0:
			continue
		if input.select_entity(entity.id) and input.can_issue_target():
			return entity.id
	return -1


func _first_resource_target_id_for_owner(
	state: MatchState, registry: EntityRegistry, owner: int
) -> int:
	if state == null or registry == null:
		return -1
	for entity: Entity in state.entities_sorted_by_id():
		if entity == null:
			continue
		if not _is_resource_target_for_test(entity, registry):
			continue
		if GatherSystem.resolve_source_for_worker(state, registry, entity.id, owner) != null:
			return entity.id
	return -1


func _is_resource_target_for_test(entity: Entity, registry: EntityRegistry) -> bool:
	if entity == null or registry == null:
		return false
	var def_id: String = entity.current_def_id if entity.current_def_id != "" else entity.def_id
	var def: EntityDef = registry.get_by_id(def_id)
	if def == null:
		return false
	return def.resource_source != null or def.tags.has("refinery") or def.tags.has("extractor")


func _first_valid_build_tile(input: DevTurnInput, def_id: String, state: MatchState) -> Vector2i:
	if input == null or state == null or state.tile_grid == null:
		return Vector2i(-1, -1)
	for y in range(state.tile_grid.height):
		for x in range(state.tile_grid.width):
			var tile := Vector2i(x, y)
			var preview: Dictionary = input.build_placement_preview(def_id, tile)
			if preview.get("valid", false):
				return tile
	return Vector2i(-1, -1)


func _has_order_type(orders: Array[EntityOrder], entity_id: int, order_type: int) -> bool:
	for order: EntityOrder in orders:
		if order != null and order.entity_id == entity_id and order.type == order_type:
			return true
	return false


func _has_gather_order(orders: Array[EntityOrder], entity_id: int, target_entity_id: int) -> bool:
	for order: EntityOrder in orders:
		if (
			order != null
			and order.entity_id == entity_id
			and order.type == EntityOrder.Type.GATHER
			and order.target_entity_id == target_entity_id
		):
			return true
	return false


func _repeat_train_order_def_id(orders: Array[EntityOrder], producer_id: int) -> String:
	for order: EntityOrder in orders:
		if (
			order != null
			and order.entity_id == producer_id
			and order.type == EntityOrder.Type.REPEAT_TRAIN_TOGGLE
			and order.enabled
		):
			return order.def_id
	return ""


func _has_move_order(orders: Array[EntityOrder], entity_id: int, target_tile: Vector2i) -> bool:
	for order: EntityOrder in orders:
		if (
			order != null
			and order.entity_id == entity_id
			and order.type == EntityOrder.Type.MOVE
			and order.target_tile == target_tile
		):
			return true
	return false


func _train_completed_target_id(events: Array, producer_id: int, def_id: String) -> int:
	for item in events:
		var event: ResolverEvent = item as ResolverEvent
		if (
			event != null
			and event.type == ResolverEvent.Type.TRAIN_COMPLETED
			and event.actor_id == producer_id
			and event.def_id == def_id
		):
			return event.target_id
	return -1


func _events_from_peer_messages(messages_by_peer: Dictionary, peer_id: int) -> Array:
	var message: Dictionary = _message_from_list(messages_by_peer.get(peer_id, []), "turn_resolved")
	var payload: Dictionary = message.get("payload", {})
	return payload.get("events", [])


func _events_have_type(events: Array, event_type: ResolverEvent.Type) -> bool:
	for item in events:
		var event: ResolverEvent = item as ResolverEvent
		if event != null and event.type == event_type:
			return true
	return false


func _entity_count_by_def_and_owner(state: MatchState, def_id: String, owner_player_id: int) -> int:
	if state == null:
		return 0
	var count := 0
	for entity: Entity in state.entities_sorted_by_id():
		if entity != null and entity.def_id == def_id and entity.owner_player_id == owner_player_id:
			count += 1
	return count


func _give_generous_player_resources(state: MatchState, player_id: int) -> void:
	if state == null:
		return
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return
	player.minerals = 10000
	player.gas = 10000
	player.pop_cap = 200


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
		Vector2i(2, 0),
		Vector2i(-2, 0),
		Vector2i(0, 2),
		Vector2i(0, -2),
	]
	for offset in offsets:
		var tile: Vector2i = entity.origin + offset
		if state.tile_grid.is_in_bounds(tile) and state.tile_grid.entity_at(tile) < 0:
			return tile
	return Vector2i(-1, -1)


func _first_empty_tile(state: MatchState) -> Vector2i:
	if state == null or state.tile_grid == null:
		return Vector2i(-1, -1)
	for y in range(state.tile_grid.height):
		for x in range(state.tile_grid.width):
			var tile := Vector2i(x, y)
			if state.tile_grid.entity_at(tile) < 0:
				return tile
	return Vector2i(-1, -1)


func _select_entities_for_test(input: DevTurnInput, ids: Array[int]) -> bool:
	if input == null:
		return false
	if not input.has_method("select_entities"):
		push_error("DevTurnInput should expose select_entities")
		return false
	return input.call("select_entities", ids)


func _selected_ids_for_test(input: DevTurnInput) -> Array[int]:
	var out: Array[int] = []
	if input == null:
		return out
	if not input.has_method("selected_entity_ids"):
		push_error("DevTurnInput should expose selected_entity_ids")
		return out
	var raw: Array = input.call("selected_entity_ids")
	for item in raw:
		out.append(int(item))
	return out


func _world_box_for_entities(state: MatchState, entity_ids: Array[int]) -> Rect2:
	if state == null or entity_ids.is_empty():
		return Rect2()
	var min_tile: Vector2i = Vector2i(100000, 100000)
	var max_tile: Vector2i = Vector2i(-100000, -100000)
	for entity_id in entity_ids:
		var entity: Entity = state.get_entity_by_id(entity_id)
		if entity == null:
			continue
		var rect: Rect2i = (
			state.tile_grid.entity_rect(entity.id) if state.tile_grid != null else Rect2i()
		)
		if rect.size == Vector2i.ZERO:
			rect = Rect2i(entity.origin, Vector2i.ONE)
		min_tile.x = mini(min_tile.x, rect.position.x)
		min_tile.y = mini(min_tile.y, rect.position.y)
		max_tile.x = maxi(max_tile.x, rect.position.x + rect.size.x)
		max_tile.y = maxi(max_tile.y, rect.position.y + rect.size.y)
	var tile_size: float = float(_load_tunables().tile_pixel_size)
	var start: Vector2 = (Vector2(min_tile) - Vector2(0.25, 0.25)) * tile_size
	var end: Vector2 = (Vector2(max_tile) + Vector2(0.25, 0.25)) * tile_size
	return Rect2(start, end - start)


func _drag_box(mode: Node, box: Rect2, shift_pressed: bool) -> void:
	mode.call(
		"_unhandled_input", _mouse_button(MOUSE_BUTTON_LEFT, true, box.position, shift_pressed)
	)
	mode.call(
		"_unhandled_input", _mouse_motion(box.size, MOUSE_BUTTON_MASK_LEFT, box.end, shift_pressed)
	)
	mode.call("_unhandled_input", _mouse_button(MOUSE_BUTTON_LEFT, false, box.end, shift_pressed))


func _tile_center_px(tile: Vector2i) -> Vector2:
	var tile_size: float = float(_load_tunables().tile_pixel_size)
	return (Vector2(tile) + Vector2(0.5, 0.5)) * tile_size


func _mouse_button(
	button_index: MouseButton, pressed: bool, position: Vector2, shift_pressed: bool = false
) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = pressed
	event.position = position
	event.shift_pressed = shift_pressed
	return event


func _mouse_motion(
	relative: Vector2,
	button_mask: MouseButtonMask,
	position: Vector2 = Vector2.ZERO,
	shift_pressed: bool = false
) -> InputEventMouseMotion:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.relative = relative
	event.button_mask = button_mask
	event.position = position
	event.shift_pressed = shift_pressed
	return event


func _far_open_tile(state: MatchState, entity_id: int) -> Vector2i:
	if state == null or state.tile_grid == null or entity_id < 0:
		return Vector2i(-1, -1)
	var entity: Entity = state.get_entity_by_id(entity_id)
	if entity == null:
		return Vector2i(-1, -1)
	var best_tile := Vector2i(-1, -1)
	var best_distance: int = -1
	for y in range(state.tile_grid.height):
		for x in range(state.tile_grid.width):
			var tile := Vector2i(x, y)
			if state.tile_grid.entity_at(tile) >= 0:
				continue
			var distance: int = absi(tile.x - entity.origin.x) + absi(tile.y - entity.origin.y)
			if distance > best_distance:
				best_distance = distance
				best_tile = tile
	return best_tile


func _remove_user_file(path: String) -> void:
	var absolute: String = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path) or FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)


func _peer_has_message_kind(messages_by_peer: Dictionary, peer_id: int, kind: String) -> bool:
	var messages: Array = messages_by_peer.get(peer_id, [])
	return _message_list_has_kind(messages, kind)


func _message_list_has_kind(messages: Array, kind: String) -> bool:
	for message: Dictionary in messages:
		if message.get("kind", "") == kind:
			return true
	return false


func _message_from_list(messages: Array, kind: String) -> Dictionary:
	for message: Dictionary in messages:
		if message.get("kind", "") == kind:
			return message
	return {}


func _events_include_match_winner(events: Array, winner_player_id: int) -> bool:
	for item: Variant in events:
		var event: ResolverEvent = item as ResolverEvent
		if (
			event != null
			and event.type == ResolverEvent.Type.MATCH_ENDED
			and event.winner_player_id == winner_player_id
		):
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
