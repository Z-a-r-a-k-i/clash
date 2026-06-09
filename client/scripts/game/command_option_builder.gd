class_name CommandOptionBuilder
extends RefCounted


static func build_options(input: DevTurnInput, ids: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if input == null:
		return out
	for id in ids:
		var def_id: String = id
		(
			out
			. append(
				{
					"id": def_id,
					"label": input.label_for_entity_def_id_with_cost(def_id),
					"disabled": not input.can_afford_build(def_id),
				}
			)
		)
	return out


static func entity_options(input: DevTurnInput, ids: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if input == null:
		return out
	for id in ids:
		var def_id: String = id
		out.append({"id": def_id, "label": input.label_for_entity_def_id_with_cost(def_id)})
	return out


static func research_options(input: DevTurnInput, ids: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if input == null:
		return out
	for id in ids:
		var research_id: String = id
		out.append({"id": research_id, "label": input.label_for_research_id_with_cost(research_id)})
	return out


static func ability_options(input: DevTurnInput, ids: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if input == null:
		return out
	for id in ids:
		var ability_id: String = id
		out.append({"id": ability_id, "label": input.label_for_ability_id(ability_id)})
	return out
