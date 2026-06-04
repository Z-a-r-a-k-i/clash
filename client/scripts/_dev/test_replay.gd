@tool
extends Node

const DEV_PLAY_MODE_PATH := "res://scripts/_dev/dev_play_mode.gd"
const COMBAT_SCENARIO_PATH := "res://data/scenarios/combat_marines_vs_tanks.tres"
const MVP_SCENARIO_PATH := "res://data/scenarios/mvp_map.tres"
const SNAPSHOT_PATH := "user://test_replay_snapshot.tres"
const REPLAY_PATH := "user://test_replay_latest.tres"
const BAD_REPLAY_PATH := "user://test_replay_bad.tres"


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	_run_all()


func _run_all() -> int:
	var passed := 0
	var failed := 0
	var fail_names: Array[String] = []
	for test_pair in _all_tests():
		var test_name: String = test_pair[0]
		var fn: Callable = test_pair[1]
		var ok: bool = fn.call()
		if ok:
			passed += 1
		else:
			failed += 1
			fail_names.append(test_name)
	print("[test_replay] %d passed, %d failed" % [passed, failed])
	for test_name in fail_names:
		push_error("  failed: %s" % test_name)
	return failed


func _all_tests() -> Array:
	return [
		["replay_journal_reaches_live_final_state", _test_replay_reaches_live_final_state],
		["replay_jump_uses_recorded_checkpoints", _test_replay_jump_checkpoints],
		["replay_next_recomputes_turn", _test_replay_next_recomputes_turn],
		["snapshot_save_load_round_trips_input", _test_snapshot_round_trip],
		["dev_play_mode_load_snapshot_can_resolve", _test_load_snapshot_can_resolve],
		["replay_mode_rejects_gameplay_edits", _test_replay_mode_rejects_edits],
		["bad_replay_load_preserves_current_timeline", _test_bad_replay_load_preserves_current],
		["replay_restore_then_resolve_truncates_history", _test_restore_truncates_history],
		["replay_save_load_rebuilds_checkpoints", _test_replay_save_load],
		["replay_timeline_scrubs_recorded_checkpoints", _test_replay_timeline_scrubs],
		["dev_play_mode_auto_saves_replay_to_tmp", _test_auto_replay_save],
	]


func _test_replay_reaches_live_final_state() -> bool:
	var mode: Node = _make_loaded_mode()
	if mode == null:
		return false
	_queue_attack(mode)
	if not mode.resolve_turn():
		return _fail_mode(mode, "first resolve failed")
	if not mode.resolve_turn():
		return _fail_mode(mode, "second resolve failed")
	if not mode.resolve_turn():
		return _fail_mode(mode, "third resolve failed")
	var live_final: MatchState = mode.current_state().clone()
	if not mode.replay_start():
		return _fail_mode(mode, "replay_start failed")
	for i in range(10):
		if not mode.replay_next():
			break
	var ok: bool = _states_equal(live_final, mode.current_state())
	if not ok:
		push_error("replay final state should match recorded live final")
	_free_mode(mode)
	return ok


func _test_replay_jump_checkpoints() -> bool:
	var mode: Node = _make_loaded_mode_for(MVP_SCENARIO_PATH)
	if mode == null:
		return false
	var expected: Array[MatchState] = [mode.current_state().clone()]
	for i in range(3):
		if not mode.resolve_turn():
			return _fail_mode(mode, "resolve %d failed" % i)
		expected.append(mode.current_state().clone())
	var ok := true
	for turn_index in expected.size():
		if not mode.replay_jump_to_turn(turn_index):
			push_error("expected replay checkpoint for turn %d" % turn_index)
			ok = false
			continue
		if not _states_equal(expected[turn_index], mode.current_state()):
			push_error("checkpoint %d did not match recorded state" % turn_index)
			ok = false
	_free_mode(mode)
	return ok


func _test_replay_next_recomputes_turn() -> bool:
	var mode: Node = _make_loaded_mode()
	if mode == null:
		return false
	_queue_attack(mode)
	if not mode.resolve_turn():
		return _fail_mode(mode, "resolve failed")
	var expected_turn_1: MatchState = mode.current_state().clone()
	if not mode.replay_start():
		return _fail_mode(mode, "replay_start failed")
	if not mode.replay_next():
		return _fail_mode(mode, "replay_next failed")
	var ok: bool = _states_equal(expected_turn_1, mode.current_state())
	if not ok:
		push_error("replay_next should recompute the next checkpoint state")
	_free_mode(mode)
	return ok


func _test_snapshot_round_trip() -> bool:
	var mode: Node = _make_loaded_mode()
	if mode == null:
		return false
	mode.set_active_player_id(0)
	mode.select_entity_id(1)
	mode.issue_move_only_selected(Vector2i(9, 10))
	if not mode.save_snapshot_to_path(SNAPSHOT_PATH):
		return _fail_mode(mode, "snapshot save failed")
	var session: SavedSession = MatchSaver.load_from(SNAPSHOT_PATH)
	if session == null:
		return _fail_mode(mode, "snapshot load failed")
	var ok := true
	if not _states_equal(mode.current_state(), session.state):
		push_error("saved snapshot state should round-trip")
		ok = false
	if session.input_snapshot == null:
		push_error("saved snapshot should include DevInputSnapshot")
		ok = false
	else:
		var restored := DevTurnInput.new()
		restored.restore_snapshot(session.input_snapshot, session.state, session.registry)
		if restored.active_player_id() != 0 or restored.selected_entity_id() != 1:
			push_error("snapshot input selection should round-trip")
			ok = false
		if restored.submit_for_player(0).orders.size() != 1:
			push_error("snapshot pending submission should round-trip")
			ok = false
	_free_mode(mode)
	return ok


func _test_load_snapshot_can_resolve() -> bool:
	var mode: Node = _make_loaded_mode()
	if mode == null:
		return false
	mode.set_active_player_id(0)
	mode.select_entity_id(1)
	mode.issue_attack_selected(4)
	if not mode.save_snapshot_to_path(SNAPSHOT_PATH):
		return _fail_mode(mode, "snapshot save failed")
	mode.load_scenario_path(COMBAT_SCENARIO_PATH)
	if not mode.load_snapshot_from_path(SNAPSHOT_PATH):
		return _fail_mode(mode, "snapshot reload failed")
	if mode.pending_order_count(0) != 1:
		return _fail_mode(mode, "snapshot load should restore pending order")
	if mode.replay_mode_active():
		return _fail_mode(mode, "snapshot load should return to playable mode")
	var play_panel: PanelContainer = mode.get_node_or_null("DevHUD/Panel") as PanelContainer
	var replay_panel: PanelContainer = mode.get_node_or_null("DevHUD/ReplayPanel") as PanelContainer
	if play_panel == null or not play_panel.visible or replay_panel == null or replay_panel.visible:
		return _fail_mode(mode, "snapshot load should show the play interface")
	if not mode.resolve_turn():
		return _fail_mode(mode, "resolve after snapshot load failed")
	var ok: bool = mode.current_state().turn_index == 1
	if not ok:
		push_error("snapshot-loaded match should resolve to turn 1")
	_free_mode(mode)
	return ok


func _test_replay_mode_rejects_edits() -> bool:
	var mode: Node = _make_loaded_mode()
	if mode == null:
		return false
	mode.set_active_player_id(0)
	mode.select_entity_id(1)
	if not mode.resolve_turn():
		return _fail_mode(mode, "resolve failed")
	if not mode.replay_jump_to_turn(1):
		return _fail_mode(mode, "replay jump failed")
	var marine: Entity = mode.current_state().get_entity_by_id(1)
	if marine == null:
		return _fail_mode(mode, "expected marine #1")
	var ok := true
	mode.set_active_player_id(1)
	if mode.input_model().active_player_id() != 0:
		push_error("replay mode should reject active player edits")
		ok = false
	if mode.select_entity_id(2):
		push_error("replay mode should reject selection edits")
		ok = false
	if mode.issue_attack_target_selected(4):
		push_error("replay mode should reject state-mutating commands")
		ok = false
	if marine.focus_target_entity_id != -1:
		push_error("replay mode command rejection should leave MatchState unchanged")
		ok = false
	if mode.resolve_turn():
		push_error("resolve_turn should remain blocked in replay mode")
		ok = false
	_free_mode(mode)
	return ok


func _test_bad_replay_load_preserves_current() -> bool:
	var mode: Node = _make_loaded_mode_for(MVP_SCENARIO_PATH)
	if mode == null:
		return false
	if not mode.resolve_turn():
		return _fail_mode(mode, "resolve failed")
	var expected_state: MatchState = mode.current_state().clone()
	var expected_frames: int = mode.replay_frame_count()
	var bad_replay := MatchReplay.new()
	bad_replay.initial_session = SavedSession.new()
	bad_replay.initial_session.state = expected_state.clone()
	bad_replay.initial_session.registry = load("res://data/entity_registry.tres") as EntityRegistry
	bad_replay.initial_session.input_snapshot = DevInputSnapshot.new()
	var bad_frame := ReplayTurnFrame.new()
	bad_frame.turn_index = 999
	bad_frame.submit_a = SubmitTurn.new()
	bad_frame.submit_b = SubmitTurn.new()
	var bad_frames: Array[ReplayTurnFrame] = [bad_frame]
	bad_replay.frames = bad_frames
	var err: Error = ResourceSaver.save(bad_replay, BAD_REPLAY_PATH)
	if err != OK:
		return _fail_mode(mode, "bad replay save failed")
	if mode.load_replay_from_path(BAD_REPLAY_PATH):
		return _fail_mode(mode, "bad replay load should fail")
	var ok := true
	if mode.replay_frame_count() != expected_frames:
		push_error("failed replay load should preserve current frame journal")
		ok = false
	if not _states_equal(expected_state, mode.current_state()):
		push_error("failed replay load should preserve current state")
		ok = false
	if not mode.replay_jump_to_turn(1):
		push_error("failed replay load should preserve current checkpoints")
		ok = false
	_free_mode(mode)
	return ok


func _test_restore_truncates_history() -> bool:
	var mode: Node = _make_loaded_mode_for(MVP_SCENARIO_PATH)
	if mode == null:
		return false
	for i in range(3):
		if not mode.resolve_turn():
			return _fail_mode(mode, "resolve %d failed" % i)
	if mode.replay_frame_count() != 3:
		return _fail_mode(mode, "expected three replay frames before restore")
	if not mode.replay_jump_to_turn(1):
		return _fail_mode(mode, "jump to old checkpoint failed")
	if not mode.restore_replay_here():
		return _fail_mode(mode, "restore replay checkpoint failed")
	if not mode.resolve_turn():
		return _fail_mode(mode, "resolve after restore failed")
	var ok := true
	if mode.replay_frame_count() != 2:
		push_error("resolving after restoring turn 1 should leave frames 0 and 1")
		ok = false
	if mode.replay_jump_to_turn(3):
		push_error("future checkpoint should be truncated after branch resolve")
		ok = false
	_free_mode(mode)
	return ok


func _test_replay_save_load() -> bool:
	var mode: Node = _make_loaded_mode()
	if mode == null:
		return false
	_queue_attack(mode)
	if not mode.resolve_turn() or not mode.resolve_turn():
		return _fail_mode(mode, "recorded resolves failed")
	var expected: MatchState = mode.current_state().clone()
	if not mode.save_replay_to_path(REPLAY_PATH):
		return _fail_mode(mode, "replay save failed")
	var loaded_mode: Node = _make_loaded_mode()
	if loaded_mode == null:
		_free_mode(mode)
		return false
	if not loaded_mode.load_replay_from_path(REPLAY_PATH):
		_free_mode(mode)
		return _fail_mode(loaded_mode, "replay load failed")
	var ok: bool = _states_equal(expected, loaded_mode.current_state())
	if not ok:
		push_error("loaded replay latest checkpoint should match saved live state")
	var play_panel: PanelContainer = loaded_mode.get_node_or_null("DevHUD/Panel") as PanelContainer
	var replay_panel: PanelContainer = loaded_mode.get_node_or_null("DevHUD/ReplayPanel") as PanelContainer
	if (
		not loaded_mode.replay_mode_active()
		or play_panel == null
		or play_panel.visible
		or replay_panel == null
		or not replay_panel.visible
	):
		push_error("loaded replay should show replay controls without the play interface")
		ok = false
	_free_mode(mode)
	_free_mode(loaded_mode)
	return ok


func _test_replay_timeline_scrubs() -> bool:
	var mode: Node = _make_loaded_mode()
	if mode == null:
		return false
	if not mode.resolve_turn() or not mode.resolve_turn():
		return _fail_mode(mode, "recorded resolves failed")
	if not mode.replay_latest():
		return _fail_mode(mode, "replay latest failed")
	var timeline: HSlider = mode.get_node_or_null(
		"DevHUD/ReplayPanel/Root/ReplayTimelineRow/ReplayTimeline"
	) as HSlider
	if timeline == null:
		return _fail_mode(mode, "replay timeline slider should exist")
	timeline.value = 1.0
	var ok: bool = mode.current_state().turn_index == 1
	if not ok:
		push_error("timeline slider should jump to the requested checkpoint")
	_free_mode(mode)
	return ok


func _test_auto_replay_save() -> bool:
	var mode: Node = _make_mode(true)
	if mode == null:
		return false
	mode.scenario_path = COMBAT_SCENARIO_PATH
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	var auto_path: String = mode.auto_replay_path()
	if auto_path != "":
		_remove_user_file(auto_path)
		return _fail_mode(mode, "auto replay should wait until the first resolved turn")
	_queue_attack(mode)
	if not mode.resolve_turn():
		return _fail_mode(mode, "auto replay resolve failed")
	auto_path = mode.auto_replay_path()
	if not auto_path.begins_with("user://tmp/replays/dev_replay_"):
		_remove_user_file(auto_path)
		return _fail_mode(mode, "auto replay path should live under user://tmp/replays")
	if not FileAccess.file_exists(auto_path):
		_remove_user_file(auto_path)
		return _fail_mode(mode, "auto replay should save after first resolved turn")
	var replay: MatchReplay = ResourceLoader.load(
		auto_path, "MatchReplay", ResourceLoader.CACHE_MODE_IGNORE
	) as MatchReplay
	if replay == null:
		_remove_user_file(auto_path)
		return _fail_mode(mode, "auto replay should reload as MatchReplay")
	var ok := true
	if replay.frames.size() != 1:
		push_error("auto replay should persist one frame after one resolve")
		ok = false
	if replay.initial_session == null or replay.initial_session.input_snapshot == null:
		push_error("auto replay should persist initial session and input snapshot")
		ok = false
	var file: FileAccess = FileAccess.open(auto_path, FileAccess.READ)
	var byte_count: int = 0
	if file != null:
		byte_count = file.get_length()
		file.close()
	if byte_count <= 0:
		push_error("auto replay file should have non-zero size")
		ok = false
	_remove_user_file(auto_path)
	_free_mode(mode)
	return ok


func _queue_attack(mode: Node) -> void:
	mode.set_active_player_id(0)
	mode.select_entity_id(1)
	mode.issue_attack_selected(4)


func _make_loaded_mode() -> Node:
	return _make_loaded_mode_for(COMBAT_SCENARIO_PATH)


func _make_loaded_mode_for(path: String) -> Node:
	var mode: Node = _make_mode()
	if mode == null:
		return null
	add_child(mode)
	if not mode.load_scenario_path(path):
		_free_mode(mode)
		return null
	return mode


func _make_mode(auto_save_replays_enabled: bool = false) -> Node:
	var script: Script = load(DEV_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % DEV_PLAY_MODE_PATH)
		return null
	var mode: Node = script.new()
	mode.set_auto_save_replays_enabled(auto_save_replays_enabled)
	return mode


func _fail_mode(mode: Node, message: String) -> bool:
	push_error(message)
	_free_mode(mode)
	return false


func _free_mode(mode: Node) -> void:
	if mode == null:
		return
	if mode.is_inside_tree():
		remove_child(mode)
	mode.queue_free()


func _remove_user_file(path: String) -> void:
	if path == "":
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _states_equal(a: MatchState, b: MatchState) -> bool:
	return _state_signature(a) == _state_signature(b)


func _state_signature(state: MatchState) -> Dictionary:
	if state == null:
		return {}
	var entities: Array[Dictionary] = []
	for entity in state.entities_sorted_by_id():
		entities.append(_entity_signature(entity, state))
	var players: Array[Dictionary] = []
	for player in state.players:
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
		"seed": state.rng_seed,
		"next_entity_id": state.next_entity_id,
		"winner": state.winner_player_id,
		"over": state.match_over,
		"players": players,
		"entities": entities,
	}


func _entity_signature(entity: Entity, state: MatchState) -> Dictionary:
	var rect := Rect2i()
	if state != null and state.tile_grid != null:
		rect = state.tile_grid.entity_rect(entity.id)
	return {
		"id": entity.id,
		"def": entity.def_id,
		"current_def": entity.current_def_id,
		"owner": entity.owner_player_id,
		"origin": entity.origin,
		"rect": rect,
		"layer": entity.current_layer,
		"hp": entity.current_hp,
		"moves": entity.moves_used_this_turn,
		"focus": entity.focus_target_entity_id,
		"halt": entity.halt_on_sight,
		"hidden": entity.is_hidden,
		"resource": entity.current_resource_amount,
		"constructing": entity.is_constructing,
		"construction_turns": entity.construction_turns_remaining,
		"construction_worker": entity.construction_worker_id,
		"locked": entity.locked_to_building_id,
		"pending_build": entity.pending_build_def_id,
		"pending_build_tile": entity.pending_build_target_tile,
		"pending_build_target": entity.pending_build_target_entity_id,
		"orders": _orders_signature(entity.order_queue),
		"production": _production_signature(entity.production_state),
		"gather": _gather_signature(entity.gather_state),
		"cooldowns": entity.ability_cooldowns.duplicate(),
		"cast": _cast_signature(entity.ability_cast),
	}


func _orders_signature(orders: Array[EntityOrder]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for order in orders:
		if order == null:
			out.append({})
		else:
			(
				out
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
	return out


func _production_signature(production: ProductionState) -> Dictionary:
	if production == null:
		return {}
	return {
		"active": production.active.duplicate(true),
		"queue": production.queue.duplicate(true),
		"repeat": production.repeat_train_enabled,
		"repeat_def": production.repeat_train_def_id,
		"rally": production.rally_mode,
		"rally_tile": production.rally_target_tile,
		"rally_target": production.rally_target_entity_id,
	}


func _gather_signature(gather: GatherState) -> Dictionary:
	if gather == null:
		return {}
	return {
		"source": gather.assigned_source_entity_id,
		"type": gather.carrying_resource_type,
		"amount": gather.carrying_amount,
		"phase": gather.phase,
	}


func _cast_signature(cast: AbilityCastState) -> Dictionary:
	if cast == null:
		return {}
	return {
		"ability": cast.ability_id,
		"turns": cast.turns_remaining,
	}
