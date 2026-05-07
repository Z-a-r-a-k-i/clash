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
