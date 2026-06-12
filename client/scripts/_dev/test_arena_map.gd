@tool
extends Node

# Arena 1v1 map tests (plan/m1/03): bake symmetry, terrain round-trip,
# choke pathing for ground vs flying, and build rejection on cliffs.

const ARENA_SCENARIO_PATH := "res://data/scenarios/arena_1v1.tres"
const REGISTRY_PATH := "res://data/entity_registry.tres"
const TUNABLES_PATH := "res://data/tunables.tres"


func run_all() -> Dictionary:
	var passed := 0
	var failed := 0
	for entry in _all_tests():
		var test_name: String = entry[0]
		var test_callable: Callable = entry[1]
		if test_callable.call():
			passed += 1
		else:
			failed += 1
			push_error("  failed: %s" % test_name)
	return {"passed": passed, "failed": failed}


func _all_tests() -> Array:
	return [
		["arena_bake_is_mirror_symmetric", _test_bake_is_mirror_symmetric],
		["arena_terrain_loads_into_grid", _test_terrain_loads_into_grid],
		["arena_ground_paths_through_choke_flying_over", _test_ground_choke_flying_over],
		["arena_build_rejected_on_cliff", _test_build_rejected_on_cliff],
		["arena_baker_rejects_placement_on_terrain", _test_baker_rejects_placement_on_terrain],
		["arena_full_turn_resolves", _test_full_turn_resolves],
	]


func _load_arena() -> LoadedScenario:
	var scenario: ScenarioDef = load(ARENA_SCENARIO_PATH) as ScenarioDef
	var registry: EntityRegistry = load(REGISTRY_PATH) as EntityRegistry
	var tunables: Tunables = load(TUNABLES_PATH) as Tunables
	if scenario == null or registry == null or tunables == null:
		push_error("arena tests require scenario, registry, and tunables")
		return null
	return ScenarioLoader.load(scenario, registry, tunables)


func _test_bake_is_mirror_symmetric() -> bool:
	var scenario: ScenarioDef = load(ARENA_SCENARIO_PATH) as ScenarioDef
	var registry: EntityRegistry = load(REGISTRY_PATH) as EntityRegistry
	if scenario == null or registry == null:
		return false
	var ok := true
	# Per-player roster counts are identical.
	for def_id in ["base", "worker"]:
		var p0 := 0
		var p1 := 0
		for placement in scenario.placements:
			if placement.def_id == def_id:
				if placement.owner_player_id == 0:
					p0 += 1
				elif placement.owner_player_id == 1:
					p1 += 1
		if p0 != p1:
			push_error("count mismatch for %s: P0=%d P1=%d" % [def_id, p0, p1])
			ok = false
	if ok:
		var p0_bases := 0
		for placement in scenario.placements:
			if placement.def_id == "base" and placement.owner_player_id == 0:
				p0_bases += 1
		if p0_bases != 3:
			push_error("each player should have 3 bases, got %d" % p0_bases)
			ok = false
	# Every placement has its exact mirror (geometry symmetry).
	var keys: Dictionary = {}
	for placement in scenario.placements:
		var def: EntityDef = registry.get_by_id(placement.def_id)
		var footprint: Vector2i = def.footprint if def != null else Vector2i.ONE
		footprint = Vector2i(maxi(footprint.x, 1), maxi(footprint.y, 1))
		var key := (
			"%s|%d|%d,%d"
			% [placement.def_id, placement.owner_player_id, placement.origin.x, placement.origin.y]
		)
		keys[key] = [placement, footprint]
	for key in keys:
		var placement: ScenarioPlacement = keys[key][0]
		var footprint: Vector2i = keys[key][1]
		var mirror_x: int = MapBaker.mirror_x_for(
			placement.origin.x, footprint.x, scenario.map_width
		)
		var mirror_owner: int = MapBaker.mirror_owner_for(placement.owner_player_id)
		var mirror_key := (
			"%s|%d|%d,%d" % [placement.def_id, mirror_owner, mirror_x, placement.origin.y]
		)
		if not keys.has(mirror_key):
			push_error("missing mirror for %s" % key)
			ok = false
	# Terrain symmetry.
	for patch in scenario.terrain_patches:
		var mirror_x: int = MapBaker.mirror_x_for(
			patch.rect.position.x, patch.rect.size.x, scenario.map_width
		)
		var found := false
		for other in scenario.terrain_patches:
			if (
				other.rect.position == Vector2i(mirror_x, patch.rect.position.y)
				and other.rect.size == patch.rect.size
				and other.tags == patch.tags
			):
				found = true
				break
		if not found:
			push_error("missing terrain mirror for %s" % str(patch.rect))
			ok = false
	return ok


func _test_terrain_loads_into_grid() -> bool:
	var loaded: LoadedScenario = _load_arena()
	if loaded == null:
		return false
	var scenario: ScenarioDef = load(ARENA_SCENARIO_PATH) as ScenarioDef
	var tagged: Array[Vector2i] = loaded.state.tile_grid.terrain_tiles()
	if tagged.is_empty():
		push_error("arena grid should carry terrain-tagged tiles")
		return false
	var expected := 0
	for patch in scenario.terrain_patches:
		expected += patch.rect.size.x * patch.rect.size.y
	if tagged.size() != expected:
		push_error("expected %d tagged tiles, got %d" % [expected, tagged.size()])
		return false
	for tile in tagged:
		if not loaded.state.tile_grid.tile_terrain_tags(tile).has("cliff"):
			push_error("tagged tile %s should carry the cliff tag" % str(tile))
			return false
	return true


func _test_ground_choke_flying_over() -> bool:
	# A marine inside the main plateau pathing to a tile straight across
	# the east wall must detour (path longer than chebyshev); a helicopter
	# flies straight over. Start (12,8); goal (20,8) across the x=14..15
	# wall (sealed until y=15, choke at the south gap x=10..13,y=14..15).
	var loaded: LoadedScenario = _load_arena()
	if loaded == null:
		return false
	var state: MatchState = loaded.state
	var registry: EntityRegistry = loaded.registry
	var start := Vector2i(12, 8)
	var goal := Vector2i(20, 8)
	var chebyshev: int = maxi(absi(goal.x - start.x), absi(goal.y - start.y))

	var marine := Entity.new()
	marine.id = state.allocate_entity_id()
	marine.def_id = "marine"
	marine.current_def_id = "marine"
	marine.owner_player_id = 0
	marine.origin = start
	marine.current_hp = 45
	marine.current_layer = "ground"
	state.entities.append(marine)
	if not state.tile_grid.place(marine.id, Rect2i(start, Vector2i.ONE)):
		push_error("could not place test marine at %s" % str(start))
		return false
	var ground_path: Array[Vector2i] = PathfindingSystem.find_path(state, marine, goal, registry)
	if ground_path.is_empty() or ground_path[ground_path.size() - 1] != goal:
		push_error("marine should still reach across the wall via the choke")
		return false
	if ground_path.size() <= chebyshev:
		push_error(
			(
				"ground path should detour around the cliff (len %d <= chebyshev %d)"
				% [ground_path.size(), chebyshev]
			)
		)
		return false
	for step in ground_path:
		if state.tile_grid.tile_terrain_tags(step).has("cliff"):
			push_error("ground path crosses a cliff tile at %s" % str(step))
			return false

	var heli := Entity.new()
	heli.id = state.allocate_entity_id()
	heli.def_id = "helicopter"
	heli.current_def_id = "helicopter"
	heli.owner_player_id = 0
	heli.origin = start + Vector2i(0, 1)
	heli.current_hp = 140
	heli.current_layer = "flying"
	state.entities.append(heli)
	if not state.tile_grid.place(heli.id, Rect2i(heli.origin, Vector2i.ONE)):
		push_error("could not place test helicopter")
		return false
	var air_goal := goal + Vector2i(0, 1)
	var air_path: Array[Vector2i] = PathfindingSystem.find_path(state, heli, air_goal, registry)
	var air_chebyshev: int = maxi(
		absi(air_goal.x - heli.origin.x), absi(air_goal.y - heli.origin.y)
	)
	if air_path.is_empty() or air_path.size() != air_chebyshev:
		push_error(
			(
				"helicopter should fly straight over the cliff (len %d, chebyshev %d)"
				% [air_path.size(), air_chebyshev]
			)
		)
		return false
	return true


func _test_build_rejected_on_cliff() -> bool:
	# BUILD orders whose rect touches a cliff tile are rejected at order
	# distribution (plan/m1/03 unbuildable terrain).
	var loaded: LoadedScenario = _load_arena()
	if loaded == null:
		return false
	var state: MatchState = loaded.state
	var worker: Entity = null
	for entity in state.entities_sorted_by_id():
		if entity.current_def_id == "worker" and entity.owner_player_id == 0:
			worker = entity
			break
	if worker == null:
		push_error("arena should start with P0 workers")
		return false
	state.get_player(0).minerals = 1000
	var order := EntityOrder.new()
	order.type = EntityOrder.Type.BUILD
	order.entity_id = worker.id
	order.def_id = "barracks"
	order.target_tile = Vector2i(14, 4)  # on the main east wall
	var submit := SubmitTurn.new()
	submit.orders = [order]
	var result: ResolveResult = Resolver.resolve(
		state, submit, SubmitTurn.new(), loaded.registry, null
	)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.BUILD_STARTED:
			push_error("BUILD on a cliff should not start")
			return false
	var new_worker: Entity = result.new_state.get_entity_by_id(worker.id)
	if new_worker.pending_build_def_id != "":
		push_error("BUILD on a cliff should not reserve a pending build")
		return false
	return true


func _test_baker_rejects_placement_on_terrain() -> bool:
	# A synthetic map with a base sitting on a cliff rect must fail the bake.
	var registry: EntityRegistry = load(REGISTRY_PATH) as EntityRegistry
	if registry == null:
		return false
	var root := Node2D.new()
	var placements := Node2D.new()
	placements.name = "Placements"
	root.add_child(placements)
	var ep := Node2D.new()
	ep.set_script(load("res://scripts/data/entity_placement.gd"))
	ep.name = "BadBase"
	ep.def_id = "base"
	ep.owner_player_id = 0
	ep.tile_position = Vector2i(4, 4)
	placements.add_child(ep)
	var terrain := Node2D.new()
	terrain.name = "Terrain"
	root.add_child(terrain)
	var tp := Node2D.new()
	tp.set_script(load("res://scripts/data/terrain_patch.gd"))
	tp.name = "Cliff"
	tp.rect_position = Vector2i(5, 5)
	tp.rect_size = Vector2i(4, 4)
	terrain.add_child(tp)
	var sd: ScenarioDef = MapBaker.bake_to_resource_from_scene(root, 40, 40, {}, registry, false)
	root.queue_free()
	if sd != null:
		push_error("bake should fail when a placement overlaps terrain")
		return false
	return true


func _test_full_turn_resolves() -> bool:
	# Smoke: a full resolve on the arena map (auto gather active) works and
	# leaves the grid consistent.
	var loaded: LoadedScenario = _load_arena()
	if loaded == null:
		return false
	var result: ResolveResult = Resolver.resolve(
		loaded.state, SubmitTurn.new(), SubmitTurn.new(), loaded.registry, null
	)
	if result == null or result.new_state == null:
		push_error("arena resolve returned null")
		return false
	if result.new_state.match_over:
		push_error("arena resolve should not end the match")
		return false
	return true
