class_name DevPlayMode
extends Node

const DEFAULT_SCENARIO_PATH := "res://data/scenarios/mvp_map.tres"
const MATCH_SCENE_PATH := "res://scenes/match.tscn"
const REGISTRY_PATH := "res://data/entity_registry.tres"
const TUNABLES_PATH := "res://data/tunables.tres"
const DEV_TURN_INPUT_SCRIPT := preload("res://scripts/game/dev_turn_input.gd")
const _RESOLVE_PROFILE_FLAG_PATH := "res://resolver_profile_enabled"
const _DEV_RESOLVE_PROFILE_LOG_PATH := "user://dev_play_resolve_latest.log"
const _DEV_SNAPSHOT_LATEST_PATH := "user://dev_snapshot_latest.tres"
const _DEV_REPLAY_LATEST_PATH := "user://dev_replay_latest.tres"
const COMMAND_CARD_SCRIPT := preload("res://scripts/game/command_card.gd")
const PATHFINDING_SCRIPT := preload("res://scripts/resolver/pathfinding_system.gd")
const PENDING_NONE := ""
const PENDING_MOVE := "move"
const PENDING_MOVE_ONLY := "move_only"
const PENDING_TARGET := "target"
const PENDING_BUILD := "build"
const PENDING_GATHER := "gather"
const CONTEXT_NONE := "none"
const CONTEXT_MOVE_ONLY := "move_only"
const CONTEXT_TARGET_CHASE := "target_chase"
const CONTEXT_GATHER := "gather"
const CONTEXT_RALLY_MOVE := "rally_move"
const CONTEXT_RALLY_GATHER := "rally_gather"
const CONTEXT_INVALID := "invalid"
const HUD_MARGIN := 12.0
const HUD_WIDTH := 440.0
const HUD_HEIGHT := 720.0
const CAMERA_ZOOM_STEP := 1.15
const CAMERA_DRAG_THRESHOLD := 4.0

@export_file("*.tres") var scenario_path: String = DEFAULT_SCENARIO_PATH

var _renderer: MatchRenderer = null
var _loaded: LoadedScenario = null
var _tunables: Tunables = null
var _input: DevTurnInput = DEV_TURN_INPUT_SCRIPT.new() as DevTurnInput
var _hud_layer: CanvasLayer = null
var _active_label: Label = null
var _resources_label: Label = null
var _queue_label: Label = null
var _replay_label: Label = null
var _replay_turn_spin: SpinBox = null
var _status_label: Label = null
var _command_card: Control = null
var _pending_command: String = PENDING_NONE
var _pending_build_def_id: String = ""
var _is_panning_camera: bool = false
var _left_empty_drag_candidate: bool = false
var _left_empty_drag_moved: bool = false
var _left_empty_drag_start: Vector2 = Vector2.ZERO
var _show_all_friendly_action_previews: bool = false
var _replay: MatchReplay = MatchReplay.new()
var _checkpoints: Dictionary[int, SavedSession] = {}
var _replay_mode_active: bool = false
var _replay_cursor_turn: int = 0


func _ready() -> void:
	_build_hud()
	if _loaded == null:
		load_scenario_path(scenario_path)


func load_scenario_path(path: String) -> bool:
	_build_hud()
	var scenario: ScenarioDef = load(path) as ScenarioDef
	var registry: EntityRegistry = load(REGISTRY_PATH) as EntityRegistry
	_tunables = load(TUNABLES_PATH) as Tunables
	if scenario == null or registry == null or _tunables == null:
		push_error("DevPlayMode: missing scenario, registry, or tunables.")
		return false
	_loaded = ScenarioLoader.load(scenario, registry, _tunables)
	if _loaded == null:
		push_error("DevPlayMode: ScenarioLoader returned null.")
		return false
	_clear_pending_command()
	_input.set_queue_modifier_active(false)
	_ensure_renderer()
	if _renderer == null:
		return false
	_renderer.bind_state(_loaded.state, _loaded.registry)
	_renderer.set_perspective_player_id(_input.active_player_id())
	_renderer.focus_player_start(_input.active_player_id())
	_input.bind_context(_loaded.state, _loaded.registry)
	_input.clear_submissions()
	_start_replay_journal()
	_reset_context_cursor()
	_update_hud()
	return true


func current_state() -> MatchState:
	if _loaded == null:
		return null
	return _loaded.state


func renderer() -> MatchRenderer:
	return _renderer


func input_model() -> DevTurnInput:
	return _input


func command_card() -> Control:
	return _command_card


func replay_frame_count() -> int:
	return _replay.frames.size() if _replay != null else 0


func replay_checkpoint_count() -> int:
	return _checkpoints.size()


func replay_cursor_turn() -> int:
	return _replay_cursor_turn


func replay_mode_active() -> bool:
	return _replay_mode_active


func pending_command_kind() -> String:
	return _pending_command


func _reject_replay_edit() -> bool:
	_clear_pending_command()
	_update_hud("Replay is read-only. Use Restore Here to branch from this turn.")
	return false


func set_show_all_friendly_action_previews(enabled: bool) -> void:
	_show_all_friendly_action_previews = enabled
	_refresh_action_previews()


func set_active_player_id(player_id: int) -> void:
	if _replay_mode_active:
		_reject_replay_edit()
		return
	_input.set_active_player_id(player_id)
	_clear_pending_command()
	if _renderer != null:
		_renderer.set_perspective_player_id(player_id)
		_renderer.focus_player_start(player_id)
		_renderer.clear_input_highlights()
	_reset_context_cursor()
	_update_hud()


func select_entity_id(entity_id: int) -> bool:
	if _replay_mode_active:
		return _reject_replay_edit()
	var ok: bool = _input.select_entity(entity_id)
	if _renderer != null:
		_clear_build_placement_preview()
		if ok:
			_renderer.set_selected_entity_id(entity_id)
		else:
			_renderer.clear_input_highlights()
	if not ok:
		_reset_context_cursor()
	_update_hud()
	return ok


func issue_move_selected(tile: Vector2i, queue_requested: bool = false) -> bool:
	if _replay_mode_active:
		return _reject_replay_edit()
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_move(tile)
	_input.set_queue_modifier_active(false)
	_update_hud()
	return ok


func issue_move_only_selected(tile: Vector2i, queue_requested: bool = false) -> bool:
	if _replay_mode_active:
		return _reject_replay_edit()
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_move_only(tile)
	_input.set_queue_modifier_active(false)
	_update_hud()
	return ok


func issue_attack_selected(target_entity_id: int, queue_requested: bool = false) -> bool:
	if _replay_mode_active:
		return _reject_replay_edit()
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_attack(target_entity_id)
	_input.set_queue_modifier_active(false)
	_update_hud()
	return ok


func issue_attack_target_selected(target_entity_id: int) -> bool:
	if _replay_mode_active:
		return _reject_replay_edit()
	var ok: bool = _input.issue_attack_target(target_entity_id)
	_update_hud()
	return ok


func issue_target_chase_selected(target_entity_id: int, queue_requested: bool = false) -> bool:
	if _replay_mode_active:
		return _reject_replay_edit()
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_target_chase(target_entity_id)
	_input.set_queue_modifier_active(false)
	_update_hud()
	return ok


func issue_gather_selected(target_entity_id: int, queue_requested: bool = false) -> bool:
	if _replay_mode_active:
		return _reject_replay_edit()
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_gather(target_entity_id)
	_input.set_queue_modifier_active(false)
	_update_hud()
	return ok


func issue_rally_move_selected(tile: Vector2i) -> bool:
	if _replay_mode_active:
		return _reject_replay_edit()
	var ok: bool = _input.issue_rally_move(tile)
	_update_hud()
	return ok


func issue_rally_gather_selected(target_entity_id: int) -> bool:
	if _replay_mode_active:
		return _reject_replay_edit()
	var ok: bool = _input.issue_rally_gather(target_entity_id)
	_update_hud()
	return ok


func issue_halt_on_sight_selected(enabled: bool) -> bool:
	if _replay_mode_active:
		return _reject_replay_edit()
	var ok: bool = _input.issue_halt_on_sight_toggle(enabled)
	_update_hud()
	return ok


func issue_build_selected(def_id: String, tile: Vector2i, queue_requested: bool = false) -> bool:
	if _replay_mode_active:
		return _reject_replay_edit()
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_build(def_id, tile)
	_input.set_queue_modifier_active(false)
	_update_hud()
	return ok


func issue_train_selected(def_id: String) -> bool:
	if _replay_mode_active:
		return _reject_replay_edit()
	var ok: bool = _input.issue_train(def_id)
	_update_hud()
	return ok


func issue_research_selected(def_id: String) -> bool:
	if _replay_mode_active:
		return _reject_replay_edit()
	var ok: bool = _input.issue_research(def_id)
	_update_hud()
	return ok


func issue_ability_selected(ability_id: String) -> bool:
	if _replay_mode_active:
		return _reject_replay_edit()
	var ok: bool = _input.issue_ability(ability_id)
	_update_hud()
	return ok


func issue_repeat_train_selected(enabled: bool) -> bool:
	if _replay_mode_active:
		return _reject_replay_edit()
	var ok: bool = _input.issue_repeat_train_toggle(enabled)
	_update_hud()
	return ok


func issue_cancel_selected(cancel_index: int = -1) -> bool:
	if _replay_mode_active:
		return _reject_replay_edit()
	var ok: bool = _input.issue_cancel(cancel_index)
	_update_hud()
	return ok


func issue_context_at_tile(tile: Vector2i, queue_requested: bool = false) -> bool:
	if _replay_mode_active:
		return _reject_replay_edit()
	var context: Dictionary = context_action_at_tile(tile)
	var action: String = context.get("action", CONTEXT_NONE)
	if action == CONTEXT_MOVE_ONLY:
		return issue_move_only_selected(tile, queue_requested)
	if action == CONTEXT_TARGET_CHASE:
		return issue_target_chase_selected(context.get("target_entity_id", -1), queue_requested)
	if action == CONTEXT_GATHER:
		return issue_gather_selected(context.get("target_entity_id", -1), queue_requested)
	if action == CONTEXT_RALLY_MOVE:
		return issue_rally_move_selected(tile)
	if action == CONTEXT_RALLY_GATHER:
		return issue_rally_gather_selected(context.get("target_entity_id", -1))
	var message: String = context.get("message", "")
	if message != "":
		_update_hud(message)
	return false


func context_action_at_tile(tile: Vector2i) -> Dictionary:
	if _replay_mode_active:
		return _context_result(CONTEXT_NONE, Input.CURSOR_ARROW, "")
	if _pending_command != PENDING_NONE:
		return _context_result(CONTEXT_NONE, Input.CURSOR_ARROW, "")
	if _loaded == null or _loaded.state == null or _loaded.state.tile_grid == null:
		return _context_result(CONTEXT_NONE, Input.CURSOR_ARROW, "")
	if not _loaded.state.tile_grid.is_in_bounds(tile):
		return _context_result(CONTEXT_NONE, Input.CURSOR_ARROW, "")
	if _selected_entity() == null:
		return _context_result(CONTEXT_NONE, Input.CURSOR_ARROW, "")
	var target_id: int = _entity_id_at_tile(tile)
	if target_id >= 0:
		var target: Entity = _loaded.state.get_entity_by_id(target_id)
		if target == null:
			return _context_result(CONTEXT_INVALID, Input.CURSOR_FORBIDDEN, "Invalid target.")
		if _is_enemy_target(target):
			if _input.can_issue_target_chase():
				return _context_result(
					CONTEXT_TARGET_CHASE, Input.CURSOR_CROSS, "", {"target_entity_id": target_id}
				)
			return _context_result(
				CONTEXT_INVALID, Input.CURSOR_FORBIDDEN, "Selected entity cannot chase targets."
			)
		if _is_resource_context_target(target):
			if _selected_can_gather_from(target_id):
				return _context_result(
					CONTEXT_GATHER, Input.CURSOR_POINTING_HAND, "", {"target_entity_id": target_id}
				)
			if _selected_can_rally_gather_to(target_id):
				return _context_result(
					CONTEXT_RALLY_GATHER,
					Input.CURSOR_POINTING_HAND,
					"",
					{"target_entity_id": target_id}
				)
			return _context_result(
				CONTEXT_INVALID,
				Input.CURSOR_FORBIDDEN,
				"That resource target is not valid for the selected entity."
			)
		return _context_result(CONTEXT_INVALID, Input.CURSOR_FORBIDDEN, "Target tile is occupied.")
	if _input.can_issue_rally_move():
		return _context_result(CONTEXT_RALLY_MOVE, Input.CURSOR_MOVE, "")
	if _input.can_issue_move_only():
		return _context_result(CONTEXT_MOVE_ONLY, Input.CURSOR_MOVE, "")
	return _context_result(CONTEXT_INVALID, Input.CURSOR_FORBIDDEN, "Selected entity cannot move.")


func context_cursor_shape_at_tile(tile: Vector2i) -> int:
	var context: Dictionary = context_action_at_tile(tile)
	return context.get("cursor_shape", Input.CURSOR_ARROW)


func begin_move() -> void:
	if _replay_mode_active:
		_reject_replay_edit()
		return
	if not _input.can_issue_move():
		_update_hud("Select a movable unit before Attack and Move.")
		return
	_clear_build_placement_preview()
	_pending_command = PENDING_MOVE
	_pending_build_def_id = ""
	_reset_context_cursor()
	_update_hud("Click a target tile for Attack and Move.")


func begin_move_only() -> void:
	if _replay_mode_active:
		_reject_replay_edit()
		return
	if not _input.can_issue_move_only():
		_update_hud("Select a movable unit before MOVE ONLY.")
		return
	_clear_build_placement_preview()
	_pending_command = PENDING_MOVE_ONLY
	_pending_build_def_id = ""
	_reset_context_cursor()
	_update_hud("Click a target tile for MOVE ONLY. Unit will not shoot this turn.")


func begin_target() -> void:
	if _replay_mode_active:
		_reject_replay_edit()
		return
	if not _input.can_issue_attack_target():
		_update_hud("Select a combat unit before TARGET.")
		return
	_clear_build_placement_preview()
	_pending_command = PENDING_TARGET
	_pending_build_def_id = ""
	_reset_context_cursor()
	_update_hud("Click an enemy for TARGET.")


func begin_build(def_id: String) -> void:
	if _replay_mode_active:
		_reject_replay_edit()
		return
	_clear_build_placement_preview()
	if not _input.build_option_ids().has(def_id):
		_update_hud("Selected entity cannot BUILD %s." % def_id)
		return
	_pending_command = PENDING_BUILD
	_pending_build_def_id = def_id
	_reset_context_cursor()
	_update_hud("Click a placement tile for BUILD %s." % def_id)


func confirm_pending_at_tile(tile: Vector2i, queue_requested: bool = false) -> bool:
	if _replay_mode_active:
		return _reject_replay_edit()
	if _pending_command == PENDING_MOVE:
		var move_ok: bool = issue_move_selected(tile, queue_requested)
		if move_ok:
			_clear_pending_command()
			_update_hud()
		return move_ok
	if _pending_command == PENDING_MOVE_ONLY:
		var move_only_ok: bool = issue_move_only_selected(tile, queue_requested)
		if move_only_ok:
			_clear_pending_command()
			_update_hud()
		return move_only_ok
	if _pending_command == PENDING_TARGET:
		var target_id: int = (
			_renderer.entity_id_at_tile(tile)
			if _renderer != null
			else _loaded.state.tile_grid.entity_at(tile)
		)
		var target: Entity = _loaded.state.get_entity_by_id(target_id)
		if (
			target == null
			or target.owner_player_id < 0
			or target.owner_player_id == _input.active_player_id()
		):
			_update_hud("Click an enemy to set TARGET.")
			return false
		var target_ok: bool = issue_attack_target_selected(target_id)
		if target_ok:
			_clear_pending_command()
			_update_hud()
		return target_ok
	if _pending_command == PENDING_BUILD:
		var build_ok: bool = issue_build_selected(_pending_build_def_id, tile, queue_requested)
		if build_ok:
			_clear_pending_command()
			_update_hud()
		return build_ok
	if _pending_command == PENDING_GATHER:
		if _loaded == null or _loaded.state == null:
			return false
		var target_id: int = (
			_renderer.entity_id_at_tile(tile)
			if _renderer != null
			else _loaded.state.tile_grid.entity_at(tile)
		)
		if not _selected_can_gather_from(target_id):
			_update_hud("Click a mineral patch or refinery to GATHER.")
			return false
		var gather_ok: bool = issue_gather_selected(target_id, queue_requested)
		if gather_ok:
			_clear_pending_command()
			_update_hud()
		return gather_ok
	return false


func cancel_pending_command() -> void:
	if _replay_mode_active:
		_reject_replay_edit()
		return
	if _pending_command == PENDING_NONE:
		return
	_clear_pending_command()
	_reset_context_cursor()
	_update_hud("Pending command cancelled.")


func _emit_dev_resolve_profile(lines: Array[String]) -> void:
	for line in lines:
		print(line)
	var file := FileAccess.open(_DEV_RESOLVE_PROFILE_LOG_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines) + "\n")


func pending_order_count(player_id: int) -> int:
	return _input.queued_order_count(player_id)


func save_latest_snapshot() -> bool:
	return save_snapshot_to_path(_DEV_SNAPSHOT_LATEST_PATH)


func load_latest_snapshot() -> bool:
	return load_snapshot_from_path(_DEV_SNAPSHOT_LATEST_PATH)


func save_snapshot_to_path(path: String) -> bool:
	if _loaded == null or _loaded.state == null or _loaded.registry == null:
		_update_hud("No match loaded to snapshot.")
		return false
	var err: Error = MatchSaver.save(
		_loaded.state, _loaded.registry, path, _input.create_snapshot()
	)
	if err != OK:
		_update_hud("Snapshot save failed: %d." % err)
		return false
	_update_hud("Saved snapshot to %s." % path)
	return true


func load_snapshot_from_path(path: String) -> bool:
	var session: SavedSession = MatchSaver.load_from(path)
	if session == null:
		_update_hud("Snapshot load failed: %s." % path)
		return false
	if not _bind_session(session, false, "Loaded snapshot turn %d." % session.state.turn_index):
		return false
	_start_replay_journal()
	_update_hud("Loaded snapshot turn %d." % session.state.turn_index)
	return true


func save_latest_replay() -> bool:
	return save_replay_to_path(_DEV_REPLAY_LATEST_PATH)


func load_latest_replay() -> bool:
	return load_replay_from_path(_DEV_REPLAY_LATEST_PATH)


func save_replay_to_path(path: String) -> bool:
	if _replay == null or _replay.initial_session == null:
		_update_hud("No replay journal to save.")
		return false
	var err: Error = ResourceSaver.save(_replay, path)
	if err != OK:
		_update_hud("Replay save failed: %d." % err)
		return false
	_update_hud("Saved replay to %s." % path)
	return true


func load_replay_from_path(path: String) -> bool:
	var resource: Resource = ResourceLoader.load(
		path, "MatchReplay", ResourceLoader.CACHE_MODE_IGNORE
	)
	var loaded_replay := resource as MatchReplay
	if loaded_replay == null:
		_update_hud("Replay load failed: %s." % path)
		return false
	if loaded_replay.format_version != MatchReplay.CURRENT_FORMAT_VERSION:
		_update_hud("Replay format %d is not supported." % loaded_replay.format_version)
		return false
	if loaded_replay.initial_session == null:
		_update_hud("Replay has no initial session.")
		return false
	var candidate: MatchReplay = loaded_replay.clone()
	if not _ensure_tunables():
		return false
	var rebuilt_checkpoints: Dictionary[int, SavedSession] = _checkpoints_for_replay(candidate)
	if rebuilt_checkpoints.is_empty():
		_update_hud("Replay checkpoint rebuild failed.")
		return false
	_replay = candidate
	_checkpoints = rebuilt_checkpoints
	return replay_latest()


func replay_start() -> bool:
	return replay_jump_to_turn(_replay_initial_turn())


func replay_previous() -> bool:
	if _loaded == null or _loaded.state == null:
		return false
	return replay_jump_to_turn(_loaded.state.turn_index - 1)


func replay_next() -> bool:
	if _loaded == null or _loaded.state == null or _loaded.registry == null:
		return false
	if not _ensure_tunables():
		return false
	var turn_before: int = _loaded.state.turn_index
	var frame: ReplayTurnFrame = _frame_for_turn(turn_before)
	if frame == null:
		_update_hud("Replay is already at the latest turn.")
		return false
	var result: ResolveResult = Resolver.resolve(
		_loaded.state, frame.submit_a, frame.submit_b, _loaded.registry, _tunables
	)
	if result == null or result.new_state == null:
		_update_hud("Replay step failed at turn %d." % turn_before)
		return false
	if result.new_state.turn_index <= turn_before:
		_update_hud("Replay step did not advance past turn %d." % turn_before)
		return false
	_loaded.state = result.new_state
	_clear_pending_command()
	if _renderer != null:
		_renderer.render_step(result.new_state, result.events)
		_renderer.clear_input_highlights()
	_input.bind_context(_loaded.state, _loaded.registry)
	_input.clear_submissions(false, false)
	_input.apply_resolve_events(result.events)
	_input.queue_rally_orders_for_train_completed(result.events)
	_input.queue_move_assists_for_next_turn()
	_input.promote_future_orders_for_next_turn()
	_replay_mode_active = true
	_replay_cursor_turn = _loaded.state.turn_index
	_record_checkpoint(_loaded.state.turn_index)
	_reset_context_cursor()
	_update_hud("Replay stepped to turn %d." % _loaded.state.turn_index)
	return true


func replay_latest() -> bool:
	return replay_jump_to_turn(_latest_checkpoint_turn())


func replay_jump_to_turn(turn_index: int) -> bool:
	if not _checkpoints.has(turn_index):
		_update_hud("Replay checkpoint %d is not available." % turn_index)
		return false
	var session: SavedSession = _checkpoints[turn_index]
	return _bind_session(session, true, "Replay jumped to turn %d." % turn_index)


func restore_replay_here() -> bool:
	if _loaded == null or _loaded.state == null:
		return false
	var turn_index: int = _loaded.state.turn_index
	if not _checkpoints.has(turn_index):
		_record_checkpoint(turn_index)
	var session: SavedSession = _checkpoints[turn_index]
	if not _bind_session(session, false, "Restored playable timeline at turn %d." % turn_index):
		return false
	_truncate_replay_after_turn(turn_index)
	_record_checkpoint(turn_index)
	return true


func resolve_turn() -> bool:
	if _loaded == null or _loaded.state == null or _loaded.registry == null or _tunables == null:
		return false
	if _replay_mode_active:
		_update_hud("Use Restore Here before resolving from a replay checkpoint.")
		return false
	var profile_enabled := FileAccess.file_exists(_RESOLVE_PROFILE_FLAG_PATH)
	var profile_lines: Array[String] = []
	var profile_total_start := Time.get_ticks_usec()
	var profile_step := profile_total_start
	if profile_enabled:
		profile_lines.append(
			"[dev_resolve_profile] captured_at=%s" % Time.get_datetime_string_from_system()
		)
		profile_lines.append(
			"[dev_resolve_profile] before entities=%d" % _loaded.state.entities.size()
		)
	var turn_before: int = _loaded.state.turn_index
	var submit_a: SubmitTurn = _input.submit_for_player(0)
	var submit_b: SubmitTurn = _input.submit_for_player(1)
	var journal_submit_a: SubmitTurn = submit_a.clone()
	var journal_submit_b: SubmitTurn = submit_b.clone()
	if profile_enabled:
		(
			profile_lines
			. append(
				(
					"[dev_resolve_profile] submit_inputs=%.3fms orders_a=%d orders_b=%d"
					% [
						float(Time.get_ticks_usec() - profile_step) / 1000.0,
						submit_a.orders.size(),
						submit_b.orders.size(),
					]
				)
			)
		)
		profile_step = Time.get_ticks_usec()
	var result: ResolveResult = Resolver.resolve(
		_loaded.state, submit_a, submit_b, _loaded.registry, _tunables
	)
	if profile_enabled:
		profile_lines.append(
			(
				"[dev_resolve_profile] resolver=%.3fms"
				% (float(Time.get_ticks_usec() - profile_step) / 1000.0)
			)
		)
		profile_step = Time.get_ticks_usec()
	if result == null or result.new_state == null:
		if profile_enabled:
			profile_lines.append("[dev_resolve_profile] failed_result=true")
			_emit_dev_resolve_profile(profile_lines)
		return false
	_truncate_replay_after_turn(turn_before)
	_append_replay_frame(turn_before, journal_submit_a, journal_submit_b)
	_loaded.state = result.new_state
	_clear_pending_command()
	if _renderer != null:
		_renderer.render_step(result.new_state, result.events)
		if profile_enabled:
			profile_lines.append(
				(
					"[dev_resolve_profile] renderer.render_step=%.3fms events=%d"
					% [float(Time.get_ticks_usec() - profile_step) / 1000.0, result.events.size()]
				)
			)
			profile_step = Time.get_ticks_usec()
		_renderer.clear_input_highlights()
		if profile_enabled:
			profile_lines.append(
				(
					"[dev_resolve_profile] renderer.clear_input_highlights=%.3fms"
					% (float(Time.get_ticks_usec() - profile_step) / 1000.0)
				)
			)
			profile_step = Time.get_ticks_usec()
	_input.bind_context(_loaded.state, _loaded.registry)
	if profile_enabled:
		profile_lines.append(
			(
				"[dev_resolve_profile] input.bind_context=%.3fms"
				% (float(Time.get_ticks_usec() - profile_step) / 1000.0)
			)
		)
		profile_step = Time.get_ticks_usec()
	_input.clear_submissions(false, false)
	_input.apply_resolve_events(result.events)
	_input.queue_rally_orders_for_train_completed(result.events)
	_input.queue_move_assists_for_next_turn()
	_input.promote_future_orders_for_next_turn()
	_record_checkpoint(_loaded.state.turn_index)
	_replay_cursor_turn = _loaded.state.turn_index
	if profile_enabled:
		profile_lines.append(
			(
				"[dev_resolve_profile] input.post_resolve=%.3fms"
				% (float(Time.get_ticks_usec() - profile_step) / 1000.0)
			)
		)
		profile_step = Time.get_ticks_usec()
	_reset_context_cursor()
	_update_hud("Resolved turn %d." % _loaded.state.turn_index)
	if profile_enabled:
		profile_lines.append(
			(
				"[dev_resolve_profile] hud=%.3fms"
				% (float(Time.get_ticks_usec() - profile_step) / 1000.0)
			)
		)
		(
			profile_lines
			. append(
				(
					"[dev_resolve_profile] total=%.3fms after_entities=%d"
					% [
						float(Time.get_ticks_usec() - profile_total_start) / 1000.0,
						_loaded.state.entities.size(),
					]
				)
			)
		)
		_emit_dev_resolve_profile(profile_lines)
	return true


func _unhandled_input(event: InputEvent) -> void:
	if _renderer == null or _loaded == null:
		return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if (
			_left_empty_drag_candidate
			and (
				_left_empty_drag_moved
				or (
					motion.button_mask & MOUSE_BUTTON_MASK_LEFT != 0
					and motion.position.distance_to(_left_empty_drag_start) >= CAMERA_DRAG_THRESHOLD
				)
			)
		):
			_left_empty_drag_moved = true
			_is_panning_camera = true
		if _is_panning_camera:
			_renderer.pan_camera_by_screen_delta(motion.relative)
			return
		var hover_tile: Vector2i = _renderer.world_to_tile(_event_world_position(motion))
		_set_hover_tile(hover_tile)
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_renderer.zoom_camera(CAMERA_ZOOM_STEP)
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_renderer.zoom_camera(1.0 / CAMERA_ZOOM_STEP)
			return
		if button.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning_camera = button.pressed
			return
		if _replay_mode_active:
			return
		if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
			if _left_empty_drag_candidate:
				if not _left_empty_drag_moved:
					_input.clear_selection()
					_renderer.clear_input_highlights()
					_reset_context_cursor()
					_update_hud("Selection cleared.")
				_reset_left_empty_drag()
				return
			_reset_left_empty_drag()
		if not button.pressed:
			return
		var tile: Vector2i = _renderer.world_to_tile(_event_world_position(button))
		var entity_id: int = _renderer.entity_id_at_tile(tile)
		if button.button_index == MOUSE_BUTTON_LEFT:
			if _pending_command != PENDING_NONE:
				confirm_pending_at_tile(tile, button.shift_pressed)
				return
			if entity_id >= 0:
				select_entity_id(entity_id)
			else:
				_left_empty_drag_candidate = true
				_left_empty_drag_moved = false
				_left_empty_drag_start = button.position
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			if _pending_command != PENDING_NONE:
				cancel_pending_command()
				return
			issue_context_at_tile(tile, button.shift_pressed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		_reset_context_cursor()


func _ensure_renderer() -> void:
	if _renderer != null:
		return
	var packed: PackedScene = load(MATCH_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("DevPlayMode: failed to load %s" % MATCH_SCENE_PATH)
		return
	_renderer = packed.instantiate() as MatchRenderer
	if _renderer == null:
		push_error("DevPlayMode: match scene root is not a MatchRenderer.")
		return
	add_child(_renderer)


func _ensure_tunables() -> bool:
	if _tunables != null:
		return true
	_tunables = load(TUNABLES_PATH) as Tunables
	if _tunables == null:
		push_error("DevPlayMode: missing tunables.")
		_update_hud("Missing tunables.")
		return false
	return true


func _start_replay_journal() -> void:
	if _loaded == null or _loaded.state == null or _loaded.registry == null:
		return
	_replay = MatchReplay.new()
	_replay.initial_session = _make_session(
		_loaded.state, _loaded.registry, _input.create_snapshot()
	)
	_replay.frames = []
	_checkpoints.clear()
	_record_checkpoint(_loaded.state.turn_index)
	_replay_mode_active = false
	_replay_cursor_turn = _loaded.state.turn_index


func _make_session(
	state: MatchState, registry: EntityRegistry, input_snapshot: DevInputSnapshot
) -> SavedSession:
	var session := SavedSession.new()
	session.state = state.clone() if state != null else null
	session.registry = registry
	session.input_snapshot = input_snapshot.clone() if input_snapshot != null else null
	return session


func _record_checkpoint(turn_index: int) -> void:
	if _loaded == null or _loaded.state == null or _loaded.registry == null:
		return
	_checkpoints[turn_index] = _make_session(
		_loaded.state, _loaded.registry, _input.create_snapshot()
	)


func _bind_session(session: SavedSession, replay_mode: bool, status_message: String) -> bool:
	if session == null or session.state == null or session.registry == null:
		_update_hud("Cannot bind an incomplete session.")
		return false
	if _loaded == null:
		_loaded = LoadedScenario.new()
	_loaded.state = session.state.clone()
	_loaded.registry = session.registry
	_ensure_renderer()
	if _renderer != null:
		_renderer.bind_state(_loaded.state, _loaded.registry)
		_renderer.set_perspective_player_id(_input.active_player_id())
		_renderer.clear_input_highlights()
	_input.restore_snapshot(session.input_snapshot, _loaded.state, _loaded.registry)
	if _renderer != null:
		_renderer.set_perspective_player_id(_input.active_player_id())
		_renderer.set_selected_entity_id(_input.selected_entity_id())
	_clear_pending_command()
	_replay_mode_active = replay_mode
	_replay_cursor_turn = _loaded.state.turn_index
	_reset_context_cursor()
	_update_hud(status_message)
	return true


func _append_replay_frame(turn_index: int, submit_a: SubmitTurn, submit_b: SubmitTurn) -> void:
	if _replay == null:
		_replay = MatchReplay.new()
	if _replay.initial_session == null:
		_replay.initial_session = _make_session(
			_loaded.state, _loaded.registry, _input.create_snapshot()
		)
	var frame := ReplayTurnFrame.new()
	frame.turn_index = turn_index
	frame.submit_a = submit_a.clone() if submit_a != null else SubmitTurn.new()
	frame.submit_b = submit_b.clone() if submit_b != null else SubmitTurn.new()
	_replay.frames.append(frame)


func _truncate_replay_after_turn(turn_index: int) -> void:
	if _replay != null:
		for i in range(_replay.frames.size() - 1, -1, -1):
			var frame: ReplayTurnFrame = _replay.frames[i]
			if frame == null or frame.turn_index >= turn_index:
				_replay.frames.remove_at(i)
	for checkpoint_turn in _checkpoints.keys():
		var key: int = checkpoint_turn
		if key > turn_index:
			_checkpoints.erase(key)


func _checkpoints_for_replay(replay: MatchReplay) -> Dictionary[int, SavedSession]:
	var checkpoints: Dictionary[int, SavedSession] = {}
	if replay == null or replay.initial_session == null:
		return checkpoints
	var initial: SavedSession = replay.initial_session
	if initial.state == null or initial.registry == null:
		return checkpoints
	var state: MatchState = initial.state.clone()
	var registry: EntityRegistry = initial.registry
	var replay_input: DevTurnInput = DEV_TURN_INPUT_SCRIPT.new() as DevTurnInput
	replay_input.restore_snapshot(initial.input_snapshot, state, registry)
	checkpoints[state.turn_index] = _make_session(state, registry, replay_input.create_snapshot())
	for item in replay.frames:
		var frame: ReplayTurnFrame = item
		if frame == null or frame.turn_index != state.turn_index:
			return {}
		var result: ResolveResult = Resolver.resolve(
			state, frame.submit_a, frame.submit_b, registry, _tunables
		)
		if result == null or result.new_state == null:
			return {}
		state = result.new_state
		replay_input.bind_context(state, registry)
		replay_input.clear_submissions(false, false)
		replay_input.apply_resolve_events(result.events)
		replay_input.queue_rally_orders_for_train_completed(result.events)
		replay_input.queue_move_assists_for_next_turn()
		replay_input.promote_future_orders_for_next_turn()
		checkpoints[state.turn_index] = _make_session(
			state, registry, replay_input.create_snapshot()
		)
	return checkpoints


func _frame_for_turn(turn_index: int) -> ReplayTurnFrame:
	if _replay == null:
		return null
	for item in _replay.frames:
		var frame: ReplayTurnFrame = item
		if frame != null and frame.turn_index == turn_index:
			return frame
	return null


func _replay_initial_turn() -> int:
	if (
		_replay != null
		and _replay.initial_session != null
		and _replay.initial_session.state != null
	):
		return _replay.initial_session.state.turn_index
	return 0


func _latest_checkpoint_turn() -> int:
	var latest: int = _replay_initial_turn()
	for checkpoint_turn in _checkpoints.keys():
		latest = maxi(latest, int(checkpoint_turn))
	return latest


func _event_world_position(event: InputEventMouse) -> Vector2:
	if _renderer == null:
		return event.position
	if _renderer.get_viewport() == null:
		return event.position
	return _renderer.get_global_mouse_position()


func _reset_left_empty_drag() -> void:
	_left_empty_drag_candidate = false
	_left_empty_drag_moved = false
	_left_empty_drag_start = Vector2.ZERO
	_is_panning_camera = false


func _set_hover_tile(tile: Vector2i) -> void:
	if _renderer == null:
		return
	_renderer.set_hover_tile(tile)
	if _pending_command == PENDING_BUILD:
		_refresh_build_placement_preview(tile)
		_reset_context_cursor()
	else:
		_clear_build_placement_preview()
		_update_context_cursor_for_tile(tile)


func _build_hud() -> void:
	if _hud_layer != null:
		return
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "DevHUD"
	add_child(_hud_layer)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -HUD_WIDTH - HUD_MARGIN
	panel.offset_top = HUD_MARGIN
	panel.offset_right = -HUD_MARGIN
	panel.offset_bottom = HUD_MARGIN + HUD_HEIGHT
	_hud_layer.add_child(panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.name = "Root"
	panel.add_child(root)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.name = "Buttons"
	root.add_child(buttons)

	var p0_button: Button = _button("P0")
	p0_button.pressed.connect(func() -> void: set_active_player_id(0))
	buttons.add_child(p0_button)

	var p1_button: Button = _button("P1")
	p1_button.pressed.connect(func() -> void: set_active_player_id(1))
	buttons.add_child(p1_button)

	var resolve_button: Button = _button("Resolve")
	resolve_button.pressed.connect(resolve_turn)
	buttons.add_child(resolve_button)

	var clear_button: Button = _button("Clear")
	clear_button.pressed.connect(_clear_queues_from_hud)
	buttons.add_child(clear_button)

	var surrender_button: Button = _button("Surrender")
	surrender_button.pressed.connect(_surrender_from_hud)
	buttons.add_child(surrender_button)

	var snapshot_buttons: HBoxContainer = HBoxContainer.new()
	snapshot_buttons.name = "SnapshotButtons"
	root.add_child(snapshot_buttons)

	var save_snapshot_button: Button = _button("Save Snap")
	save_snapshot_button.pressed.connect(save_latest_snapshot)
	snapshot_buttons.add_child(save_snapshot_button)

	var load_snapshot_button: Button = _button("Load Snap")
	load_snapshot_button.pressed.connect(load_latest_snapshot)
	snapshot_buttons.add_child(load_snapshot_button)

	var save_replay_button: Button = _button("Save Replay")
	save_replay_button.pressed.connect(save_latest_replay)
	snapshot_buttons.add_child(save_replay_button)

	var load_replay_button: Button = _button("Load Replay")
	load_replay_button.pressed.connect(load_latest_replay)
	snapshot_buttons.add_child(load_replay_button)

	var replay_buttons: HBoxContainer = HBoxContainer.new()
	replay_buttons.name = "ReplayButtons"
	root.add_child(replay_buttons)

	var replay_start_button: Button = _button("Start")
	replay_start_button.pressed.connect(replay_start)
	replay_buttons.add_child(replay_start_button)

	var replay_prev_button: Button = _button("Prev")
	replay_prev_button.pressed.connect(replay_previous)
	replay_buttons.add_child(replay_prev_button)

	var replay_next_button: Button = _button("Next")
	replay_next_button.pressed.connect(replay_next)
	replay_buttons.add_child(replay_next_button)

	var replay_latest_button: Button = _button("Latest")
	replay_latest_button.pressed.connect(replay_latest)
	replay_buttons.add_child(replay_latest_button)

	var restore_button: Button = _button("Restore Here")
	restore_button.pressed.connect(restore_replay_here)
	replay_buttons.add_child(restore_button)

	var replay_jump: HBoxContainer = HBoxContainer.new()
	replay_jump.name = "ReplayJump"
	root.add_child(replay_jump)

	var replay_turn_label := Label.new()
	replay_turn_label.text = "Turn"
	_style_label(replay_turn_label)
	replay_jump.add_child(replay_turn_label)

	_replay_turn_spin = SpinBox.new()
	_replay_turn_spin.name = "ReplayTurn"
	_replay_turn_spin.min_value = 0.0
	_replay_turn_spin.max_value = 0.0
	_replay_turn_spin.step = 1.0
	_replay_turn_spin.custom_minimum_size = Vector2(88.0, 34.0)
	_replay_turn_spin.add_theme_font_size_override("font_size", 18)
	replay_jump.add_child(_replay_turn_spin)

	var replay_jump_button: Button = _button("Jump")
	replay_jump_button.pressed.connect(_jump_replay_from_hud)
	replay_jump.add_child(replay_jump_button)

	var preview_toggle := CheckBox.new()
	preview_toggle.name = "ShowFriendlyPreviews"
	preview_toggle.text = "Show all friendly orders"
	preview_toggle.button_pressed = _show_all_friendly_action_previews
	preview_toggle.add_theme_font_size_override("font_size", 18)
	preview_toggle.toggled.connect(set_show_all_friendly_action_previews)
	root.add_child(preview_toggle)

	_active_label = Label.new()
	_active_label.name = "ActivePlayer"
	_style_label(_active_label)
	root.add_child(_active_label)
	_resources_label = Label.new()
	_resources_label.name = "Resources"
	_style_label(_resources_label)
	root.add_child(_resources_label)
	_queue_label = Label.new()
	_queue_label.name = "QueuedOrders"
	_style_label(_queue_label)
	root.add_child(_queue_label)
	_replay_label = Label.new()
	_replay_label.name = "ReplayStatus"
	_style_label(_replay_label)
	root.add_child(_replay_label)
	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(_status_label)
	root.add_child(_status_label)

	_command_card = COMMAND_CARD_SCRIPT.new() as Control
	_command_card.connect("move_requested", Callable(self, "begin_move"))
	_command_card.connect("move_only_requested", Callable(self, "begin_move_only"))
	_command_card.connect("target_requested", Callable(self, "begin_target"))
	_command_card.connect("halt_on_sight_requested", Callable(self, "issue_halt_on_sight_selected"))
	_command_card.connect("gather_requested", Callable(self, "begin_gather"))
	_command_card.connect("build_requested", Callable(self, "begin_build"))
	_command_card.connect("train_requested", Callable(self, "issue_train_selected"))
	_command_card.connect("research_requested", Callable(self, "issue_research_selected"))
	_command_card.connect("ability_requested", Callable(self, "issue_ability_selected"))
	_command_card.connect("cancel_requested", Callable(self, "issue_cancel_selected"))
	_command_card.connect("repeat_train_toggled", Callable(self, "issue_repeat_train_selected"))
	root.add_child(_command_card)
	_update_hud()


func _button(text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 34.0)
	button.add_theme_font_size_override("font_size", 18)
	return button


func _style_label(label: Label) -> void:
	label.add_theme_font_size_override("font_size", 18)


func _clear_queues_from_hud() -> void:
	if _replay_mode_active:
		_reject_replay_edit()
		return
	_input.clear_submissions()
	_clear_pending_command()
	_update_hud()


func _surrender_from_hud() -> void:
	if _replay_mode_active:
		_reject_replay_edit()
		return
	_input.surrender_active_player()
	_update_hud()


func _jump_replay_from_hud() -> void:
	if _replay_turn_spin == null:
		return
	replay_jump_to_turn(int(_replay_turn_spin.value))


func _update_hud(override_status: String = "") -> void:
	if _active_label != null:
		_active_label.text = "Active player: P%d" % _input.active_player_id()
	if _resources_label != null:
		var player := (
			_loaded.state.get_player(_input.active_player_id()) if _loaded != null else null
		)
		if player == null:
			_resources_label.text = ""
		else:
			_resources_label.text = (
				"Minerals: %d  Gas: %d  Pop: %d/%d"
				% [player.minerals, player.gas, player.pop_used, player.pop_cap]
			)
	if _queue_label != null:
		_queue_label.visible = false
		_queue_label.text = ""
	if _replay_label != null:
		var replay_mode_text := "replay" if _replay_mode_active else "live"
		_replay_label.text = (
			"Timeline: %s  Turn: %d/%d  Frames: %d"
			% [
				replay_mode_text,
				_replay_cursor_turn,
				_latest_checkpoint_turn(),
				replay_frame_count(),
			]
		)
	if _replay_turn_spin != null:
		_replay_turn_spin.max_value = float(maxi(_latest_checkpoint_turn(), _replay_initial_turn()))
		_replay_turn_spin.value = float(_replay_cursor_turn)
	if _status_label != null:
		var status_message: String = _input.status_message()
		if override_status != "":
			_status_label.text = override_status
		elif (
			_pending_command != PENDING_NONE
			and status_message != ""
			and not status_message.begins_with("Queued")
			and not status_message.begins_with("Selected")
		):
			_status_label.text = status_message
		elif _pending_command == PENDING_MOVE:
			_status_label.text = "Pending Attack and Move: click target tile."
		elif _pending_command == PENDING_MOVE_ONLY:
			_status_label.text = "Pending MOVE ONLY: click target tile. Unit will not shoot."
		elif _pending_command == PENDING_TARGET:
			_status_label.text = "Pending TARGET: click an enemy."
		elif _pending_command == PENDING_BUILD:
			_status_label.text = "Pending BUILD %s: click placement tile." % _pending_build_def_id
		elif _pending_command == PENDING_GATHER:
			_status_label.text = "Pending GATHER: click a mineral patch or refinery."
		else:
			_status_label.text = status_message
	_refresh_command_card()
	_refresh_action_previews()


func _context_result(
	action: String, cursor_shape: int, message: String, extra: Dictionary = {}
) -> Dictionary:
	var out: Dictionary = {"action": action, "cursor_shape": cursor_shape, "message": message}
	for key in extra:
		out[key] = extra[key]
	return out


func _update_context_cursor_for_tile(tile: Vector2i) -> void:
	if _pending_command != PENDING_NONE:
		_reset_context_cursor()
		return
	var shape: int = context_cursor_shape_at_tile(tile)
	Input.set_default_cursor_shape(shape)


func _reset_context_cursor() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _selected_entity() -> Entity:
	if _loaded == null or _loaded.state == null:
		return null
	var entity_id: int = _input.selected_entity_id()
	if entity_id < 0:
		return null
	return _loaded.state.get_entity_by_id(entity_id)


func _entity_id_at_tile(tile: Vector2i) -> int:
	if _loaded == null or _loaded.state == null or _loaded.state.tile_grid == null:
		return -1
	if not _loaded.state.tile_grid.is_in_bounds(tile):
		return -1
	if _renderer != null:
		return _renderer.entity_id_at_tile(tile)
	return _loaded.state.tile_grid.entity_at(tile)


func _is_enemy_target(entity: Entity) -> bool:
	return (
		entity != null
		and entity.current_hp > 0
		and entity.owner_player_id >= 0
		and entity.owner_player_id != _input.active_player_id()
	)


func _selected_can_gather_from(target_entity_id: int) -> bool:
	if not _input.can_issue_gather():
		return false
	return _selected_can_gather_target_valid(target_entity_id)


func _selected_can_rally_gather_to(target_entity_id: int) -> bool:
	if not _input.can_issue_rally_gather():
		return false
	return _selected_can_gather_target_valid(target_entity_id)


func _selected_can_gather_target_valid(target_entity_id: int) -> bool:
	var actor: Entity = _selected_entity()
	if actor == null:
		return false
	var target: Entity = _loaded.state.get_entity_by_id(target_entity_id)
	if not _is_resource_context_target(target):
		return false
	return (
		GatherSystem.resolve_source_for_worker(
			_loaded.state, _loaded.registry, target_entity_id, actor.owner_player_id
		)
		!= null
	)


func _is_resource_context_target(entity: Entity) -> bool:
	if entity == null or _loaded == null or _loaded.registry == null:
		return false
	var def_id: String = entity.current_def_id if entity.current_def_id != "" else entity.def_id
	var def: EntityDef = _loaded.registry.get_by_id(def_id)
	if def == null:
		return false
	return def.resource_source != null or def.tags.has("refinery") or def.tags.has("extractor")


func _is_gather_target(entity: Entity) -> bool:
	return _is_resource_context_target(entity)


func _clear_pending_command() -> void:
	_pending_command = PENDING_NONE
	_pending_build_def_id = ""
	_clear_build_placement_preview()
	_reset_context_cursor()


func begin_gather() -> void:
	if _replay_mode_active:
		_reject_replay_edit()
		return
	if not _input.can_issue_gather():
		_update_hud("Select a worker before GATHER.")
		return
	_clear_build_placement_preview()
	_pending_command = PENDING_GATHER
	_pending_build_def_id = ""
	_reset_context_cursor()
	_update_hud("Click a mineral patch or refinery to GATHER.")


func _refresh_build_placement_preview(tile: Vector2i) -> void:
	if _renderer == null or not _renderer.has_method("set_build_placement_preview"):
		return
	if _pending_command != PENDING_BUILD or _pending_build_def_id == "":
		_clear_build_placement_preview()
		return
	var preview: Dictionary = _input.build_placement_preview(_pending_build_def_id, tile)
	_renderer.call("set_build_placement_preview", preview)


func _clear_build_placement_preview() -> void:
	if _renderer == null or not _renderer.has_method("clear_build_placement_preview"):
		return
	_renderer.call("clear_build_placement_preview")


func _refresh_command_card() -> void:
	if _command_card == null:
		return
	if _replay_mode_active:
		var empty_options: Array[Dictionary] = []
		_command_card.call(
			"set_command_state",
			"Replay",
			false,
			false,
			false,
			false,
			false,
			false,
			empty_options,
			empty_options,
			empty_options,
			empty_options,
			false,
			false,
			false
		)
		return
	_command_card.call(
		"set_command_state",
		_input.selected_entity_label(),
		_input.can_issue_move(),
		_input.can_issue_move_only(),
		_input.can_issue_attack_target(),
		_input.can_issue_halt_on_sight_toggle(),
		_input.can_issue_gather(),
		_input.selected_halt_on_sight(),
		_build_options(_input.build_option_ids()),
		_entity_options(_input.train_option_ids()),
		_research_options(_input.research_option_ids()),
		_ability_options(_input.ability_option_ids()),
		_input.can_issue_cancel(),
		_input.can_issue_repeat_train_toggle(),
		_input.selected_repeat_train_enabled()
	)


func _refresh_action_previews() -> void:
	if _renderer == null or not _renderer.has_method("set_action_previews"):
		return
	var previews: Array[Dictionary] = []
	var selected_id: int = _input.selected_entity_id()
	previews.append_array(_previews_for_entity(selected_id))
	if _show_all_friendly_action_previews:
		if _loaded == null or _loaded.state == null:
			_renderer.call("set_action_previews", previews)
			return
		var active_player_id: int = _input.active_player_id()
		var seen: Dictionary[int, bool] = {}
		if selected_id >= 0:
			seen[selected_id] = true
		for entity in _loaded.state.entities_sorted_by_id():
			if entity == null or entity.owner_player_id != active_player_id or seen.has(entity.id):
				continue
			var entity_previews: Array[Dictionary] = _previews_for_entity(entity.id)
			if entity_previews.is_empty():
				continue
			previews.append_array(entity_previews)
			seen[entity.id] = true
	_renderer.call("set_action_previews", previews)


func _previews_for_entity(entity_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if entity_id < 0 or _loaded == null or _loaded.state == null:
		return out
	var sequence_index: int = 1
	var has_planned_tile: bool = false
	var planned_tile: Vector2i = Vector2i.ZERO
	for queued in _queued_orders_for_entity(entity_id):
		var queued_preview: Dictionary = _preview_for_order(queued, planned_tile, has_planned_tile)
		if not queued_preview.is_empty():
			queued_preview["sequence_index"] = sequence_index
			queued_preview["future"] = false
			out.append(queued_preview)
			if _preview_keeps_planned_tile(queued_preview, has_planned_tile):
				planned_tile = _preview_planned_tile_value(queued_preview, planned_tile)
				has_planned_tile = true
			sequence_index += 1
	for future in _future_orders_for_entity(entity_id):
		var future_preview: Dictionary = _preview_for_order(future, planned_tile, has_planned_tile)
		if not future_preview.is_empty():
			future_preview["sequence_index"] = sequence_index
			future_preview["future"] = true
			out.append(future_preview)
			if _preview_keeps_planned_tile(future_preview, has_planned_tile):
				planned_tile = _preview_planned_tile_value(future_preview, planned_tile)
				has_planned_tile = true
			sequence_index += 1
	var rally_preview: Dictionary = _rally_preview_for_entity(entity_id)
	if not rally_preview.is_empty():
		out.append(rally_preview)
	if not out.is_empty():
		return out
	var entity: Entity = _loaded.state.get_entity_by_id(entity_id)
	if entity == null:
		return out
	if out.is_empty():
		var shot_target_id: int = _attack_target_for_entity(entity.id)
		if shot_target_id >= 0:
			out.append(
				{"entity_id": entity.id, "kind": "Idle + Shoot", "target_entity_id": shot_target_id}
			)
		elif _will_halt_on_sight(entity.id):
			var visible_enemy_id := _visible_enemy_for_entity(entity)
			out.append(
				{"entity_id": entity.id, "kind": "Halted", "target_entity_id": visible_enemy_id}
			)
	if entity.focus_target_entity_id >= 0:
		(
			out
			. append(
				{
					"entity_id": entity.id,
					"kind": "Target",
					"target_entity_id": entity.focus_target_entity_id,
				}
			)
		)
	if (
		entity.gather_state != null
		and entity.gather_state.phase != GatherState.Phase.IDLE
		and entity.gather_state.assigned_source_entity_id >= 0
	):
		(
			out
			. append(
				{
					"entity_id": entity.id,
					"kind": "Gather",
					"target_entity_id": entity.gather_state.assigned_source_entity_id,
				}
			)
		)
	return out


func _rally_preview_for_entity(entity_id: int) -> Dictionary:
	if entity_id < 0 or _loaded == null or _loaded.state == null:
		return {}
	var entity: Entity = _loaded.state.get_entity_by_id(entity_id)
	if entity == null or entity.production_state == null:
		return {}
	var mode: String = entity.production_state.rally_mode
	if mode == ProductionState.RALLY_MODE_MOVE:
		return {
			"entity_id": entity.id,
			"kind": "Rally",
			"target_tile": entity.production_state.rally_target_tile,
		}
	if mode == ProductionState.RALLY_MODE_GATHER:
		return {
			"entity_id": entity.id,
			"kind": "Rally Gather",
			"target_entity_id": entity.production_state.rally_target_entity_id,
		}
	return {}


func _queued_orders_for_entity(entity_id: int) -> Array[EntityOrder]:
	var out: Array[EntityOrder] = []
	var submit: SubmitTurn = _input.submit_for_player(_input.active_player_id())
	for order in submit.orders:
		if order != null and order.entity_id == entity_id:
			out.append(order)
	return out


func _future_orders_for_entity(entity_id: int) -> Array[EntityOrder]:
	if _input == null or not _input.has_method("future_orders_for_entity"):
		var empty: Array[EntityOrder] = []
		return empty
	return _input.future_orders_for_entity(entity_id)


func _preview_for_order(
	order: EntityOrder, start_tile: Vector2i = Vector2i.ZERO, has_start_tile: bool = false
) -> Dictionary:
	if order == null:
		return {}
	var preview: Dictionary = {}
	match order.type:
		EntityOrder.Type.MOVE:
			var kind: String = "Attack and Move"
			if _will_halt_on_sight(order.entity_id) and order.target_priority_chain.is_empty():
				kind = (
					"Shoot + Hold" if _attack_target_for_entity(order.entity_id) >= 0 else "Halted"
				)
				preview = _halted_move_preview(order.entity_id, kind)
			elif _attack_target_for_entity(order.entity_id) >= 0:
				kind = "Shoot + Move"
				preview = _move_preview(order, kind, start_tile, has_start_tile)
			else:
				preview = _move_preview(order, kind, start_tile, has_start_tile)
		EntityOrder.Type.MOVE_ONLY:
			preview = _move_preview(order, "Move Only", start_tile, has_start_tile)
		EntityOrder.Type.ATTACK:
			var target_id := -1
			if not order.target_priority_chain.is_empty():
				target_id = order.target_priority_chain[0]
			preview = {
				"entity_id": order.entity_id, "kind": "Target", "target_entity_id": target_id
			}
		EntityOrder.Type.GATHER:
			preview = _gather_preview(order, start_tile, has_start_tile)
		EntityOrder.Type.BUILD:
			preview = _build_preview(order, start_tile, has_start_tile)
		EntityOrder.Type.TRAIN:
			preview = {"entity_id": order.entity_id, "kind": "Train", "def_id": order.def_id}
		EntityOrder.Type.RESEARCH:
			preview = {"entity_id": order.entity_id, "kind": "Research", "def_id": order.def_id}
		EntityOrder.Type.USE_ABILITY:
			preview = {"entity_id": order.entity_id, "kind": "Ability", "def_id": order.def_id}
		_:
			preview = {}
	if not preview.is_empty() and has_start_tile:
		preview["start_tile"] = start_tile
	return preview


func _halted_move_preview(entity_id: int, kind: String) -> Dictionary:
	var preview: Dictionary = {
		"entity_id": entity_id,
		"kind": kind,
	}
	var target_id: int = _attack_target_for_entity(entity_id)
	if target_id < 0:
		var actor: Entity = _loaded.state.get_entity_by_id(entity_id) if _loaded != null else null
		target_id = _visible_enemy_for_entity(actor)
	if target_id >= 0:
		preview["target_entity_id"] = target_id
	return preview


func _move_preview(
	order: EntityOrder,
	kind: String,
	start_tile: Vector2i = Vector2i.ZERO,
	has_start_tile: bool = false
) -> Dictionary:
	var preview: Dictionary = {
		"entity_id": order.entity_id,
		"kind": kind,
		"target_tile": order.target_tile,
	}
	var actor: Entity = _loaded.state.get_entity_by_id(order.entity_id) if _loaded != null else null
	if actor == null or _loaded.registry == null:
		return preview
	var goal: Dictionary = _move_preview_goal(order, actor)
	var target_origin: Vector2i = goal.get("target_origin", order.target_tile)
	preview["target_tile"] = target_origin
	if goal.has("target_entity_id"):
		preview["target_entity_id"] = goal["target_entity_id"]
	var start_origin: Vector2i = start_tile if has_start_tile else actor.origin
	if not _should_preview_move_path(order, actor, start_origin, target_origin):
		return preview
	var path_actor: Entity = _preview_actor_at(actor, start_tile, has_start_tile)
	var options: Dictionary = _path_preview_options(actor.owner_player_id)
	if goal.has("goal_rect"):
		options[PATHFINDING_SCRIPT.OPTION_GOAL_RECT] = goal["goal_rect"]
		options[PATHFINDING_SCRIPT.OPTION_GOAL_RANGE] = goal.get("goal_range", 0)
		options[PATHFINDING_SCRIPT.OPTION_EXACT_ORIGIN] = goal.get("exact_origin", true)
	var path: Array[Vector2i] = PATHFINDING_SCRIPT.find_path(
		_loaded.state, path_actor, target_origin, _loaded.registry, options
	)
	if not path.is_empty():
		preview["path"] = path
	return preview


func _move_preview_goal(order: EntityOrder, actor: Entity) -> Dictionary:
	var fallback: Dictionary = {
		"target_origin": order.target_tile,
		"exact_origin": true,
		"goal_range": 0,
	}
	if (
		order == null
		or actor == null
		or order.type != EntityOrder.Type.MOVE
		or order.target_priority_chain.is_empty()
		or _loaded == null
		or _loaded.state == null
		or _loaded.state.tile_grid == null
	):
		return fallback
	for target_id in order.target_priority_chain:
		var target: Entity = _loaded.state.get_entity_by_id(target_id)
		if target == null or target.current_hp <= 0:
			continue
		if target.owner_player_id < 0 or target.owner_player_id == actor.owner_player_id:
			continue
		var target_rect: Rect2i = _entity_rect(target)
		if target_rect.size == Vector2i.ZERO:
			target_rect = Rect2i(target.origin, Vector2i.ONE)
		return {
			"target_origin": target_rect.position,
			"target_entity_id": target.id,
			"goal_rect": target_rect,
			"exact_origin": false,
			"goal_range": 1,
		}
	return fallback


func _gather_preview(
	order: EntityOrder, start_tile: Vector2i = Vector2i.ZERO, has_start_tile: bool = false
) -> Dictionary:
	var preview: Dictionary = {
		"entity_id": order.entity_id,
		"kind": "Gather",
		"target_entity_id": order.target_entity_id,
	}
	var actor: Entity = _loaded.state.get_entity_by_id(order.entity_id) if _loaded != null else null
	var target: Entity = (
		_loaded.state.get_entity_by_id(order.target_entity_id) if _loaded != null else null
	)
	if actor == null or target == null or _loaded.registry == null:
		return preview
	var target_rect: Rect2i = _entity_rect(target)
	if target_rect.size == Vector2i.ZERO:
		return preview
	var options: Dictionary = _path_preview_options(actor.owner_player_id)
	options[PATHFINDING_SCRIPT.OPTION_GOAL_RECT] = target_rect
	options[PATHFINDING_SCRIPT.OPTION_GOAL_RANGE] = 1
	options[PATHFINDING_SCRIPT.OPTION_EXACT_ORIGIN] = false
	var path_actor: Entity = _preview_actor_at(actor, start_tile, has_start_tile)
	var handoff_tile: Vector2i = path_actor.origin
	var path: Array[Vector2i] = PATHFINDING_SCRIPT.find_path(
		_loaded.state, path_actor, target_rect.position, _loaded.registry, options
	)
	if not path.is_empty():
		preview["path"] = path
		handoff_tile = path[path.size() - 1]
	preview["handoff_tile"] = handoff_tile
	return preview


func _build_preview(
	order: EntityOrder, start_tile: Vector2i = Vector2i.ZERO, has_start_tile: bool = false
) -> Dictionary:
	var preview: Dictionary = {
		"entity_id": order.entity_id,
		"kind": "Build",
		"target_tile": order.target_tile,
		"def_id": order.def_id,
	}
	var actor: Entity = _loaded.state.get_entity_by_id(order.entity_id) if _loaded != null else null
	if actor == null or _loaded.registry == null:
		return preview
	var def: EntityDef = _loaded.registry.get_by_id(order.def_id)
	var footprint: Vector2i = def.footprint if def != null else Vector2i.ONE
	if footprint == Vector2i.ZERO:
		footprint = Vector2i.ONE
	var build_rect := Rect2i(order.target_tile, footprint)
	var options: Dictionary = _path_preview_options(actor.owner_player_id)
	options[PATHFINDING_SCRIPT.OPTION_GOAL_RECT] = build_rect
	options[PATHFINDING_SCRIPT.OPTION_GOAL_RANGE] = 1
	options[PATHFINDING_SCRIPT.OPTION_EXACT_ORIGIN] = false
	var path_actor: Entity = _preview_actor_at(actor, start_tile, has_start_tile)
	var handoff_tile: Vector2i = path_actor.origin
	var path: Array[Vector2i] = PATHFINDING_SCRIPT.find_path(
		_loaded.state, path_actor, order.target_tile, _loaded.registry, options
	)
	if not path.is_empty():
		preview["path"] = path
		handoff_tile = path[path.size() - 1]
	preview["handoff_tile"] = handoff_tile
	return preview


func _preview_actor_at(actor: Entity, start_tile: Vector2i, has_start_tile: bool) -> Entity:
	if actor == null or not has_start_tile:
		return actor
	var preview_actor: Entity = actor.clone()
	preview_actor.origin = start_tile
	return preview_actor


func _should_preview_move_path(
	order: EntityOrder, actor: Entity, start_origin: Vector2i, target_origin: Vector2i
) -> bool:
	if order == null or actor == null:
		return false
	if not _can_preview_spend_movement(actor):
		return false
	if actor.ability_cast != null:
		return false
	if (
		order.type == EntityOrder.Type.MOVE
		and _will_halt_on_sight(actor.id)
		and order.target_priority_chain.is_empty()
	):
		return false
	return start_origin != target_origin


func _preview_keeps_planned_tile(preview: Dictionary, has_planned_tile: bool) -> bool:
	return preview.has("handoff_tile") or preview.has("target_tile") or has_planned_tile


func _preview_planned_tile_value(preview: Dictionary, fallback: Vector2i) -> Vector2i:
	if preview.has("handoff_tile"):
		return preview.get("handoff_tile", fallback)
	return preview.get("target_tile", fallback)


func _path_preview_options(player_id: int) -> Dictionary:
	return {
		PATHFINDING_SCRIPT.OPTION_KNOWN_ENTITY_IDS: _preview_known_entity_ids(player_id),
		PATHFINDING_SCRIPT.OPTION_PASSABLE_ENTITY_IDS: _preview_passable_entity_ids(),
	}


func _preview_known_entity_ids(player_id: int) -> Dictionary:
	var known: Dictionary = {}
	if _loaded == null or _loaded.state == null:
		return known
	for entity in _loaded.state.entities_sorted_by_id():
		if entity == null:
			continue
		if entity.owner_player_id == player_id or entity.owner_player_id < 0:
			known[entity.id] = true
			continue
		if _renderer != null and _renderer.is_entity_view_visible(entity.id):
			known[entity.id] = true
	return known


func _preview_passable_entity_ids() -> Dictionary:
	var passable: Dictionary = {}
	if _loaded == null or _loaded.state == null:
		return passable
	var submit: SubmitTurn = _input.submit_for_player(_input.active_player_id())
	for order in submit.orders:
		if order == null:
			continue
		if _is_preview_explicit_mover(order):
			passable[order.entity_id] = true
	for entity in _loaded.state.entities_sorted_by_id():
		if entity == null or entity.current_hp <= 0:
			continue
		if _is_preview_gather_travel(entity):
			passable[entity.id] = true
		if _is_preview_construction_travel(entity):
			passable[entity.id] = true
	return passable


func _is_preview_explicit_mover(order: EntityOrder) -> bool:
	if order.type != EntityOrder.Type.MOVE and order.type != EntityOrder.Type.MOVE_ONLY:
		return false
	var actor: Entity = _loaded.state.get_entity_by_id(order.entity_id)
	if not _can_preview_spend_movement(actor):
		return false
	if actor.ability_cast != null:
		return false
	if order.type == EntityOrder.Type.MOVE and _will_halt_on_sight(actor.id):
		return false
	return actor.origin != order.target_tile


func _is_preview_gather_travel(entity: Entity) -> bool:
	return (
		entity.gather_state != null
		and entity.gather_state.phase == GatherState.Phase.MOVING_TO_SOURCE
		and _can_preview_spend_movement(entity)
	)


func _is_preview_construction_travel(entity: Entity) -> bool:
	if entity.locked_to_building_id < 0 or not _can_preview_spend_movement(entity):
		return false
	var building: Entity = _loaded.state.get_entity_by_id(entity.locked_to_building_id)
	if building == null or building.current_hp <= 0 or not building.is_constructing:
		return false
	return not _are_entities_adjacent(entity, building)


func _can_preview_spend_movement(entity: Entity) -> bool:
	if entity == null or entity.current_hp <= 0 or _loaded == null or _loaded.registry == null:
		return false
	var movement: MovementDef = PATHFINDING_SCRIPT.movement_def_for_entity(entity, _loaded.registry)
	return movement != null and entity.moves_used_this_turn < movement.speed_tiles_per_turn


func _are_entities_adjacent(a: Entity, b: Entity) -> bool:
	if _loaded == null or _loaded.state == null or _loaded.state.tile_grid == null:
		return false
	var a_rect: Rect2i = _loaded.state.tile_grid.entity_rect(a.id)
	var b_rect: Rect2i = _loaded.state.tile_grid.entity_rect(b.id)
	if a_rect.size == Vector2i.ZERO or b_rect.size == Vector2i.ZERO:
		return false
	return TileGrid.distance_between_rects(a_rect, b_rect) <= 1


func _attack_target_for_entity(entity_id: int) -> int:
	if _loaded == null or _loaded.state == null or _loaded.registry == null:
		return -1
	var actor := _loaded.state.get_entity_by_id(entity_id)
	if not _can_preview_attack(actor):
		return -1
	var def := _loaded.registry.get_by_id(
		actor.current_def_id if actor.current_def_id != "" else actor.def_id
	)
	if def == null or def.combat == null:
		return -1
	if actor.focus_target_entity_id >= 0:
		var focus := _loaded.state.get_entity_by_id(actor.focus_target_entity_id)
		if _is_attack_target_in_range(actor, focus, def.combat):
			return focus.id
	var closest_id := -1
	var closest_dist := -1
	for candidate in _loaded.state.entities_sorted_by_id():
		if not _is_attack_target_in_range(actor, candidate, def.combat):
			continue
		var dist := _entity_distance(actor, candidate)
		if closest_id < 0 or dist < closest_dist:
			closest_id = candidate.id
			closest_dist = dist
	return closest_id


func _will_halt_on_sight(entity_id: int) -> bool:
	if _loaded == null or _loaded.state == null or _loaded.registry == null:
		return false
	var actor := _loaded.state.get_entity_by_id(entity_id)
	if not _can_preview_attack(actor) or not actor.halt_on_sight:
		return false
	return _visible_enemy_for_entity(actor) >= 0


func _can_preview_attack(entity: Entity) -> bool:
	if entity == null or entity.current_hp <= 0:
		return false
	if entity.ability_cast != null:
		return false
	if entity.gather_state != null and entity.gather_state.phase != GatherState.Phase.IDLE:
		return false
	if (
		ConstructionSystem.has_pending_build(entity)
		or entity.locked_to_building_id >= 0
		or entity.is_constructing
	):
		return false
	return true


func _visible_enemy_for_entity(actor: Entity) -> int:
	if actor == null or _loaded == null or _loaded.state == null or _loaded.registry == null:
		return -1
	var visibility := VisionSystem.compute_player_visibility(
		_loaded.state, _loaded.registry, actor.owner_player_id
	)
	for candidate in _loaded.state.entities_sorted_by_id():
		if candidate == null or candidate.current_hp <= 0:
			continue
		if candidate.owner_player_id < 0 or candidate.owner_player_id == actor.owner_player_id:
			continue
		if VisionSystem.is_entity_visible_to_player(
			candidate, _loaded.state, _loaded.registry, actor.owner_player_id, visibility
		):
			return candidate.id
	return -1


func _is_attack_target_in_range(actor: Entity, target: Entity, combat: CombatDef) -> bool:
	if actor == null or target == null or combat == null:
		return false
	if target.id == actor.id or target.current_hp <= 0:
		return false
	if target.owner_player_id < 0 or target.owner_player_id == actor.owner_player_id:
		return false
	if not combat.target_layers.has(target.current_layer):
		return false
	var dist := _entity_distance(actor, target)
	return dist >= 0 and dist <= combat.attack_range


func _entity_distance(a: Entity, b: Entity) -> int:
	if _loaded == null or _loaded.state == null or _loaded.registry == null:
		return -1
	var a_rect := _entity_rect(a)
	var b_rect := _entity_rect(b)
	if a_rect.size == Vector2i.ZERO or b_rect.size == Vector2i.ZERO:
		return -1
	return TileGrid.distance_between_rects(a_rect, b_rect)


func _entity_rect(entity: Entity) -> Rect2i:
	if entity == null or _loaded == null or _loaded.state == null or _loaded.registry == null:
		return Rect2i()
	if _loaded.state.tile_grid != null:
		var rect := _loaded.state.tile_grid.entity_rect(entity.id)
		if rect.size != Vector2i.ZERO:
			return rect
	var def := _loaded.registry.get_by_id(
		entity.current_def_id if entity.current_def_id != "" else entity.def_id
	)
	if def == null:
		return Rect2i()
	return Rect2i(entity.origin, def.footprint)


func _build_options(ids: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in ids:
		var def_id: String = id
		(
			out
			. append(
				{
					"id": def_id,
					"label": _input.label_for_entity_def_id_with_cost(def_id),
					"disabled": not _input.can_afford_build(def_id),
				}
			)
		)
	return out


func _entity_options(ids: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in ids:
		var def_id: String = id
		out.append({"id": def_id, "label": _input.label_for_entity_def_id_with_cost(def_id)})
	return out


func _research_options(ids: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in ids:
		var research_id: String = id
		out.append(
			{"id": research_id, "label": _input.label_for_research_id_with_cost(research_id)}
		)
	return out


func _ability_options(ids: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in ids:
		var ability_id: String = id
		out.append({"id": ability_id, "label": _input.label_for_ability_id(ability_id)})
	return out
