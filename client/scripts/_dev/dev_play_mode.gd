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
const _DEV_SNAPSHOT_DIR := "user://tmp/snapshots"
const _DEV_SNAPSHOT_PREFIX := "dev_snapshot"
const _DEV_REPLAY_AUTO_DIR := "user://tmp/replays"
const _DEV_REPLAY_AUTO_PREFIX := "dev_replay"
const COMMAND_CARD_SCRIPT := preload("res://scripts/game/command_card.gd")
const ACTION_PREVIEW_BUILDER_SCRIPT := preload("res://scripts/game/action_preview_builder.gd")
const TACTICAL_PREVIEW_BUILDER_SCRIPT := preload("res://scripts/game/tactical_preview_builder.gd")
const COMMAND_OPTION_BUILDER := preload("res://scripts/game/command_option_builder.gd")
const PATHFINDING_SCRIPT := preload("res://scripts/resolver/pathfinding_system.gd")
const PENDING_NONE := ""
const PENDING_MOVE := "move"
const PENDING_TARGET := "target"
const PENDING_BUILD := "build"
const PENDING_GATHER := "gather"
const CONTEXT_NONE := "none"
const CONTEXT_MOVE := "move"
const CONTEXT_ATTACK := "attack"
const CONTEXT_GATHER := "gather"
const CONTEXT_RALLY_MOVE := "rally_move"
const CONTEXT_RALLY_GATHER := "rally_gather"
const CONTEXT_INVALID := "invalid"
const HUD_MARGIN := 12.0
const HUD_WIDTH := 440.0
const HUD_HEIGHT := 720.0
const REPLAY_PANEL_LEFT := 384.0
const REPLAY_PANEL_TOP := HUD_MARGIN
const REPLAY_PANEL_HEIGHT := 220.0
const ESCAPE_MENU_WIDTH := 360.0
const ESCAPE_MENU_HEIGHT := 300.0
const REPLAY_PLAY_STEP_SECONDS := 0.75
const MENU_LOAD_SNAPSHOT := 0
const MENU_LOAD_REPLAY := 1
const CAMERA_ZOOM_STEP := 1.15
const CAMERA_DRAG_THRESHOLD := 4.0

@export_file("*.tres") var scenario_path: String = DEFAULT_SCENARIO_PATH
@export var auto_save_replays: bool = true

var _renderer: MatchRenderer = null
var _loaded: LoadedScenario = null
var _tunables: Tunables = null
var _input: DevTurnInput = DEV_TURN_INPUT_SCRIPT.new() as DevTurnInput
var _hud_layer: CanvasLayer = null
var _play_panel: PanelContainer = null
var _replay_panel: PanelContainer = null
var _escape_menu_panel: PanelContainer = null
var _menu_save_snapshot_button: Button = null
var _menu_load_kind: OptionButton = null
var _active_label: Label = null
var _resources_label: Label = null
var _queue_label: Label = null
var _replay_label: Label = null
var _replay_turn_label: Label = null
var _replay_timeline: HSlider = null
var _replay_play_button: Button = null
var _replay_play_timer: Timer = null
var _snapshot_file_dialog: FileDialog = null
var _replay_file_dialog: FileDialog = null
var _status_label: Label = null
var _command_card: Control = null
var _pending_command: String = PENDING_NONE
var _pending_build_def_id: String = ""
var _is_panning_camera: bool = false
var _left_empty_drag_candidate: bool = false
var _left_empty_drag_moved: bool = false
var _left_empty_drag_start: Vector2 = Vector2.ZERO
var _show_all_friendly_action_previews: bool = false
var _range_projection_active: bool = false
var _last_hover_tile: Vector2i = Vector2i.ZERO
var _has_last_hover_tile: bool = false
var _replay: MatchReplay = MatchReplay.new()
var _checkpoints: Dictionary[int, SavedSession] = {}
var _replay_mode_active: bool = false
var _replay_cursor_turn: int = 0
var _replay_playing: bool = false
var _updating_replay_timeline: bool = false
var _auto_replay_path: String = ""
var _action_preview_builder: ActionPreviewBuilder = (
	ACTION_PREVIEW_BUILDER_SCRIPT.new() as ActionPreviewBuilder
)
var _tactical_preview_builder: TacticalPreviewBuilder = (
	TACTICAL_PREVIEW_BUILDER_SCRIPT.new() as TacticalPreviewBuilder
)


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
	_range_projection_active = false
	_has_last_hover_tile = false
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


func replay_panel_visible() -> bool:
	return _replay_panel != null and _replay_panel.visible


func auto_replay_path() -> String:
	return _auto_replay_path


func set_auto_save_replays_enabled(enabled: bool) -> void:
	auto_save_replays = enabled
	if not enabled:
		_auto_replay_path = ""


func pending_command_kind() -> String:
	return _pending_command


func pending_cursor_shape() -> int:
	return _pending_cursor_shape()


func _reject_replay_edit() -> bool:
	_clear_pending_command()
	_update_hud("Replay is read-only. Use Play From Here to branch from this turn.")
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


func issue_attack_move_selected(tile: Vector2i, queue_requested: bool = false) -> bool:
	if _replay_mode_active:
		return _reject_replay_edit()
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_attack_move(tile)
	_input.set_queue_modifier_active(false)
	_update_hud()
	return ok


func issue_attack_selected(target_entity_id: int, queue_requested: bool = false) -> bool:
	if _replay_mode_active:
		return _reject_replay_edit()
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_target(target_entity_id)
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
	if action == CONTEXT_MOVE:
		return issue_move_selected(tile, queue_requested)
	if action == CONTEXT_ATTACK:
		return issue_attack_selected(context.get("target_entity_id", -1), queue_requested)
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
			if _input.can_issue_target():
				return _context_result(
					CONTEXT_ATTACK, Input.CURSOR_CROSS, "", {"target_entity_id": target_id}
				)
			return _context_result(
				CONTEXT_INVALID, Input.CURSOR_FORBIDDEN, "Selected entity cannot attack."
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
	if _input.can_issue_move():
		return _context_result(CONTEXT_MOVE, Input.CURSOR_MOVE, "")
	return _context_result(CONTEXT_INVALID, Input.CURSOR_FORBIDDEN, "Selected entity cannot move.")


func context_cursor_shape_at_tile(tile: Vector2i) -> int:
	var context: Dictionary = context_action_at_tile(tile)
	return context.get("cursor_shape", Input.CURSOR_ARROW)


func begin_move() -> void:
	if _replay_mode_active:
		_reject_replay_edit()
		return
	if not _input.can_issue_move():
		_update_hud("Select a movable unit before Move.")
		return
	_clear_build_placement_preview()
	_pending_command = PENDING_MOVE
	_pending_build_def_id = ""
	_set_pending_cursor()
	_update_hud("Click a target tile for Move.")


func begin_target() -> void:
	if _replay_mode_active:
		_reject_replay_edit()
		return
	if not _input.can_issue_target():
		_update_hud("Select a combat unit before Attack.")
		return
	_clear_build_placement_preview()
	_pending_command = PENDING_TARGET
	_pending_build_def_id = ""
	_set_pending_cursor()
	_update_hud("Click an enemy or destination tile for Attack.")


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
	if _pending_command == PENDING_TARGET:
		var target_id: int = (
			_renderer.entity_id_at_tile(tile)
			if _renderer != null
			else _loaded.state.tile_grid.entity_at(tile)
		)
		var target: Entity = _loaded.state.get_entity_by_id(target_id)
		if (
			target != null
			and target.owner_player_id >= 0
			and target.owner_player_id != _input.active_player_id()
		):
			var target_ok: bool = issue_attack_selected(target_id, queue_requested)
			if target_ok:
				_clear_pending_command()
				_update_hud()
			return target_ok
		var attack_move_ok: bool = issue_attack_move_selected(tile, queue_requested)
		if attack_move_ok:
			_clear_pending_command()
			_update_hud()
		return attack_move_ok
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


func save_snapshot_to_folder() -> bool:
	return save_snapshot_to_path(
		_new_timestamped_file_path(_DEV_SNAPSHOT_DIR, _DEV_SNAPSHOT_PREFIX)
	)


func save_snapshot_to_path(path: String) -> bool:
	if _loaded == null or _loaded.state == null or _loaded.registry == null:
		_update_hud("No match loaded to snapshot.")
		return false
	var dir_err: Error = _ensure_parent_dir(path)
	if dir_err != OK:
		_update_hud("Snapshot save path failed: %d." % dir_err)
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
	_stop_replay_playback()
	var session: SavedSession = MatchSaver.load_from(path)
	if session == null:
		_update_hud("Snapshot load failed: %s." % path)
		return false
	if not _bind_session(session, false, "Loaded snapshot turn %d." % session.state.turn_index):
		return false
	_start_replay_journal()
	_set_escape_menu_visible(false)
	_update_hud("Loaded snapshot turn %d." % session.state.turn_index)
	return true


func save_latest_replay() -> bool:
	return save_replay_to_path(_DEV_REPLAY_LATEST_PATH)


func load_latest_replay() -> bool:
	return load_replay_from_path(_DEV_REPLAY_LATEST_PATH)


func save_replay_to_folder() -> bool:
	return save_replay_to_path(
		_new_timestamped_file_path(_DEV_REPLAY_AUTO_DIR, _DEV_REPLAY_AUTO_PREFIX)
	)


func save_replay_to_path(path: String) -> bool:
	if _replay == null or _replay.initial_session == null:
		_update_hud("No replay journal to save.")
		return false
	var dir_err: Error = _ensure_parent_dir(path)
	if dir_err != OK:
		_update_hud("Replay save path failed: %d." % dir_err)
		return false
	var err: Error = ResourceSaver.save(_replay, path)
	if err != OK:
		_update_hud("Replay save failed: %d." % err)
		return false
	_update_hud("Saved replay to %s." % path)
	return true


func load_replay_from_path(path: String) -> bool:
	_stop_replay_playback()
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
	var ok: bool = replay_latest()
	_set_escape_menu_visible(false)
	return ok


func replay_start() -> bool:
	_stop_replay_playback()
	return replay_jump_to_turn(_replay_initial_turn())


func replay_previous() -> bool:
	_stop_replay_playback()
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
	_stop_replay_playback()
	return replay_jump_to_turn(_latest_checkpoint_turn())


func replay_jump_to_turn(turn_index: int) -> bool:
	if not _checkpoints.has(turn_index):
		_update_hud("Replay checkpoint %d is not available." % turn_index)
		return false
	var session: SavedSession = _checkpoints[turn_index]
	return _bind_session(session, true, "Replay jumped to turn %d." % turn_index)


func restore_replay_here() -> bool:
	_stop_replay_playback()
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
	_reset_auto_replay_file()
	_set_escape_menu_visible(false)
	return true


func resolve_turn() -> bool:
	if _loaded == null or _loaded.state == null or _loaded.registry == null or _tunables == null:
		return false
	if _replay_mode_active:
		_update_hud("Use Play From Here before resolving from a replay checkpoint.")
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
	var auto_save_ok: bool = _save_auto_replay()
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
	var resolve_status: String = "Resolved turn %d." % _loaded.state.turn_index
	if not auto_save_ok:
		resolve_status += " Auto replay save failed."
	_update_hud(resolve_status)
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
	var cancel_pressed: bool = event.is_action_pressed("ui_cancel")
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		cancel_pressed = (
			cancel_pressed
			or (key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE)
		)
	if cancel_pressed:
		_toggle_escape_menu()
		var viewport: Viewport = get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		return
	if _renderer == null or _loaded == null:
		return
	if _escape_menu_panel != null and _escape_menu_panel.visible:
		_reset_left_empty_drag()
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.keycode == KEY_ALT and not key_event.echo:
			_set_range_projection_active(key_event.pressed)
			var viewport: Viewport = get_viewport()
			if viewport != null:
				viewport.set_input_as_handled()
			return
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_A:
			begin_target()
			var viewport: Viewport = get_viewport()
			if viewport != null:
				viewport.set_input_as_handled()
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
		_record_hover_tile(tile)
		if _range_projection_active:
			_refresh_range_previews()
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
		_has_last_hover_tile = false
		_refresh_range_previews()
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
	_stop_replay_playback()
	_replay = MatchReplay.new()
	_replay.initial_session = _make_session(
		_loaded.state, _loaded.registry, _input.create_snapshot()
	)
	_replay.frames = []
	_checkpoints.clear()
	_record_checkpoint(_loaded.state.turn_index)
	_replay_mode_active = false
	_replay_cursor_turn = _loaded.state.turn_index
	_reset_auto_replay_file()


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


func _reset_auto_replay_file() -> void:
	_auto_replay_path = ""


func _save_auto_replay() -> bool:
	if not auto_save_replays:
		return true
	if _auto_replay_path == "":
		_auto_replay_path = _new_auto_replay_path()
	if _replay == null or _replay.initial_session == null:
		return false
	var dir_err: Error = _ensure_parent_dir(_auto_replay_path)
	if dir_err != OK:
		push_error("DevPlayMode: could not create auto replay directory: %d" % dir_err)
		return false
	var err: Error = ResourceSaver.save(_replay, _auto_replay_path)
	if err != OK:
		push_error("DevPlayMode: auto replay save failed for %s: %d" % [_auto_replay_path, err])
		return false
	return true


func _new_auto_replay_path() -> String:
	return _new_timestamped_file_path(_DEV_REPLAY_AUTO_DIR, _DEV_REPLAY_AUTO_PREFIX)


func _new_timestamped_file_path(dir_path: String, prefix: String) -> String:
	var stamp: String = Time.get_datetime_string_from_system()
	stamp = stamp.replace(":", "").replace("-", "").replace("T", "_")
	var unique: String = "%s_%d" % [stamp, Time.get_ticks_usec()]
	return dir_path.path_join("%s_%s.tres" % [prefix, unique])


func _ensure_dir(path: String) -> Error:
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


func _ensure_parent_dir(path: String) -> Error:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	var parent_dir: String = absolute_path.get_base_dir()
	if parent_dir == "":
		return OK
	return DirAccess.make_dir_recursive_absolute(parent_dir)


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
	_record_hover_tile(tile)
	_renderer.set_hover_tile(tile)
	if _pending_command == PENDING_BUILD:
		_refresh_build_placement_preview(tile)
		_reset_context_cursor()
	else:
		_clear_build_placement_preview()
		_update_context_cursor_for_tile(tile)
	_refresh_range_previews()


func _record_hover_tile(tile: Vector2i) -> void:
	_last_hover_tile = tile
	_has_last_hover_tile = true


func _build_hud() -> void:
	if _hud_layer != null:
		return
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "DevHUD"
	add_child(_hud_layer)

	_play_panel = PanelContainer.new()
	_play_panel.name = "Panel"
	_play_panel.anchor_left = 1.0
	_play_panel.anchor_right = 1.0
	_play_panel.anchor_top = 0.0
	_play_panel.anchor_bottom = 0.0
	_play_panel.offset_left = -HUD_WIDTH - HUD_MARGIN
	_play_panel.offset_top = HUD_MARGIN
	_play_panel.offset_right = -HUD_MARGIN
	_play_panel.offset_bottom = HUD_MARGIN + HUD_HEIGHT
	_hud_layer.add_child(_play_panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.name = "Root"
	_play_panel.add_child(root)

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
	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(_status_label)
	root.add_child(_status_label)

	_command_card = COMMAND_CARD_SCRIPT.new() as Control
	_command_card.connect("move_requested", Callable(self, "begin_move"))
	_command_card.connect("target_requested", Callable(self, "begin_target"))
	_command_card.connect("gather_requested", Callable(self, "begin_gather"))
	_command_card.connect("build_requested", Callable(self, "begin_build"))
	_command_card.connect("train_requested", Callable(self, "issue_train_selected"))
	_command_card.connect("research_requested", Callable(self, "issue_research_selected"))
	_command_card.connect("ability_requested", Callable(self, "issue_ability_selected"))
	_command_card.connect("cancel_requested", Callable(self, "issue_cancel_selected"))
	_command_card.connect("repeat_train_toggled", Callable(self, "issue_repeat_train_selected"))
	root.add_child(_command_card)
	_build_replay_panel()
	_build_escape_menu()
	_build_file_dialogs()
	_build_replay_play_timer()
	_update_hud()


func _build_replay_panel() -> void:
	if _hud_layer == null:
		return
	_replay_panel = PanelContainer.new()
	_replay_panel.name = "ReplayPanel"
	_replay_panel.anchor_left = 0.0
	_replay_panel.anchor_right = 0.0
	_replay_panel.anchor_top = 0.0
	_replay_panel.anchor_bottom = 0.0
	_replay_panel.offset_left = REPLAY_PANEL_LEFT
	_replay_panel.offset_top = REPLAY_PANEL_TOP
	_replay_panel.offset_right = REPLAY_PANEL_LEFT + HUD_WIDTH
	_replay_panel.offset_bottom = REPLAY_PANEL_TOP + REPLAY_PANEL_HEIGHT
	_replay_panel.visible = false
	_hud_layer.add_child(_replay_panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.name = "Root"
	_replay_panel.add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.name = "Header"
	root.add_child(header)

	var title: Label = Label.new()
	title.text = "Replay"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_label(title)
	header.add_child(title)

	var replay_buttons: HBoxContainer = HBoxContainer.new()
	replay_buttons.name = "ReplayButtons"
	root.add_child(replay_buttons)

	var replay_start_button: Button = _button("Start")
	replay_start_button.pressed.connect(_start_replay_from_hud)
	replay_buttons.add_child(replay_start_button)

	var replay_prev_button: Button = _button("Prev")
	replay_prev_button.pressed.connect(_previous_replay_from_hud)
	replay_buttons.add_child(replay_prev_button)

	_replay_play_button = _button("Play")
	_replay_play_button.name = "ReplayPlay"
	_replay_play_button.pressed.connect(_toggle_replay_playback)
	replay_buttons.add_child(_replay_play_button)

	var replay_next_button: Button = _button("Next")
	replay_next_button.pressed.connect(_next_replay_from_hud)
	replay_buttons.add_child(replay_next_button)

	var replay_latest_button: Button = _button("Latest")
	replay_latest_button.pressed.connect(_latest_replay_from_hud)
	replay_buttons.add_child(replay_latest_button)

	var timeline_row: HBoxContainer = HBoxContainer.new()
	timeline_row.name = "ReplayTimelineRow"
	root.add_child(timeline_row)

	_replay_timeline = HSlider.new()
	_replay_timeline.name = "ReplayTimeline"
	_replay_timeline.min_value = 0.0
	_replay_timeline.max_value = 0.0
	_replay_timeline.step = 1.0
	_replay_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_replay_timeline.value_changed.connect(_replay_timeline_changed)
	timeline_row.add_child(_replay_timeline)

	_replay_turn_label = Label.new()
	_replay_turn_label.name = "ReplayTurnLabel"
	_replay_turn_label.custom_minimum_size = Vector2(96.0, 34.0)
	_style_label(_replay_turn_label)
	timeline_row.add_child(_replay_turn_label)

	var replay_actions: HBoxContainer = HBoxContainer.new()
	replay_actions.name = "ReplayActions"
	root.add_child(replay_actions)

	var restore_button: Button = _button("Play From Here")
	restore_button.pressed.connect(restore_replay_here)
	replay_actions.add_child(restore_button)

	_replay_label = Label.new()
	_replay_label.name = "ReplayStatus"
	_replay_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(_replay_label)
	root.add_child(_replay_label)
	_sync_mode_ui()


func _build_escape_menu() -> void:
	if _hud_layer == null:
		return
	_escape_menu_panel = PanelContainer.new()
	_escape_menu_panel.name = "EscapeMenu"
	_escape_menu_panel.anchor_left = 0.5
	_escape_menu_panel.anchor_right = 0.5
	_escape_menu_panel.anchor_top = 0.5
	_escape_menu_panel.anchor_bottom = 0.5
	_escape_menu_panel.offset_left = ESCAPE_MENU_WIDTH * -0.5
	_escape_menu_panel.offset_right = ESCAPE_MENU_WIDTH * 0.5
	_escape_menu_panel.offset_top = ESCAPE_MENU_HEIGHT * -0.5
	_escape_menu_panel.offset_bottom = ESCAPE_MENU_HEIGHT * 0.5
	_escape_menu_panel.visible = false
	_hud_layer.add_child(_escape_menu_panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.name = "Root"
	_escape_menu_panel.add_child(root)

	var title: Label = Label.new()
	title.text = "Menu"
	_style_label(title)
	root.add_child(title)

	var resume_button: Button = _button("Resume")
	resume_button.pressed.connect(func() -> void: _set_escape_menu_visible(false))
	root.add_child(resume_button)

	var new_game_button: Button = _button("New Game")
	new_game_button.pressed.connect(_new_game_from_menu)
	root.add_child(new_game_button)

	var main_menu_button: Button = _button("Main Menu")
	main_menu_button.name = "MainMenu"
	main_menu_button.pressed.connect(_main_menu_from_menu)
	root.add_child(main_menu_button)

	_menu_save_snapshot_button = _button("Save Snapshot")
	_menu_save_snapshot_button.name = "SaveSnapshot"
	_menu_save_snapshot_button.pressed.connect(save_snapshot_to_folder)
	root.add_child(_menu_save_snapshot_button)

	var load_row: HBoxContainer = HBoxContainer.new()
	load_row.name = "LoadRow"
	root.add_child(load_row)

	_menu_load_kind = OptionButton.new()
	_menu_load_kind.name = "LoadKind"
	_menu_load_kind.add_item("Snapshot", MENU_LOAD_SNAPSHOT)
	_menu_load_kind.add_item("Replay", MENU_LOAD_REPLAY)
	_menu_load_kind.select(MENU_LOAD_SNAPSHOT)
	_menu_load_kind.custom_minimum_size = Vector2(160.0, 34.0)
	_menu_load_kind.add_theme_font_size_override("font_size", 18)
	load_row.add_child(_menu_load_kind)

	var load_button: Button = _button("Load...")
	load_button.name = "Load"
	load_button.pressed.connect(_open_menu_load_dialog)
	load_row.add_child(load_button)
	_sync_mode_ui()


func _build_file_dialogs() -> void:
	_snapshot_file_dialog = _file_dialog(
		"SnapshotLoadDialog", _DEV_SNAPSHOT_DIR, _load_snapshot_file_selected
	)
	_hud_layer.add_child(_snapshot_file_dialog)
	_replay_file_dialog = _file_dialog(
		"ReplayLoadDialog", _DEV_REPLAY_AUTO_DIR, _load_replay_file_selected
	)
	_hud_layer.add_child(_replay_file_dialog)


func _build_replay_play_timer() -> void:
	_replay_play_timer = Timer.new()
	_replay_play_timer.name = "ReplayPlayTimer"
	_replay_play_timer.one_shot = false
	_replay_play_timer.wait_time = REPLAY_PLAY_STEP_SECONDS
	_replay_play_timer.timeout.connect(_advance_replay_playback)
	add_child(_replay_play_timer)


func _toggle_escape_menu() -> void:
	_set_escape_menu_visible(not (_escape_menu_panel != null and _escape_menu_panel.visible))


func _set_escape_menu_visible(visible: bool) -> void:
	if _escape_menu_panel != null:
		_escape_menu_panel.visible = visible
	_update_hud()


func _sync_mode_ui() -> void:
	if _play_panel != null:
		_play_panel.visible = not _replay_mode_active
	if _replay_panel != null:
		_replay_panel.visible = _replay_mode_active
	if _menu_save_snapshot_button != null:
		_menu_save_snapshot_button.visible = not _replay_mode_active
	if _replay_play_button != null:
		_replay_play_button.text = "Pause" if _replay_playing else "Play"


func _file_dialog(dialog_name: String, current_dir: String, callback: Callable) -> FileDialog:
	_ensure_dir(current_dir)
	var dialog: FileDialog = FileDialog.new()
	dialog.name = dialog_name
	dialog.access = FileDialog.ACCESS_USERDATA
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.current_dir = current_dir
	dialog.filters = PackedStringArray(["*.tres ; Godot resources"])
	dialog.file_selected.connect(callback)
	return dialog


func _open_menu_load_dialog() -> void:
	if _menu_load_kind != null and _menu_load_kind.get_selected_id() == MENU_LOAD_REPLAY:
		_open_file_dialog(_replay_file_dialog, _DEV_REPLAY_AUTO_DIR)
	else:
		_open_file_dialog(_snapshot_file_dialog, _DEV_SNAPSHOT_DIR)


func _open_file_dialog(dialog: FileDialog, dir_path: String) -> void:
	if dialog == null:
		return
	var err: Error = _ensure_dir(dir_path)
	if err != OK:
		_update_hud("Could not open folder %s: %d." % [dir_path, err])
		return
	dialog.current_dir = dir_path
	dialog.popup_centered_ratio(0.7)


func _load_snapshot_file_selected(path: String) -> void:
	load_snapshot_from_path(path)


func _load_replay_file_selected(path: String) -> void:
	load_replay_from_path(path)


func _new_game_from_menu() -> void:
	_stop_replay_playback()
	_set_escape_menu_visible(false)
	var path: String = scenario_path if scenario_path != "" else DEFAULT_SCENARIO_PATH
	load_scenario_path(path)


func _main_menu_from_menu() -> void:
	_stop_replay_playback()
	var err: Error = get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	if err != OK:
		push_error("DevPlayMode: failed to return to main menu: %d" % err)


func _start_replay_from_hud() -> void:
	_stop_replay_playback()
	replay_start()


func _previous_replay_from_hud() -> void:
	_stop_replay_playback()
	replay_previous()


func _next_replay_from_hud() -> void:
	_stop_replay_playback()
	replay_next()


func _latest_replay_from_hud() -> void:
	_stop_replay_playback()
	replay_latest()


func _toggle_replay_playback() -> void:
	if not _replay_mode_active:
		return
	if _replay_playing:
		_stop_replay_playback()
		return
	if _frame_for_turn(_replay_cursor_turn) == null:
		_update_hud("Replay is already at the latest turn.")
		return
	_replay_playing = true
	if _replay_play_timer != null:
		_replay_play_timer.start()
	_update_hud()


func _advance_replay_playback() -> void:
	if not _replay_playing:
		return
	if not replay_next() or _frame_for_turn(_replay_cursor_turn) == null:
		_stop_replay_playback()


func _stop_replay_playback() -> void:
	_replay_playing = false
	if _replay_play_timer != null:
		_replay_play_timer.stop()
	if _replay_play_button != null:
		_replay_play_button.text = "Play"


func _replay_timeline_changed(value: float) -> void:
	if _updating_replay_timeline:
		return
	_stop_replay_playback()
	replay_jump_to_turn(int(round(value)))


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


func _update_hud(override_status: String = "") -> void:
	_sync_mode_ui()
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
	if _replay_timeline != null:
		_updating_replay_timeline = true
		_replay_timeline.min_value = float(_replay_initial_turn())
		_replay_timeline.max_value = float(maxi(_latest_checkpoint_turn(), _replay_initial_turn()))
		_replay_timeline.value = float(_replay_cursor_turn)
		_updating_replay_timeline = false
	if _replay_turn_label != null:
		_replay_turn_label.text = "%d / %d" % [_replay_cursor_turn, _latest_checkpoint_turn()]
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
			_status_label.text = "Pending Move: click target tile."
		elif _pending_command == PENDING_TARGET:
			_status_label.text = "Pending Attack: click an enemy or destination tile."
		elif _pending_command == PENDING_BUILD:
			_status_label.text = "Pending BUILD %s: click placement tile." % _pending_build_def_id
		elif _pending_command == PENDING_GATHER:
			_status_label.text = "Pending GATHER: click a mineral patch or refinery."
		else:
			_status_label.text = status_message
	_refresh_command_card()
	_refresh_action_previews()
	_refresh_range_previews()


func _context_result(
	action: String, cursor_shape: int, message: String, extra: Dictionary = {}
) -> Dictionary:
	var out: Dictionary = {"action": action, "cursor_shape": cursor_shape, "message": message}
	for key in extra:
		out[key] = extra[key]
	return out


func _update_context_cursor_for_tile(tile: Vector2i) -> void:
	if _pending_command != PENDING_NONE:
		_set_pending_cursor()
		return
	var shape: int = context_cursor_shape_at_tile(tile)
	Input.set_default_cursor_shape(shape)


func _set_pending_cursor() -> void:
	Input.set_default_cursor_shape(_pending_cursor_shape())


func _pending_cursor_shape() -> int:
	if _pending_command == PENDING_TARGET:
		return Input.CURSOR_CROSS
	return Input.CURSOR_ARROW


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
	return _input.can_issue_rally_gather_to(target_entity_id)


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
		_input.can_issue_target(),
		_input.can_issue_gather(),
		COMMAND_OPTION_BUILDER.build_options(_input, _input.build_option_ids()),
		COMMAND_OPTION_BUILDER.entity_options(_input, _input.train_option_ids()),
		COMMAND_OPTION_BUILDER.research_options(_input, _input.research_option_ids()),
		COMMAND_OPTION_BUILDER.ability_options(_input, _input.ability_option_ids()),
		_input.can_issue_cancel(),
		_input.can_issue_repeat_train_toggle(),
		_input.selected_repeat_train_enabled()
	)


func _refresh_action_previews() -> void:
	if _renderer == null:
		return
	var state: MatchState = _loaded.state if _loaded != null else null
	var registry: EntityRegistry = _loaded.registry if _loaded != null else null
	if _renderer.has_method("set_action_previews"):
		var previews: Array[Dictionary] = _action_preview_builder.build(
			state,
			registry,
			_input,
			_input.active_player_id(),
			_input.selected_entity_id(),
			_show_all_friendly_action_previews,
			_renderer
		)
		_renderer.call("set_action_previews", previews)
	if _renderer.has_method("set_target_intent_previews"):
		var target_intents: Array[Dictionary] = _action_preview_builder.build_target_intents(
			state,
			registry,
			_input,
			_input.active_player_id(),
			_input.selected_entity_id(),
			_show_all_friendly_action_previews,
			_renderer
		)
		_renderer.call("set_target_intent_previews", target_intents)


func _set_range_projection_active(enabled: bool) -> void:
	if _range_projection_active == enabled:
		return
	_range_projection_active = enabled
	_refresh_range_previews()


func _refresh_range_previews() -> void:
	if _renderer == null or not _renderer.has_method("set_range_preview_tiles"):
		return
	var current_tiles: Array[Vector2i] = []
	var projected_tiles: Array[Vector2i] = []
	if _loaded != null and _loaded.state != null and _loaded.registry != null:
		var entity_id: int = _input.selected_entity_id()
		if entity_id >= 0:
			current_tiles = _tactical_preview_builder.attack_range_tiles(
				_loaded.state, _loaded.registry, entity_id
			)
			if (
				_range_projection_active
				and _has_last_hover_tile
				and _loaded.state.tile_grid != null
				and _loaded.state.tile_grid.is_in_bounds(_last_hover_tile)
			):
				projected_tiles = _tactical_preview_builder.attack_range_tiles_from_origin(
					_loaded.state, _loaded.registry, entity_id, _last_hover_tile
				)
	_renderer.call("set_range_preview_tiles", current_tiles, projected_tiles)


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
