extends SceneTree

const DEFAULT_OUTPUT_PATH := "res://exports/balance_stats.csv"
const REGISTRY_PATH := "res://data/entity_registry.tres"
const ABILITIES_DIR := "res://data/abilities"

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


func _init() -> void:
	var output_path: String = _output_path_from_args(OS.get_cmdline_user_args())
	var err: Error = export_to_csv(output_path)
	if err != OK:
		print("FAIL: balance CSV export returned %d" % err)
		quit(1)
		return
	print("OK: exported balance stats CSV to %s" % output_path)
	quit(0)


static func export_to_csv(output_path: String = DEFAULT_OUTPUT_PATH) -> Error:
	var registry: EntityRegistry = load(REGISTRY_PATH) as EntityRegistry
	if registry == null:
		push_error("[export_balance_csv] could not load %s" % REGISTRY_PATH)
		return ERR_CANT_OPEN

	var rows: Array[Dictionary] = []
	for entity in registry.entities:
		if entity == null:
			continue
		rows.append(_entity_row(entity))
	for research in registry.researches:
		if research == null:
			continue
		rows.append(_research_row(research))

	var ability_paths: Array[String] = []
	var collect_err: Error = _collect_tres_paths(ABILITIES_DIR, ability_paths)
	if collect_err != OK:
		return collect_err
	ability_paths.sort()
	for ability_path in ability_paths:
		var ability: AbilityDef = load(ability_path) as AbilityDef
		if ability == null:
			push_warning("[export_balance_csv] skipping non-AbilityDef resource: %s" % ability_path)
			continue
		rows.append(_ability_row(ability, ability_path))

	return _write_csv(output_path, rows)


static func _output_path_from_args(args: PackedStringArray) -> String:
	var output_path: String = DEFAULT_OUTPUT_PATH
	for arg in args:
		if arg == "":
			continue
		if arg.begins_with("OUT="):
			output_path = arg.substr("OUT=".length())
		else:
			output_path = arg
	return output_path


static func _entity_row(entity: EntityDef) -> Dictionary:
	var row: Dictionary = _base_row(
		"entity",
		_entity_category(entity.resource_path),
		entity.id,
		entity.display_name,
		entity.resource_path
	)
	row["footprint"] = _format_size(entity.footprint)
	row["tags"] = _join_values(entity.tags)
	row["default_hidden"] = _bool_string(entity.default_hidden)

	if entity.health != null:
		row["health_max_hp"] = str(entity.health.max_hp)

	if entity.combat != null:
		row["combat_damage"] = str(entity.combat.damage)
		row["combat_attack_range"] = str(entity.combat.attack_range)
		row["combat_attacks_before_movement"] = _bool_string(entity.combat.attacks_before_movement)
		row["combat_attacks_after_movement"] = _bool_string(entity.combat.attacks_after_movement)
		row["combat_has_initiative"] = _bool_string(entity.combat.has_initiative)
		row["combat_target_layers"] = _join_values(entity.combat.target_layers)
		row["combat_attack_modifiers"] = _format_attack_modifiers(entity.combat.attack_modifiers)

	if entity.movement != null:
		row["movement_speed"] = str(entity.movement.speed_tiles_per_turn)
		row["movement_post_shot_move_fraction"] = str(entity.movement.post_shot_move_fraction)
		row["movement_default_layer"] = entity.movement.default_layer
		row["movement_pathable_tags"] = _join_values(entity.movement.pathable_terrain_tags)
		row["movement_impassable_tags"] = _join_values(entity.movement.impassable_terrain_tags)

	if entity.vision != null:
		row["vision_sight_radius"] = str(entity.vision.sight_radius)
		row["vision_detection_radius"] = str(entity.vision.detection_radius)

	if entity.population != null:
		row["population_pop_cost"] = str(entity.population.pop_cost)
		row["population_pop_provides"] = str(entity.population.pop_provides)

	if entity.construction != null:
		row["construction_build_time_turns"] = str(entity.construction.build_time_turns)
		row["construction_mineral_cost"] = str(entity.construction.mineral_cost)
		row["construction_gas_cost"] = str(entity.construction.gas_cost)
		row["construction_built_by_tag"] = entity.construction.built_by_tag
		row["construction_requires_target_tag"] = entity.construction.requires_target_tag

	if entity.production != null:
		row["production_produces"] = _join_values(entity.production.produces)
		row["production_researches"] = _join_values(entity.production.researches)
		row["production_queue_capacity"] = str(entity.production.queue_capacity)
		row["production_rally_offset"] = _format_vector(entity.production.rally_offset)

	if entity.gather != null:
		row["gather_per_turn"] = str(entity.gather.gather_per_turn)
		row["gather_carry_amount"] = str(entity.gather.carry_amount)
		row["gather_accepts_resource_types"] = _join_values(entity.gather.accepts_resource_types)

	if entity.resource_source != null:
		row["resource_type"] = entity.resource_source.resource_type
		row["resource_yield_per_worker"] = str(entity.resource_source.yield_per_worker_per_turn)
		row["resource_capacity"] = str(entity.resource_source.capacity)
		row["resource_requires_extractor"] = _bool_string(entity.resource_source.requires_extractor)

	if entity.abilities != null:
		row["ability_ids"] = _format_ability_ids(entity.abilities.abilities)

	return row


static func _research_row(research: ResearchDef) -> Dictionary:
	var row: Dictionary = _base_row(
		"research", "researches", research.id, research.display_name, research.resource_path
	)
	row["research_mineral_cost"] = str(research.mineral_cost)
	row["research_gas_cost"] = str(research.gas_cost)
	row["research_time_turns"] = str(research.research_time_turns)
	return row


static func _ability_row(ability: AbilityDef, ability_path: String) -> Dictionary:
	var row: Dictionary = _base_row(
		"ability", "abilities", ability.id, ability.display_name, ability_path
	)
	row["ability_target_type"] = ability.target_type
	row["ability_target_range"] = str(ability.target_range)
	row["ability_cooldown_turns"] = str(ability.cooldown_turns)
	row["ability_cast_time_turns"] = str(ability.cast_time_turns)
	row["ability_requires_research_id"] = ability.requires_research_id
	row["ability_costs"] = _format_ability_costs(ability.costs)
	_fill_effect_columns(row, ability.effect)
	return row


static func _fill_effect_columns(row: Dictionary, effect: Effect) -> void:
	if effect == null:
		return
	if effect is StatBuffEffect:
		var stat_buff: StatBuffEffect = effect
		row["ability_effect_type"] = "stat_buff"
		row["effect_duration_turns"] = str(stat_buff.duration_turns)
		row["effect_damage_mult"] = str(stat_buff.damage_mult)
		row["effect_speed_mult"] = str(stat_buff.speed_mult)
		return
	if effect is TransformEffect:
		var transform: TransformEffect = effect
		row["ability_effect_type"] = "transform"
		row["effect_to_def_id"] = transform.to_def_id
		return
	row["ability_effect_type"] = effect.get_class()


static func _base_row(
	kind: String, category: String, id: String, display_name: String, resource_path: String
) -> Dictionary:
	var row: Dictionary = {}
	for column in HEADER:
		row[column] = ""
	row["kind"] = kind
	row["category"] = category
	row["id"] = id
	row["display_name"] = display_name
	row["resource_path"] = resource_path
	return row


static func _entity_category(resource_path: String) -> String:
	const PREFIX := "res://data/entities/"
	if not resource_path.begins_with(PREFIX):
		return ""
	var relative_path: String = resource_path.substr(PREFIX.length())
	var slash_index: int = relative_path.find("/")
	if slash_index < 0:
		return ""
	return relative_path.substr(0, slash_index)


static func _format_size(value: Vector2i) -> String:
	return "%dx%d" % [value.x, value.y]


static func _format_vector(value: Vector2i) -> String:
	return "%d,%d" % [value.x, value.y]


static func _join_values(values: Array) -> String:
	var parts: Array[String] = []
	for value in values:
		parts.append(str(value))
	return ";".join(parts)


static func _format_attack_modifiers(modifiers: Array[AttackModifier]) -> String:
	var parts: Array[String] = []
	for modifier in modifiers:
		if modifier == null:
			continue
		parts.append("%s:%s" % [modifier.target_tag, str(modifier.damage_mult)])
	return ";".join(parts)


static func _format_ability_ids(abilities: Array[AbilityDef]) -> String:
	var parts: Array[String] = []
	for ability in abilities:
		if ability == null:
			continue
		parts.append(ability.id)
	return ";".join(parts)


static func _format_ability_costs(costs: Array[AbilityCost]) -> String:
	var parts: Array[String] = []
	for cost in costs:
		if cost == null:
			continue
		parts.append("%s:%d" % [cost.type, cost.amount])
	return ";".join(parts)


static func _bool_string(value: bool) -> String:
	return "true" if value else "false"


static func _collect_tres_paths(dir_path: String, paths: Array[String]) -> Error:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_error("[export_balance_csv] could not open directory: %s" % dir_path)
		return DirAccess.get_open_error()

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var child_path: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			var err: Error = _collect_tres_paths(child_path, paths)
			if err != OK:
				dir.list_dir_end()
				return err
		elif entry.get_extension() == "tres":
			paths.append(child_path)
		entry = dir.get_next()
	dir.list_dir_end()
	return OK


static func _write_csv(output_path: String, rows: Array[Dictionary]) -> Error:
	var dir_err: Error = _ensure_parent_dir(output_path)
	if dir_err != OK:
		return dir_err
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		var open_err: Error = FileAccess.get_open_error()
		push_error(
			"[export_balance_csv] could not open output file %s: %d" % [output_path, open_err]
		)
		return open_err

	file.store_csv_line(_packed_line(HEADER))
	for row in rows:
		file.store_csv_line(_row_line(row))
	file.close()
	return OK


static func _ensure_parent_dir(path: String) -> Error:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	var parent_dir: String = absolute_path.get_base_dir()
	if parent_dir == "":
		return OK
	var err: Error = DirAccess.make_dir_recursive_absolute(parent_dir)
	if err != OK:
		push_error("[export_balance_csv] could not create directory %s: %d" % [parent_dir, err])
	return err


static func _row_line(row: Dictionary) -> PackedStringArray:
	var values := PackedStringArray()
	for column in HEADER:
		values.append(str(row.get(column, "")))
	return values


static func _packed_line(values: Array[String]) -> PackedStringArray:
	var packed := PackedStringArray()
	for value in values:
		packed.append(value)
	return packed
