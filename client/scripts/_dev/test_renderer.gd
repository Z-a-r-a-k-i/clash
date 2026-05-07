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
		["match_renderer_owner_modulate", _test_match_renderer_owner_modulate],
		["match_renderer_uses_visuals_registry", _test_match_renderer_uses_visuals_registry],
		# Chunk 4 — render_step events + reconciliation.
		["match_renderer_step_reconciles_destroyed_entity", _test_step_reconciles_destroyed_entity],
		["match_renderer_step_renders_attack_event", _test_step_renders_attack_event],
		["match_renderer_step_appends_combat_log", _test_step_appends_combat_log],
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
				"footprint": Vector2i(1, 3)
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
				"footprint": Vector2i(1, 3)
			},
			{
				"def_id": "mineral_patch",
				"owner": -1,
				"origin": Vector2i(5, 2),
				"footprint": Vector2i(1, 3)
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


# ---------- Helpers ----------


func _make_renderer() -> MatchRenderer:
	var scene: PackedScene = load(MATCH_SCENE_PATH)
	var instance := scene.instantiate() as MatchRenderer
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
		state.entities.append(e)
		var fp: Vector2i = spec.get("footprint", Vector2i(1, 1))
		state.tile_grid.place(e.id, Rect2i(e.origin, fp))
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
		["mineral_patch", Vector2i(1, 3)],
		["gas_geyser", Vector2i(3, 3)],
	]:
		var d := EntityDef.new()
		d.id = entry[0]
		d.footprint = entry[1]
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
