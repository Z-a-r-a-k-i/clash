extends SceneTree

# One-shot bake invocation for the arena 1v1 map (plan/m1/03). Reads the
# authored arena_1v1.tscn and writes arena_1v1.tres. Run via:
#   godot --headless --path client --script scripts/_dev/run_arena_bake.gd

const MAP_WIDTH := 80
const MAP_HEIGHT := 60


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
			"res://data/scenarios/arena_1v1.tscn",
			"res://data/scenarios/arena_1v1.tres",
			MAP_WIDTH,
			MAP_HEIGHT,
			starting_resources,
			registry,
			true,
		)
	)
	if err != OK:
		print("FAIL: bake returned %d" % err)
		quit(1)
		return
	var sd: ScenarioDef = load("res://data/scenarios/arena_1v1.tres")
	if sd == null:
		print("FAIL: baked .tres failed to load")
		quit(1)
		return
	print(
		(
			"OK: baked arena_1v1.tres (map=%dx%d, %d placements, %d terrain patches)"
			% [sd.map_width, sd.map_height, sd.placements.size(), sd.terrain_patches.size()]
		)
	)
	quit(0)
