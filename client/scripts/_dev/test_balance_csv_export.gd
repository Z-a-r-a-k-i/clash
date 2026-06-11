@tool
extends Node

const EXPORT_SCRIPT_PATH := "res://scripts/_dev/export_balance_csv.gd"
const OUT_PATH := "user://balance_stats_export_test.csv"

const HEADER: Array[String] = [
	"kind",
	"category",
	"id",
	"display_name",
	"resource_path",
	"footprint",
	"tags",
	"default_hidden",
	"health_max_hp",
	"combat_damage",
	"combat_attack_range",
	"combat_attacks_before_movement",
	"combat_attacks_after_movement",
	"combat_has_initiative",
	"combat_target_layers",
	"combat_attack_modifiers",
	"movement_speed",
	"movement_post_shot_move_fraction",
	"movement_default_layer",
	"movement_pathable_tags",
	"movement_impassable_tags",
	"vision_sight_radius",
	"vision_detection_radius",
	"population_pop_cost",
	"population_pop_provides",
	"construction_build_time_turns",
	"construction_mineral_cost",
	"construction_gas_cost",
	"construction_built_by_tag",
	"construction_requires_target_tag",
	"production_produces",
	"production_researches",
	"production_queue_capacity",
	"production_rally_offset",
	"gather_per_turn",
	"gather_carry_amount",
	"gather_accepts_resource_types",
	"resource_type",
	"resource_yield_per_worker",
	"resource_capacity",
	"resource_requires_extractor",
	"ability_ids",
	"research_mineral_cost",
	"research_gas_cost",
	"research_time_turns",
	"ability_target_type",
	"ability_target_range",
	"ability_cooldown_turns",
	"ability_cast_time_turns",
	"ability_requires_research_id",
	"ability_costs",
	"ability_effect_type",
	"effect_duration_turns",
	"effect_damage_mult",
	"effect_speed_mult",
	"effect_to_def_id",
]

var _csv_loaded := false
var _csv_ok := false
var _rows: Array[Dictionary] = []


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
	print("[test_balance_csv_export] %d passed, %d failed" % [passed, failed])
	for test_name in fail_names:
		push_error("  failed: %s" % test_name)
	return failed


func _all_tests() -> Array:
	return [
		["csv_header_is_stable", _test_csv_header_is_stable],
		["known_rows_exist", _test_known_rows_exist],
		["nested_values_are_exported", _test_nested_values_are_exported],
		["balance_adjustments_are_exported", _test_balance_adjustments_are_exported],
		["missing_capabilities_are_empty", _test_missing_capabilities_are_empty],
	]


func _test_csv_header_is_stable() -> bool:
	if not _ensure_csv_loaded():
		return false
	var file := FileAccess.open(OUT_PATH, FileAccess.READ)
	if file == null:
		push_error("expected exported CSV to be readable")
		return false
	var raw_header: PackedStringArray = file.get_csv_line()
	file.close()
	var header: Array[String] = []
	for value in raw_header:
		header.append(value)
	if header != HEADER:
		push_error("CSV header changed.\nexpected=%s\nactual=%s" % [str(HEADER), str(header)])
		return false
	return true


func _test_known_rows_exist() -> bool:
	if not _ensure_csv_loaded():
		return false
	var ok := true
	for id in ["marine", "base", "stim_research", "stim"]:
		if _row_by_id(id).is_empty():
			push_error("missing expected balance row for id '%s'" % id)
			ok = false
	return ok


func _test_nested_values_are_exported() -> bool:
	if not _ensure_csv_loaded():
		return false
	var ok := true
	var marine := _row_by_id("marine")
	ok = _expect_cell(marine, "kind", "entity") and ok
	ok = _expect_cell(marine, "category", "units") and ok
	ok = _expect_cell(marine, "footprint", "1x1") and ok
	ok = _expect_cell(marine, "tags", "light;biological;ground") and ok
	ok = _expect_cell(marine, "combat_attacks_before_movement", "true") and ok
	ok = _expect_cell(marine, "combat_attacks_after_movement", "false") and ok
	ok = _expect_cell(marine, "combat_has_initiative", "false") and ok
	ok = _expect_cell(marine, "combat_target_layers", "ground;flying") and ok
	ok = _expect_cell(marine, "ability_ids", "stim") and ok

	var siege_tank := _row_by_id("siege_tank")
	ok = _expect_cell(siege_tank, "combat_attack_modifiers", "") and ok

	var base := _row_by_id("base")
	ok = _expect_cell(base, "production_produces", "worker") and ok
	ok = _expect_cell(base, "production_rally_offset", "0,4") and ok

	var barracks := _row_by_id("barracks")
	ok = _expect_cell(barracks, "production_produces", "marine") and ok
	ok = _expect_cell(barracks, "production_researches", "stim_research") and ok

	var mineral_patch := _row_by_id("mineral_patch")
	ok = _expect_cell(mineral_patch, "resource_type", "minerals") and ok
	ok = _expect_cell(mineral_patch, "resource_yield_per_worker", "1") and ok
	ok = _expect_cell(mineral_patch, "resource_capacity", "1500") and ok
	ok = _expect_cell(mineral_patch, "resource_requires_extractor", "false") and ok

	var gas_geyser := _row_by_id("gas_geyser")
	ok = _expect_cell(gas_geyser, "resource_type", "gas") and ok
	ok = _expect_cell(gas_geyser, "resource_requires_extractor", "true") and ok

	var research := _row_by_id("stim_research")
	ok = _expect_cell(research, "kind", "research") and ok
	ok = _expect_cell(research, "research_mineral_cost", "100") and ok
	ok = _expect_cell(research, "research_gas_cost", "0") and ok
	ok = _expect_cell(research, "research_time_turns", "12") and ok

	var stim := _row_by_id("stim")
	ok = _expect_cell(stim, "kind", "ability") and ok
	ok = _expect_cell(stim, "ability_target_type", "self") and ok
	ok = _expect_cell(stim, "ability_cooldown_turns", "5") and ok
	ok = _expect_cell(stim, "ability_requires_research_id", "stim_research") and ok
	ok = _expect_cell(stim, "ability_costs", "hp:10") and ok
	ok = _expect_cell(stim, "ability_effect_type", "stat_buff") and ok
	ok = _expect_cell(stim, "effect_duration_turns", "3") and ok
	ok = _expect_cell(stim, "effect_damage_mult", "1.5") and ok
	ok = _expect_cell(stim, "effect_speed_mult", "1.5") and ok
	return ok


func _test_balance_adjustments_are_exported() -> bool:
	if not _ensure_csv_loaded():
		return false
	var ok := true

	var worker := _row_by_id("worker")
	ok = _expect_cell(worker, "movement_speed", "6") and ok

	var marine := _row_by_id("marine")
	ok = _expect_cell(marine, "health_max_hp", "45") and ok
	ok = _expect_cell(marine, "combat_damage", "18") and ok
	ok = _expect_cell(marine, "combat_attack_range", "3") and ok
	ok = _expect_cell(marine, "movement_speed", "10") and ok
	ok = _expect_cell(marine, "vision_sight_radius", "4") and ok

	var tank := _row_by_id("tank")
	ok = _expect_cell(tank, "health_max_hp", "175") and ok
	ok = _expect_cell(tank, "combat_damage", "30") and ok
	ok = _expect_cell(tank, "combat_attack_range", "3") and ok
	ok = _expect_cell(tank, "movement_speed", "8") and ok
	ok = _expect_cell(tank, "construction_gas_cost", "125") and ok

	var siege_tank := _row_by_id("siege_tank")
	ok = _expect_cell(siege_tank, "combat_damage", "40") and ok
	ok = _expect_cell(siege_tank, "combat_attack_range", "6") and ok
	ok = _expect_cell(siege_tank, "combat_attack_modifiers", "") and ok

	var helicopter := _row_by_id("helicopter")
	ok = _expect_cell(helicopter, "combat_damage", "25") and ok
	ok = _expect_cell(helicopter, "combat_attack_range", "3") and ok
	ok = _expect_cell(helicopter, "movement_speed", "14") and ok
	ok = _expect_cell(helicopter, "vision_sight_radius", "4") and ok
	ok = _expect_cell(helicopter, "combat_attack_modifiers", "") and ok

	var siege_mode := _row_by_id("siege_mode")
	ok = _expect_cell(siege_mode, "ability_requires_research_id", "") and ok

	var unsiege_mode := _row_by_id("unsiege_mode")
	ok = _expect_cell(unsiege_mode, "ability_requires_research_id", "") and ok

	return ok


func _test_missing_capabilities_are_empty() -> bool:
	if not _ensure_csv_loaded():
		return false
	var mineral_patch := _row_by_id("mineral_patch")
	var ok := true
	for column in [
		"health_max_hp",
		"combat_damage",
		"movement_speed",
		"vision_sight_radius",
		"production_produces",
		"ability_ids",
	]:
		ok = _expect_cell(mineral_patch, column, "") and ok
	return ok


func _ensure_csv_loaded() -> bool:
	if _csv_loaded:
		return _csv_ok
	_csv_loaded = true
	_remove_output()
	if not _export_csv():
		_csv_ok = false
		return false
	_csv_ok = _read_rows()
	return _csv_ok


func _export_csv() -> bool:
	var script: Script = load(EXPORT_SCRIPT_PATH) as Script
	if script == null:
		push_error("could not load exporter script: %s" % EXPORT_SCRIPT_PATH)
		return false
	var result: Variant = script.call("export_to_csv", OUT_PATH)
	if typeof(result) != TYPE_INT:
		push_error(
			"export_to_csv should return an Error code, got %s" % type_string(typeof(result))
		)
		return false
	if int(result) != OK:
		push_error("export_to_csv returned %d" % int(result))
		return false
	return true


func _read_rows() -> bool:
	var file := FileAccess.open(OUT_PATH, FileAccess.READ)
	if file == null:
		push_error("exporter did not create %s" % OUT_PATH)
		return false
	var raw_header: PackedStringArray = file.get_csv_line()
	var header: Array[String] = []
	for value in raw_header:
		header.append(value)
	var ok := true
	var line_number := 1
	while file.get_position() < file.get_length():
		line_number += 1
		var values: PackedStringArray = file.get_csv_line()
		if values.size() == 1 and values[0] == "":
			continue
		if values.size() != header.size():
			push_error(
				"line %d has %d cells, expected %d" % [line_number, values.size(), header.size()]
			)
			ok = false
			continue
		var row := {}
		for i in header.size():
			row[header[i]] = values[i]
		_rows.append(row)
	file.close()
	if _rows.is_empty():
		push_error("exported CSV contained no data rows")
		ok = false
	return ok


func _row_by_id(id: String) -> Dictionary:
	for row in _rows:
		if row.get("id", "") == id:
			return row
	return {}


func _expect_cell(row: Dictionary, column: String, expected: String) -> bool:
	if row.is_empty():
		push_error("missing row while checking column '%s'" % column)
		return false
	var actual := str(row.get(column, "<missing column>"))
	if actual != expected:
		push_error(
			"expected %s=%s for id=%s, got %s" % [column, expected, row.get("id", ""), actual]
		)
		return false
	return true


func _remove_output() -> void:
	if FileAccess.file_exists(OUT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT_PATH))
