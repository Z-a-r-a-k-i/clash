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
	var first: Dictionary = SimulationRunner.run_pairing(
		"res://data/scenarios/arena_1v1.tres", "rush_marines", "rush_marines", 2, 60, 7
	)
	var second: Dictionary = SimulationRunner.run_pairing(
		"res://data/scenarios/arena_1v1.tres", "rush_marines", "rush_marines", 2, 60, 7
	)
	var csv_a: String = SimulationRunner.matches_csv(first["rows"], false)
	var csv_b: String = SimulationRunner.matches_csv(second["rows"], false)
	if csv_a != csv_b:
		push_error("seeded runs diverged:\n%s\nvs\n%s" % [csv_a, csv_b])
		return false
	var ts_a: String = SimulationRunner.timeseries_csv(first["timeseries"])
	var ts_b: String = SimulationRunner.timeseries_csv(second["timeseries"])
	if ts_a != ts_b:
		push_error("seeded timeseries diverged")
		return false
	return true


func _test_stall_watchdog_fires() -> bool:
	# Two deliberately inert configs (no build order, no mix, no worker
	# margin) on the minimal scenario produce no events -> the watchdog
	# must end the match as a stall instead of spinning to the cap.
	var inert: AiConfig = AiConfig.new()
	inert.build_order = []
	inert.unit_mix = {}
	inert.worker_margin = 0
	inert.attack_army_value = 1 << 30
	var outcome: Dictionary = SimulationRunner.run_match_with_configs(
		"res://data/scenarios/smoke_minimal.tres",
		"inert_a",
		inert,
		"inert_b",
		inert,
		1,
		SimulationRunner.STALL_QUIET_TURNS + 10
	)
	var row: Dictionary = outcome["row"]
	if row["end_reason"] == "stall":
		return true
	push_error("inert configs should trip the stall watchdog, got %s" % row["end_reason"])
	return false
