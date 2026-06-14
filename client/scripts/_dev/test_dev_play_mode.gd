@tool
extends Node

const DEV_PLAY_MODE_PATH := "res://scripts/_dev/dev_play_mode.gd"
const COMMAND_CARD_PATH := "res://scripts/game/command_card.gd"
const DEV_PLAY_COCKPIT_SCENE_PATH := "res://scenes/ui/dev_play_cockpit.tscn"
const COMBAT_SCENARIO_PATH := "res://data/scenarios/combat_marines_vs_tanks.tres"
const MVP_SCENARIO_PATH := "res://data/scenarios/mvp_map.tres"
const TUNABLES_PATH := "res://data/tunables.tres"


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
	print("[test_dev_play_mode] %d passed, %d failed" % [passed, failed])
	for test_name in fail_names:
		push_error("  failed: %s" % test_name)
	return failed


# Minimal session delegate: proves a third submission source (e.g. the M1
# AI mode) can drive MatchSessionController without dev/network machinery.
class StubSessionHost:
	extends Node

	var state: MatchState = null
	var registry: EntityRegistry = null
	var statuses: Array[String] = []
	var hud_updates: int = 0

	func session_state() -> MatchState:
		return state

	func session_registry() -> EntityRegistry:
		return registry

	func session_renderer() -> MatchRenderer:
		return null

	func session_local_player_id() -> int:
		return 0

	func session_cockpit() -> Control:
		return null

	func session_input_enabled() -> bool:
		return state != null

	func session_is_blocking_overlay_visible() -> bool:
		return false

	func session_reject_edit() -> bool:
		return false

	func session_reject_context_query() -> bool:
		return false

	func session_show_status(message: String) -> void:
		statuses.append(message)

	func session_update_hud() -> void:
		hud_updates += 1

	func session_on_escape() -> void:
		pass

	func session_handle_mode_key_input(_event: InputEventKey) -> bool:
		return false

	func session_on_hover_tile(_tile: Vector2i) -> void:
		pass

	func session_on_pointer_exited_viewport() -> void:
		pass

	func session_on_order_issued(_kind: String, _context: Dictionary, _ok: bool) -> void:
		pass


func _test_selecting_a_resource_shows_remaining_amount() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	var patch_id: int = _add_runtime_entity(
		mode.current_state(), "mineral_patch", -1, Vector2i(20, 20)
	)
	if patch_id < 0:
		push_error("could not place test mineral patch")
		_free_mode(mode)
		return false
	var patch: Entity = mode.current_state().get_entity_by_id(patch_id)
	patch.current_resource_amount = 321
	var ok := true
	if not mode.select_entity_id(patch_id):
		push_error("mineral patches should be selectable for inspection")
		ok = false
	var controller: MatchSessionController = mode.get("_controller") as MatchSessionController
	var text: String = controller.selection_resource_text() if controller != null else ""
	if not text.contains("321"):
		push_error("selection should show remaining minerals, got '%s'" % text)
		ok = false
	if mode.input_model().can_issue_move() or mode.input_model().can_issue_target():
		push_error("a selected resource must not enable unit commands")
		ok = false
	_free_mode(mode)
	return ok


func _test_session_controller_runs_with_stub_delegate() -> bool:
	var scenario: ScenarioDef = load(COMBAT_SCENARIO_PATH) as ScenarioDef
	var registry: EntityRegistry = _load_registry()
	var tunables: Tunables = load("res://data/tunables.tres") as Tunables
	if scenario == null or registry == null or tunables == null:
		push_error("stub delegate test requires canonical data fixtures")
		return false
	var loaded: LoadedScenario = ScenarioLoader.load(scenario, registry, tunables)
	if loaded == null:
		return false
	var host: StubSessionHost = StubSessionHost.new()
	add_child(host)
	host.state = loaded.state
	host.registry = loaded.registry
	var input: DevTurnInput = DevTurnInput.new()
	input.set_active_player_id(0)
	input.bind_context(loaded.state, loaded.registry)
	var controller: MatchSessionController = MatchSessionController.new()
	controller.setup(host, input, 4.0)
	var ok: bool = true
	var unit_id: int = -1
	for entity: Entity in loaded.state.entities_sorted_by_id():
		var def: EntityDef = loaded.registry.get_by_id(entity.current_def_id)
		if entity.owner_player_id == 0 and def != null and def.movement != null:
			unit_id = entity.id
			break
	if unit_id < 0 or not controller.select_entity_id(unit_id):
		push_error("stub delegate should select a movable unit")
		ok = false
	elif not controller.issue_move_selected(Vector2i(3, 3)):
		push_error("stub delegate should issue a MOVE through the controller")
		ok = false
	else:
		var orders: Array[EntityOrder] = input.submit_for_player(0).orders
		if orders.size() != 1 or orders[0].type != EntityOrder.Type.MOVE:
			push_error("stub delegate should produce one MOVE order")
			ok = false
		if host.hud_updates < 2:
			push_error("controller should call the delegate HUD hook")
			ok = false
	remove_child(host)
	host.queue_free()
	return ok


func _all_tests() -> Array:
	return [
		["dev_play_mode_loads_scenario_and_binds_renderer", _test_loads_scenario],
		[
			"session_controller_runs_with_stub_delegate",
			_test_session_controller_runs_with_stub_delegate
		],
		[
			"selecting_a_resource_shows_remaining_amount",
			_test_selecting_a_resource_shows_remaining_amount
		],
		["dev_play_mode_uses_authored_cockpit_shell", _test_uses_authored_cockpit_shell],
		["cockpit_styles_derive_from_ui_tokens", _test_cockpit_styles_derive_from_ui_tokens],
		[
			"cockpit_economy_state_renders_income_and_committed",
			_test_cockpit_economy_state_renders_income_and_committed
		],
		[
			"cockpit_selection_stats_renders_hp_bar_statuses_and_preview",
			_test_cockpit_selection_stats_renders_hp_bar_statuses_and_preview
		],
		[
			"cockpit_production_state_builds_chips_with_cancel_indices",
			_test_cockpit_production_state_builds_chips_with_cancel_indices
		],
		[
			"cockpit_idle_worker_button_visibility_and_signal",
			_test_cockpit_idle_worker_button_visibility_and_signal
		],
		[
			"dev_play_mode_top_bar_shows_income_and_committed_spend",
			_test_top_bar_shows_income_and_committed_spend
		],
		[
			"dev_play_mode_selection_panel_shows_effective_stats_statuses_and_hp",
			_test_selection_panel_shows_effective_stats_statuses_and_hp
		],
		[
			"dev_play_mode_selection_panel_shows_worker_state_and_occupancy",
			_test_selection_panel_shows_worker_state_and_occupancy
		],
		[
			"dev_play_mode_damage_preview_for_ordered_target",
			_test_damage_preview_for_ordered_target
		],
		[
			"dev_play_mode_production_strip_lists_items_and_cancels_by_index",
			_test_production_strip_lists_items_and_cancels_by_index
		],
		[
			"dev_play_mode_idle_worker_button_cycles_selection",
			_test_idle_worker_button_cycles_selection
		],
		[
			"dev_play_mode_move_and_gather_hotkeys_begin_pending_commands",
			_test_move_and_gather_hotkeys_begin_pending_commands
		],
		["dev_play_mode_queues_and_resolves_turn", _test_queues_and_resolves_turn],
		[
			"dev_play_mode_blocks_input_during_resolve_playback",
			_test_blocks_input_during_resolve_playback
		],
		["dev_play_mode_routes_context_actions", _test_routes_context_actions],
		["dev_play_mode_context_cursor_classifier", _test_context_cursor_classifier],
		[
			"dev_play_mode_switches_input_and_render_perspective",
			_test_switches_input_and_render_perspective
		],
		["dev_play_mode_command_card_tracks_selection", _test_command_card_tracks_selection],
		[
			"dev_play_mode_command_card_hides_when_not_actionable",
			_test_command_card_hides_when_not_actionable
		],
		[
			"command_card_primary_visibility_tracks_each_command",
			_test_command_card_primary_visibility_tracks_each_command
		],
		["dev_play_mode_command_card_shows_costs", _test_command_card_shows_costs],
		[
			"dev_play_mode_worker_gather_command_targets_resource",
			_test_worker_gather_command_targets_resource
		],
		[
			"dev_play_mode_right_click_gather_rejects_raw_gas",
			_test_right_click_gather_rejects_raw_gas
		],
		["dev_play_mode_producer_right_click_sets_rally", _test_producer_right_click_sets_rally],
		[
			"dev_play_mode_affordable_build_interrupts_auto_gather",
			_test_affordable_build_interrupts_auto_gather
		],
		["dev_play_mode_mvp_worker_builds_refinery", _test_mvp_worker_builds_refinery],
		[
			"dev_play_mode_selected_and_friendly_action_previews",
			_test_selected_and_friendly_action_previews
		],
		[
			"dev_play_mode_idle_worker_indicator_counts_active_idle_workers",
			_test_idle_worker_indicator_counts_active_idle_workers
		],
		[
			"dev_play_mode_idle_worker_indicator_excludes_busy_workers",
			_test_idle_worker_indicator_excludes_busy_workers
		],
		["dev_play_mode_cockpit_all_orders_toggle_routes", _test_cockpit_all_orders_toggle_routes],
		["dev_play_mode_selected_combat_unit_shows_range", _test_selected_combat_unit_shows_range],
		[
			"dev_play_mode_alt_projects_range_from_hover_tile",
			_test_alt_projects_range_from_hover_tile
		],
		[
			"dev_play_mode_move_preview_shows_turn_stop_marker",
			_test_move_preview_shows_turn_stop_marker
		],
		[
			"dev_play_mode_selected_and_friendly_target_intents",
			_test_selected_and_friendly_target_intents
		],
		[
			"dev_play_mode_gather_and_build_previews_route_around_blockers",
			_test_gather_and_build_previews_route_around_blockers
		],
		["dev_play_mode_shift_click_routes_future_orders", _test_shift_click_routes_future_orders],
		[
			"dev_play_mode_shift_click_routes_future_gather_and_build_orders",
			_test_shift_click_routes_future_gather_and_build_orders
		],
		[
			"dev_play_mode_direct_attack_preview_tracks_live_target",
			_test_direct_attack_preview_tracks_live_target
		],
		[
			"dev_play_mode_pending_build_updates_placement_preview",
			_test_pending_build_updates_placement_preview
		],
		[
			"dev_play_mode_requeues_unfinished_move_after_resolve",
			_test_requeues_unfinished_move_after_resolve
		],
		[
			"dev_play_mode_tied_same_target_move_completes_for_future_queue",
			_test_tied_same_target_move_completes_for_future_queue
		],
		["dev_play_mode_routes_command_card_orders", _test_routes_command_card_orders],
		["dev_play_mode_ai_opponent_toggle", _test_ai_opponent_toggle_drives_player_one],
		["dev_play_mode_pending_target_targets_enemy", _test_pending_target_targets_enemy],
		["dev_play_mode_a_key_attack_mode", _test_a_key_attack_mode],
		[
			"dev_play_mode_drag_box_replace_shift_toggle_and_shift_box_add",
			_test_drag_box_replace_shift_toggle_and_shift_box_add
		],
		["dev_play_mode_drag_box_filters_immobile_units", _test_drag_box_filters_immobile_units],
		[
			"dev_play_mode_click_selection_uses_press_modifier",
			_test_click_selection_uses_press_modifier
		],
		[
			"dev_play_mode_shift_click_failure_updates_status",
			_test_shift_click_failure_updates_status
		],
		[
			"dev_play_mode_drag_box_selection_uses_press_modifier",
			_test_drag_box_selection_uses_press_modifier
		],
		["dev_play_mode_group_right_click_orders", _test_group_right_click_orders],
		[
			"dev_play_mode_left_drag_box_does_not_pan_camera",
			_test_left_drag_box_does_not_pan_camera
		],
		[
			"dev_play_mode_escape_resets_active_selection_drag",
			_test_escape_resets_active_selection_drag
		],
		["dev_play_mode_escape_menu_contains_debug_controls", _test_escape_debug_controls],
		[
			"dev_play_mode_switching_player_keeps_camera_bounded",
			_test_switching_player_keeps_camera_bounded
		],
		[
			"dev_play_mode_zoom_debug_hidden_until_menu_toggle",
			_test_zoom_debug_hidden_until_menu_toggle
		],
		[
			"dev_play_mode_hud_stays_inside_window_and_camera_uses_safe_area",
			_test_hud_stays_inside_window_and_camera_uses_safe_area
		],
	]


func _test_loads_scenario() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	var ok: bool = mode.load_scenario_path(COMBAT_SCENARIO_PATH)
	if not ok:
		push_error("load_scenario_path returned false")
		_free_mode(mode)
		return false
	if mode.current_state() == null or mode.current_state().entities.size() != 4:
		push_error("expected combat scenario to load four entities")
		_free_mode(mode)
		return false
	if mode.renderer() == null or mode.renderer().entity_view_count() != 4:
		push_error("expected renderer to bind four entity views")
		_free_mode(mode)
		return false
	_free_mode(mode)
	return true


func _test_queues_and_resolves_turn() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	if not _move_entity_to(mode.current_state(), 4, Vector2i(8, 10)):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	if not mode.select_entity_id(1):
		push_error("expected P0 marine #1 to be selectable")
		_free_mode(mode)
		return false
	if not mode.issue_attack_selected(4):
		push_error("expected ATTACK against P1 tank #4 to queue")
		_free_mode(mode)
		return false
	if mode.pending_order_count(0) != 1:
		push_error("expected one queued P0 order before resolve")
		_free_mode(mode)
		return false
	if not mode.resolve_turn():
		push_error("resolve_turn returned false")
		_free_mode(mode)
		return false
	if mode.current_state().turn_index != 1:
		push_error("expected turn index 1 after resolve, got %d" % mode.current_state().turn_index)
		_free_mode(mode)
		return false
	var queued_after_resolve: Array[EntityOrder] = mode.input_model().submit_for_player(0).orders
	var marine_after: Entity = mode.current_state().get_entity_by_id(1)
	if queued_after_resolve.size() != 0 or mode.pending_order_count(1) != 0:
		push_error("resolve_turn should clear submitted TARGET orders after distribution")
		_free_mode(mode)
		return false
	if marine_after == null or marine_after.focus_target_entity_id != 4:
		push_error("resolve_turn should persist TARGET focus in resolved state")
		_free_mode(mode)
		return false
	_free_mode(mode)
	return true


func _test_blocks_input_during_resolve_playback() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	var renderer: MatchRenderer = mode.renderer()
	var state: MatchState = mode.current_state()
	var actor_id: int = _find_entity_id(state, "marine", 0)
	var actor: Entity = state.get_entity_by_id(actor_id) if state != null else null
	var target_tile: Vector2i = _move_target_tile_for_entity(state, actor_id)
	if renderer == null or actor == null or target_tile == actor.origin:
		push_error("resolve playback input gate test requires a movable actor and renderer")
		_free_mode(mode)
		return false
	var next_state: MatchState = state.clone()
	var next_actor: Entity = next_state.get_entity_by_id(actor_id)
	if next_actor == null or not next_state.tile_grid.move(actor_id, target_tile):
		push_error("resolve playback input gate test could not build the next state")
		_free_mode(mode)
		return false
	next_actor.origin = target_tile
	var event: ResolverEvent = _move_event_for_test(actor_id, actor.origin, target_tile)
	renderer.render_step(next_state, [event])
	var ok: bool = true
	if bool(mode.session_input_enabled()):
		push_error("dev play input should be disabled while resolve movement playback is active")
		ok = false
	if not renderer.has_method("finish_resolve_animation_for_tests"):
		push_error("renderer should expose finish_resolve_animation_for_tests")
		ok = false
	else:
		renderer.call("finish_resolve_animation_for_tests")
		if not bool(mode.session_input_enabled()):
			push_error("dev play input should be enabled after resolve movement playback finishes")
			ok = false
	_free_mode(mode)
	return ok


func _test_routes_context_actions() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	if not _move_entity_to(mode.current_state(), 4, Vector2i(8, 10)):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	mode.select_entity_id(1)
	mode.renderer().set_perspective_player_id(0)
	if not mode.issue_context_at_tile(Vector2i(8, 10)):
		push_error("right-clicking visible enemy-occupied tile should queue direct attack")
		_free_mode(mode)
		return false
	var marine: Entity = mode.current_state().get_entity_by_id(1)
	if marine == null or marine.focus_target_entity_id != -1:
		push_error("context enemy action should not mutate focus before resolve")
		_free_mode(mode)
		return false
	var attack_orders: Array[EntityOrder] = mode.input_model().submit_for_player(0).orders
	if attack_orders.size() != 1:
		push_error("context enemy target should queue one atomic order")
		_free_mode(mode)
		return false
	var attack_order: EntityOrder = attack_orders[0]
	if (
		attack_order.type != EntityOrder.Type.TARGET
		or attack_order.target_priority_chain != ([4] as Array[int])
		or attack_order.target_entity_id != 4
		or attack_order.target_tile != Vector2i(8, 10)
	):
		push_error("context enemy action should queue TARGET for #4")
		_free_mode(mode)
		return false
	mode.input_model().clear_submissions()
	mode.set_active_player_id(0)
	mode.select_entity_id(1)
	if not mode.issue_context_at_tile(Vector2i(7, 10)):
		push_error("right-clicking empty tile should queue Move")
		_free_mode(mode)
		return false
	var move_order: EntityOrder = mode.input_model().submit_for_player(0).orders[0]
	if move_order.type != EntityOrder.Type.MOVE or move_order.target_tile != Vector2i(7, 10):
		push_error("context empty-tile action should be Move to (7, 10)")
		_free_mode(mode)
		return false
	_free_mode(mode)
	return true


func _test_context_cursor_classifier() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	mode.select_entity_id(1)
	mode.renderer().set_perspective_player_id(1)
	var enemy_context: Dictionary = mode.context_action_at_tile(Vector2i(13, 10))
	var ok := true
	if (
		enemy_context.get("action", "") != "attack"
		or enemy_context.get("cursor_shape", -1) != Input.CURSOR_CROSS
	):
		push_error("enemy hover should classify as attack with cross cursor")
		ok = false
	var empty_context: Dictionary = mode.context_action_at_tile(Vector2i(9, 10))
	if (
		empty_context.get("action", "") != "move"
		or empty_context.get("cursor_shape", -1) != Input.CURSOR_MOVE
	):
		push_error("empty hover should classify as move with move cursor")
		ok = false
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	var mineral_id: int = _find_entity_id_any_hp(mode.current_state(), "mineral_patch", -1)
	if worker_id < 0 or mineral_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected worker and mineral for gather cursor classifier")
		_free_mode(mode)
		return false
	var mineral: Entity = mode.current_state().get_entity_by_id(mineral_id)
	var gather_context: Dictionary = mode.context_action_at_tile(mineral.origin)
	if (
		gather_context.get("action", "") != "gather"
		or gather_context.get("cursor_shape", -1) != Input.CURSOR_POINTING_HAND
	):
		push_error("resource hover should classify as gather with pointing-hand cursor")
		ok = false
	_free_mode(mode)
	return ok


func _test_switches_input_and_render_perspective() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	if not mode.select_entity_id(1):
		push_error("expected P0 marine #1 to be selectable")
		_free_mode(mode)
		return false
	mode.set_active_player_id(1)
	var ok: bool = true
	if mode.input_model().active_player_id() != 1:
		push_error("input model did not switch to P1")
		ok = false
	if mode.input_model().selected_entity_id() != -1:
		push_error("selection should clear when switching away from owner")
		ok = false
	if mode.renderer().call("perspective_player_id") != 1:
		push_error("renderer perspective should follow active player")
		ok = false
	_free_mode(mode)
	return ok


func _test_uses_authored_cockpit_shell() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	var cockpit: Control = mode.find_child("DevPlayCockpit", true, false) as Control
	if cockpit == null:
		push_error("dev play should instantiate the authored DevPlayCockpit scene")
		_free_mode(mode)
		return false
	var ok := true
	if cockpit.scene_file_path != DEV_PLAY_COCKPIT_SCENE_PATH:
		push_error(
			(
				"cockpit should come from %s, got %s"
				% [DEV_PLAY_COCKPIT_SCENE_PATH, cockpit.scene_file_path]
			)
		)
		ok = false
	for expected in ["P1", "Turn 0", "Minerals", "Gas", "Pop"]:
		if _find_label_with_substring(cockpit, expected) == null:
			push_error("cockpit should show '%s' in its player-facing HUD" % expected)
			ok = false
	for hidden_text in ["P0", "Queued", "Planning"]:
		if _find_label_with_substring(cockpit, hidden_text) != null:
			push_error("cockpit should not show default debug label '%s'" % hidden_text)
			ok = false
	if _find_button_with_substring(cockpit, "Resolve") == null:
		push_error("cockpit should expose Resolve as a player-facing command")
		ok = false
	if _find_check_box_with_substring(cockpit, "All Orders") == null:
		push_error("cockpit should expose an all-orders toggle")
		ok = false
	var top_bar: PanelContainer = cockpit.get_node_or_null("TopBar") as PanelContainer
	if top_bar == null:
		push_error("cockpit should have a TopBar")
		ok = false
	elif top_bar.offset_left != 0.0 or top_bar.offset_top != 0.0 or top_bar.offset_right != 0.0:
		push_error("top bar should be full-width and flush to the top edge, got %s" % top_bar)
		ok = false
	var bottom_deck: PanelContainer = cockpit.get_node_or_null("BottomDeck") as PanelContainer
	if bottom_deck == null or not bottom_deck.has_theme_stylebox_override("panel"):
		push_error("bottom deck should use the authored RTS console panel style")
		ok = false
	elif (
		bottom_deck.offset_left != 0.0
		or bottom_deck.offset_right != 0.0
		or bottom_deck.offset_bottom != 0.0
	):
		push_error("bottom deck should be full-width and flush to the bottom edge")
		ok = false
	if cockpit.find_child("CommandGrid", true, false) == null:
		push_error("cockpit should organize actions in a stable command grid")
		ok = false
	var command_panel: PanelContainer = (
		cockpit.get_node_or_null("BottomDeck/Row/CommandPanel") as PanelContainer
	)
	var build_panel: PanelContainer = (
		cockpit.get_node_or_null("BottomDeck/Row/BuildPanel") as PanelContainer
	)
	if command_panel == null:
		push_error("cockpit should keep primary commands in their own panel")
		ok = false
	if build_panel == null:
		push_error("cockpit should split build options into a separate right-hand panel")
		ok = false
	elif command_panel != null and build_panel.get_index() <= command_panel.get_index():
		push_error("build panel should sit to the right of the command panel")
		ok = false
	if cockpit.get_node_or_null("BottomDeck/Row/CommandPanel/Stack/OptionColumns") != null:
		push_error("build options should not live inside the command panel")
		ok = false
	if cockpit.get_node_or_null("BottomDeck/Row/BuildPanel/Stack/BuildScroll") != null:
		push_error("build panel should avoid scrollbars by showing all options in its own box")
		ok = false
	if cockpit.get_node_or_null("BottomDeck/Row/BuildPanel/Stack/OptionColumns") == null:
		push_error("build panel should lay out option columns directly in the visible build box")
		ok = false
	for section_name in ["Build", "Train", "Research", "Abilities"]:
		var button_grid: GridContainer = (
			cockpit.get_node_or_null(
				"BottomDeck/Row/BuildPanel/Stack/OptionColumns/%s/Buttons" % section_name
			)
			as GridContainer
		)
		if button_grid == null or button_grid.columns != 2:
			push_error("%s options should use a compact two-column button grid" % section_name)
			ok = false
	if (
		cockpit.get_node_or_null("BottomDeck/Row/CommandPanel/Stack/CommandGrid/RepeatTrain")
		!= null
	):
		push_error("repeat train should not live in the primary command grid")
		ok = false
	var unit_cancel_button: Button = (
		cockpit.get_node_or_null("BottomDeck/Row/CommandPanel/Stack/CommandGrid/Cancel") as Button
	)
	if unit_cancel_button == null:
		push_error("unit cancel should live in the primary command grid")
		ok = false
	var build_cancel_button: Button = (
		cockpit.get_node_or_null("BottomDeck/Row/BuildPanel/Stack/ProductionControls/Cancel")
		as Button
	)
	if build_cancel_button == null:
		push_error("cancel training should live in the build command box")
		ok = false
	var repeat_train_toggle: CheckBox = (
		cockpit.get_node_or_null("BottomDeck/Row/BuildPanel/Stack/ProductionControls/RepeatTrain")
		as CheckBox
	)
	if repeat_train_toggle == null:
		push_error("repeat train should live in the build command box")
		ok = false
	else:
		var empty_options: Array[Dictionary] = []
		cockpit.call(
			"set_command_state",
			"Producer",
			false,
			false,
			false,
			empty_options,
			empty_options,
			empty_options,
			empty_options,
			false,
			true,
			true
		)
		if not build_panel.visible or command_panel.visible:
			push_error("repeat train alone should show the build box without the command box")
			ok = false
		if not repeat_train_toggle.visible or not repeat_train_toggle.button_pressed:
			push_error("repeat train should be visible and stateful inside the build box")
			ok = false
		if (
			not repeat_train_toggle.has_theme_stylebox_override("normal")
			or not repeat_train_toggle.has_theme_stylebox_override("hover")
			or not repeat_train_toggle.has_theme_stylebox_override("pressed")
		):
			push_error("repeat train should keep an explicit dark background while hovering")
			ok = false
	if build_cancel_button != null:
		var empty_options: Array[Dictionary] = []
		cockpit.call(
			"set_command_state",
			"Producer",
			false,
			false,
			false,
			empty_options,
			empty_options,
			empty_options,
			empty_options,
			true,
			false,
			false
		)
		if not build_panel.visible or command_panel.visible:
			push_error("cancel training alone should show the build box without the command box")
			ok = false
		if not build_cancel_button.visible:
			push_error("cancel training should be visible inside the build box")
			ok = false
		if unit_cancel_button != null and unit_cancel_button.visible:
			push_error("unit cancel should stay hidden for production cancellation")
			ok = false
	var resolve_button: Button = _find_exact_button(cockpit, "Resolve")
	if resolve_button == null or not resolve_button.has_theme_stylebox_override("normal"):
		push_error("Resolve should use an authored amber command style")
		ok = false
	for cluster_path in [
		"TopBar/Row/MineralsCluster/Value",
		"TopBar/Row/GasCluster/Value",
		"TopBar/Row/SupplyCluster/Value",
	]:
		if cockpit.get_node_or_null(cluster_path) == null:
			push_error("cockpit top bar should expose %s" % cluster_path)
			ok = false
	_free_mode(mode)
	return ok


func _make_cockpit() -> Control:
	var scene: PackedScene = load(DEV_PLAY_COCKPIT_SCENE_PATH) as PackedScene
	if scene == null:
		push_error("could not load the cockpit scene")
		return null
	var cockpit: Control = scene.instantiate() as Control
	if cockpit == null:
		push_error("cockpit scene root should be a Control")
		return null
	add_child(cockpit)
	# Headless runners drive tests from SceneTree._init, before deferred
	# _ready notifications run; feed an initial state the way play modes do
	# so the cockpit resolves its nodes and applies the token theme.
	cockpit.call("set_match_state", 0, 0, 0, 0, 0, 0, false, -1)
	return cockpit


func _test_cockpit_styles_derive_from_ui_tokens() -> bool:
	var cockpit: Control = _make_cockpit()
	if cockpit == null:
		return false
	var ok := true
	var ramp: Array[int] = [
		UiTokens.FONT_CAPTION,
		UiTokens.FONT_BODY,
		UiTokens.FONT_EMPHASIS,
		UiTokens.FONT_TITLE,
		UiTokens.FONT_DISPLAY,
	]
	for label in cockpit.find_children("*", "Label", true, false):
		var typed_label: Label = label as Label
		var size: int = typed_label.get_theme_font_size("font_size")
		if not ramp.has(size):
			push_error("label '%s' font size %d is off the token ramp" % [typed_label.name, size])
			ok = false
	var top_style: StyleBoxFlat = (
		(cockpit.get_node("TopBar") as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
	)
	if top_style == null or top_style.bg_color != UiTokens.COLOR_BG:
		push_error("top bar panel should use the UiTokens raised surface")
		ok = false
	var selection_style: StyleBoxFlat = (
		(cockpit.get_node("BottomDeck/Row/SelectionPanel") as PanelContainer).get_theme_stylebox(
			"panel"
		)
		as StyleBoxFlat
	)
	if selection_style == null or selection_style.bg_color != UiTokens.COLOR_SURFACE:
		push_error("inner panels should use the UiTokens surface color")
		ok = false
	var resolve_button: Button = _find_exact_button(cockpit, "Resolve")
	if resolve_button == null:
		push_error("resolve button should exist in cockpit shell")
		ok = false
	else:
		var resolve_style: StyleBoxFlat = (
			resolve_button.get_theme_stylebox("normal") as StyleBoxFlat
		)
		if resolve_style == null or resolve_style.bg_color != UiTokens.COLOR_AMBER:
			push_error("resolve button should use the UiTokens amber role")
			ok = false
	_free_mode(cockpit)
	return ok


func _test_cockpit_economy_state_renders_income_and_committed() -> bool:
	var cockpit: Control = _make_cockpit()
	if cockpit == null:
		return false
	var ok := true
	cockpit.call("set_match_state", 0, 3, 120, 40, 8, 20, false, -1)
	(
		cockpit
		. call(
			"set_economy_state",
			{
				"income_minerals": 18,
				"income_gas": 4,
				"income_known": true,
				"committed_minerals": 50,
				"committed_gas": 25,
				"committed_pop": 2,
			}
		)
	)
	var checks: Dictionary = {
		"TopBar/Row/MineralsCluster/Value": "120",
		"TopBar/Row/MineralsCluster/Income": "+18/turn",
		"TopBar/Row/MineralsCluster/Committed": "-50",
		"TopBar/Row/GasCluster/Value": "40",
		"TopBar/Row/GasCluster/Income": "+4/turn",
		"TopBar/Row/GasCluster/Committed": "-25",
		"TopBar/Row/SupplyCluster/Value": "8/20",
		"TopBar/Row/SupplyCluster/Committed": "+2",
	}
	for path: String in checks:
		var label: Label = cockpit.get_node_or_null(path) as Label
		if label == null or not label.visible or label.text != checks[path]:
			push_error(
				(
					"economy label %s should show '%s', got '%s'"
					% [path, checks[path], label.text if label != null else "<missing>"]
				)
			)
			ok = false
	cockpit.call("set_economy_state", {})
	for path in [
		"TopBar/Row/MineralsCluster/Income",
		"TopBar/Row/MineralsCluster/Committed",
		"TopBar/Row/SupplyCluster/Committed",
	]:
		var label: Label = cockpit.get_node_or_null(path) as Label
		if label != null and label.visible:
			push_error("economy label %s should hide when no economy data is reported" % path)
			ok = false
	_free_mode(cockpit)
	return ok


func _test_cockpit_selection_stats_renders_hp_bar_statuses_and_preview() -> bool:
	var cockpit: Control = _make_cockpit()
	if cockpit == null:
		return false
	var ok := true
	(
		cockpit
		. call(
			"set_selection_stats",
			{
				"hp": 9,
				"hp_max": 45,
				"damage": 18,
				"range": 5,
				"speed": 3,
				"statuses": [{"id": "sieged", "duration": -1}, {"id": "slowed", "duration": 2}],
				"worker_state": "Gathering minerals",
				"damage_preview": {"target_label": "Tank", "amount": 18},
			}
		)
	)
	var stats_block: Control = cockpit.find_child("StatsBlock", true, false) as Control
	if stats_block == null or not stats_block.visible:
		push_error("stats block should show for a populated selection")
		ok = false
	var hp_bar: ProgressBar = cockpit.find_child("HpBar", true, false) as ProgressBar
	if hp_bar == null or hp_bar.max_value != 45.0 or hp_bar.value != 9.0:
		push_error("hp bar should reflect hp/hp_max")
		ok = false
	else:
		var fill: StyleBoxFlat = hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill == null or fill.bg_color != UiTokens.COLOR_HP_LOW:
			push_error("hp bar fill should use the low-HP token color at 20%")
			ok = false
	if _find_label_with_substring(cockpit, "9/45") == null:
		push_error("hp caption should show current/max")
		ok = false
	var stat_row: Label = cockpit.find_child("StatRow", true, false) as Label
	if stat_row == null or not stat_row.visible:
		push_error("stat row should be visible")
		ok = false
	else:
		for needle in ["DMG 18", "RNG 5", "SPD 3"]:
			if not stat_row.text.contains(needle):
				push_error("stat row should contain '%s', got '%s'" % [needle, stat_row.text])
				ok = false
	if _find_label_with_substring(cockpit, "SIEGED ∞") == null:
		push_error("indefinite statuses should render with the infinity duration")
		ok = false
	if _find_label_with_substring(cockpit, "SLOWED 2") == null:
		push_error("finite statuses should render their remaining turns")
		ok = false
	if _find_label_with_substring(cockpit, "Gathering minerals") == null:
		push_error("worker state should surface in the context row")
		ok = false
	var preview_row: Label = cockpit.find_child("PreviewRow", true, false) as Label
	if (
		preview_row == null
		or not preview_row.visible
		or not preview_row.text.contains("18")
		or not preview_row.text.contains("Tank")
	):
		push_error("damage preview should show amount and target")
		ok = false
	cockpit.call("set_selection_stats", {})
	if stats_block != null and stats_block.visible:
		push_error("stats block should hide for an empty selection")
		ok = false
	_free_mode(cockpit)
	return ok


func _test_cockpit_production_state_builds_chips_with_cancel_indices() -> bool:
	var cockpit: Control = _make_cockpit()
	if cockpit == null:
		return false
	var ok := true
	var captured: Array[int] = []
	cockpit.connect("cancel_requested", func(index: int) -> void: captured.append(index))
	(
		cockpit
		. call(
			"set_production_state",
			{
				"visible": true,
				"active": {"label": "Marine", "turns_remaining": 1, "total_turns": 2},
				"queue": [{"label": "Marine"}, {"label": "Tank"}],
				"pending": [{"label": "Helicopter"}],
				"pending_cancel_indices": [],
			}
		)
	)
	var strip: Control = cockpit.find_child("ProductionStrip", true, false) as Control
	var items: Control = cockpit.find_child("Items", true, false) as Control
	if strip == null or not strip.visible or items == null or items.get_child_count() != 4:
		push_error("production strip should show active + 2 queue + 1 pending chips")
		ok = false
		_free_mode(cockpit)
		return ok
	var progress: ProgressBar = items.find_children("*", "ProgressBar", true, false).front()
	if progress == null or progress.max_value != 2.0 or progress.value != 1.0:
		push_error("active chip should show production progress (1 of 2 turns elapsed)")
		ok = false
	var cancel_buttons: Array[Node] = items.find_children("*", "Button", true, false)
	if cancel_buttons.size() != 3:
		push_error("only active + queue chips should expose cancel buttons")
		ok = false
	else:
		for button in cancel_buttons:
			(button as Button).pressed.emit()
		if captured != [0, 1, 2]:
			push_error("cancel buttons should emit resolver cancel indices, got %s" % [captured])
			ok = false
	(
		cockpit
		. call(
			"set_production_state",
			{
				"visible": true,
				"active": {"label": "Marine", "turns_remaining": 1, "total_turns": 2},
				"queue": [{"label": "Marine"}, {"label": "Tank"}],
				"pending": [],
				"pending_cancel_indices": [2],
			}
		)
	)
	var refreshed_buttons: Array[Node] = items.find_children("*", "Button", true, false)
	var disabled_count: int = 0
	for button in refreshed_buttons:
		if (button as Button).disabled:
			disabled_count += 1
	if disabled_count != 1:
		push_error("a pending cancel should disable exactly its own chip button")
		ok = false
	cockpit.call("set_production_state", {"visible": false})
	if strip.visible:
		push_error("production strip should hide when not visible")
		ok = false
	_free_mode(cockpit)
	return ok


func _test_top_bar_shows_income_and_committed_spend() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var cockpit: Control = mode.find_child("DevPlayCockpit", true, false) as Control
	var income_label: Label = cockpit.get_node_or_null("TopBar/Row/MineralsCluster/Income") as Label
	var committed_label: Label = (
		cockpit.get_node_or_null("TopBar/Row/MineralsCluster/Committed") as Label
	)
	if income_label == null or committed_label == null:
		push_error("cockpit top bar should expose minerals income and committed labels")
		_free_mode(mode)
		return false
	var ok := true
	if income_label.visible:
		push_error("income should stay hidden before the first resolve")
		ok = false
	mode.current_state().get_player(0).minerals = 500
	var base_id: int = _find_entity_id(mode.current_state(), "base", 0)
	if base_id < 0 or not mode.select_entity_id(base_id):
		push_error("expected a selectable P0 base")
		_free_mode(mode)
		return false
	if not mode.issue_train_selected("worker"):
		push_error("expected a worker train order to queue")
		_free_mode(mode)
		return false
	mode.call("_update_hud")
	var registry: EntityRegistry = _load_registry()
	var worker_def: EntityDef = registry.get_by_id("worker") if registry != null else null
	var worker_cost: int = (
		worker_def.construction.mineral_cost
		if worker_def != null and worker_def.construction != null
		else 0
	)
	if worker_cost <= 0:
		push_error("MVP worker def should carry a mineral cost for this test")
		ok = false
	elif not committed_label.visible or committed_label.text != "-%d" % worker_cost:
		push_error(
			(
				"committed label should show the queued worker cost -%d, got '%s' (visible=%s)"
				% [worker_cost, committed_label.text, committed_label.visible]
			)
		)
		ok = false
	mode.resolve_turn()
	if not income_label.visible or not income_label.text.begins_with("+"):
		push_error(
			(
				"income label should report last-resolve income, got '%s' (visible=%s)"
				% [income_label.text, income_label.visible]
			)
		)
		ok = false
	_free_mode(mode)
	return ok


func _test_selection_panel_shows_effective_stats_statuses_and_hp() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var marine_id: int = _find_entity_id(mode.current_state(), "marine", 0)
	var marine: Entity = mode.current_state().get_entity_by_id(marine_id)
	if marine == null:
		push_error("expected a P0 marine in the combat scenario")
		_free_mode(mode)
		return false
	marine.current_hp = 10
	var template := StatusEffect.new()
	template.status_id = "sieged"
	template.duration_turns = StatusEffect.INDEFINITE
	template.damage_override = 99
	var events: Array[ResolverEvent] = []
	StatusSystem.apply_status(marine, template, events)
	var ok := true
	if not mode.select_entity_id(marine_id):
		push_error("expected to select the marine")
		ok = false
	mode.call("_update_hud")
	var cockpit: Control = mode.find_child("DevPlayCockpit", true, false) as Control
	var stat_row: Label = cockpit.find_child("StatRow", true, false) as Label
	if stat_row == null or not stat_row.visible or not stat_row.text.contains("DMG 99"):
		push_error(
			(
				"stat row should show status-modified effective damage, got '%s'"
				% (stat_row.text if stat_row != null else "<missing>")
			)
		)
		ok = false
	var registry: EntityRegistry = _load_registry()
	var marine_max_hp: int = registry.get_by_id("marine").health.max_hp
	var hp_bar: ProgressBar = cockpit.find_child("HpBar", true, false) as ProgressBar
	if hp_bar == null or hp_bar.value != 10.0 or hp_bar.max_value != float(marine_max_hp):
		push_error("selection hp bar should reflect the unit's current/max hp")
		ok = false
	if _find_label_with_substring(cockpit, "SIEGED ∞") == null:
		push_error("indefinite statuses should show as chips with the infinity marker")
		ok = false
	_free_mode(mode)
	return ok


func _test_selection_panel_shows_worker_state_and_occupancy() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	var patch_id: int = _find_entity_id_any_hp(mode.current_state(), "mineral_patch", -1)
	var worker: Entity = mode.current_state().get_entity_by_id(worker_id)
	var patch: Entity = mode.current_state().get_entity_by_id(patch_id)
	if worker == null or worker.gather_state == null or patch == null:
		push_error("expected an MVP worker with gather state and a mineral patch")
		_free_mode(mode)
		return false
	worker.gather_state.phase = GatherState.Phase.GATHERING
	worker.gather_state.assigned_source_entity_id = patch_id
	var ok := true
	if not mode.select_entity_id(worker_id):
		push_error("expected to select the worker")
		ok = false
	mode.call("_update_hud")
	var cockpit: Control = mode.find_child("DevPlayCockpit", true, false) as Control
	var context_row: Label = cockpit.find_child("ContextRow", true, false) as Label
	if context_row == null or not context_row.visible or context_row.text != "Gathering minerals":
		push_error(
			(
				"a gathering worker should show its state, got '%s'"
				% (context_row.text if context_row != null else "<missing>")
			)
		)
		ok = false
	if not mode.select_entity_id(patch_id):
		push_error("expected the mineral patch to be selectable")
		ok = false
	mode.call("_update_hud")
	var registry: EntityRegistry = _load_registry()
	var cap: int = registry.get_by_id("mineral_patch").resource_source.max_gatherers
	var expected: String = "Workers 1/%d" % cap
	if context_row == null or not context_row.visible or context_row.text != expected:
		push_error(
			(
				"a selected source should show gatherer occupancy '%s', got '%s'"
				% [expected, context_row.text if context_row != null else "<missing>"]
			)
		)
		ok = false
	_free_mode(mode)
	return ok


func _test_damage_preview_for_ordered_target() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var state: MatchState = mode.current_state()
	var marine_id: int = _find_entity_id(state, "marine", 0)
	var tank_id: int = _find_entity_id(state, "tank", 1)
	if marine_id < 0 or tank_id < 0:
		push_error("expected a P0 marine and a P1 tank")
		_free_mode(mode)
		return false
	if (
		not _move_entity_to(state, marine_id, Vector2i(6, 11))
		or not _move_entity_to(state, tank_id, Vector2i(10, 11))
	):
		_free_mode(mode)
		return false
	mode.renderer().bind_state(state, _load_registry())
	var ok := true
	if not mode.select_entity_id(marine_id):
		push_error("expected to select the marine")
		ok = false
	if not mode.issue_attack_selected(tank_id):
		push_error("expected the attack order to queue: %s" % mode.input_model().status_message())
		ok = false
	mode.call("_update_hud")
	var registry: EntityRegistry = _load_registry()
	var marine: Entity = state.get_entity_by_id(marine_id)
	var tank: Entity = state.get_entity_by_id(tank_id)
	var expected_damage: int = CombatSystem.preview_damage(marine, tank, registry)
	if expected_damage <= 0:
		push_error("marine vs tank preview damage should be positive")
		ok = false
	var cockpit: Control = mode.find_child("DevPlayCockpit", true, false) as Control
	var preview_row: Label = cockpit.find_child("PreviewRow", true, false) as Label
	if (
		preview_row == null
		or not preview_row.visible
		or not preview_row.text.contains("%d dmg" % expected_damage)
		or not preview_row.text.contains("Tank")
	):
		push_error(
			(
				"damage preview should show '%d dmg vs Tank', got '%s'"
				% [expected_damage, preview_row.text if preview_row != null else "<missing>"]
			)
		)
		ok = false
	_free_mode(mode)
	return ok


func _test_move_and_gather_hotkeys_begin_pending_commands() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected to select a P0 worker")
		_free_mode(mode)
		return false
	var controller: MatchSessionController = mode.get("_controller") as MatchSessionController
	var ok := true
	mode.call("_unhandled_input", _key_press(KEY_M))
	if mode.pending_command_kind() != "move":
		push_error("M should begin a pending move command")
		ok = false
	controller.cancel_pending_command()
	mode.select_entity_id(worker_id)
	mode.call("_unhandled_input", _key_press(KEY_G))
	if mode.pending_command_kind() != "gather":
		push_error("G should begin a pending gather command")
		ok = false
	controller.cancel_pending_command()
	mode.select_entity_id(worker_id)
	var alted: InputEventKey = _key_press(KEY_M)
	alted.alt_pressed = true
	mode.call("_unhandled_input", alted)
	if mode.pending_command_kind() == "move":
		push_error("Alt-modified keys must not trigger command hotkeys")
		ok = false
	_free_mode(mode)
	return ok


func _test_production_strip_lists_items_and_cancels_by_index() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var base_id: int = _find_entity_id(mode.current_state(), "base", 0)
	var base: Entity = mode.current_state().get_entity_by_id(base_id)
	if base == null or base.production_state == null:
		push_error("expected a P0 base producer")
		_free_mode(mode)
		return false
	base.production_state.active = {
		ProductionState.KEY_DEF_ID: "worker",
		ProductionState.KEY_KIND: ProductionState.KIND_UNIT,
		ProductionState.KEY_TURNS_REMAINING: 1,
		ProductionState.KEY_PAID_MINERALS: 50,
		ProductionState.KEY_PAID_GAS: 0,
		ProductionState.KEY_PAID_POP: 1,
	}
	base.production_state.queue = [
		{
			ProductionState.KEY_DEF_ID: "worker",
			ProductionState.KEY_KIND: ProductionState.KIND_UNIT,
		},
		{
			ProductionState.KEY_DEF_ID: "worker",
			ProductionState.KEY_KIND: ProductionState.KIND_UNIT,
		},
	]
	var ok := true
	if not mode.select_entity_id(base_id):
		push_error("expected to select the base")
		ok = false
	mode.call("_update_hud")
	var cockpit: Control = mode.find_child("DevPlayCockpit", true, false) as Control
	var strip: Control = cockpit.find_child("ProductionStrip", true, false) as Control
	var items: Control = cockpit.find_child("Items", true, false) as Control
	if strip == null or not strip.visible or items == null or items.get_child_count() != 3:
		push_error(
			(
				"production strip should show active + 2 queue chips, got %d"
				% (items.get_child_count() if items != null else -1)
			)
		)
		_free_mode(mode)
		return false
	var worker_label: String = mode.input_model().label_for_entity_def_id("worker")
	if _find_label_with_substring(items, worker_label) == null:
		push_error("production chips should use the def display label '%s'" % worker_label)
		ok = false
	var cancel_buttons: Array[Node] = items.find_children("*", "Button", true, false)
	if cancel_buttons.size() != 3:
		push_error("active + queue chips should expose 3 cancel buttons")
		_free_mode(mode)
		return false
	(cancel_buttons[2] as Button).pressed.emit()
	var found_cancel: bool = false
	for order: EntityOrder in mode.input_model().submit_for_player(0).orders:
		if (
			order != null
			and order.type == EntityOrder.Type.CANCEL
			and order.entity_id == base_id
			and order.cancel_index == 2
		):
			found_cancel = true
	if not found_cancel:
		push_error("pressing the second queue chip cancel should queue CANCEL index 2")
		ok = false
	mode.call("_update_hud")
	var disabled_count: int = 0
	for button in items.find_children("*", "Button", true, false):
		if (button as Button).disabled:
			disabled_count += 1
	if disabled_count != 1:
		push_error("the pending cancel should dim exactly its own chip, got %d" % disabled_count)
		ok = false
	mode.current_state().get_player(0).minerals = 500
	if not mode.issue_train_selected("worker"):
		push_error("expected a fresh train order to queue")
		ok = false
	mode.call("_update_hud")
	if items.get_child_count() != 4:
		push_error("a this-turn train order should add a pending chip")
		ok = false
	if items.find_children("*", "Button", true, false).size() != 3:
		push_error("pending chips must not offer cancel before the order resolves")
		ok = false
	_free_mode(mode)
	return ok


func _test_idle_worker_button_cycles_selection() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var worker_ids: Array[int] = _find_entity_ids(mode.current_state(), "worker", 0)
	if worker_ids.size() < 2:
		push_error("expected at least two P0 workers in the MVP scenario")
		_free_mode(mode)
		return false
	for worker_id in [worker_ids[0], worker_ids[1]]:
		var worker: Entity = mode.current_state().get_entity_by_id(worker_id)
		worker.gather_state.phase = GatherState.Phase.IDLE
		worker.gather_state.assigned_source_entity_id = -1
	mode.input_model().clear_submissions()
	mode.call("_update_hud")
	var controller: MatchSessionController = mode.get("_controller") as MatchSessionController
	var idle_ids: Array[int] = controller.active_idle_worker_ids()
	if idle_ids.size() < 2:
		push_error("expected at least two idle workers after forcing idle state")
		_free_mode(mode)
		return false
	var ok := true
	var cockpit: Control = mode.find_child("DevPlayCockpit", true, false) as Control
	var idle_button: Button = cockpit.find_child("IdleWorkers", true, false) as Button
	if idle_button == null or not idle_button.visible:
		push_error("idle workers button should be visible with idle workers present")
		ok = false
	elif idle_button.text != "Idle %d" % idle_ids.size():
		push_error("idle workers button should show the count, got '%s'" % idle_button.text)
		ok = false
	if not mode.select_next_idle_worker():
		push_error("idle cycle should select an idle worker")
		ok = false
	if mode.input_model().selected_entity_id() != idle_ids[0]:
		push_error("first cycle should select the lowest idle worker id")
		ok = false
	if not mode.select_next_idle_worker():
		push_error("idle cycle should keep cycling")
		ok = false
	if mode.input_model().selected_entity_id() != idle_ids[1]:
		push_error("second cycle should select the next idle worker id")
		ok = false
	_free_mode(mode)
	return ok


func _test_cockpit_idle_worker_button_visibility_and_signal() -> bool:
	var cockpit: Control = _make_cockpit()
	if cockpit == null:
		return false
	var ok := true
	var presses: Array[int] = []
	cockpit.connect("idle_workers_requested", func() -> void: presses.append(1))
	var idle_button: Button = cockpit.find_child("IdleWorkers", true, false) as Button
	cockpit.call("set_idle_worker_state", 0)
	if idle_button == null or idle_button.visible:
		push_error("idle worker button should hide at zero idle workers")
		ok = false
	cockpit.call("set_idle_worker_state", 3)
	if idle_button == null or not idle_button.visible or idle_button.text != "Idle 3":
		push_error("idle worker button should show the idle count")
		ok = false
	if idle_button != null:
		idle_button.pressed.emit()
	if presses.size() != 1:
		push_error("pressing the idle worker button should emit idle_workers_requested")
		ok = false
	_free_mode(cockpit)
	return ok


func _test_hud_stays_inside_window_and_camera_uses_safe_area() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	var cockpit: Control = mode.find_child("DevPlayCockpit", true, false) as Control
	var renderer: MatchRenderer = mode.renderer()
	var camera: Camera2D = (
		renderer.get_node_or_null("Camera2D") as Camera2D if renderer != null else null
	)
	if cockpit == null or renderer == null or camera == null:
		push_error("test setup expected cockpit, renderer, and camera")
		_free_mode(mode)
		return false
	var ok := true
	var viewport_size: Vector2 = _logical_viewport_size()
	var top_bar: Control = cockpit.get_node_or_null("TopBar") as Control
	var bottom_deck: Control = cockpit.get_node_or_null("BottomDeck") as Control
	if top_bar == null or bottom_deck == null:
		push_error("cockpit should have top and bottom HUD bands")
		ok = false
	else:
		var top_height: float = top_bar.offset_bottom - top_bar.offset_top
		if top_bar.offset_top != 0.0 or top_height <= 0.0:
			push_error("top bar should occupy only its required top strip, got %s" % top_bar)
			ok = false
		var deck_top: float = viewport_size.y + bottom_deck.offset_top
		var deck_bottom: float = viewport_size.y + bottom_deck.offset_bottom
		if deck_top < 0.0 or deck_bottom != viewport_size.y or deck_bottom <= deck_top:
			push_error(
				(
					"bottom deck should occupy only its required bottom strip, top=%s bottom=%s viewport=%s"
					% [deck_top, deck_bottom, viewport_size.y]
				)
			)
			ok = false
		var deck_height: float = deck_bottom - deck_top
		if deck_height < 188.0:
			push_error("bottom deck should keep stable console height, got %s" % deck_height)
			ok = false
		if deck_height > 190.0:
			push_error("bottom deck should keep the previous compact height, got %s" % deck_height)
			ok = false
		if not bottom_deck.clip_contents:
			push_error("bottom deck should clip child content instead of drawing under the window")
			ok = false
		var build_panel: Control = cockpit.get_node_or_null("BottomDeck/Row/BuildPanel") as Control
		if build_panel == null or not build_panel.clip_contents:
			push_error("build panel should clip overflowing build content inside the bottom strip")
			ok = false
	if renderer.get_node_or_null("HUD/CombatLog") != null:
		push_error("legacy renderer CombatLog overlay should not reserve screen space")
		ok = false
	var game_container: SubViewportContainer = (
		mode.find_child("GameViewportContainer", true, false) as SubViewportContainer
	)
	if game_container == null:
		push_error("game renderer should live in a reserved middle viewport container")
		ok = false
	else:
		var top_height: float = (
			top_bar.offset_bottom - top_bar.offset_top if top_bar != null else 46.0
		)
		var reserved_bottom: float = absf(bottom_deck.offset_top) if bottom_deck != null else 190.0
		var expected_height: float = viewport_size.y - top_height - reserved_bottom
		if (
			game_container.position != Vector2(0.0, top_height)
			or game_container.size.x != viewport_size.x
			or absf(game_container.size.y - expected_height) > 1.0
		):
			push_error(
				(
					"game viewport should fill exactly between HUD bands, position=%s size=%s expected_height=%s"
					% [game_container.position, game_container.size, expected_height]
				)
			)
			ok = false
		var renderer_viewport: SubViewport = renderer.get_parent() as SubViewport
		if renderer_viewport == null or renderer_viewport.get_parent() != game_container:
			push_error("renderer should be parented inside the reserved child SubViewport")
			ok = false
		else:
			var renderer_view_size: Vector2 = Vector2(renderer_viewport.size)
			if absf(renderer_view_size.y - expected_height) > 1.0:
				push_error(
					(
						"renderer viewport should match reserved middle height, got %s expected %s"
						% [renderer_view_size.y, expected_height]
					)
				)
				ok = false
	if camera.offset != Vector2.ZERO:
		push_error("camera should not fake HUD layout with screen offset, got %s" % camera.offset)
		ok = false
	_free_mode(mode)
	return ok


func _test_command_card_tracks_selection() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected to select a P0 worker on mvp_map")
		_free_mode(mode)
		return false
	var card: Control = mode.command_card()
	if card == null:
		push_error("expected command card to exist")
		_free_mode(mode)
		return false
	if not _command_card_ids(card, "build_option_ids").has("barracks"):
		push_error("worker command card should expose barracks build option")
		_free_mode(mode)
		return false
	mode.set_active_player_id(1)
	if not _command_card_ids(card, "build_option_ids").is_empty():
		push_error("switching player should refresh command card after selection clears")
		_free_mode(mode)
		return false
	_free_mode(mode)
	return true


func _test_command_card_hides_when_not_actionable() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	var card: Control = mode.command_card()
	if card == null:
		push_error("expected command card to exist")
		_free_mode(mode)
		return false
	var ok: bool = true
	if _command_surface_visible(card):
		push_error("command surface should be hidden while nothing actionable is selected")
		ok = false
	mode.set_active_player_id(0)
	var mineral_id: int = _find_entity_id_any_hp(mode.current_state(), "mineral_patch", -1)
	if mineral_id < 0 or not mode.select_entity_id(mineral_id):
		push_error("mineral patches should be selectable for inspection")
		ok = false
	if _command_surface_visible(card):
		push_error("command surface should stay hidden for a resource selection")
		ok = false
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected to select a P0 worker")
		ok = false
	if not _command_surface_visible(card):
		push_error("command surface should become visible for an actionable worker")
		ok = false
	if _find_label_with_substring(card, "#") != null:
		push_error("command card should not expose debug entity ids")
		ok = false
	_free_mode(mode)
	return ok


func _test_command_card_primary_visibility_tracks_each_command() -> bool:
	var card: Control = _make_command_card()
	if card == null:
		return false
	add_child(card)
	var ok: bool = true
	_set_command_card_state(card, false, false, false, false)
	if card.visible:
		push_error("command card should hide when no command section has visible actions")
		ok = false

	_set_command_card_state(card, true, false, false, false)
	if not _expect_button_visibility(card, "Move (M)", true):
		ok = false
	if not _expect_button_visibility(card, "Gather (G)", false):
		ok = false

	_set_command_card_state(card, true, false, false, false)
	if not _expect_button_visibility(card, "Move (M)", true):
		ok = false

	_set_command_card_state(card, false, false, false, false)
	if not _expect_button_visibility(card, "Move (M)", false):
		ok = false

	_set_command_card_state(card, false, true, true, true)
	for label in ["Attack-move (A)", "Gather (G)", "Cancel"]:
		if not _expect_button_visibility(card, label, true):
			ok = false
	if not _expect_button_visibility(card, "Move (M)", false):
		ok = false
	if not card.visible:
		push_error("command card should show when non-move commands are visible")
		ok = false

	_free_mode(card)
	return ok


func _test_command_card_shows_costs() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var card: Control = mode.command_card()
	if card == null:
		push_error("expected command card")
		_free_mode(mode)
		return false

	var ok: bool = true
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected to select a worker")
		ok = false
	else:
		mode.current_state().get_player(0).minerals = 149
		mode.select_entity_id(worker_id)
		var barracks_button: Button = _find_button_with_substring(card, "Barracks")
		if barracks_button == null:
			push_error("worker command card should show Barracks")
			ok = false
		elif not _button_text_has_all(barracks_button, _entity_cost_parts("barracks")):
			push_error(
				"Barracks button should show mineral cost and build time: %s" % barracks_button.text
			)
			ok = false
		elif not barracks_button.disabled:
			push_error("Barracks button should be disabled until P0 can pay 150M")
			ok = false
		mode.current_state().get_player(0).minerals = 150
		mode.select_entity_id(worker_id)
		barracks_button = _find_button_with_substring(card, "Barracks")
		if barracks_button == null or barracks_button.disabled:
			push_error("Barracks button should enable once P0 can pay 150M")
			ok = false

	var base_id: int = _find_entity_id(mode.current_state(), "base", 0)
	if base_id < 0 or not mode.select_entity_id(base_id):
		push_error("expected to select a base")
		ok = false
	else:
		var worker_button: Button = _find_button_with_substring(card, "Worker")
		if worker_button == null:
			push_error("base command card should show Worker")
			ok = false
		elif not _button_text_has_all(worker_button, _entity_cost_parts("worker")):
			push_error(
				"Worker button should show mineral, pop, and train time: %s" % worker_button.text
			)
			ok = false

	var barracks_id: int = _add_runtime_entity(mode.current_state(), "barracks", 0, Vector2i(16, 2))
	if barracks_id < 0 or not mode.select_entity_id(barracks_id):
		push_error("expected to select injected barracks")
		ok = false
	else:
		var marine_button: Button = _find_button_with_substring(card, "Marine")
		if marine_button == null:
			push_error("barracks command card should show Marine")
			ok = false
		elif not _button_text_has_all(marine_button, _entity_cost_parts("marine")):
			push_error(
				"Marine button should show mineral, pop, and train time: %s" % marine_button.text
			)
			ok = false
		var research_button: Button = _find_button_with_substring(card, "Siege")
		if (
			research_button != null
			and not _button_text_has_all(
				research_button, _research_cost_parts("siege_mode_research")
			)
		):
			push_error(
				(
					"research button should show mineral cost and research time: %s"
					% research_button.text
				)
			)
			ok = false
		var repeat_toggle: CheckBox = _find_check_box_with_substring(card, "Repeat Train")
		if repeat_toggle == null or not repeat_toggle.visible:
			push_error("training producer command card should show Repeat Train")
			ok = false
		else:
			repeat_toggle.emit_signal("toggled", true)
			var barracks: Entity = mode.current_state().get_entity_by_id(barracks_id)
			if barracks == null or not barracks.production_state.repeat_train_enabled:
				push_error("Repeat Train toggle should update selected producer state")
				ok = false

	_free_mode(mode)
	return ok


func _test_worker_gather_command_targets_resource() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	var mineral_id: int = _find_entity_id_any_hp(mode.current_state(), "mineral_patch", -1)
	if worker_id < 0 or mineral_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected worker and mineral on MVP map")
		_free_mode(mode)
		return false
	var card: Control = mode.command_card()
	if card == null or not card.has_signal("gather_requested"):
		push_error("worker command card should expose gather_requested")
		_free_mode(mode)
		return false
	card.emit_signal("gather_requested")
	if mode.pending_command_kind() != "gather":
		push_error("Gather command should enter pending gather mode")
		_free_mode(mode)
		return false
	var mineral: Entity = mode.current_state().get_entity_by_id(mineral_id)
	if mineral == null or not mode.confirm_pending_at_tile(mineral.origin):
		push_error("pending gather should accept a mineral target tile")
		_free_mode(mode)
		return false
	var orders: Array[EntityOrder] = mode.input_model().submit_for_player(0).orders
	var ok := true
	if orders.size() != 1:
		push_error("expected one GATHER order, got %d" % orders.size())
		ok = false
	elif orders[0].type != EntityOrder.Type.GATHER or orders[0].target_entity_id != mineral_id:
		push_error("expected GATHER targeting mineral #%d" % mineral_id)
		ok = false
	if mode.pending_command_kind() != "":
		push_error("successful gather target should clear pending mode")
		ok = false
	_free_mode(mode)
	return ok


func _test_right_click_gather_rejects_raw_gas() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected worker for raw-gas context test")
		_free_mode(mode)
		return false
	var worker: Entity = mode.current_state().get_entity_by_id(worker_id)
	var gas_origin: Vector2i = _find_clear_rect_origin_near(
		mode.current_state(), worker.origin, Vector2i(2, 2)
	)
	var gas_id: int = _add_runtime_entity(mode.current_state(), "gas_geyser", -1, gas_origin)
	if gas_id < 0:
		push_error("expected to add raw gas geyser to MVP map")
		_free_mode(mode)
		return false
	mode.current_state().get_entity_by_id(gas_id).current_resource_amount = 1000
	mode.renderer().bind_state(mode.current_state(), _load_registry())
	mode.renderer().set_perspective_player_id(0)
	var context: Dictionary = mode.context_action_at_tile(gas_origin)
	var ok := true
	if (
		context.get("action", "") != "invalid"
		or context.get("cursor_shape", -1) != Input.CURSOR_FORBIDDEN
	):
		push_error("raw gas without owned refinery should classify as invalid")
		ok = false
	if mode.issue_context_at_tile(gas_origin):
		push_error("right-click raw gas without owned refinery should be rejected")
		ok = false
	if mode.input_model().submit_for_player(0).orders.size() != 0:
		push_error("rejected raw-gas context action should not fall back to movement")
		ok = false
	_free_mode(mode)
	return ok


func _test_producer_right_click_sets_rally() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var base_id: int = _find_entity_id(mode.current_state(), "base", 0)
	var mineral_id: int = _find_entity_id_any_hp(mode.current_state(), "mineral_patch", -1)
	if base_id < 0 or mineral_id < 0 or not mode.select_entity_id(base_id):
		push_error("expected base producer and mineral target")
		_free_mode(mode)
		return false
	var rally_tile: Vector2i = _find_clear_rect_origin_near(
		mode.current_state(), mode.current_state().get_entity_by_id(base_id).origin, Vector2i.ONE
	)
	var ok := true
	if not mode.issue_context_at_tile(rally_tile):
		push_error("producer right-click empty tile should set move rally")
		ok = false
	var base: Entity = mode.current_state().get_entity_by_id(base_id)
	if (
		base == null
		or base.production_state == null
		or base.production_state.rally_mode != ProductionState.RALLY_MODE_MOVE
		or base.production_state.rally_target_tile != rally_tile
	):
		push_error("producer move rally state was not stored")
		ok = false
	var renderer: MatchRenderer = mode.renderer()
	if renderer != null and renderer.action_preview_count() < 1:
		push_error("selected producer rally should render an action preview")
		ok = false
	var mineral: Entity = mode.current_state().get_entity_by_id(mineral_id)
	if not mode.issue_context_at_tile(mineral.origin):
		push_error("producer right-click resource should set gather rally")
		ok = false
	if (
		base.production_state.rally_mode != ProductionState.RALLY_MODE_GATHER
		or base.production_state.rally_target_entity_id != mineral_id
	):
		push_error("producer gather rally state was not stored")
		ok = false
	_free_mode(mode)
	return ok


func _test_affordable_build_interrupts_auto_gather() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	mode.current_state().get_player(0).minerals = 200
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected to select an auto-gathering P0 worker")
		_free_mode(mode)
		return false
	var worker_before: Entity = mode.current_state().get_entity_by_id(worker_id)
	if (
		worker_before.gather_state == null
		or worker_before.gather_state.phase == GatherState.Phase.IDLE
	):
		push_error("setup expected worker to start auto-gathering")
		_free_mode(mode)
		return false
	mode.begin_build("barracks")
	if mode.pending_command_kind() != "build":
		push_error("affordable barracks should enter pending build mode")
		_free_mode(mode)
		return false
	if not mode.confirm_pending_at_tile(Vector2i(16, 12)):
		push_error("affordable build on clear tile should queue BUILD")
		_free_mode(mode)
		return false
	if not mode.resolve_turn():
		push_error("resolve_turn should process queued BUILD")
		_free_mode(mode)
		return false
	var worker_after: Entity = mode.current_state().get_entity_by_id(worker_id)
	if (
		worker_after == null
		or (
			worker_after.locked_to_building_id < 0
			and not ConstructionSystem.has_pending_build(worker_after)
		)
	):
		push_error("BUILD should commit the worker to construction")
		_free_mode(mode)
		return false
	if (
		worker_after.gather_state == null
		or worker_after.gather_state.phase != GatherState.Phase.IDLE
	):
		push_error("BUILD should interrupt auto-gathering")
		_free_mode(mode)
		return false
	if worker_after.gather_state.assigned_source_entity_id != -1:
		push_error("BUILD should clear the prior mineral assignment")
		_free_mode(mode)
		return false
	if worker_after.locked_to_building_id >= 0:
		var building: Entity = mode.current_state().get_entity_by_id(
			worker_after.locked_to_building_id
		)
		if building == null or building.def_id != "barracks" or not building.is_constructing:
			push_error("adjacent BUILD should create a constructing barracks")
			_free_mode(mode)
			return false
	elif worker_after.pending_build_def_id != "barracks":
		push_error("far BUILD should remain pending until the worker reaches the site")
		_free_mode(mode)
		return false
	_free_mode(mode)
	return true


func _test_mvp_worker_builds_refinery() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var player: PlayerState = mode.current_state().get_player(0)
	player.minerals = 10000
	player.gas = 10000
	player.pop_cap = 200
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected to select a P0 worker on mvp_map")
		_free_mode(mode)
		return false
	mode.begin_build("refinery")
	if mode.pending_command_kind() != "build":
		push_error("refinery should enter pending BUILD mode for the selected worker")
		_free_mode(mode)
		return false
	if not mode.confirm_pending_at_tile(Vector2i(6, 23)):
		push_error("expected refinery BUILD to queue on the P0 geyser")
		_free_mode(mode)
		return false
	var queued_orders: Array[EntityOrder] = mode.input_model().submit_for_player(0).orders
	if queued_orders.size() != 1:
		push_error("expected one queued refinery BUILD order, got %d" % queued_orders.size())
		_free_mode(mode)
		return false
	var queued_order: EntityOrder = queued_orders[0]
	if (
		queued_order.type != EntityOrder.Type.BUILD
		or queued_order.def_id != "refinery"
		or queued_order.target_tile != Vector2i(6, 23)
		or queued_order.target_entity_id != -1
	):
		push_error("unexpected queued refinery BUILD order: %s" % str(queued_order))
		_free_mode(mode)
		return false
	if not mode.resolve_turn():
		push_error("expected resolve_turn to succeed after refinery BUILD")
		_free_mode(mode)
		return false
	var refinery_id: int = _find_entity_id(mode.current_state(), "refinery", 0)
	var refinery: Entity = mode.current_state().get_entity_by_id(refinery_id)
	var worker: Entity = mode.current_state().get_entity_by_id(worker_id)
	var geyser_id: int = _find_entity_id(mode.current_state(), "gas_geyser", -1)
	if geyser_id < 0:
		geyser_id = _find_entity_id_any_hp(mode.current_state(), "gas_geyser", -1)
	var geyser: Entity = mode.current_state().get_entity_by_id(geyser_id)
	if refinery == null:
		var worker_summary := "missing worker"
		if worker != null:
			worker_summary = (
				"origin=%s pending=%s pending_tile=%s locked=%d"
				% [
					str(worker.origin),
					worker.pending_build_def_id,
					str(worker.pending_build_target_tile),
					worker.locked_to_building_id,
				]
			)
		push_error(
			(
				"refinery BUILD should create a constructing refinery on the geyser; worker %s"
				% worker_summary
			)
		)
		_free_mode(mode)
		return false
	if worker == null or geyser == null:
		_free_mode(mode)
		return false
	var refinery_rect: Rect2i = mode.current_state().tile_grid.entity_rect(refinery.id)
	var geyser_rect: Rect2i = mode.current_state().tile_grid.entity_rect(geyser.id)
	var worker_rect: Rect2i = mode.current_state().tile_grid.entity_rect(worker.id)
	var ok: bool = true
	if not refinery.is_constructing:
		push_error("refinery should be under construction immediately after the worker arrives")
		ok = false
	if refinery.construction_worker_id != worker.id or worker.locked_to_building_id != refinery.id:
		push_error("worker should be locked to the started refinery")
		ok = false
	if refinery_rect != geyser_rect:
		push_error("refinery rect should overlap the geyser rect")
		ok = false
	if TileGrid.distance_between_rects(worker_rect, refinery_rect) > 1:
		push_error("worker should be adjacent to the refinery after starting construction")
		ok = false
	_free_mode(mode)
	return ok


func _test_selected_and_friendly_action_previews() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	var renderer: MatchRenderer = mode.renderer()
	if renderer == null:
		push_error("expected renderer")
		_free_mode(mode)
		return false
	for method in ["set_action_previews", "action_preview_count"]:
		if not renderer.has_method(method):
			push_error("renderer should expose %s" % method)
			_free_mode(mode)
			return false
	mode.set_active_player_id(0)
	var workers: Array[int] = _find_entity_ids(mode.current_state(), "worker", 0)
	if workers.size() < 2:
		push_error("expected multiple P0 workers on MVP map")
		_free_mode(mode)
		return false
	if not mode.select_entity_id(workers[0]) or not mode.issue_move_selected(Vector2i(13, 22)):
		push_error("expected first worker move preview")
		_free_mode(mode)
		return false
	if renderer.call("action_preview_count") != 1:
		push_error("selected queued action should always show one preview")
		_free_mode(mode)
		return false
	if not mode.select_entity_id(workers[1]) or not mode.issue_move_selected(Vector2i(13, 25)):
		push_error("expected second worker move preview")
		_free_mode(mode)
		return false
	if renderer.call("action_preview_count") != 1:
		push_error("all-friendly previews should be off by default")
		_free_mode(mode)
		return false
	if not mode.has_method("set_show_all_friendly_action_previews"):
		push_error("dev play mode should expose all-friendly preview toggle")
		_free_mode(mode)
		return false
	mode.call("set_show_all_friendly_action_previews", true)
	var expected_previews: int = workers.size()
	if renderer.call("action_preview_count") != expected_previews:
		push_error(
			(
				"all-friendly preview toggle should show one preview per active worker, got %d expected %d"
				% [renderer.call("action_preview_count"), expected_previews]
			)
		)
		_free_mode(mode)
		return false
	_free_mode(mode)
	return true


func _test_idle_worker_indicator_counts_active_idle_workers() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var state: MatchState = mode.current_state()
	_set_all_workers_busy_gathering(state, -1)
	var idle_worker_id: int = _add_idle_worker_for_test(state, 0)
	var opponent_idle_worker_id: int = _add_idle_worker_for_test(state, 1)
	if idle_worker_id < 0 or opponent_idle_worker_id < 0:
		_free_mode(mode)
		return false
	var renderer: MatchRenderer = mode.renderer()
	if renderer == null or not renderer.has_method("idle_worker_indicator_count"):
		push_error("renderer should expose idle_worker_indicator_count")
		_free_mode(mode)
		return false
	renderer.bind_state(state, _load_registry())
	renderer.set_perspective_player_id(0)
	mode.call("_update_hud")
	var label: Label = mode.find_child("IdleWorkers", true, false) as Label
	var ok: bool = true
	if label != null:
		push_error("cockpit HUD should not reintroduce the old IdleWorkers label")
		ok = false
	if renderer.call("idle_worker_indicator_count") != 1:
		push_error("renderer should show one idle worker badge for the active player")
		ok = false
	_free_mode(mode)
	return ok


func _test_idle_worker_indicator_excludes_busy_workers() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var state: MatchState = mode.current_state()
	_set_all_workers_busy_gathering(state, -1)
	var gathering_id: int = _add_idle_worker_for_test(state, 0)
	var queued_id: int = _add_idle_worker_for_test(state, 0)
	var future_id: int = _add_idle_worker_for_test(state, 0)
	var assist_id: int = _add_idle_worker_for_test(state, 0)
	var pending_build_id: int = _add_idle_worker_for_test(state, 0)
	var locked_id: int = _add_idle_worker_for_test(state, 0)
	var ability_id: int = _add_idle_worker_for_test(state, 0)
	var ids: Array[int] = [
		gathering_id,
		queued_id,
		future_id,
		assist_id,
		pending_build_id,
		locked_id,
		ability_id,
	]
	for entity_id: int in ids:
		if entity_id < 0:
			_free_mode(mode)
			return false
	var gathering_worker: Entity = state.get_entity_by_id(gathering_id)
	gathering_worker.gather_state.phase = GatherState.Phase.GATHERING
	var input: DevTurnInput = mode.input_model()
	input.clear_submissions()
	input.submit_for_player(0).orders.append(_move_order_for_worker(state, queued_id))
	var snapshot: DevInputSnapshot = input.create_snapshot()
	snapshot.future_orders = {future_id: [_move_order_for_worker(state, future_id)]}
	snapshot.move_assists = {assist_id: _move_order_for_worker(state, assist_id)}
	input.restore_snapshot(snapshot, state, _load_registry())
	var pending_worker: Entity = state.get_entity_by_id(pending_build_id)
	pending_worker.pending_build_def_id = "barracks"
	var locked_worker: Entity = state.get_entity_by_id(locked_id)
	locked_worker.locked_to_building_id = 42
	var ability_worker: Entity = state.get_entity_by_id(ability_id)
	ability_worker.ability_cast = AbilityCastState.new()
	ability_worker.ability_cast.ability_id = "surge"
	ability_worker.ability_cast.turns_remaining = 1
	var renderer: MatchRenderer = mode.renderer()
	if renderer == null or not renderer.has_method("idle_worker_indicator_count"):
		push_error("renderer should expose idle_worker_indicator_count")
		_free_mode(mode)
		return false
	renderer.bind_state(state, _load_registry())
	renderer.set_perspective_player_id(0)
	mode.call("_update_hud")
	var label: Label = mode.find_child("IdleWorkers", true, false) as Label
	var ok: bool = true
	if label != null:
		push_error("cockpit HUD should not reintroduce the old IdleWorkers label")
		ok = false
	if renderer.call("idle_worker_indicator_count") != 0:
		push_error("busy active workers should not receive idle worker badges")
		ok = false
	_free_mode(mode)
	return ok


func _test_cockpit_all_orders_toggle_routes() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	var renderer: MatchRenderer = mode.renderer()
	var cockpit: Control = mode.find_child("DevPlayCockpit", true, false) as Control
	if renderer == null or cockpit == null:
		push_error("expected renderer and cockpit")
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var workers: Array[int] = _find_entity_ids(mode.current_state(), "worker", 0)
	if workers.size() < 2:
		push_error("expected multiple P0 workers")
		_free_mode(mode)
		return false
	if not mode.select_entity_id(workers[0]) or not mode.issue_move_selected(Vector2i(13, 22)):
		push_error("expected first worker move preview")
		_free_mode(mode)
		return false
	if not mode.select_entity_id(workers[1]) or not mode.issue_move_selected(Vector2i(13, 25)):
		push_error("expected second worker move preview")
		_free_mode(mode)
		return false
	var toggle: CheckBox = _find_check_box_with_substring(cockpit, "All Orders")
	if toggle == null:
		push_error("cockpit should contain All Orders toggle")
		_free_mode(mode)
		return false
	if toggle.button_pressed:
		push_error("all-orders toggle should be off by default")
		_free_mode(mode)
		return false
	if renderer.call("action_preview_count") != 1:
		push_error("selected intent should be the only default action preview")
		_free_mode(mode)
		return false
	toggle.button_pressed = true
	var expected_previews: int = workers.size()
	if renderer.call("action_preview_count") != expected_previews:
		push_error(
			(
				"cockpit toggle should route all-friendly previews, got %d expected %d"
				% [renderer.call("action_preview_count"), expected_previews]
			)
		)
		_free_mode(mode)
		return false
	_free_mode(mode)
	return true


func _test_selected_and_friendly_target_intents() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var state: MatchState = mode.current_state()
	var marines: Array[int] = _find_entity_ids(state, "marine", 0)
	var target_id: int = _find_entity_id(state, "tank", 1)
	var renderer: MatchRenderer = mode.renderer()
	if marines.size() < 2 or target_id < 0 or renderer == null:
		push_error("expected two P0 marines, P1 target, and renderer")
		_free_mode(mode)
		return false
	for method in ["set_target_intent_previews", "target_intent_preview_count"]:
		if not renderer.has_method(method):
			push_error("renderer should expose %s" % method)
			_free_mode(mode)
			return false
	if (
		not _move_entity_to(state, marines[0], Vector2i(6, 10))
		or not _move_entity_to(state, marines[1], Vector2i(6, 12))
		or not _move_entity_to(state, target_id, Vector2i(10, 11))
	):
		_free_mode(mode)
		return false
	renderer.bind_state(state, _load_registry())
	if not mode.select_entity_id(marines[0]) or not mode.issue_attack_selected(target_id):
		push_error("expected first marine target intent")
		_free_mode(mode)
		return false
	if renderer.call("target_intent_preview_count") != 1:
		push_error("selected target intent should always show one preview")
		_free_mode(mode)
		return false
	if not mode.select_entity_id(marines[1]) or not mode.issue_attack_selected(target_id):
		push_error("expected second marine target intent")
		_free_mode(mode)
		return false
	if renderer.call("target_intent_preview_count") != 1:
		push_error("all-friendly target intents should be off by default")
		_free_mode(mode)
		return false
	if not _select_entities_for_test(mode.input_model(), [marines[0], marines[1]]):
		_free_mode(mode)
		return false
	mode.call("_update_hud")
	if renderer.call("target_intent_preview_count") != 2:
		push_error("multi-selected target intents should show one preview per selected unit")
		_free_mode(mode)
		return false
	mode.call("set_show_all_friendly_action_previews", true)
	var expected_intents: int = 2
	if renderer.call("target_intent_preview_count") != expected_intents:
		push_error(
			(
				"all-friendly preview toggle should show friendly target intents, got %d expected %d"
				% [renderer.call("target_intent_preview_count"), expected_intents]
			)
		)
		_free_mode(mode)
		return false
	_free_mode(mode)
	return true


func _test_selected_combat_unit_shows_range() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	var renderer: MatchRenderer = mode.renderer()
	if renderer == null or not renderer.has_method("range_preview_tile_count"):
		push_error("renderer should expose range preview tile count")
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var marine_id: int = _find_entity_id(mode.current_state(), "marine", 0)
	if marine_id < 0 or not mode.select_entity_id(marine_id):
		push_error("expected to select a P0 marine")
		_free_mode(mode)
		return false
	var count: int = renderer.call("range_preview_tile_count")
	var ok := count > 0
	if not ok:
		push_error("selecting a combat unit should draw current range tiles")
	_free_mode(mode)
	return ok


func _test_alt_projects_range_from_hover_tile() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	var renderer: MatchRenderer = mode.renderer()
	if renderer == null or not renderer.has_method("range_preview_tile_count"):
		push_error("renderer should expose range preview tile count")
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var marine_id: int = _find_entity_id(mode.current_state(), "marine", 0)
	if marine_id < 0 or not mode.select_entity_id(marine_id):
		push_error("expected to select a P0 marine")
		_free_mode(mode)
		return false
	var controller: MatchSessionController = mode.get("_controller") as MatchSessionController
	var current_count: int = renderer.call("range_preview_tile_count")
	mode.call("_unhandled_input", _key_event(KEY_ALT, true))
	mode.call("_set_hover_tile", Vector2i(12, 12))
	var projected_count: int = renderer.call("range_preview_tile_count")
	mode.call("_notification", NOTIFICATION_WM_MOUSE_EXIT)
	var exited_count: int = renderer.call("range_preview_tile_count")
	mode.call("_unhandled_input", _key_event(KEY_ALT, false))
	var restored_count: int = renderer.call("range_preview_tile_count")
	var ok := true
	if controller.range_projection_active():
		push_error("releasing Alt should clear the projection flag")
		ok = false
	if projected_count <= current_count:
		push_error("Alt projection should add hover-anchored range tiles to current range preview")
		ok = false
	if restored_count != current_count:
		push_error("releasing Alt should restore the selected unit's current range preview")
		ok = false
	if exited_count != current_count:
		push_error("mouse exit should clear hover-projected range tiles")
		ok = false
	_free_mode(mode)
	return ok


func _test_move_preview_shows_turn_stop_marker() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	var renderer: MatchRenderer = mode.renderer()
	if (
		renderer == null
		or not renderer.has_method("action_preview_stop_marker_count")
		or not renderer.has_method("action_preview_stop_marker_tile")
	):
		push_error("renderer should expose action preview stop marker helpers")
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected to select a P0 worker")
		_free_mode(mode)
		return false
	if not mode.issue_move_selected(Vector2i(20, 22)):
		push_error("expected long-range move to queue")
		_free_mode(mode)
		return false
	var stop_count: int = renderer.call("action_preview_stop_marker_count")
	var stop_tile: Vector2i = renderer.call("action_preview_stop_marker_tile", 0)
	var ok := true
	if stop_count < 2:
		push_error("queued long move should draw a stop marker for every turn of travel")
		ok = false
	if stop_tile == Vector2i(20, 22):
		push_error("the first stop marker should not be the final destination")
		ok = false
	if stop_tile == Vector2i(-999999, -999999):
		push_error("long move stop marker should record a concrete tile")
		ok = false
	var last_tile: Vector2i = renderer.call("action_preview_stop_marker_tile", stop_count - 1)
	if last_tile != Vector2i(20, 22):
		push_error("the last stop marker should be the arrival tile, got %s" % last_tile)
		ok = false
	if (
		renderer.call("action_preview_stop_marker_turn_index", 0) != 1
		or renderer.call("action_preview_stop_marker_turn_index", stop_count - 1) != stop_count
	):
		push_error("stop markers should carry 1-based turn indices")
		ok = false
	_free_mode(mode)
	return ok


func _test_gather_and_build_previews_route_around_blockers() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	var gather_target_id: int = _add_runtime_entity(
		mode.current_state(), "mineral_patch", -1, Vector2i(17, 23)
	)
	var renderer: MatchRenderer = mode.renderer()
	if worker_id < 0 or gather_target_id < 0 or renderer == null:
		push_error("expected worker, injected mineral patch, and renderer for preview test")
		_free_mode(mode)
		return false
	renderer.bind_state(mode.current_state(), _load_registry())
	if not mode.select_entity_id(worker_id) or not mode.issue_gather_selected(gather_target_id):
		push_error("expected cross-base GATHER preview to queue")
		_free_mode(mode)
		return false
	var ok := true
	if renderer.action_preview_line_point_count(0) <= 2:
		push_error("GATHER preview should draw a routed path, not a straight fallback line")
		ok = false

	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		push_error("expected scenario reload before BUILD preview")
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	mode.current_state().get_player(0).minerals = 10000
	mode.current_state().get_player(0).gas = 10000
	worker_id = _find_entity_id(mode.current_state(), "worker", 0)
	renderer = mode.renderer()
	if worker_id < 0 or renderer == null:
		push_error("expected worker and renderer after scenario reload")
		_free_mode(mode)
		return false
	if (
		not mode.select_entity_id(worker_id)
		or not mode.issue_build_selected("barracks", Vector2i(18, 23))
	):
		push_error("expected cross-base BUILD preview to queue")
		_free_mode(mode)
		return false
	if renderer.action_preview_line_point_count(0) <= 2:
		push_error("BUILD preview should draw a routed path, not a straight fallback line")
		ok = false
	_free_mode(mode)
	return ok


func _test_shift_click_routes_future_orders() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected to select a P0 worker")
		_free_mode(mode)
		return false
	var card: Control = mode.command_card()
	if card == null:
		push_error("expected command card")
		_free_mode(mode)
		return false
	if _find_check_box_with_substring(card, "Queue") != null:
		push_error("command card should not expose a Queue toggle; use Shift-click instead")
		_free_mode(mode)
		return false
	if not mode.issue_move_selected(Vector2i(13, 22)):
		push_error("expected first queued move")
		_free_mode(mode)
		return false
	if not mode.issue_move_selected(Vector2i(13, 25), true):
		push_error("expected Shift-click move to become future order")
		_free_mode(mode)
		return false
	var renderer: MatchRenderer = mode.renderer()
	var ok: bool = true
	if mode.input_model().submit_for_player(0).orders.size() != 1:
		push_error("Shift-click queueing should keep one current order")
		ok = false
	if mode.input_model().future_order_count_for_entity(worker_id) != 1:
		push_error("Shift-click should append a future order")
		ok = false
	if mode.input_model().queue_modifier_active():
		push_error("Shift-click queue modifier should be one-shot")
		ok = false
	if renderer != null and renderer.action_preview_count() != 2:
		push_error("selected previews should include current and future orders")
		ok = false
	elif renderer != null:
		var preview_root: Node2D = renderer.get_node_or_null("Overlays/ActionPreviews") as Node2D
		var future_preview: Node = (
			preview_root.get_child(1)
			if preview_root != null and preview_root.get_child_count() > 1
			else null
		)
		var future_line: Line2D = (
			future_preview.get_child(0) as Line2D if future_preview != null else null
		)
		var expected_future_start: Vector2 = Vector2(13.5, 22.5) * 32.0
		if (
			future_line == null
			or future_line.points.size() < 2
			or future_line.points[0].distance_to(expected_future_start) > 0.5
		):
			push_error(
				(
					"future queued move preview should start at previous move destination, got %s"
					% str(future_line)
				)
			)
			ok = false
	mode.set_active_player_id(1)
	if mode.input_model().queue_modifier_active():
		push_error("queue modifier should stay inactive when switching active player")
		ok = false
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		push_error("scenario reload should succeed")
		ok = false
	elif mode.input_model().queue_modifier_active():
		push_error("queue modifier should stay inactive on scenario reload")
		ok = false
	_free_mode(mode)
	return ok


func _test_shift_click_routes_future_gather_and_build_orders() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	var ok: bool = true
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	var gather_target_id: int = _add_runtime_entity(
		mode.current_state(), "mineral_patch", -1, Vector2i(17, 23)
	)
	if worker_id < 0 or gather_target_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected worker and mineral patch for future gather preview")
		_free_mode(mode)
		return false
	if not mode.issue_move_selected(Vector2i(13, 22)):
		push_error("expected first queued move before future gather")
		ok = false
	if not mode.issue_gather_selected(gather_target_id, true):
		push_error("expected Shift-click gather to become future order")
		ok = false
	var renderer: MatchRenderer = mode.renderer()
	var expected_start: Vector2 = Vector2(13.5, 22.5) * 32.0
	if ok and not _action_preview_starts_near(renderer, 1, expected_start):
		push_error("future gather preview should start at previous move destination")
		ok = false

	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		push_error("expected scenario reload before future build preview")
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	mode.current_state().get_player(0).minerals = 10000
	mode.current_state().get_player(0).gas = 10000
	worker_id = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected worker for future build preview")
		_free_mode(mode)
		return false
	if not mode.issue_move_selected(Vector2i(13, 22)):
		push_error("expected first queued move before future build")
		ok = false
	if not mode.issue_build_selected("barracks", Vector2i(18, 23), true):
		push_error("expected Shift-click build to become future order")
		ok = false
	renderer = mode.renderer()
	if ok and not _action_preview_starts_near(renderer, 1, expected_start):
		push_error("future build preview should start at previous move destination")
		ok = false
	_free_mode(mode)
	return ok


func _test_direct_attack_preview_tracks_live_target() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var state: MatchState = mode.current_state()
	var actor_id: int = _find_entity_id(state, "marine", 0)
	var target_id: int = _find_entity_id(state, "tank", 1)
	var actor: Entity = state.get_entity_by_id(actor_id) if state != null else null
	var target: Entity = state.get_entity_by_id(target_id) if state != null else null
	var renderer: MatchRenderer = mode.renderer()
	if actor == null or target == null or state.tile_grid == null or renderer == null:
		push_error("expected opposing marines and renderer for direct attack preview test")
		_free_mode(mode)
		return false
	if not renderer.has_method("target_intent_preview_count"):
		push_error("renderer should expose target_intent_preview_count")
		_free_mode(mode)
		return false
	if not _move_entity_to(state, actor.id, Vector2i(6, 10)):
		_free_mode(mode)
		return false
	# Within CIRCULAR sight of the marine (dx^2 + dy^2 <= r^2 = 16) but
	# outside attack range 3, so the preview routes a movement path. A
	# second marine spots the live tile after the target relocates.
	if not _move_entity_to(state, target.id, Vector2i(10, 10)):
		_free_mode(mode)
		return false
	var spotter_id: int = -1
	for entity: Entity in state.entities_sorted_by_id():
		if entity.def_id == "marine" and entity.owner_player_id == 0 and entity.id != actor_id:
			spotter_id = entity.id
			break
	if spotter_id < 0 or not _move_entity_to(state, spotter_id, Vector2i(8, 8)):
		push_error("expected a spotter marine for the live-target tile")
		_free_mode(mode)
		return false
	if not mode.select_entity_id(actor.id) or not mode.issue_attack_selected(target.id):
		push_error("expected direct attack order to queue")
		_free_mode(mode)
		return false
	var stale_target_tile: Vector2i = target.origin
	# The live hop stays out of attack range but inside the spotter's
	# circular sight.
	var live_target_tile: Vector2i = stale_target_tile + Vector2i(0, -2)
	if not state.tile_grid.is_rect_clear(Rect2i(live_target_tile, Vector2i.ONE)):
		live_target_tile = _find_clear_rect_origin_near(state, live_target_tile, Vector2i.ONE)
	if not state.tile_grid.move(target.id, live_target_tile):
		push_error("expected target move setup to succeed")
		_free_mode(mode)
		return false
	target.origin = live_target_tile
	renderer.bind_state(state, _load_registry())
	mode.call("_update_hud")
	var stale_target_center: Vector2 = _tile_center_px(stale_target_tile)
	var target_view: EntityView = renderer.get_entity_view(target.id)
	var live_target_center: Vector2 = (
		target_view.position if target_view != null else _tile_center_px(live_target_tile)
	)
	var ok: bool = true
	if renderer.action_preview_count() != 1:
		push_error("out-of-range target command should keep one generated movement action preview")
		ok = false
	if renderer.call("target_intent_preview_count") != 1:
		push_error("out-of-range target command should show one target intent preview")
		ok = false
	var movement_points: PackedVector2Array = _action_preview_line_points(renderer, 0)
	var intent_points: PackedVector2Array = _target_intent_line_points(renderer, 0)
	if movement_points.size() < 2:
		push_error("direct attack movement preview should draw a routed path")
		ok = false
	if intent_points.size() < 2:
		push_error("direct attack target intent should draw a combat-lock line")
		ok = false
	if movement_points.size() >= 2:
		var movement_end: Vector2 = movement_points[movement_points.size() - 1]
		if movement_end.distance_to(stale_target_center) <= 0.5:
			push_error("movement preview should not end at the stale fallback target tile")
			ok = false
		# Tracking the LIVE target means the planned stop is a firing
		# tile for the live rect (within attack range), not a march to
		# the stale tile.
		var end_tile := Vector2i(int(movement_end.x / 32.0), int(movement_end.y / 32.0))
		var live_rect: Rect2i = state.tile_grid.entity_rect(target.id)
		if TileGrid.distance_between_rects(Rect2i(end_tile, Vector2i.ONE), live_rect) > 3:
			push_error("movement preview should stop within firing range of the live target")
			ok = false
		if intent_points.size() >= 2:
			var intent_start: Vector2 = intent_points[0]
			if intent_start.distance_to(movement_end) > 0.5:
				push_error("target intent should start from the planned firing position")
				ok = false
	if intent_points.size() >= 2:
		var intent_end: Vector2 = intent_points[intent_points.size() - 1]
		if intent_end.distance_to(stale_target_center) <= 0.5:
			push_error("target intent should not end at the stale fallback target tile")
			ok = false
		if intent_end.distance_to(live_target_center) > 0.5:
			push_error("target intent should lock onto the live target position")
			ok = false
	_free_mode(mode)
	return ok


func _test_pending_build_updates_placement_preview() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var player: PlayerState = mode.current_state().get_player(0)
	player.minerals = 10000
	player.gas = 10000
	player.pop_cap = 200
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected to select a P0 worker on mvp_map")
		_free_mode(mode)
		return false
	var renderer: MatchRenderer = mode.renderer()
	if renderer == null or not renderer.has_method("build_placement_preview_count"):
		push_error("renderer should expose build placement preview count")
		_free_mode(mode)
		return false
	mode.begin_build("barracks")
	if mode.pending_command_kind() != "build":
		push_error("begin_build should enter pending build mode")
		_free_mode(mode)
		return false
	mode.call("_set_hover_tile", Vector2i(12, 2))
	var ok: bool = true
	if renderer.call("build_placement_preview_count") != 1:
		push_error("pending BUILD hover should create a placement preview")
		ok = false
	mode.cancel_pending_command()
	if renderer.call("build_placement_preview_count") != 0:
		push_error("cancel_pending_command should clear placement preview")
		ok = false
	mode.begin_build("barracks")
	mode.call("_set_hover_tile", Vector2i(12, 2))
	if renderer.call("build_placement_preview_count") != 1:
		push_error("second pending BUILD hover should recreate placement preview")
		ok = false
	if not mode.confirm_pending_at_tile(Vector2i(12, 2)):
		push_error("confirming valid pending BUILD should queue the order")
		ok = false
	var orders: Array[EntityOrder] = mode.input_model().submit_for_player(0).orders
	if orders.is_empty() or orders[0].target_tile != Vector2i(11, 1):
		push_error("pending BUILD should queue the centered origin shown by the preview")
		ok = false
	if renderer.call("build_placement_preview_count") != 0:
		push_error("successful pending BUILD confirm should clear placement preview")
		ok = false
	_free_mode(mode)
	return ok


func _test_requeues_unfinished_move_after_resolve() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected to select a P0 worker")
		_free_mode(mode)
		return false
	if not mode.issue_move_selected(Vector2i(20, 22)):
		push_error("expected long-range move to queue")
		_free_mode(mode)
		return false
	var renderer: MatchRenderer = mode.renderer()
	if renderer == null or not renderer.has_method("action_preview_line_point_count"):
		push_error("renderer should expose path preview point counts")
		_free_mode(mode)
		return false
	var preview_points_before: int = renderer.call("action_preview_line_point_count", 0)
	if preview_points_before <= 2:
		push_error("long-range move preview should draw a path polyline before resolve")
		_free_mode(mode)
		return false
	if not mode.resolve_turn():
		push_error("expected resolve to succeed")
		_free_mode(mode)
		return false
	var orders: Array[EntityOrder] = mode.input_model().submit_for_player(0).orders
	if orders.size() != 1:
		push_error("unfinished long-range move should requeue, got %d orders" % orders.size())
		_free_mode(mode)
		return false
	var order: EntityOrder = orders[0]
	var ok := (
		order.type == EntityOrder.Type.MOVE
		and order.entity_id == worker_id
		and order.target_tile == Vector2i(20, 22)
	)
	if not ok:
		push_error("requeued move should preserve type, actor, and target")
	if renderer != null and renderer.action_preview_count() != 1:
		push_error("requeued move should remain visible as an action preview")
		ok = false
	var preview_points_after: int = renderer.call("action_preview_line_point_count", 0)
	if preview_points_after <= 2:
		push_error("requeued move preview should still draw a path polyline")
		ok = false
	elif preview_points_after >= preview_points_before:
		push_error("requeued move preview should recompute from the post-resolve origin")
		ok = false
	_free_mode(mode)
	return ok


func _test_tied_same_target_move_completes_for_future_queue() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var marines: Array[int] = _find_entity_ids(mode.current_state(), "marine", 0)
	if marines.size() < 2:
		push_error("expected at least two P0 marines")
		_free_mode(mode)
		return false
	var left_id: int = marines[0]
	var right_id: int = marines[2] if marines.size() > 2 else marines[1]
	if not mode.select_entity_id(left_id):
		push_error("expected to select first marine")
		_free_mode(mode)
		return false
	if not mode.issue_move_selected(Vector2i(6, 11)):
		push_error("expected first contested move to queue")
		_free_mode(mode)
		return false
	if not mode.issue_move_selected(Vector2i(8, 10), true):
		push_error("expected first future move to queue")
		_free_mode(mode)
		return false
	if not mode.select_entity_id(right_id):
		push_error("expected to select second marine")
		_free_mode(mode)
		return false
	if not mode.issue_move_selected(Vector2i(6, 11)):
		push_error("expected second contested move to queue")
		_free_mode(mode)
		return false
	if not mode.issue_move_selected(Vector2i(8, 12), true):
		push_error("expected second future move to queue")
		_free_mode(mode)
		return false
	if not mode.resolve_turn():
		push_error("expected resolve to succeed")
		_free_mode(mode)
		return false
	var left_after: Entity = mode.current_state().get_entity_by_id(left_id)
	var right_after: Entity = mode.current_state().get_entity_by_id(right_id)
	var ok := true
	if left_after.origin != Vector2i(6, 10) or right_after.origin != Vector2i(6, 12):
		push_error(
			(
				"tied movers should stop at reachable spaces around the contested target, got %s and %s"
				% [str(left_after.origin), str(right_after.origin)]
			)
		)
		ok = false
	var orders: Array[EntityOrder] = mode.input_model().submit_for_player(0).orders
	if orders.size() != 2:
		push_error(
			"future orders should promote after tied move completion, got %d" % orders.size()
		)
		ok = false
	else:
		if not _expect_order(orders[0], EntityOrder.Type.MOVE, left_id, Vector2i(8, 10)):
			ok = false
		if not _expect_order(orders[1], EntityOrder.Type.MOVE, right_id, Vector2i(8, 12)):
			ok = false
	_free_mode(mode)
	return ok


func _test_routes_command_card_orders() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected to select a P0 worker on mvp_map")
		_free_mode(mode)
		return false
	var card: Control = mode.command_card()
	if card == null:
		push_error("expected command card to exist")
		_free_mode(mode)
		return false
	card.emit_signal("move_requested")
	if mode.pending_command_kind() != "move":
		push_error("move signal should enter pending move mode")
		_free_mode(mode)
		return false
	if not mode.confirm_pending_at_tile(Vector2i(9, 22)):
		push_error("pending move click should queue Move")
		_free_mode(mode)
		return false
	var move_order: EntityOrder = mode.input_model().submit_for_player(0).orders[0]
	if move_order.type != EntityOrder.Type.MOVE:
		push_error("expected MOVE after pending Move click")
		_free_mode(mode)
		return false
	var unit_cancel_button: Button = (
		card.get_node_or_null("BottomDeck/Row/CommandPanel/Stack/CommandGrid/Cancel") as Button
	)
	var build_cancel_button: Button = (
		card.get_node_or_null("BottomDeck/Row/BuildPanel/Stack/ProductionControls/Cancel") as Button
	)
	if unit_cancel_button == null or not unit_cancel_button.visible:
		push_error("selected unit with a queued order should expose Cancel in Commands")
		_free_mode(mode)
		return false
	if build_cancel_button != null and build_cancel_button.visible:
		push_error("selected unit with a queued order should not expose Cancel in Build")
		_free_mode(mode)
		return false
	card.emit_signal("cancel_requested", -1)
	if mode.pending_order_count(0) != 0:
		push_error("Cancel should remove the selected worker's queued Move")
		_free_mode(mode)
		return false
	mode.input_model().clear_submissions()
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		push_error("expected combat scenario reload for target command")
		_free_mode(mode)
		return false
	if not _move_entity_to(mode.current_state(), 4, Vector2i(8, 10)):
		_free_mode(mode)
		return false
	card = mode.command_card()
	if card == null:
		push_error("expected command card after combat scenario reload")
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	if not mode.select_entity_id(1):
		push_error("expected P0 marine #1 to be selectable")
		_free_mode(mode)
		return false
	card.emit_signal("target_requested")
	if mode.pending_command_kind() != "target":
		push_error("attack signal should enter pending attack mode")
		_free_mode(mode)
		return false
	mode.renderer().set_perspective_player_id(0)
	if not mode.confirm_pending_at_tile(Vector2i(8, 10)):
		push_error("pending attack click should queue direct attack target")
		_free_mode(mode)
		return false
	var marine: Entity = mode.current_state().get_entity_by_id(1)
	if marine == null or marine.focus_target_entity_id != -1:
		push_error("pending attack click should not mutate focus before resolve")
		_free_mode(mode)
		return false
	var target_orders: Array[EntityOrder] = mode.input_model().submit_for_player(0).orders
	if (
		target_orders.size() != 1
		or target_orders[0].type != EntityOrder.Type.TARGET
		or target_orders[0].target_priority_chain != ([4] as Array[int])
		or target_orders[0].target_entity_id != 4
	):
		push_error("attack command should queue TARGET")
		_free_mode(mode)
		return false
	mode.input_model().clear_submissions()
	card.emit_signal("move_requested")
	if mode.pending_command_kind() != "move":
		push_error("Move signal should enter pending move mode")
		_free_mode(mode)
		return false
	if not mode.confirm_pending_at_tile(Vector2i(8, 10)):
		push_error("pending Move click should queue MOVE")
		_free_mode(mode)
		return false
	card.emit_signal("cancel_requested", -1)
	var orders: Array[EntityOrder] = mode.input_model().submit_for_player(0).orders
	if orders.size() != 0:
		push_error("Cancel should remove the selected marine's queued Move, got %d" % orders.size())
		_free_mode(mode)
		return false
	if marine == null or marine.focus_target_entity_id != -1:
		push_error("TARGET command should not leave focus state before resolve")
		_free_mode(mode)
		return false
	mode.input_model().clear_submissions()
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		push_error("expected mvp scenario reload for build commands")
		_free_mode(mode)
		return false
	card = mode.command_card()
	if card == null:
		push_error("expected command card after mvp scenario reload")
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	worker_id = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected to reselect P0 worker on mvp_map")
		_free_mode(mode)
		return false
	mode.current_state().get_player(0).minerals = 150
	card.emit_signal("build_requested", "barracks")
	if mode.pending_command_kind() != "build":
		push_error("build signal should enter pending build mode")
		_free_mode(mode)
		return false
	if not mode.confirm_pending_at_tile(Vector2i(12, 2)):
		push_error("pending build click should queue BUILD")
		_free_mode(mode)
		return false
	var build: EntityOrder = mode.input_model().submit_for_player(0).orders[0]
	if build.type != EntityOrder.Type.BUILD or build.def_id != "barracks":
		push_error("expected BUILD barracks after pending click")
		_free_mode(mode)
		return false
	mode.input_model().clear_submissions()
	var barracks_id: int = _add_runtime_entity(mode.current_state(), "barracks", 0, Vector2i(16, 2))
	if barracks_id < 0 or not mode.select_entity_id(barracks_id):
		push_error("expected to select injected barracks")
		_free_mode(mode)
		return false
	card.emit_signal("train_requested", "marine")
	orders = mode.input_model().submit_for_player(0).orders
	if orders[0].type != EntityOrder.Type.TRAIN or orders[0].def_id != "marine":
		push_error("train signal should queue TRAIN marine")
		_free_mode(mode)
		return false
	# No researches remain in the roster (siege tech removed, plan m1/06
	# wave 1); RESEARCH order routing stays covered by resolver tests
	# with synthetic registries.
	if not mode.select_entity_id(barracks_id):
		push_error("expected to reselect barracks")
		_free_mode(mode)
		return false
	build_cancel_button = (
		card.get_node_or_null("BottomDeck/Row/BuildPanel/Stack/ProductionControls/Cancel") as Button
	)
	unit_cancel_button = (
		card.get_node_or_null("BottomDeck/Row/CommandPanel/Stack/CommandGrid/Cancel") as Button
	)
	if build_cancel_button == null or not build_cancel_button.visible:
		push_error("selected building with queued production should expose Cancel in Build")
		_free_mode(mode)
		return false
	if unit_cancel_button != null and unit_cancel_button.visible:
		push_error("selected building with queued production should not expose Cancel in Commands")
		_free_mode(mode)
		return false
	mode.input_model().clear_submissions()
	var tank_id: int = _add_runtime_entity(mode.current_state(), "tank", 0, Vector2i(21, 2))
	if tank_id < 0 or not mode.select_entity_id(tank_id):
		push_error("expected to select injected tank")
		_free_mode(mode)
		return false
	if not _command_card_ids(card, "ability_option_ids").has("siege_mode"):
		push_error("tank command card should expose siege_mode ability")
		_free_mode(mode)
		return false
	card.emit_signal("ability_requested", "siege_mode")
	orders = mode.input_model().submit_for_player(0).orders
	if orders[0].type != EntityOrder.Type.USE_ABILITY or orders[0].def_id != "siege_mode":
		push_error("ability signal should queue USE_ABILITY siege_mode")
		_free_mode(mode)
		return false
	_free_mode(mode)
	return true


func _test_pending_target_targets_enemy() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	if not _move_entity_to(mode.current_state(), 4, Vector2i(8, 10)):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	if not mode.select_entity_id(1):
		push_error("expected to select P0 marine #1")
		_free_mode(mode)
		return false
	var card: Control = mode.command_card()
	card.emit_signal("target_requested")
	mode.renderer().set_perspective_player_id(0)
	if not mode.confirm_pending_at_tile(Vector2i(8, 10)):
		push_error("pending target click on enemy should queue TARGET")
		_free_mode(mode)
		return false
	var marine: Entity = mode.current_state().get_entity_by_id(1)
	if marine == null or marine.focus_target_entity_id != -1:
		push_error("pending target click should not mutate focus before resolve")
		_free_mode(mode)
		return false
	var orders: Array[EntityOrder] = mode.input_model().submit_for_player(0).orders
	if (
		orders.size() != 1
		or orders[0].type != EntityOrder.Type.TARGET
		or orders[0].target_priority_chain != ([4] as Array[int])
		or orders[0].target_entity_id != 4
	):
		push_error("pending enemy click should queue TARGET")
		_free_mode(mode)
		return false
	_free_mode(mode)
	return true


func _test_a_key_attack_mode() -> bool:
	var original_cursor_shape: int = Input.get_current_cursor_shape()
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	var ok: bool = true
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		ok = false
	if ok:
		mode.set_active_player_id(0)
		if not mode.select_entity_id(1):
			push_error("expected to select P0 marine #1")
			ok = false
	if ok:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		mode.call("_unhandled_input", _key_press(KEY_A))
		if mode.pending_command_kind() != "target":
			push_error("A key should enter pending attack mode")
			ok = false
	if ok and mode.pending_cursor_shape() != Input.CURSOR_CROSS:
		push_error("pending attack should use the crosshair cursor")
		ok = false
	var orders: Array[EntityOrder] = mode.input_model().submit_for_player(0).orders
	if ok and not mode.confirm_pending_at_tile(Vector2i(8, 10)):
		push_error("A-key ground click should queue attack movement")
		ok = false
	orders = mode.input_model().submit_for_player(0).orders
	if (
		ok
		and (
			orders.size() != 1
			or orders[0].type != EntityOrder.Type.ATTACK_MOVE
			or orders[0].target_tile != Vector2i(8, 10)
		)
	):
		push_error("A-key ground click should queue ATTACK_MOVE")
		ok = false
	if ok and mode.pending_command_kind() != "":
		push_error("A-key ground click should clear pending attack mode after queuing")
		ok = false
	if ok:
		mode.input_model().clear_submissions()
		if not _move_entity_to(mode.current_state(), 4, Vector2i(8, 10)):
			ok = false
	if ok:
		mode.call("_unhandled_input", _key_press(KEY_A))
		mode.renderer().set_perspective_player_id(0)
		if not mode.confirm_pending_at_tile(Vector2i(8, 10)):
			push_error("A-key enemy click should queue TARGET")
			ok = false
		orders = mode.input_model().submit_for_player(0).orders
	if (
		ok
		and (
			orders.size() != 1
			or orders[0].type != EntityOrder.Type.TARGET
			or orders[0].target_priority_chain != ([4] as Array[int])
			or orders[0].target_entity_id != 4
			or orders[0].target_tile != Vector2i(8, 10)
		)
	):
		push_error("A-key enemy click should queue TARGET against #4")
		ok = false
	Input.set_default_cursor_shape(original_cursor_shape)
	_free_mode(mode)
	return ok


func _test_drag_box_replace_shift_toggle_and_shift_box_add() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var ids: Array[int] = _find_entity_ids(mode.current_state(), "marine", 0)
	if ids.size() < 2:
		push_error("combat scenario should have at least two P0 marines")
		_free_mode(mode)
		return false
	_drag_box(mode, _world_box_for_entities(mode.current_state(), ids), false)
	var selected: Array[int] = _selected_ids_for_test(mode.input_model())
	var ok := true
	if selected != ids:
		push_error(
			(
				"plain drag-box should replace selection with boxed owned movers, got %s"
				% str(selected)
			)
		)
		ok = false
	mode.call(
		"_unhandled_input",
		_mouse_button(
			MOUSE_BUTTON_LEFT,
			true,
			_tile_center_px(mode.current_state().get_entity_by_id(ids[0]).origin),
			true
		)
	)
	mode.call(
		"_unhandled_input",
		_mouse_button(
			MOUSE_BUTTON_LEFT,
			false,
			_tile_center_px(mode.current_state().get_entity_by_id(ids[0]).origin),
			true
		)
	)
	selected = _selected_ids_for_test(mode.input_model())
	var expected_after_toggle: Array[int] = ids.duplicate()
	expected_after_toggle.remove_at(0)
	if selected != expected_after_toggle:
		push_error("shift-click should toggle one owned movable unit out, got %s" % str(selected))
		ok = false
	_drag_box(mode, _world_box_for_entities(mode.current_state(), [ids[0]]), true)
	selected = _selected_ids_for_test(mode.input_model())
	var expected_after_add: Array[int] = expected_after_toggle.duplicate()
	expected_after_add.append(ids[0])
	if selected != expected_after_add:
		push_error("shift drag-box should add boxed owned movers, got %s" % str(selected))
		ok = false
	_free_mode(mode)
	return ok


func _test_drag_box_filters_immobile_units() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var ids: Array[int] = _find_entity_ids(mode.current_state(), "marine", 0)
	if ids.size() < 2:
		push_error("combat scenario should have at least two P0 marines")
		_free_mode(mode)
		return false
	var locked_id: int = ids[1]
	var locked: Entity = mode.current_state().get_entity_by_id(locked_id)
	if locked == null:
		push_error("expected a marine to lock for drag-box filtering")
		_free_mode(mode)
		return false
	locked.locked_to_building_id = 42
	_drag_box(mode, _world_box_for_entities(mode.current_state(), ids), false)
	var selected: Array[int] = _selected_ids_for_test(mode.input_model())
	var expected: Array[int] = ids.duplicate()
	expected.erase(locked_id)
	var ok: bool = selected == expected
	if not ok:
		push_error("plain drag-box should skip immobile units, got %s" % str(selected))
	_free_mode(mode)
	return ok


func _test_click_selection_uses_press_modifier() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var ids: Array[int] = _find_entity_ids(mode.current_state(), "marine", 0)
	if ids.size() < 2:
		push_error("combat scenario should have at least two P0 marines")
		_free_mode(mode)
		return false
	if not mode.select_entity_id(ids[0]):
		push_error("expected first marine to be selectable")
		_free_mode(mode)
		return false
	var second_pos: Vector2 = _tile_center_px(mode.current_state().get_entity_by_id(ids[1]).origin)
	mode.call("_unhandled_input", _mouse_button(MOUSE_BUTTON_LEFT, true, second_pos, true))
	mode.call("_unhandled_input", _mouse_button(MOUSE_BUTTON_LEFT, false, second_pos, false))
	var selected: Array[int] = _selected_ids_for_test(mode.input_model())
	var expected_add: Array[int] = [ids[0], ids[1]]
	var ok := true
	if selected != expected_add:
		push_error(
			(
				"shift-down click should stay additive even if Shift is released, got %s"
				% str(selected)
			)
		)
		ok = false
	var first_pos: Vector2 = _tile_center_px(mode.current_state().get_entity_by_id(ids[0]).origin)
	mode.call("_unhandled_input", _mouse_button(MOUSE_BUTTON_LEFT, true, first_pos, false))
	mode.call("_unhandled_input", _mouse_button(MOUSE_BUTTON_LEFT, false, first_pos, true))
	selected = _selected_ids_for_test(mode.input_model())
	var expected_replace: Array[int] = [ids[0]]
	if selected != expected_replace:
		push_error(
			(
				"plain-down click should replace even if Shift is pressed on release, got %s"
				% str(selected)
			)
		)
		ok = false
	_free_mode(mode)
	return ok


func _test_shift_click_failure_updates_status() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var ids: Array[int] = _find_entity_ids(mode.current_state(), "marine", 0)
	if ids.size() < 2:
		push_error("status update test requires two P0 marines")
		_free_mode(mode)
		return false
	if not mode.select_entity_id(ids[0]):
		push_error("expected first marine to be selectable")
		_free_mode(mode)
		return false
	var locked: Entity = mode.current_state().get_entity_by_id(ids[1])
	if locked == null:
		push_error("expected second marine to be lockable")
		_free_mode(mode)
		return false
	locked.locked_to_building_id = 42
	var locked_pos: Vector2 = _tile_center_px(locked.origin)
	mode.call("_unhandled_input", _mouse_button(MOUSE_BUTTON_LEFT, true, locked_pos, true))
	mode.call("_unhandled_input", _mouse_button(MOUSE_BUTTON_LEFT, false, locked_pos, true))
	var selected: Array[int] = _selected_ids_for_test(mode.input_model())
	var status_label: Label = mode.find_child("Status", true, false) as Label
	var ok: bool = true
	if selected != [ids[0]]:
		push_error(
			"failed Shift-click should preserve the existing selection, got %s" % str(selected)
		)
		ok = false
	if status_label == null or status_label.text.find("Select an active movable P0 entity.") == -1:
		push_error("failed Shift-click should update the HUD status")
		ok = false
	_free_mode(mode)
	return ok


func _test_drag_box_selection_uses_press_modifier() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var ids: Array[int] = _find_entity_ids(mode.current_state(), "marine", 0)
	if ids.size() < 2:
		push_error("combat scenario should have at least two P0 marines")
		_free_mode(mode)
		return false
	if not mode.select_entity_id(ids[0]):
		push_error("expected first marine to be selectable")
		_free_mode(mode)
		return false
	var add_box: Rect2 = _world_box_for_entities(mode.current_state(), [ids[1]])
	var boxed_add: Array[int] = _boxed_ids_for_test(mode, add_box)
	_drag_box(mode, add_box, true, false, false)
	var selected: Array[int] = _selected_ids_for_test(mode.input_model())
	var expected_add: Array[int] = [ids[0]]
	for entity_id in boxed_add:
		if not expected_add.has(entity_id):
			expected_add.append(entity_id)
	var ok := true
	if selected != expected_add:
		push_error(
			"shift-down drag should stay additive even if Shift is released, got %s" % str(selected)
		)
		ok = false
	var replace_box: Rect2 = _world_box_for_entities(mode.current_state(), [ids[0]])
	var expected_replace: Array[int] = _boxed_ids_for_test(mode, replace_box)
	_drag_box(mode, replace_box, false, true, true)
	selected = _selected_ids_for_test(mode.input_model())
	if selected != expected_replace:
		push_error(
			(
				"plain-down drag should replace even if Shift is pressed on release, got %s"
				% str(selected)
			)
		)
		ok = false
	_free_mode(mode)
	return ok


func _test_group_right_click_orders() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var ids: Array[int] = _find_entity_ids(mode.current_state(), "marine", 0)
	if ids.size() < 2:
		push_error("combat scenario should have at least two P0 marines")
		_free_mode(mode)
		return false
	if not _select_entities_for_test(mode.input_model(), ids):
		_free_mode(mode)
		return false
	mode.call("_update_hud")
	var target_tile: Vector2i = _first_empty_tile(mode.current_state())
	mode.call(
		"_unhandled_input", _mouse_button(MOUSE_BUTTON_RIGHT, true, _tile_center_px(target_tile))
	)
	var orders: Array[EntityOrder] = mode.input_model().submit_for_player(0).orders
	var ok := true
	if orders.size() != ids.size():
		push_error(
			"group right-click should queue one order per selected mover, got %d" % orders.size()
		)
		ok = false
	else:
		var target_tiles: Array[Vector2i] = []
		for i in orders.size():
			var order: EntityOrder = orders[i]
			if order == null or order.type != EntityOrder.Type.MOVE or order.entity_id != ids[i]:
				push_error("expected MOVE for selected unit #%d" % ids[i])
				ok = false
			else:
				target_tiles.append(order.target_tile)
		if not target_tiles.has(target_tile):
			push_error("group right-click formation should include clicked tile")
			ok = false
		if _unique_tile_count(target_tiles) != ids.size():
			push_error(
				(
					"group right-click should assign distinct formation targets, got %s"
					% str(target_tiles)
				)
			)
			ok = false
	_free_mode(mode)
	return ok


func _test_left_drag_box_does_not_pan_camera() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	var renderer: MatchRenderer = mode.renderer()
	if renderer == null:
		push_error("expected renderer")
		_free_mode(mode)
		return false
	var camera := renderer.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		push_error("renderer has no Camera2D")
		_free_mode(mode)
		return false
	var original_position: Vector2 = camera.position
	mode.call("_unhandled_input", _mouse_button(MOUSE_BUTTON_LEFT, true, Vector2(8.0, 8.0)))
	mode.call(
		"_unhandled_input",
		_mouse_motion(Vector2(0.0, 96.0), MOUSE_BUTTON_MASK_LEFT, Vector2(8.0, 104.0))
	)
	mode.call("_unhandled_input", _mouse_button(MOUSE_BUTTON_LEFT, false, Vector2(8.0, 104.0)))
	var ok := true
	if camera.position != original_position:
		push_error("left-dragging should draw a selection box, not pan the camera")
		ok = false
	if mode.pending_command_kind() != "":
		push_error("selection drag should not leave a pending command")
		ok = false
	_free_mode(mode)
	return ok


func _test_escape_resets_active_selection_drag() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var ids: Array[int] = _find_entity_ids(mode.current_state(), "marine", 0)
	if ids.size() < 2:
		push_error("escape drag reset test requires two P0 marines")
		_free_mode(mode)
		return false
	if not mode.select_entity_id(ids[0]):
		push_error("escape drag reset test should select the first marine")
		_free_mode(mode)
		return false
	var box: Rect2 = _world_box_for_entities(mode.current_state(), [ids[1]])
	mode.call("_unhandled_input", _mouse_button(MOUSE_BUTTON_LEFT, true, box.position))
	mode.call("_unhandled_input", _mouse_motion(box.size, MOUSE_BUTTON_MASK_LEFT, box.end))
	mode.call("_unhandled_input", _escape_key())
	if bool(mode.renderer().call("is_selection_box_visible")):
		push_error("Escape should immediately clear the active selection box")
		_free_mode(mode)
		return false
	mode.call("_set_escape_menu_visible", false)
	mode.call("_unhandled_input", _mouse_button(MOUSE_BUTTON_LEFT, false, box.end))
	var selected: Array[int] = _selected_ids_for_test(mode.input_model())
	var ok: bool = selected == [ids[0]]
	if not ok:
		push_error("Escape should cancel active selection drag, got %s" % str(selected))
	_free_mode(mode)
	return ok


func _test_escape_debug_controls() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.call("_set_escape_menu_visible", true)
	var menu: Control = mode.find_child("EscapeMenu", true, false) as Control
	if menu == null or not menu.visible:
		push_error("escape menu should be visible for debug controls")
		_free_mode(mode)
		return false
	var ok := true
	for label in [
		"P1",
		"P2",
		"Clear",
		"Surrender",
		"Save Snapshot",
		"Load",
		"Replay",
		"New Game",
		"Main Menu",
	]:
		if _find_button_with_substring(menu, label) == null:
			push_error("escape menu should expose debug control '%s'" % label)
			ok = false
	if _find_exact_button(menu, "P0") != null:
		push_error("escape menu should use one-based player labels")
		ok = false
	var p2_button: Button = _find_exact_button(menu, "P2")
	if p2_button != null:
		p2_button.emit_signal("pressed")
		if mode.input_model().active_player_id() != 1:
			push_error("P2 debug button should switch to internal player 1")
			ok = false
	var p1_button: Button = _find_exact_button(menu, "P1")
	if p1_button != null:
		p1_button.emit_signal("pressed")
		if mode.input_model().active_player_id() != 0:
			push_error("P1 debug button should switch to internal player 0")
			ok = false
	if _find_check_box_with_substring(menu, "Debug Info") == null:
		push_error("escape menu should expose a Debug Info toggle")
		ok = false
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 1)
	if worker_id >= 0:
		mode.set_active_player_id(1)
		var queued_order_for_clear: bool = false
		if not mode.select_entity_id(worker_id):
			push_error("Clear control test should select a P1 worker before pressing Clear")
			ok = false
		elif not mode.issue_move_selected(Vector2i(24, 14)):
			push_error("Clear control test should queue a P1 move before pressing Clear")
			ok = false
		elif mode.pending_order_count(1) != 1:
			push_error("Clear control test expected one queued P1 order before pressing Clear")
			ok = false
		else:
			queued_order_for_clear = true
		var clear_button: Button = _find_button_with_substring(menu, "Clear")
		if clear_button != null and queued_order_for_clear:
			clear_button.emit_signal("pressed")
			if mode.pending_order_count(1) != 0:
				push_error("Clear debug button should clear active-player queued orders")
				ok = false
	_free_mode(mode)
	return ok


func _test_zoom_debug_hidden_until_menu_toggle() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	var renderer: MatchRenderer = mode.renderer()
	if renderer == null:
		push_error("expected renderer")
		_free_mode(mode)
		return false
	var zoom_label: Label = renderer.get_node_or_null("HUD/ZoomDebug") as Label
	var ok := true
	if renderer.zoom_debug_text().find("Zoom") == -1:
		push_error("renderer should keep zoom debug text available internally")
		ok = false
	if zoom_label == null:
		push_error("renderer should keep a ZoomDebug label for opt-in diagnostics")
		ok = false
	elif zoom_label.visible:
		push_error("ZoomDebug should be hidden by default")
		ok = false
	mode.call("_set_escape_menu_visible", true)
	var menu: Control = mode.find_child("EscapeMenu", true, false) as Control
	var debug_toggle: CheckBox = _find_check_box_with_substring(menu, "Debug Info")
	if debug_toggle == null:
		push_error("Debug Info toggle should exist in escape menu")
		ok = false
	else:
		debug_toggle.button_pressed = true
		debug_toggle.emit_signal("toggled", true)
		if zoom_label == null or not zoom_label.visible:
			push_error("Debug Info should show the ZoomDebug label")
			ok = false
		debug_toggle.button_pressed = false
		debug_toggle.emit_signal("toggled", false)
		if zoom_label != null and zoom_label.visible:
			push_error("Debug Info off should hide the ZoomDebug label again")
			ok = false
	_free_mode(mode)
	return ok


func _test_switching_player_keeps_camera_bounded() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	var renderer: MatchRenderer = mode.renderer()
	if renderer == null:
		push_error("expected renderer")
		_free_mode(mode)
		return false
	if not renderer.has_method("focus_player_start"):
		push_error("renderer should expose focus_player_start for player switching")
		_free_mode(mode)
		return false
	var camera := renderer.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		push_error("renderer has no Camera2D")
		_free_mode(mode)
		return false
	var ok: bool = _camera_visible_rect_inside_state(
		camera, mode.current_state(), "P0 player focus"
	)
	mode.set_active_player_id(1)
	ok = _camera_visible_rect_inside_state(camera, mode.current_state(), "P1 player focus") and ok
	if renderer.call("perspective_player_id") != 1:
		push_error("switching player should still update renderer perspective")
		ok = false
	_free_mode(mode)
	return ok


func _test_tile_size() -> float:
	var tunables: Tunables = load(TUNABLES_PATH) as Tunables
	if tunables == null:
		return 32.0
	return float(tunables.tile_pixel_size)


func _camera_visible_rect_inside_state(
	camera: Camera2D, state: MatchState, context: String
) -> bool:
	if state == null or state.tile_grid == null:
		push_error("camera bounds check requires a loaded tile grid")
		return false
	var viewport: Viewport = camera.get_viewport()
	var viewport_size: Vector2 = (
		viewport.get_visible_rect().size if viewport != null else Vector2.ZERO
	)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = Vector2(
			float(ProjectSettings.get_setting("display/window/size/viewport_width", 1920.0)),
			float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080.0))
		)
	var safe_zoom_x: float = maxf(camera.zoom.x, 0.01)
	var safe_zoom_y: float = maxf(camera.zoom.y, 0.01)
	var visible_size: Vector2 = Vector2(
		viewport_size.x / safe_zoom_x, viewport_size.y / safe_zoom_y
	)
	var visible: Rect2 = Rect2(camera.position - visible_size * 0.5, visible_size)
	var tile_size: float = _test_tile_size()
	var map_bounds: Rect2 = Rect2(
		Vector2.ZERO, Vector2(state.tile_grid.width * tile_size, state.tile_grid.height * tile_size)
	)
	var epsilon: float = 0.01
	var ok: bool = (
		visible.position.x >= map_bounds.position.x - epsilon
		and visible.position.y >= map_bounds.position.y - epsilon
		and visible.end.x <= map_bounds.end.x + epsilon
		and visible.end.y <= map_bounds.end.y + epsilon
	)
	if not ok:
		push_error(
			(
				"camera visible rect escaped map after %s: visible=%s map=%s zoom=%s"
				% [context, str(visible), str(map_bounds), str(camera.zoom)]
			)
		)
	return ok


func _logical_viewport_size() -> Vector2:
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1920.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080.0))
	)


func _make_mode() -> Node:
	var script: Script = load(DEV_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % DEV_PLAY_MODE_PATH)
		return null
	var mode: Node = script.new()
	mode.set_auto_save_replays_enabled(false)
	return mode


func _make_command_card() -> Control:
	var script: Script = load(COMMAND_CARD_PATH) as Script
	if script == null:
		push_error("could not load %s" % COMMAND_CARD_PATH)
		return null
	return script.new() as Control


func _set_command_card_state(
	card: Control, can_move: bool, can_target: bool, can_gather: bool, can_cancel: bool
) -> void:
	var build_options: Array[Dictionary] = []
	var train_options: Array[Dictionary] = []
	var research_options: Array[Dictionary] = []
	var ability_options: Array[Dictionary] = []
	card.call(
		"set_command_state",
		"Selection",
		can_move,
		can_target,
		can_gather,
		build_options,
		train_options,
		research_options,
		ability_options,
		can_cancel
	)


func _test_ai_opponent_toggle_drives_player_one() -> bool:
	# Plan m1/01: selecting an AI opponent makes the AI submit player 1's
	# turns at resolve time and locks the perspective to player 0.
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path("res://data/scenarios/arena_1v1.tres"):
		_free_mode(mode)
		return false
	if mode.command_card().opponent_option_count() < 4:
		push_error("cockpit should offer None + three AI strategies")
		_free_mode(mode)
		return false
	mode.set_ai_opponent("res://data/ai/rush_marines.tres")
	if not mode.ai_opponent_active():
		push_error("AI opponent should be active after selection")
		_free_mode(mode)
		return false
	mode.set_active_player_id(1)
	if mode.input_model().active_player_id() != 0:
		push_error("perspective must stay locked to player 0 while the AI plays")
		_free_mode(mode)
		return false
	var before: int = _count_owned(mode.current_state(), 1)
	for i in range(10):
		if not mode.resolve_turn():
			push_error("resolve_turn should succeed while AI opponent is active")
			_free_mode(mode)
			return false
	var after: int = _count_owned(mode.current_state(), 1)
	if after <= before:
		push_error("AI player 1 should have grown its entity count (%d -> %d)" % [before, after])
		_free_mode(mode)
		return false
	mode.set_ai_opponent("")
	if mode.ai_opponent_active():
		push_error("empty path should disable the AI opponent")
		_free_mode(mode)
		return false
	mode.set_active_player_id(1)
	if mode.session_local_player_id() != 1:
		push_error("manual player switching should be restored after disabling AI opponent")
		_free_mode(mode)
		return false
	_free_mode(mode)
	return true


func _count_owned(state: MatchState, player_id: int) -> int:
	var count: int = 0
	for entity: Entity in state.entities_sorted_by_id():
		if entity.owner_player_id == player_id and entity.current_hp > 0:
			count += 1
	return count


func _find_entity_id(state: MatchState, def_id: String, owner: int) -> int:
	if state == null:
		return -1
	for entity: Entity in state.entities_sorted_by_id():
		if entity.def_id == def_id and entity.owner_player_id == owner and entity.current_hp > 0:
			return entity.id
	return -1


func _find_entity_id_any_hp(state: MatchState, def_id: String, owner: int) -> int:
	if state == null:
		return -1
	for entity: Entity in state.entities_sorted_by_id():
		if entity.def_id == def_id and entity.owner_player_id == owner:
			return entity.id
	return -1


func _find_entity_ids(state: MatchState, def_id: String, owner: int) -> Array[int]:
	var out: Array[int] = []
	if state == null:
		return out
	for entity: Entity in state.entities_sorted_by_id():
		if entity.def_id == def_id and entity.owner_player_id == owner and entity.current_hp > 0:
			out.append(entity.id)
	return out


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


func _unique_tile_count(tiles: Array[Vector2i]) -> int:
	var seen: Dictionary = {}
	for tile in tiles:
		seen[tile] = true
	return seen.size()


func _boxed_ids_for_test(mode: Node, box: Rect2) -> Array[int]:
	var out: Array[int] = []
	var renderer: MatchRenderer = mode.renderer() if mode != null else null
	if renderer == null:
		return out
	var raw: Array = renderer.call("owned_movable_entity_ids_in_world_rect", box, 0)
	for item in raw:
		out.append(int(item))
	return out


func _world_box_for_entities(state: MatchState, entity_ids: Array[int]) -> Rect2:
	if state == null or entity_ids.is_empty():
		return Rect2()
	var min_tile := Vector2i(100000, 100000)
	var max_tile := Vector2i(-100000, -100000)
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
	var tile_size: float = _test_tile_size()
	var start := (Vector2(min_tile) - Vector2(0.25, 0.25)) * tile_size
	var end := (Vector2(max_tile) + Vector2(0.25, 0.25)) * tile_size
	return Rect2(start, end - start)


func _drag_box(
	mode: Node,
	box: Rect2,
	press_shift: bool,
	motion_shift: Variant = null,
	release_shift: Variant = null
) -> void:
	var motion_shift_pressed: bool = press_shift if motion_shift == null else bool(motion_shift)
	var release_shift_pressed: bool = press_shift if release_shift == null else bool(release_shift)
	mode.call("_unhandled_input", _mouse_button(MOUSE_BUTTON_LEFT, true, box.position, press_shift))
	mode.call(
		"_unhandled_input",
		_mouse_motion(box.size, MOUSE_BUTTON_MASK_LEFT, box.end, motion_shift_pressed)
	)
	mode.call(
		"_unhandled_input", _mouse_button(MOUSE_BUTTON_LEFT, false, box.end, release_shift_pressed)
	)


func _first_empty_tile(state: MatchState) -> Vector2i:
	if state == null or state.tile_grid == null:
		return Vector2i(-1, -1)
	for y in range(state.tile_grid.height):
		for x in range(state.tile_grid.width):
			var tile := Vector2i(x, y)
			if state.tile_grid.entity_at(tile) < 0:
				return tile
	return Vector2i(-1, -1)


func _set_all_workers_busy_gathering(state: MatchState, owner: int) -> void:
	if state == null:
		return
	for entity: Entity in state.entities_sorted_by_id():
		if entity.def_id != "worker" or entity.gather_state == null:
			continue
		if owner >= 0 and entity.owner_player_id != owner:
			continue
		entity.gather_state.phase = GatherState.Phase.GATHERING
		entity.gather_state.assigned_source_entity_id = -1


func _add_idle_worker_for_test(state: MatchState, owner: int) -> int:
	var origin: Vector2i = _first_empty_tile(state)
	if origin == Vector2i(-1, -1):
		push_error("test setup could not find an empty worker tile")
		return -1
	var id: int = _add_runtime_entity(state, "worker", owner, origin)
	if id < 0:
		push_error("test setup could not add worker at %s" % str(origin))
		return -1
	var worker: Entity = state.get_entity_by_id(id)
	if worker == null:
		push_error("test setup added worker #%d but could not load it" % id)
		return -1
	if worker.gather_state == null:
		worker.gather_state = GatherState.new()
	worker.gather_state.phase = GatherState.Phase.IDLE
	worker.gather_state.assigned_source_entity_id = -1
	worker.gather_state.carrying_amount = 0
	worker.gather_state.carrying_resource_type = ""
	return id


func _move_order_for_worker(state: MatchState, entity_id: int) -> EntityOrder:
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.MOVE
	order.entity_id = entity_id
	order.target_tile = _move_target_tile_for_entity(state, entity_id)
	return order


func _move_event_for_test(
	actor_id: int, from_origin: Vector2i, to_origin: Vector2i
) -> ResolverEvent:
	var event := ResolverEvent.new()
	event.type = ResolverEvent.Type.ENTITY_MOVED
	event.actor_id = actor_id
	event.from_origin = from_origin
	event.to_origin = to_origin
	return event


func _move_target_tile_for_entity(state: MatchState, entity_id: int) -> Vector2i:
	var entity: Entity = state.get_entity_by_id(entity_id) if state != null else null
	if entity == null or state.tile_grid == null:
		return Vector2i.ZERO
	var candidates: Array[Vector2i] = [
		entity.origin + Vector2i(1, 0),
		entity.origin + Vector2i(0, 1),
		entity.origin + Vector2i(-1, 0),
		entity.origin + Vector2i(0, -1),
	]
	for tile: Vector2i in candidates:
		if state.tile_grid.is_in_bounds(tile) and state.tile_grid.entity_at(tile) < 0:
			return tile
	var fallback: Vector2i = _find_clear_rect_origin_near(state, entity.origin, Vector2i.ONE)
	if state.tile_grid.is_rect_clear(Rect2i(fallback, Vector2i.ONE)):
		return fallback
	return entity.origin


func _find_clear_rect_origin_near(
	state: MatchState, near_tile: Vector2i, footprint: Vector2i
) -> Vector2i:
	if state == null or state.tile_grid == null:
		return Vector2i.ZERO
	for radius in range(1, 20):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dy) != radius:
					continue
				var origin := near_tile + Vector2i(dx, dy)
				var rect := Rect2i(origin, footprint)
				if state.tile_grid.is_rect_in_bounds(rect) and state.tile_grid.is_rect_clear(rect):
					return origin
	return Vector2i.ZERO


func _move_entity_to(state: MatchState, entity_id: int, origin: Vector2i) -> bool:
	var entity: Entity = state.get_entity_by_id(entity_id) if state != null else null
	if entity == null or state.tile_grid == null:
		push_error("test setup could not find entity #%d to move" % entity_id)
		return false
	if not state.tile_grid.move(entity_id, origin):
		push_error("test setup could not move entity #%d to %s" % [entity_id, str(origin)])
		return false
	entity.origin = origin
	return true


func _add_runtime_entity(state: MatchState, def_id: String, owner: int, origin: Vector2i) -> int:
	if state == null or state.tile_grid == null:
		return -1
	var entity: Entity = Entity.new()
	entity.id = state.allocate_entity_id()
	entity.def_id = def_id
	entity.current_def_id = def_id
	entity.owner_player_id = owner
	entity.origin = origin
	entity.current_layer = "ground"
	entity.current_hp = 1000
	var footprint: Vector2i = Vector2i(1, 1)
	var registry: EntityRegistry = _load_registry()
	var def: EntityDef = registry.get_by_id(def_id) if registry != null else null
	if def != null:
		footprint = def.footprint
		if def.health != null:
			entity.current_hp = def.health.max_hp
		if def.production != null:
			entity.production_state = ProductionState.new()
		if def.gather != null:
			entity.gather_state = GatherState.new()
		if def.resource_source != null:
			entity.current_resource_amount = def.resource_source.capacity
	if not state.tile_grid.place(entity.id, Rect2i(origin, footprint)):
		return -1
	state.entities.append(entity)
	return entity.id


func _action_preview_starts_near(
	renderer: MatchRenderer, preview_index: int, expected_start: Vector2
) -> bool:
	var preview_points: PackedVector2Array = _action_preview_line_points(renderer, preview_index)
	return preview_points.size() >= 2 and preview_points[0].distance_to(expected_start) <= 0.5


func _action_preview_line_points(renderer: MatchRenderer, preview_index: int) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if renderer == null:
		return out
	var preview_root: Node2D = renderer.get_node_or_null("Overlays/ActionPreviews") as Node2D
	if preview_root == null or preview_index < 0 or preview_index >= preview_root.get_child_count():
		return out
	var preview_group: Node = preview_root.get_child(preview_index)
	var preview_line: Line2D = _first_line_descendant(preview_group)
	if preview_line == null:
		return out
	return preview_line.points


func _target_intent_line_points(renderer: MatchRenderer, preview_index: int) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if renderer == null:
		return out
	var preview_root: Node2D = renderer.get_node_or_null("Overlays/TargetIntents") as Node2D
	if preview_root == null or preview_index < 0 or preview_index >= preview_root.get_child_count():
		return out
	var preview_group: Node = preview_root.get_child(preview_index)
	var lines: Array[Line2D] = []
	_collect_line_descendants(preview_group, lines)
	for line in lines:
		if line.points.size() < 2:
			continue
		if out.is_empty():
			out.append(line.points[0])
		out.append(line.points[line.points.size() - 1])
	return out


func _collect_line_descendants(root: Node, out: Array[Line2D]) -> void:
	if root == null:
		return
	if root is Line2D:
		out.append(root as Line2D)
	for child in root.get_children():
		_collect_line_descendants(child, out)


func _first_line_descendant(root: Node) -> Line2D:
	if root == null:
		return null
	if root is Line2D:
		return root as Line2D
	for child in root.get_children():
		var found: Line2D = _first_line_descendant(child)
		if found != null:
			return found
	return null


func _tile_center_px(tile: Vector2i) -> Vector2:
	return Vector2(tile.x + 0.5, tile.y + 0.5) * _test_tile_size()


func _command_card_ids(card: Control, method_name: String) -> Array[String]:
	var out: Array[String] = []
	var raw: Array = card.call(method_name)
	for item in raw:
		var id: String = item
		out.append(id)
	return out


func _command_surface_visible(card: Control) -> bool:
	if card == null:
		return false
	if not card.has_method("command_surface_visible"):
		push_error("CommandCard should expose command_surface_visible")
		return false
	return bool(card.call("command_surface_visible"))


func _expect_order(
	order: EntityOrder, expected_type: EntityOrder.Type, entity_id: int, target_tile: Vector2i
) -> bool:
	return (
		order != null
		and order.type == expected_type
		and order.entity_id == entity_id
		and order.target_tile == target_tile
	)


func _find_label_with_substring(root: Node, needle: String) -> Label:
	if root == null:
		return null
	if root is Label:
		var label: Label = root as Label
		if label.text.find(needle) != -1:
			return label
	for child in root.get_children():
		var found: Label = _find_label_with_substring(child, needle)
		if found != null:
			return found
	return null


func _find_button_with_substring(root: Node, needle: String) -> Button:
	if root == null:
		return null
	if root is Button:
		var button: Button = root as Button
		if button.text.find(needle) != -1:
			return button
	for child in root.get_children():
		var found: Button = _find_button_with_substring(child, needle)
		if found != null:
			return found
	return null


func _find_check_box_with_substring(root: Node, needle: String) -> CheckBox:
	if root == null:
		return null
	if root is CheckBox:
		var check_box: CheckBox = root as CheckBox
		if check_box.text.find(needle) != -1:
			return check_box
	for child in root.get_children():
		var found: CheckBox = _find_check_box_with_substring(child, needle)
		if found != null:
			return found
	return null


func _find_exact_button(root: Node, text: String) -> Button:
	if root == null:
		return null
	if root is Button:
		var button: Button = root as Button
		if button.text == text:
			return button
	for child in root.get_children():
		var found: Button = _find_exact_button(child, text)
		if found != null:
			return found
	return null


func _expect_button_visibility(root: Node, text: String, expected_visible: bool) -> bool:
	var button: Button = _find_exact_button(root, text)
	if button == null:
		push_error("expected button '%s' to exist" % text)
		return false
	if button.visible != expected_visible:
		push_error(
			(
				"button '%s' visibility should be %s, got %s"
				% [text, str(expected_visible), str(button.visible)]
			)
		)
		return false
	return true


func _button_text_has_all(button: Button, needles: Array[String]) -> bool:
	if button == null:
		return false
	for needle in needles:
		if button.text.find(needle) == -1:
			return false
	return true


func _entity_cost_parts(def_id: String) -> Array[String]:
	var parts: Array[String] = []
	var registry: EntityRegistry = _load_registry()
	var def: EntityDef = registry.get_by_id(def_id) if registry != null else null
	if def == null or def.construction == null:
		return parts
	parts.append("%dM" % def.construction.mineral_cost)
	if def.construction.gas_cost > 0:
		parts.append("%dG" % def.construction.gas_cost)
	if def.population != null and def.population.pop_cost > 0:
		parts.append("%dP" % def.population.pop_cost)
	parts.append("%dT" % def.construction.build_time_turns)
	return parts


func _research_cost_parts(research_id: String) -> Array[String]:
	var parts: Array[String] = []
	var registry: EntityRegistry = _load_registry()
	var research: ResearchDef = (
		registry.get_research_by_id(research_id) if registry != null else null
	)
	if research == null:
		return parts
	parts.append("%dM" % research.mineral_cost)
	if research.gas_cost > 0:
		parts.append("%dG" % research.gas_cost)
	parts.append("%dT" % research.research_time_turns)
	return parts


func _load_registry() -> EntityRegistry:
	return load("res://data/entity_registry.tres") as EntityRegistry


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


func _escape_key() -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	return event


func _key_press(keycode: Key) -> InputEventKey:
	return _key_event(keycode, true)


func _key_event(keycode: Key, pressed: bool) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	return event


func _free_mode(mode: Node) -> void:
	if mode == null:
		return
	if mode.is_inside_tree():
		remove_child(mode)
	mode.queue_free()
