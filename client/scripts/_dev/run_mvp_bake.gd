extends SceneTree

# One-shot bake invocation. Reads the canonical mvp_map.tscn and writes
# the corresponding mvp_map.tres. Run via:
#   godot --headless --path client --script scripts/_dev/run_mvp_bake.gd


func _init() -> void:
	var registry: EntityRegistry = load("res://data/entity_registry.tres")
	var tunables: Tunables = load("res://data/tunables.tres")
	if registry == null or tunables == null:
		print("FAIL: missing registry or tunables")
		quit(1)
		return
	var starting_resources := {
		0: {"minerals": tunables.starting_minerals, "gas": tunables.starting_gas},
		1: {"minerals": tunables.starting_minerals, "gas": tunables.starting_gas},
	}
	var err := (
		MapBaker
		. bake(
			"res://data/scenarios/mvp_map.tscn",
			"res://data/scenarios/mvp_map.tres",
			tunables.map_width,
			tunables.map_height,
			starting_resources,
			registry,
		)
	)
	if err != OK:
		print("FAIL: bake returned %d" % err)
		quit(1)
		return
	# Verify output.
	var sd: ScenarioDef = load("res://data/scenarios/mvp_map.tres")
	if sd == null:
		print("FAIL: baked .tres failed to load")
		quit(1)
		return
	print(
		(
			"OK: baked mvp_map.tres (map=%dx%d, %d placements)"
			% [sd.map_width, sd.map_height, sd.placements.size()]
		)
	)
	quit(0)
