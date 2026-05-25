@tool
extends Node

# Test runner for plan-07b1's MatchRenderer + EntityView. Same @tool
# _enter_tree pattern as test_resolver.gd / test_tile_grid.gd — attach
# to a node in test_renderer_scene.tscn, save, then re-open the scene
# to trigger.
#
# Tests are grouped by 07b1 chunk so each test starts passing as the
# chunk that introduces it lands.

const MATCH_SCENE_PATH := "res://scenes/match.tscn"
const ENTITY_VIEW_SCENE_PATH := "res://scenes/entity_view.tscn"


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
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

	print("[test_renderer] %d passed, %d failed" % [passed, failed])
	for test_name in fail_names:
		push_error("  failed: %s" % test_name)


func _all_tests() -> Array:
	return [
		# Chunk 2 — scaffolding smoke.
		["match_renderer_classes_load", _test_match_renderer_classes_load],
		# Chunk 3 — initial state rendering.
		[
			"match_renderer_initial_state_spawns_views",
			_test_match_renderer_initial_state_spawns_views
		],
		["match_renderer_renders_zero_hp_resource_sources", _test_renders_zero_hp_resource_sources],
		["match_renderer_owner_modulate", _test_match_renderer_owner_modulate],
		["match_renderer_uses_visuals_registry", _test_match_renderer_uses_visuals_registry],
		# Chunk 4 — render_step events + reconciliation.
		["match_renderer_step_reconciles_destroyed_entity", _test_step_reconciles_destroyed_entity],
		["match_renderer_step_renders_attack_event", _test_step_renders_attack_event],
		["match_renderer_step_appends_combat_log", _test_step_appends_combat_log],
		# Fresh-review fixes: cover the gaps identified pre-merge.
		["match_renderer_step_spawns_added_entity", _test_step_spawns_added_entity],
		["match_renderer_step_skips_dead_entities", _test_step_skips_dead_entities],
		["match_renderer_combat_log_caps_at_max", _test_combat_log_caps_at_max],
		["match_renderer_match_ended_event_logged", _test_match_ended_event_logged],
		["match_renderer_bind_state_clears_overlays", _test_bind_state_clears_overlays],
		# Codex-pass coverage for the fresh-review-fix renderer changes.
		["match_renderer_lethal_attack_renders_overlay", _test_lethal_attack_renders_overlay],
		[
			"match_renderer_uses_current_def_id_after_transform",
			_test_uses_current_def_id_after_transform
		],
		[
			"match_renderer_fit_camera_handles_null_entity_slots",
			_test_fit_camera_handles_null_entity_slots
		],
		["match_renderer_hides_geyser_under_refinery", _test_hides_geyser_under_refinery],
		["match_renderer_match_ended_draw_event_logged", _test_match_ended_draw_event_logged],
		["match_renderer_world_tile_hit_testing", _test_world_tile_hit_testing],
		["match_renderer_input_highlights", _test_input_highlights],
		["match_renderer_action_previews", _test_action_previews],
		["match_renderer_unit_training_progress", _test_unit_training_progress],
		["match_renderer_perspective_hides_unseen_enemy", _test_perspective_hides_unseen_enemy],
		[
			"match_renderer_perspective_switch_changes_visible_entities",
			_test_perspective_switch_changes_visible_entities
		],
		[
			"match_renderer_previously_seen_building_silhouette",
			_test_previously_seen_building_silhouette
		],
		["match_renderer_fog_overlay_marks_unseen_tiles", _test_fog_overlay_marks_unseen_tiles],
		[
			"match_renderer_focuses_player_start_at_playable_zoom",
			_test_focuses_player_start_at_playable_zoom
		],
		["match_renderer_camera_pan_and_zoom_helpers", _test_camera_pan_and_zoom_helpers],
	]


# ---------- Chunk 2 — scaffolding smoke ----------


func _test_match_renderer_classes_load() -> bool:
	# Smoke: MatchRenderer.new() works, both scenes instantiate without
	# errors. Catches "I broke the scene tree" / "I deleted a class_name".
	var renderer := MatchRenderer.new()
	if renderer == null:
		push_error("MatchRenderer.new() returned null")
		return false
	renderer.queue_free()

	var ev_scene: PackedScene = load(ENTITY_VIEW_SCENE_PATH)
	if ev_scene == null:
		push_error("Could not load %s" % ENTITY_VIEW_SCENE_PATH)
		return false
	var ev_instance := ev_scene.instantiate()
	if ev_instance == null:
		push_error("EntityView scene failed to instantiate")
		return false
	ev_instance.queue_free()

	var match_scene: PackedScene = load(MATCH_SCENE_PATH)
	if match_scene == null:
		push_error("Could not load %s" % MATCH_SCENE_PATH)
		return false
	var match_instance := match_scene.instantiate()
	if match_instance == null:
		push_error("Match scene failed to instantiate")
		return false
	match_instance.queue_free()

	return true


# ---------- Chunk 3 — initial state rendering ----------


func _test_match_renderer_initial_state_spawns_views() -> bool:
	# Synthetic 10x10 state with 3 entities → after bind_state, 3
	# EntityView children at the correct world positions.
	var registry := _renderer_registry()
	var state := _make_renderer_state(
		[
			{"def_id": "base", "owner": 0, "origin": Vector2i(2, 2), "footprint": Vector2i(4, 4)},
			{"def_id": "worker", "owner": 0, "origin": Vector2i(7, 2)},
			{
				"def_id": "mineral_patch",
				"owner": -1,
				"origin": Vector2i(7, 5),
				"footprint": Vector2i(1, 1)
			},
		],
		10,
		10
	)
	var renderer := _make_renderer()
	renderer.bind_state(state, registry)
	if renderer.entity_view_count() != 3:
		push_error("expected 3 EntityView children, got %d" % renderer.entity_view_count())
		_free_renderer(renderer)
		return false

	# Spot-check: base at (2,2) with 4x4 footprint should have view position
	# at center = (2 + 4/2, 2 + 4/2) tiles = (4, 4) tiles = (128, 128) world px.
	var base_entity := state.entities[0]
	var base_view := renderer.get_entity_view(base_entity.id)
	if base_view == null:
		push_error("no EntityView for base entity")
		_free_renderer(renderer)
		return false
	var expected_x: float = (2 + 4 / 2.0) * 32.0
	var expected_y: float = (2 + 4 / 2.0) * 32.0
	if not _approximately_equal(base_view.position, Vector2(expected_x, expected_y)):
		push_error(
			(
				"base view at %s, expected ~%s"
				% [str(base_view.position), str(Vector2(expected_x, expected_y))]
			)
		)
		_free_renderer(renderer)
		return false
	_free_renderer(renderer)
	return true


func _test_renders_zero_hp_resource_sources() -> bool:
	# MVP resources are not combat objects: they have ResourceSourceDef,
	# but no HealthDef, so ScenarioLoader seeds current_hp = 0. They still
	# need views and normal visibility.
	var registry := _renderer_registry()
	var state := _make_renderer_state(
		[
			{
				"def_id": "base",
				"owner": 0,
				"origin": Vector2i(2, 2),
				"footprint": Vector2i(4, 4),
				"hp": 1500,
				"id": 1
			},
			{
				"def_id": "mineral_patch",
				"owner": -1,
				"origin": Vector2i(6, 3),
				"footprint": Vector2i(1, 1),
				"hp": 0,
				"resources": 1500,
				"id": 2
			},
		],
		10,
		10
	)
	var renderer := _make_renderer()
	renderer.bind_state(state, registry)
	var ok := true
	if renderer.entity_view_count() != 2:
		push_error("expected base + zero-hp mineral views, got %d" % renderer.entity_view_count())
		ok = false
	if renderer.get_entity_view(2) == null:
		push_error("zero-hp mineral patch should have an EntityView")
		ok = false
	if not renderer.is_entity_view_visible(2):
		push_error("zero-hp mineral patch should be visible inside player vision")
		ok = false
	_free_renderer(renderer)
	return ok


func _test_match_renderer_owner_modulate() -> bool:
	# Owner 0 sprite reads blue-dominant; owner 1 reads red-dominant;
	# neutral stays untinted. We compare channel relationships rather than
	# exact Color values so the visual palette can be retuned without
	# breaking tests, and so we sidestep editor script-class cache staleness
	# that has bitten this test before.
	var registry := _renderer_registry()
	var state := _make_renderer_state(
		[
			{"def_id": "marine", "owner": 0, "origin": Vector2i(1, 1)},
			{"def_id": "marine", "owner": 1, "origin": Vector2i(3, 1)},
			{"def_id": "mineral_patch", "owner": -1, "origin": Vector2i(5, 1)},
		],
		10,
		10
	)
	var renderer := _make_renderer()
	renderer.bind_state(state, registry)
	var p0_mod := _modulate_of(renderer.get_entity_view(state.entities[0].id))
	var p1_mod := _modulate_of(renderer.get_entity_view(state.entities[1].id))
	var n_mod := _modulate_of(renderer.get_entity_view(state.entities[2].id))
	var ok := true
	if not (p0_mod.b > p0_mod.r and p0_mod.b > p0_mod.g and p0_mod.r < 0.6):
		push_error("player 0 modulate not blue-dominant: %s" % str(p0_mod))
		ok = false
	if not (p1_mod.r > p1_mod.b and p1_mod.r > p1_mod.g and p1_mod.b < 0.6):
		push_error("player 1 modulate not red-dominant: %s" % str(p1_mod))
		ok = false
	if not (absf(n_mod.r - n_mod.g) < 0.05 and absf(n_mod.g - n_mod.b) < 0.05 and n_mod.r > 0.9):
		push_error("neutral modulate not balanced/white: %s" % str(n_mod))
		ok = false
	_free_renderer(renderer)
	return ok


func _test_match_renderer_uses_visuals_registry() -> bool:
	# Two mineral_patch entities → both EntityViews use the same Texture2D
	# loaded from entity_visuals.tres. Catches "I hard-coded a sprite path"
	# regressions.
	var registry := _renderer_registry()
	var state := _make_renderer_state(
		[
			{
				"def_id": "mineral_patch",
				"owner": -1,
				"origin": Vector2i(2, 2),
				"footprint": Vector2i(1, 1)
			},
			{
				"def_id": "mineral_patch",
				"owner": -1,
				"origin": Vector2i(5, 2),
				"footprint": Vector2i(1, 1)
			},
		],
		10,
		10
	)
	var renderer := _make_renderer()
	renderer.bind_state(state, registry)
	var v_a := renderer.get_entity_view(state.entities[0].id)
	var v_b := renderer.get_entity_view(state.entities[1].id)
	var sprite_a: Sprite2D = v_a.get_node_or_null("Sprite2D") as Sprite2D
	var sprite_b: Sprite2D = v_b.get_node_or_null("Sprite2D") as Sprite2D
	var ok := (
		sprite_a != null
		and sprite_b != null
		and sprite_a.texture != null
		and sprite_a.texture == sprite_b.texture
	)
	if not ok:
		push_error("mineral_patch sprites did not share the same Texture2D resource")
	_free_renderer(renderer)
	return ok


func _test_focuses_player_start_at_playable_zoom() -> bool:
	var registry: EntityRegistry = _renderer_registry()
	var state: MatchState = _make_renderer_state(
		[
			{
				"def_id": "base",
				"owner": 0,
				"origin": Vector2i(2, 20),
				"footprint": Vector2i(4, 4),
				"id": 1
			},
			{"def_id": "worker", "owner": 0, "origin": Vector2i(7, 20), "id": 2},
			{
				"def_id": "mineral_patch",
				"owner": -1,
				"origin": Vector2i(10, 18),
				"footprint": Vector2i(1, 1),
				"id": 5
			},
			{
				"def_id": "gas_geyser",
				"owner": -1,
				"origin": Vector2i(12, 22),
				"footprint": Vector2i(2, 2),
				"id": 6
			},
			{
				"def_id": "base",
				"owner": 1,
				"origin": Vector2i(24, 2),
				"footprint": Vector2i(4, 4),
				"id": 3
			},
			{"def_id": "worker", "owner": 1, "origin": Vector2i(23, 7), "id": 4},
			{
				"def_id": "mineral_patch",
				"owner": -1,
				"origin": Vector2i(20, 4),
				"footprint": Vector2i(1, 1),
				"id": 7
			},
			{
				"def_id": "gas_geyser",
				"owner": -1,
				"origin": Vector2i(18, 4),
				"footprint": Vector2i(2, 2),
				"id": 8
			},
		],
		30,
		30
	)
	var renderer: MatchRenderer = _make_renderer()
	renderer.bind_state(state, registry)
	if not renderer.has_method("focus_player_start"):
		push_error("renderer should expose focus_player_start for dev play mode")
		_free_renderer(renderer)
		return false
	renderer.call("focus_player_start", 0)
	var camera: Camera2D = renderer.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		push_error("renderer has no Camera2D")
		_free_renderer(renderer)
		return false
	var ok: bool = true
	if camera.position.distance_to(Vector2(8.5, 21.5) * 32.0) > 64.0:
		push_error(
			(
				"P0 focus camera position is %s, expected base + resource cluster"
				% str(camera.position)
			)
		)
		ok = false
	if camera.zoom.x < 1.5 or camera.zoom.x > 3.0:
		push_error("P0 focus zoom is %s, expected readable dev zoom" % str(camera.zoom))
		ok = false
	renderer.call("focus_player_start", 1)
	if camera.position.distance_to(Vector2(23.0, 5.0) * 32.0) > 48.0:
		push_error(
			(
				"P1 focus camera position is %s, expected base + resource cluster"
				% str(camera.position)
			)
		)
		ok = false
	_free_renderer(renderer)
	return ok


func _test_camera_pan_and_zoom_helpers() -> bool:
	var registry: EntityRegistry = _renderer_registry()
	var state: MatchState = _make_renderer_state(
		[{"def_id": "base", "owner": 0, "origin": Vector2i(2, 2), "footprint": Vector2i(4, 4)}],
		30,
		30
	)
	var renderer: MatchRenderer = _make_renderer()
	renderer.bind_state(state, registry)
	for method in ["focus_player_start", "zoom_camera", "pan_camera_by_screen_delta"]:
		if not renderer.has_method(method):
			push_error("renderer should expose %s for dev camera control" % method)
			_free_renderer(renderer)
			return false
	renderer.call("focus_player_start", 0)
	var camera: Camera2D = renderer.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		push_error("renderer has no Camera2D")
		_free_renderer(renderer)
		return false
	var original_position: Vector2 = camera.position
	var original_zoom: float = camera.zoom.x
	renderer.call("zoom_camera", 2.0)
	var ok: bool = true
	if camera.zoom.x <= original_zoom:
		push_error(
			"zoom_camera(2.0) should zoom in from %f, got %s" % [original_zoom, str(camera.zoom)]
		)
		ok = false
	for i in range(12):
		renderer.call("zoom_camera", 2.0)
	if camera.zoom.x > 4.0:
		push_error("zoom should clamp at or below 4.0, got %s" % str(camera.zoom))
		ok = false
	renderer.call("pan_camera_by_screen_delta", Vector2(64.0, 32.0))
	if camera.position == original_position:
		push_error("pan_camera_by_screen_delta should change camera position")
		ok = false
	_free_renderer(renderer)
	return ok


# ---------- Helpers ----------


func _make_renderer() -> MatchRenderer:
	var scene: PackedScene = load(MATCH_SCENE_PATH)
	if scene == null:
		push_error("_make_renderer: could not load %s" % MATCH_SCENE_PATH)
		return null
	var instance: MatchRenderer = scene.instantiate() as MatchRenderer
	if instance == null:
		push_error("_make_renderer: scene did not instantiate as MatchRenderer")
		return null
	# Add to scene tree so @onready / get_viewport_rect work.
	add_child(instance)
	return instance


func _free_renderer(renderer: MatchRenderer) -> void:
	if renderer == null:
		return
	if renderer.is_inside_tree():
		remove_child(renderer)
	renderer.queue_free()


func _make_renderer_state(entity_specs: Array, w: int, h: int) -> MatchState:
	var state := MatchState.new()
	state.tile_grid = TileGrid.new(w, h)
	state.next_entity_id = 1
	# Two players so owner_player_id 0 and 1 resolve correctly.
	for pid in [0, 1]:
		var p := PlayerState.new()
		p.player_id = pid
		state.players.append(p)
	for spec in entity_specs:
		var e := Entity.new()
		# Honor an explicit "id" in the spec so reconciliation tests can
		# build matching states across calls; otherwise auto-assign.
		if spec.has("id"):
			e.id = spec.get("id")
			state.next_entity_id = max(state.next_entity_id, e.id + 1)
		else:
			e.id = state.next_entity_id
			state.next_entity_id += 1
		e.def_id = spec.get("def_id", "")
		e.current_def_id = e.def_id
		e.owner_player_id = spec.get("owner", -1)
		e.origin = spec.get("origin", Vector2i.ZERO)
		e.current_hp = spec.get("hp", 50)
		e.current_resource_amount = spec.get("resources", -1)
		state.entities.append(e)
		var fp: Vector2i = spec.get("footprint", Vector2i(1, 1))
		var rect := Rect2i(e.origin, fp)
		if spec.has("overlap_id"):
			state.tile_grid.place_overlapping(e.id, rect, spec.get("overlap_id", -1))
		else:
			state.tile_grid.place(e.id, rect)
	return state


# Tiny EntityRegistry — defs only need id + footprint for the renderer.
func _renderer_registry() -> EntityRegistry:
	var registry := EntityRegistry.new()
	var defs: Array[EntityDef] = []
	for entry in [
		["base", Vector2i(4, 4)],
		["worker", Vector2i(1, 1)],
		["marine", Vector2i(1, 1)],
		["tank", Vector2i(2, 2)],
		["siege_tank", Vector2i(2, 2)],
		["barracks", Vector2i(3, 3)],
		["watch_tower", Vector2i(1, 1)],
		["mineral_patch", Vector2i(1, 1)],
		["gas_geyser", Vector2i(2, 2)],
		["refinery", Vector2i(2, 2)],
	]:
		var d := EntityDef.new()
		d.id = entry[0]
		d.footprint = entry[1]
		d.vision = VisionDef.new()
		if d.id == "base":
			d.vision.sight_radius = 10
		else:
			d.vision.sight_radius = 3 if d.id != "watch_tower" else 0
		if ["base", "barracks"].has(d.id):
			d.tags.append("building")
		if ["mineral_patch", "gas_geyser"].has(d.id):
			d.tags.append("resource_source")
			d.resource_source = ResourceSourceDef.new()
		if d.id == "gas_geyser":
			d.tags.append("gas_geyser")
			d.resource_source.resource_type = "gas"
			d.resource_source.requires_extractor = true
		if d.id == "refinery":
			d.tags.append_array(["building", "refinery", "extractor"])
		defs.append(d)
	registry.entities = defs
	return registry


static func _approximately_equal(a: Vector2, b: Vector2) -> bool:
	return absf(a.x - b.x) < 0.5 and absf(a.y - b.y) < 0.5


static func _modulate_of(view: EntityView) -> Color:
	if view == null:
		return Color(1, 1, 1, 1)
	var sprite := view.get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return Color(1, 1, 1, 1)
	return sprite.modulate


# ---------- Chunk 4 — render_step events + reconciliation ----------


func _test_step_reconciles_destroyed_entity() -> bool:
	# Bind a state with 3 entities, then call render_step with a state
	# missing one of them → that view fades and is removed from the
	# views_by_id map. Catches "I forgot to free dead entities" leaks.
	var registry := _renderer_registry()
	var state_a := _make_renderer_state(
		[
			{"def_id": "marine", "owner": 0, "origin": Vector2i(1, 1), "id": 1},
			{"def_id": "marine", "owner": 0, "origin": Vector2i(2, 1), "id": 2},
			{"def_id": "marine", "owner": 1, "origin": Vector2i(8, 1), "id": 3},
		],
		10,
		10
	)
	var renderer := _make_renderer()
	renderer.bind_state(state_a, registry)
	if renderer.entity_view_count() != 3:
		push_error("setup: expected 3 views, got %d" % renderer.entity_view_count())
		_free_renderer(renderer)
		return false
	# State B drops entity 2 (marine #2 destroyed).
	var state_b := _make_renderer_state(
		[
			{"def_id": "marine", "owner": 0, "origin": Vector2i(1, 1), "id": 1},
			{"def_id": "marine", "owner": 1, "origin": Vector2i(8, 1), "id": 3},
		],
		10,
		10
	)
	renderer.render_step(state_b, [])
	if renderer.entity_view_count() != 2:
		push_error("expected 2 views after destruction, got %d" % renderer.entity_view_count())
		_free_renderer(renderer)
		return false
	if renderer.get_entity_view(2) != null:
		push_error("destroyed entity #2 still has a registered view")
		_free_renderer(renderer)
		return false
	_free_renderer(renderer)
	return true


func _test_step_renders_attack_event() -> bool:
	# render_step with a single ENTITY_DAMAGED event spawns one Line2D
	# under Overlays/AttackLines and one DamageLabel under
	# Overlays/DamageLabels.
	var registry := _renderer_registry()
	var state := _make_renderer_state(
		[
			{"def_id": "marine", "owner": 0, "origin": Vector2i(1, 1), "id": 1},
			{"def_id": "marine", "owner": 1, "origin": Vector2i(8, 1), "id": 2},
		],
		10,
		10
	)
	var renderer := _make_renderer()
	renderer.bind_state(state, registry)
	var event := ResolverEvent.new()
	event.type = ResolverEvent.Type.ENTITY_DAMAGED
	event.actor_id = 1
	event.target_id = 2
	event.damage = 7
	event.hp_after = 18
	renderer.render_step(state, [event])
	var ok := true
	if renderer.attack_line_count() != 1:
		push_error("expected 1 attack line, got %d" % renderer.attack_line_count())
		ok = false
	if renderer.damage_label_count() != 1:
		push_error("expected 1 damage label, got %d" % renderer.damage_label_count())
		ok = false
	_free_renderer(renderer)
	return ok


func _test_step_appends_combat_log() -> bool:
	# Damage event + destruction event each append a line to the combat
	# log. Verify both substrings show up so we don't regress to silently
	# eating events.
	var registry := _renderer_registry()
	var state := _make_renderer_state(
		[
			{"def_id": "marine", "owner": 0, "origin": Vector2i(1, 1), "id": 1},
			{"def_id": "marine", "owner": 1, "origin": Vector2i(8, 1), "id": 2},
		],
		10,
		10
	)
	var renderer := _make_renderer()
	renderer.bind_state(state, registry)
	var damage_event := ResolverEvent.new()
	damage_event.type = ResolverEvent.Type.ENTITY_DAMAGED
	damage_event.actor_id = 1
	damage_event.target_id = 2
	damage_event.damage = 7
	damage_event.hp_after = 0
	var destroy_event := ResolverEvent.new()
	destroy_event.type = ResolverEvent.Type.ENTITY_DESTROYED
	destroy_event.actor_id = 1
	destroy_event.target_id = 2
	# State B drops the destroyed entity so reconciliation removes its view.
	var state_b := _make_renderer_state(
		[
			{"def_id": "marine", "owner": 0, "origin": Vector2i(1, 1), "id": 1},
		],
		10,
		10
	)
	renderer.render_step(state_b, [damage_event, destroy_event])
	var log_text := renderer.combat_log_text()
	var ok := log_text.find("hit #2 for 7") != -1 and log_text.find("#2 destroyed") != -1
	if not ok:
		push_error("combat log missing expected text. got: %s" % log_text)
	_free_renderer(renderer)
	return ok


# ---------- Fresh-review coverage gaps ----------


func _test_step_spawns_added_entity() -> bool:
	# Entity appears in new_state but had no view → reconciliation
	# spawns one.
	var registry := _renderer_registry()
	var state_a := _make_renderer_state(
		[{"def_id": "marine", "owner": 0, "origin": Vector2i(1, 1), "id": 1}], 10, 10
	)
	var renderer := _make_renderer()
	renderer.bind_state(state_a, registry)
	var state_b := _make_renderer_state(
		[
			{"def_id": "marine", "owner": 0, "origin": Vector2i(1, 1), "id": 1},
			{"def_id": "marine", "owner": 0, "origin": Vector2i(2, 1), "id": 2},
		],
		10,
		10
	)
	renderer.render_step(state_b, [])
	var ok := (
		renderer.entity_view_count() == 2
		and renderer.get_entity_view(1) != null
		and renderer.get_entity_view(2) != null
	)
	if not ok:
		push_error("expected views {1,2} after add, got count %d" % renderer.entity_view_count())
	_free_renderer(renderer)
	return ok


func _test_step_skips_dead_entities() -> bool:
	# Resolver keeps Entity records with current_hp=0 around until
	# end-of-turn cleanup. The renderer must not respawn views for
	# corpses on subsequent render_steps.
	var registry := _renderer_registry()
	var state_a := _make_renderer_state(
		[
			{"def_id": "marine", "owner": 0, "origin": Vector2i(1, 1), "id": 1},
			{"def_id": "marine", "owner": 1, "origin": Vector2i(8, 1), "id": 2},
		],
		10,
		10
	)
	var renderer := _make_renderer()
	renderer.bind_state(state_a, registry)
	if renderer.entity_view_count() != 2:
		push_error("setup: expected 2 views, got %d" % renderer.entity_view_count())
		_free_renderer(renderer)
		return false
	# State B keeps the killed entity's record but with hp=0.
	var state_b := _make_renderer_state(
		[
			{"def_id": "marine", "owner": 0, "origin": Vector2i(1, 1), "id": 1},
			{"def_id": "marine", "owner": 1, "origin": Vector2i(8, 1), "id": 2, "hp": 0},
		],
		10,
		10
	)
	renderer.render_step(state_b, [])
	if renderer.entity_view_count() != 1:
		push_error(
			"hp=0 entity should not have a view, got count %d" % renderer.entity_view_count()
		)
		_free_renderer(renderer)
		return false
	# Re-run render_step with the same dead-entity state — must not
	# respawn the corpse's view.
	renderer.render_step(state_b, [])
	var ok := renderer.entity_view_count() == 1
	if not ok:
		push_error("corpse respawned on second render_step")
	_free_renderer(renderer)
	return ok


func _test_combat_log_caps_at_max() -> bool:
	# Append more than the cap and verify the buffer trims oldest
	# entries while keeping the newest. Catches the "split() didn't
	# actually trim" regression.
	var registry := _renderer_registry()
	var state := _make_renderer_state(
		[
			{"def_id": "marine", "owner": 0, "origin": Vector2i(1, 1), "id": 1},
			{"def_id": "marine", "owner": 1, "origin": Vector2i(8, 1), "id": 2},
		],
		10,
		10
	)
	var renderer := _make_renderer()
	renderer.bind_state(state, registry)
	for i in range(120):
		var event := ResolverEvent.new()
		event.type = ResolverEvent.Type.ENTITY_DAMAGED
		event.actor_id = 1
		event.target_id = 2
		event.damage = i
		event.hp_after = 100
		renderer.render_step(state, [event])
	var ok := true
	if renderer.combat_log_line_count() > 50:
		push_error("combat log exceeded cap: %d lines" % renderer.combat_log_line_count())
		ok = false
	# Anchor against the full per-line prefix the renderer emits — looking
	# for "for N" alone or with a single trailing space risks matching
	# substrings of larger N (e.g. "for 100" matches a "for 10" search)
	# or going vacuous if the format changes.
	# Newest line should still be present (last loop's damage = 119).
	if renderer.combat_log_text().find("hit #2 for 119 ") == -1:
		push_error("combat log dropped newest line")
		ok = false
	# Oldest line should have been trimmed.
	if renderer.combat_log_text().find("hit #2 for 0 ") != -1:
		push_error("combat log retained oldest line past cap")
		ok = false
	_free_renderer(renderer)
	return ok


func _test_match_ended_event_logged() -> bool:
	# MATCH_ENDED → "Match ended — winner: P{n}" appended to log.
	var registry := _renderer_registry()
	var state := _make_renderer_state(
		[{"def_id": "marine", "owner": 0, "origin": Vector2i(1, 1), "id": 1}], 10, 10
	)
	var renderer := _make_renderer()
	renderer.bind_state(state, registry)
	var event := ResolverEvent.new()
	event.type = ResolverEvent.Type.MATCH_ENDED
	event.winner_player_id = 0
	renderer.render_step(state, [event])
	var ok := renderer.combat_log_text().find("winner: P0") != -1
	if not ok:
		push_error("match-ended log entry missing: %s" % renderer.combat_log_text())
	_free_renderer(renderer)
	return ok


func _test_bind_state_clears_overlays() -> bool:
	# Re-binding to a different scenario must wipe stale overlays + log,
	# otherwise yellow lines and old "#X hit #Y" entries leak across
	# matches.
	var registry := _renderer_registry()
	var state_a := _make_renderer_state(
		[
			{"def_id": "marine", "owner": 0, "origin": Vector2i(1, 1), "id": 1},
			{"def_id": "marine", "owner": 1, "origin": Vector2i(8, 1), "id": 2},
		],
		10,
		10
	)
	var renderer := _make_renderer()
	renderer.bind_state(state_a, registry)
	var event := ResolverEvent.new()
	event.type = ResolverEvent.Type.ENTITY_DAMAGED
	event.actor_id = 1
	event.target_id = 2
	event.damage = 5
	event.hp_after = 95
	renderer.render_step(state_a, [event])
	if renderer.attack_line_count() == 0 or renderer.combat_log_line_count() == 0:
		push_error("setup: expected at least one overlay + log line after attack")
		_free_renderer(renderer)
		return false
	var state_b := _make_renderer_state(
		[{"def_id": "marine", "owner": 0, "origin": Vector2i(1, 1), "id": 1}], 10, 10
	)
	renderer.bind_state(state_b, registry)
	var ok := (
		renderer.attack_line_count() == 0
		and renderer.damage_label_count() == 0
		and renderer.combat_log_line_count() == 0
	)
	if not ok:
		push_error(
			(
				"bind_state did not clear overlays/log: lines=%d labels=%d log=%d"
				% [
					renderer.attack_line_count(),
					renderer.damage_label_count(),
					renderer.combat_log_line_count()
				]
			)
		)
	_free_renderer(renderer)
	return ok


# ---------- Codex-pass coverage for fresh-review-fix changes ----------


func _test_lethal_attack_renders_overlay() -> bool:
	# Regression test for the "reconcile-before-events drops lethal-hit
	# visuals" bug. Send ENTITY_DAMAGED + ENTITY_DESTROYED in the same
	# step where the target's hp is 0 in new_state. Even though the target
	# disappears at end of step, the attack line + damage label MUST have
	# rendered before the destruction took effect.
	var registry := _renderer_registry()
	var state_a := _make_renderer_state(
		[
			{"def_id": "marine", "owner": 0, "origin": Vector2i(1, 1), "id": 1},
			{"def_id": "marine", "owner": 1, "origin": Vector2i(8, 1), "id": 2},
		],
		10,
		10
	)
	var renderer := _make_renderer()
	renderer.bind_state(state_a, registry)
	# State B: target now hp=0 (resolver kept the record per ADR-0010).
	var state_b := _make_renderer_state(
		[
			{"def_id": "marine", "owner": 0, "origin": Vector2i(1, 1), "id": 1},
			{"def_id": "marine", "owner": 1, "origin": Vector2i(8, 1), "id": 2, "hp": 0},
		],
		10,
		10
	)
	var damage := ResolverEvent.new()
	damage.type = ResolverEvent.Type.ENTITY_DAMAGED
	damage.actor_id = 1
	damage.target_id = 2
	damage.damage = 50
	damage.hp_after = 0
	var destroy := ResolverEvent.new()
	destroy.type = ResolverEvent.Type.ENTITY_DESTROYED
	destroy.actor_id = 1
	destroy.target_id = 2
	renderer.render_step(state_b, [damage, destroy])
	var ok := true
	if renderer.attack_line_count() != 1:
		push_error("lethal hit lost attack line; expected 1 got %d" % renderer.attack_line_count())
		ok = false
	if renderer.damage_label_count() != 1:
		push_error(
			"lethal hit lost damage label; expected 1 got %d" % renderer.damage_label_count()
		)
		ok = false
	# ENTITY_DESTROYED still kicked off fade + de-registration.
	if renderer.get_entity_view(2) != null:
		push_error("destroyed view still registered in views_by_id")
		ok = false
	_free_renderer(renderer)
	return ok


func _test_uses_current_def_id_after_transform() -> bool:
	# Renderer must look up sprite + def via current_def_id (post-transform
	# form), not def_id (canonical form). With def_id="tank" and
	# current_def_id="siege_tank", the view should carry the siege_tank
	# texture, not the tank one.
	var registry := _renderer_registry()
	var state := _make_renderer_state(
		[{"def_id": "tank", "owner": 0, "origin": Vector2i(2, 2), "id": 1}], 10, 10
	)
	# Simulate a transform: keep def_id (canonical) but flip current_def_id.
	state.entities[0].current_def_id = "siege_tank"
	var renderer := _make_renderer()
	renderer.bind_state(state, registry)
	var view := renderer.get_entity_view(1)
	if view == null:
		push_error("expected view for transformed entity")
		_free_renderer(renderer)
		return false
	var sprite: Sprite2D = view.get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null or sprite.texture == null:
		push_error("transformed view has no sprite/texture")
		_free_renderer(renderer)
		return false
	var expected := load("res://data/art/sprites/siege_tank.png") as Texture2D
	var ok := sprite.texture == expected
	if not ok:
		push_error(
			(
				"transformed view used wrong texture; expected siege_tank, got %s"
				% str(sprite.texture.resource_path if sprite.texture != null else "null")
			)
		)
	_free_renderer(renderer)
	return ok


func _test_fit_camera_handles_null_entity_slots() -> bool:
	# MatchState.clone() preserves null entries in state.entities to keep
	# positional indices stable. Iterating raw state.entities crashes the
	# camera-fit loop on null. Construct a state with a null slot and
	# assert bind_state completes without erroring.
	var registry := _renderer_registry()
	var state := _make_renderer_state(
		[
			{"def_id": "marine", "owner": 0, "origin": Vector2i(1, 1), "id": 1},
			{"def_id": "marine", "owner": 1, "origin": Vector2i(8, 1), "id": 2},
		],
		10,
		10
	)
	# Inject a null after construction.
	state.entities.append(null)
	var renderer := _make_renderer()
	renderer.bind_state(state, registry)
	# Both real entities still rendered.
	var ok := (
		renderer.entity_view_count() == 2
		and renderer.get_entity_view(1) != null
		and renderer.get_entity_view(2) != null
	)
	if not ok:
		push_error(
			"null slot crashed bind_state; expected 2 views, got %d" % renderer.entity_view_count()
		)
	_free_renderer(renderer)
	return ok


func _test_hides_geyser_under_refinery() -> bool:
	var registry := _renderer_registry()
	var state := _make_renderer_state(
		[
			{
				"def_id": "gas_geyser",
				"owner": -1,
				"origin": Vector2i(5, 5),
				"footprint": Vector2i(2, 2),
				"id": 1,
				"hp": 0,
				"resources": -1,
			},
			{
				"def_id": "refinery",
				"owner": 0,
				"origin": Vector2i(5, 5),
				"footprint": Vector2i(2, 2),
				"id": 2,
				"hp": 500,
				"overlap_id": 1,
			},
		],
		12,
		12
	)
	var renderer := _make_renderer()
	renderer.bind_state(state, registry)
	var ok := true
	if renderer.get_entity_view(1) == null:
		push_error("covered geyser should still have a view for reveal after refinery removal")
		ok = false
	if renderer.call("is_entity_view_visible", 1):
		push_error("covered geyser sprite should be hidden")
		ok = false
	if not renderer.call("is_entity_view_visible", 2):
		push_error("refinery covering geyser should be visible")
		ok = false
	for tile: Vector2i in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6), Vector2i(6, 6)]:
		var hit_id: int = renderer.call("entity_id_at_tile", tile)
		if hit_id != 2:
			push_error(
				"clicking covered geyser tile %s should hit refinery, got #%d" % [str(tile), hit_id]
			)
			ok = false
	_free_renderer(renderer)
	return ok


func _test_match_ended_draw_event_logged() -> bool:
	# winner_player_id == -1 is the resolver's draw/unknown sentinel.
	# Render that explicitly rather than as "P-1".
	var registry := _renderer_registry()
	var state := _make_renderer_state(
		[{"def_id": "marine", "owner": 0, "origin": Vector2i(1, 1), "id": 1}], 10, 10
	)
	var renderer := _make_renderer()
	renderer.bind_state(state, registry)
	var event := ResolverEvent.new()
	event.type = ResolverEvent.Type.MATCH_ENDED
	event.winner_player_id = -1
	renderer.render_step(state, [event])
	var log_text := renderer.combat_log_text()
	var ok := log_text.find("draw") != -1 and log_text.find("P-1") == -1
	if not ok:
		push_error("draw event not rendered as 'draw'; log: %s" % log_text)
	_free_renderer(renderer)
	return ok


# ---------- Plan 07b2 — input hit testing + highlights ----------


func _test_world_tile_hit_testing() -> bool:
	var registry := _renderer_registry()
	var state := _make_renderer_state(
		[
			{
				"def_id": "base",
				"owner": 0,
				"origin": Vector2i(2, 2),
				"footprint": Vector2i(4, 4),
				"id": 1
			},
			{"def_id": "worker", "owner": 0, "origin": Vector2i(7, 2), "id": 2},
		],
		12,
		12
	)
	var renderer := _make_renderer()
	renderer.bind_state(state, registry)
	var tile: Vector2i = renderer.call("world_to_tile", Vector2(80.0, 80.0))
	var base_id: int = renderer.call("entity_id_at_tile", Vector2i(3, 3))
	var empty_id: int = renderer.call("entity_id_at_tile", Vector2i(0, 0))
	var by_world: int = renderer.call("entity_id_at_world", Vector2(112.0, 112.0))
	var ok := true
	if tile != Vector2i(2, 2):
		push_error("world_to_tile returned %s, expected (2, 2)" % str(tile))
		ok = false
	if base_id != 1:
		push_error("entity_id_at_tile inside base returned %d, expected 1" % base_id)
		ok = false
	if empty_id != -1:
		push_error("entity_id_at_tile on empty tile returned %d, expected -1" % empty_id)
		ok = false
	if by_world != 1:
		push_error("entity_id_at_world inside base returned %d, expected 1" % by_world)
		ok = false
	_free_renderer(renderer)
	return ok


func _test_input_highlights() -> bool:
	var registry := _renderer_registry()
	var state := _make_renderer_state(
		[
			{
				"def_id": "base",
				"owner": 0,
				"origin": Vector2i(2, 2),
				"footprint": Vector2i(4, 4),
				"id": 1
			},
			{"def_id": "worker", "owner": 0, "origin": Vector2i(7, 2), "id": 2},
		],
		12,
		12
	)
	var renderer := _make_renderer()
	renderer.bind_state(state, registry)
	renderer.call("set_selected_entity_id", 1)
	renderer.call("set_hover_tile", Vector2i(8, 8))
	var highlighted: int = renderer.call("input_highlight_count")
	if highlighted != 2:
		push_error("expected selected + hover highlights, got %d" % highlighted)
		_free_renderer(renderer)
		return false
	renderer.call("clear_input_highlights")
	if renderer.call("input_highlight_count") != 0:
		push_error("clear_input_highlights should remove all input highlights")
		_free_renderer(renderer)
		return false
	renderer.call("set_selected_entity_id", 1)
	renderer.bind_state(state, registry)
	if renderer.call("input_highlight_count") != 0:
		push_error("bind_state should clear stale input highlights")
		_free_renderer(renderer)
		return false
	_free_renderer(renderer)
	return true


func _test_action_previews() -> bool:
	var registry := _renderer_registry()
	var state := _make_renderer_state(
		[
			{"def_id": "worker", "owner": 0, "origin": Vector2i(1, 1), "id": 1},
			{"def_id": "mineral_patch", "owner": -1, "origin": Vector2i(6, 1), "id": 2},
		],
		10,
		10
	)
	var renderer := _make_renderer()
	renderer.bind_state(state, registry)
	for method in ["set_action_previews", "action_preview_count"]:
		if not renderer.has_method(method):
			push_error("renderer should expose %s" % method)
			_free_renderer(renderer)
			return false
	(
		renderer
		. call(
			"set_action_previews",
			[
				{
					"entity_id": 1,
					"kind": "Gather",
					"target_entity_id": 2,
					"target_tile": Vector2i(6, 1),
				},
			]
		)
	)
	var ok := true
	if renderer.call("action_preview_count") != 1:
		push_error("expected one action preview after set_action_previews")
		ok = false
	renderer.bind_state(state, registry)
	if renderer.call("action_preview_count") != 0:
		push_error("bind_state should clear stale action previews")
		ok = false
	_free_renderer(renderer)
	return ok


func _test_unit_training_progress() -> bool:
	var registry := _renderer_registry()
	var marine_def: EntityDef = registry.get_by_id("marine")
	if marine_def == null:
		push_error("test registry missing marine")
		return false
	marine_def.construction = ConstructionDef.new()
	marine_def.construction.build_time_turns = 3
	var state := _make_renderer_state(
		[
			{"def_id": "barracks", "owner": 0, "origin": Vector2i(2, 2), "id": 1},
		],
		10,
		10
	)
	var barracks: Entity = state.get_entity_by_id(1)
	barracks.production_state = ProductionState.new()
	barracks.production_state.active = {
		ProductionState.KEY_KIND: ProductionState.KIND_UNIT,
		ProductionState.KEY_DEF_ID: "marine",
		ProductionState.KEY_TURNS_REMAINING: 2,
	}
	var renderer := _make_renderer()
	renderer.bind_state(state, registry)
	if not renderer.has_method("production_progress_count"):
		push_error("renderer should expose production_progress_count")
		_free_renderer(renderer)
		return false
	var progress_count: int = renderer.call("production_progress_count")
	var ok: bool = progress_count == 1
	if not ok:
		push_error("expected one unit-training progress bar, got %d" % progress_count)
	_free_renderer(renderer)
	return ok


# ---------- Plan 07b3 — perspective + fog ----------


func _test_perspective_hides_unseen_enemy() -> bool:
	var registry := _renderer_registry()
	var state := _make_renderer_state(
		[
			{"def_id": "worker", "owner": 0, "origin": Vector2i(1, 1), "id": 1},
			{"def_id": "marine", "owner": 1, "origin": Vector2i(8, 1), "id": 2},
		],
		12,
		12
	)
	var renderer := _make_renderer()
	renderer.bind_state(state, registry)
	renderer.call("set_perspective_player_id", 0)
	var ok := true
	if not renderer.call("is_entity_view_visible", 1):
		push_error("active player's own worker should render")
		ok = false
	if renderer.call("is_entity_view_visible", 2):
		push_error("enemy outside P0 vision should be hidden")
		ok = false
	if renderer.call("entity_id_at_tile", Vector2i(8, 1)) != -1:
		push_error("hidden enemy tile should not be hit-testable")
		ok = false
	_free_renderer(renderer)
	return ok


func _test_perspective_switch_changes_visible_entities() -> bool:
	var registry := _renderer_registry()
	var state := _make_renderer_state(
		[
			{"def_id": "worker", "owner": 0, "origin": Vector2i(1, 1), "id": 1},
			{"def_id": "marine", "owner": 1, "origin": Vector2i(8, 1), "id": 2},
		],
		12,
		12
	)
	var renderer := _make_renderer()
	renderer.bind_state(state, registry)
	renderer.call("set_perspective_player_id", 0)
	if not renderer.call("is_entity_view_visible", 1) or renderer.call("is_entity_view_visible", 2):
		push_error("setup: expected only P0 worker visible from P0 perspective")
		_free_renderer(renderer)
		return false
	renderer.call("set_perspective_player_id", 1)
	var ok := true
	if renderer.call("is_entity_view_visible", 1):
		push_error("P0 worker should hide from P1 perspective")
		ok = false
	if not renderer.call("is_entity_view_visible", 2):
		push_error("P1 marine should render from P1 perspective")
		ok = false
	if renderer.call("perspective_player_id") != 1:
		push_error("renderer did not retain P1 perspective")
		ok = false
	_free_renderer(renderer)
	return ok


func _test_previously_seen_building_silhouette() -> bool:
	var registry := _renderer_registry()
	var state_a := _make_renderer_state(
		[
			{"def_id": "worker", "owner": 0, "origin": Vector2i(1, 1), "id": 1},
			{"def_id": "barracks", "owner": 1, "origin": Vector2i(4, 1), "id": 2},
		],
		14,
		14
	)
	var renderer := _make_renderer()
	renderer.bind_state(state_a, registry)
	renderer.call("set_perspective_player_id", 0)
	if not renderer.call("is_entity_view_visible", 2):
		push_error("setup: enemy building should initially be visible")
		_free_renderer(renderer)
		return false
	var state_b := _make_renderer_state(
		[
			{"def_id": "worker", "owner": 0, "origin": Vector2i(1, 10), "id": 1},
			{"def_id": "barracks", "owner": 1, "origin": Vector2i(4, 1), "id": 2},
		],
		14,
		14
	)
	renderer.render_step(state_b, [])
	var ok := true
	if not renderer.call("is_entity_view_visible", 2):
		push_error("previously seen enemy building should stay visible as silhouette")
		ok = false
	if not renderer.call("is_entity_view_silhouette", 2):
		push_error("previously seen enemy building should be marked silhouette")
		ok = false
	if renderer.call("entity_id_at_tile", Vector2i(4, 1)) != -1:
		push_error("previously seen but not current building should not be targetable")
		ok = false
	_free_renderer(renderer)
	return ok


func _test_fog_overlay_marks_unseen_tiles() -> bool:
	var registry := _renderer_registry()
	var state := _make_renderer_state(
		[
			{"def_id": "watch_tower", "owner": 0, "origin": Vector2i(2, 2), "id": 1},
		],
		5,
		5
	)
	var renderer := _make_renderer()
	renderer.bind_state(state, registry)
	renderer.call("set_perspective_player_id", 0)
	var overlay_count: int = renderer.call("fog_overlay_count")
	var ok := overlay_count == 24
	if not ok:
		push_error("expected 24 unseen fog tiles, got %d" % overlay_count)
	_free_renderer(renderer)
	return ok
