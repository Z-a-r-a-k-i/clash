@tool
extends Node

# Simulation harness tests (plan m1/02).


func _all_tests() -> Array:
	return [
		["simulation_seeded_run_is_reproducible", _test_seeded_run_is_reproducible],
		["simulation_stall_watchdog_fires", _test_stall_watchdog_fires],
	]


func _test_seeded_run_is_reproducible() -> bool:
	# Two identical seeded 2-match pairings -> byte-identical CSVs.
	var first := SimulationRunner.run_pairing(
		"res://data/scenarios/arena_1v1.tres", "rush_marines", "rush_marines", 2, 60, 7
	)
	var second := SimulationRunner.run_pairing(
		"res://data/scenarios/arena_1v1.tres", "rush_marines", "rush_marines", 2, 60, 7
	)
	var csv_a := SimulationRunner.matches_csv(first["rows"], false)
	var csv_b := SimulationRunner.matches_csv(second["rows"], false)
	if csv_a != csv_b:
		push_error("seeded runs diverged:\n%s\nvs\n%s" % [csv_a, csv_b])
		return false
	var ts_a := SimulationRunner.timeseries_csv(first["timeseries"])
	var ts_b := SimulationRunner.timeseries_csv(second["timeseries"])
	if ts_a != ts_b:
		push_error("seeded timeseries diverged")
		return false
	return true


func _test_stall_watchdog_fires() -> bool:
	# Two deliberately inert configs (no build order, no mix, no worker
	# margin) on the minimal scenario produce no events -> the watchdog
	# must end the match as a stall instead of spinning to the cap.
	var inert := AiConfig.new()
	inert.build_order = []
	inert.unit_mix = {}
	inert.worker_margin = 0
	inert.attack_army_value = 1 << 30
	var path := "user://tmp/inert_ai.tres"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tmp"))
	ResourceSaver.save(inert, path)
	var registry: EntityRegistry = load("res://data/entity_registry.tres")
	var tunables: Tunables = load("res://data/tunables.tres")
	var scenario: ScenarioDef = load("res://data/scenarios/smoke_minimal.tres")
	var loaded := ScenarioLoader.load(scenario, registry, tunables)
	var state: MatchState = loaded.state
	var memory_a := AiMemory.new()
	var memory_b := AiMemory.new()
	var quiet := 0
	for turn in range(SimulationRunner.STALL_QUIET_TURNS + 10):
		var submit_a := AiPlayer.plan_turn(state, 0, registry, tunables, inert, memory_a)
		var submit_b := AiPlayer.plan_turn(state, 1, registry, tunables, inert, memory_b)
		var result := Resolver.resolve(state, submit_a, submit_b, registry, tunables)
		state = result.new_state
		quiet = quiet + 1 if result.events.is_empty() else 0
		if quiet >= SimulationRunner.STALL_QUIET_TURNS:
			return true
		if state.match_over:
			break
	push_error("inert configs should trip the stall watchdog")
	return false
