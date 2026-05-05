@tool
extends EditorPlugin

# Adds a "Bake MVP Map" entry under Project → Tools that re-bakes the
# canonical mvp_map.tscn into mvp_map.tres. Hardcoded paths — there's
# only one map in M0.

const _MENU_ITEM := "Bake MVP Map"
const _MAP_SCENE_PATH := "res://data/scenarios/mvp_map.tscn"
const _OUTPUT_PATH := "res://data/scenarios/mvp_map.tres"
const _REGISTRY_PATH := "res://data/entity_registry.tres"
const _TUNABLES_PATH := "res://data/tunables.tres"


func _enter_tree() -> void:
	add_tool_menu_item(_MENU_ITEM, _on_bake_mvp_map)


func _exit_tree() -> void:
	remove_tool_menu_item(_MENU_ITEM)


func _on_bake_mvp_map() -> void:
	if not ResourceLoader.exists(_MAP_SCENE_PATH):
		push_error(
			(
				"[clash_dev] %s does not exist yet — author it first (plan-08 chunk 4)."
				% _MAP_SCENE_PATH
			)
		)
		return
	var registry: EntityRegistry = load(_REGISTRY_PATH)
	var tunables: Tunables = load(_TUNABLES_PATH)
	if registry == null or tunables == null:
		push_error("[clash_dev] Missing registry or tunables.")
		return
	var starting_resources := {
		0: {"minerals": tunables.starting_minerals, "gas": tunables.starting_gas},
		1: {"minerals": tunables.starting_minerals, "gas": tunables.starting_gas},
	}
	var err := (
		MapBaker
		. bake(
			_MAP_SCENE_PATH,
			_OUTPUT_PATH,
			tunables.map_width,
			tunables.map_height,
			starting_resources,
			registry,
		)
	)
	if err == OK:
		print("[clash_dev] Baked %s" % _OUTPUT_PATH)
	else:
		push_error("[clash_dev] Bake failed: %d" % err)
