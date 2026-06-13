class_name AiPlayer
extends RefCounted

# Scripted opponent (plan m1/01). Pure planner mirroring the resolver's
# shape: plan_turn(state, player_id, ...) -> SubmitTurn, no node deps,
# headless-safe, deterministic for a given (state, config, memory)
# (id-ordered iteration, integer math, no wall-clock or RNG).
#
# Fog-honest: enemy knowledge comes from VisionSystem-visible entities
# recorded into AiMemory (last-seen), plus static map knowledge (own
# scenario layout and the mirrored enemy spawn guess). cheats_vision in
# the config bypasses the fog for simulator baselines.
#
# Decision layers per call: economy -> production -> army -> micro.
# Each entity receives at most one order per turn (first layer wins).

const VISION := preload("res://scripts/runtime/vision_system.gd")
const GATHER := preload("res://scripts/resolver/gather_system.gd")
const STATE_HELPERS := preload("res://scripts/resolver/_state_helpers.gd")


static func plan_turn(
	state: MatchState,
	player_id: int,
	registry: EntityRegistry,
	_tunables: Tunables,
	config: AiConfig,
	memory: AiMemory
) -> SubmitTurn:
	var submit: SubmitTurn = SubmitTurn.new()
	if state == null or registry == null or config == null or memory == null:
		return submit
	if state.match_over:
		return submit

	var snapshot: Dictionary = _snapshot(state, player_id, registry, config, memory)
	_update_enemy_memory(state, player_id, registry, config, memory, snapshot)

	if config.decision_cadence > 1 and state.turn_index % config.decision_cadence != 0:
		return submit

	var issued: Dictionary = {}
	_plan_economy(state, player_id, registry, config, memory, snapshot, submit, issued)
	_plan_production(state, player_id, registry, config, memory, snapshot, submit, issued)
	_plan_army(state, player_id, registry, config, memory, snapshot, submit, issued)
	return submit


# ---------- Snapshot ----------


static func _snapshot(
	state: MatchState, player_id: int, registry: EntityRegistry, _config: AiConfig, memory: AiMemory
) -> Dictionary:
	var own_bases: Array[Entity] = []
	var own_workers: Array[Entity] = []
	var own_army: Array[Entity] = []
	var own_producers: Array[Entity] = []
	var own_buildings: Array[Entity] = []
	var resource_sources: Array[Entity] = []
	for entity in state.entities_sorted_by_id():
		var def: EntityDef = registry.get_by_id(entity.current_def_id)
		if def == null:
			continue
		if def.resource_source != null:
			resource_sources.append(entity)
			continue
		if entity.owner_player_id != player_id or entity.current_hp <= 0:
			continue
		var is_building := def.tags.has("building")
		if is_building:
			own_buildings.append(entity)
			if not entity.is_constructing:
				if def.id == "base":
					own_bases.append(entity)
				if entity.production_state != null:
					own_producers.append(entity)
			continue
		if def.id == "worker":
			own_workers.append(entity)
		elif def.combat != null:
			own_army.append(entity)
	if memory.enemy_base_guess == Vector2i(-1, -1) and not own_bases.is_empty():
		var main: Entity = own_bases[0]
		var def: EntityDef = registry.get_by_id(main.current_def_id)
		var fp: Vector2i = def.footprint if def != null else Vector2i(4, 4)
		# The bake mirrors placements across the vertical axis; the
		# enemy main sits at the mirrored origin. Static map knowledge,
		# not vision cheating.
		memory.enemy_base_guess = Vector2i(
			state.tile_grid.width - main.origin.x - fp.x, main.origin.y
		)
	return {
		"bases": own_bases,
		"workers": own_workers,
		"army": own_army,
		"producers": own_producers,
		"buildings": own_buildings,
		"sources": resource_sources,
		"army_value": _army_value(own_army, registry),
	}


static func _update_enemy_memory(
	state: MatchState,
	player_id: int,
	registry: EntityRegistry,
	config: AiConfig,
	memory: AiMemory,
	_snapshot_data: Dictionary
) -> void:
	var visibility: VisionSystem.Visibility = null
	if not config.cheats_vision:
		visibility = VISION.compute_player_visibility(state, registry, player_id)
	for entity in state.entities_sorted_by_id():
		if entity.owner_player_id == player_id or entity.owner_player_id < 0:
			continue
		if entity.current_hp <= 0:
			memory.enemy_last_seen.erase(entity.id)
			continue
		var def: EntityDef = registry.get_by_id(entity.current_def_id)
		if def == null or def.resource_source != null:
			continue
		var seen := config.cheats_vision
		if not seen:
			seen = VISION.is_entity_visible_to_player(
				entity, state, registry, player_id, visibility
			)
		if seen:
			memory.enemy_last_seen[entity.id] = {
				"def_id": entity.current_def_id,
				"origin": entity.origin,
				"building": def.tags.has("building"),
				"turn": state.turn_index,
			}
			memory.last_enemy_seen_turn = state.turn_index
	# Forget entries whose recorded position is currently visible but
	# empty (the enemy moved away / died unseen elsewhere is kept).
	if visibility != null:
		var stale: Array[int] = []
		for enemy_id in memory.enemy_last_seen:
			if state.get_entity_by_id(enemy_id) == null:
				stale.append(enemy_id)
				continue
			var record: Dictionary = memory.enemy_last_seen[enemy_id]
			var origin: Vector2i = record["origin"]
			if visibility.is_tile_visible(origin) and int(record["turn"]) < state.turn_index:
				var live := state.get_entity_by_id(enemy_id)
				if live == null or live.origin != origin:
					stale.append(enemy_id)
		for enemy_id in stale:
			memory.enemy_last_seen.erase(enemy_id)


# ---------- Economy ----------


static func _plan_economy(
	state: MatchState,
	player_id: int,
	registry: EntityRegistry,
	config: AiConfig,
	memory: AiMemory,
	snapshot: Dictionary,
	submit: SubmitTurn,
	issued: Dictionary
) -> void:
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return
	var bases: Array[Entity] = snapshot["bases"]
	var workers: Array[Entity] = snapshot["workers"]
	if bases.is_empty():
		return

	# Idle workers gather the nearest open source near an owned base.
	var assignments: Dictionary = GATHER.source_assignments_by_source(state, registry)
	for worker in workers:
		if issued.has(worker.id):
			continue
		if worker.locked_to_building_id >= 0 or worker.pending_build_def_id != "":
			continue
		if worker.gather_state != null and worker.gather_state.phase != GatherState.Phase.IDLE:
			continue
		var source := _nearest_open_source(state, player_id, registry, worker, assignments)
		if source == null:
			continue
		var order := EntityOrder.new()
		order.type = EntityOrder.Type.GATHER
		order.entity_id = worker.id
		order.target_entity_id = source.id
		submit.orders.append(order)
		issued[worker.id] = true
		GATHER.replace_assignment_in_map(assignments, worker.id, source.id)

	# Keep worker production running while undersaturated: rally-gather +
	# repeat-train at every base, once each.
	var slots := _total_gather_slots(state, player_id, registry, snapshot)
	var want_workers: int = slots + config.worker_margin
	for base in bases:
		if not memory.rallied_producer_ids.has(base.id):
			var rally_source := _nearest_open_source(state, player_id, registry, base, assignments)
			if rally_source != null:
				var rally := EntityOrder.new()
				rally.type = EntityOrder.Type.SET_RALLY_POINT
				rally.entity_id = base.id
				rally.mode = ProductionState.RALLY_MODE_GATHER
				rally.target_entity_id = rally_source.id
				submit.orders.append(rally)
				memory.rallied_producer_ids[base.id] = true
		if workers.size() < want_workers and not memory.repeat_train_producer_ids.has(base.id):
			var train := EntityOrder.new()
			train.type = EntityOrder.Type.TRAIN
			train.entity_id = base.id
			train.def_id = "worker"
			submit.orders.append(train)
			var repeat := EntityOrder.new()
			repeat.type = EntityOrder.Type.REPEAT_TRAIN_TOGGLE
			repeat.entity_id = base.id
			repeat.def_id = "worker"
			repeat.enabled = true
			submit.orders.append(repeat)
			memory.repeat_train_producer_ids[base.id] = true
		elif workers.size() >= want_workers and memory.repeat_train_producer_ids.has(base.id):
			var stop := EntityOrder.new()
			stop.type = EntityOrder.Type.REPEAT_TRAIN_TOGGLE
			stop.entity_id = base.id
			stop.enabled = false
			submit.orders.append(stop)
			memory.repeat_train_producer_ids.erase(base.id)

	# Refinery when the mix wants gas and a nearby geyser is uncovered.
	if _mix_wants_gas(registry, config) and player.minerals >= 75:
		var geyser := _uncovered_geyser_near_base(state, player_id, registry, snapshot)
		if geyser != null:
			var builder := _free_builder(workers, issued)
			if builder != null:
				var build := EntityOrder.new()
				build.type = EntityOrder.Type.BUILD
				build.entity_id = builder.id
				build.def_id = "refinery"
				build.target_tile = geyser.origin
				submit.orders.append(build)
				issued[builder.id] = true

	# Expand when rich and saturated.
	var base_def: EntityDef = registry.get_by_id("base")
	var base_cost: int = base_def.construction.mineral_cost if base_def != null else 400
	if (
		player.minerals >= base_cost + config.expand_mineral_buffer
		and workers.size() >= slots
		and not _has_pending_base(state, player_id, registry, snapshot)
	):
		var spot := _expansion_build_spot(state, player_id, registry, snapshot, memory)
		if spot != Vector2i(-1, -1):
			var builder := _free_builder(workers, issued)
			if builder != null:
				var build := EntityOrder.new()
				build.type = EntityOrder.Type.BUILD
				build.entity_id = builder.id
				build.def_id = "base"
				build.target_tile = spot
				submit.orders.append(build)
				issued[builder.id] = true


# ---------- Production ----------


static func _plan_production(
	state: MatchState,
	player_id: int,
	registry: EntityRegistry,
	config: AiConfig,
	memory: AiMemory,
	snapshot: Dictionary,
	submit: SubmitTurn,
	issued: Dictionary
) -> void:
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return
	var producers: Array[Entity] = snapshot["producers"]
	var workers: Array[Entity] = snapshot["workers"]

	# Rally army producers toward the staging point, once each.
	var staging := _staging_tile(state, snapshot, config)
	for producer in producers:
		if memory.rallied_producer_ids.has(producer.id):
			continue
		var def: EntityDef = registry.get_by_id(producer.current_def_id)
		if def == null or def.id == "base":
			continue
		var rally := EntityOrder.new()
		rally.type = EntityOrder.Type.SET_RALLY_POINT
		rally.entity_id = producer.id
		rally.mode = ProductionState.RALLY_MODE_MOVE
		rally.target_tile = staging
		submit.orders.append(rally)
		memory.rallied_producer_ids[producer.id] = true

	# Opening build order, one pending item at a time.
	while memory.build_order_index < config.build_order.size():
		var item: String = config.build_order[memory.build_order_index]
		var item_def: EntityDef = registry.get_by_id(item)
		if item_def == null:
			memory.build_order_index += 1
			continue
		if item_def.construction != null and item_def.tags.has("building"):
			if (
				_count_of(state, player_id, registry, item) > 0
				or _has_pending_build_of(state, player_id, item)
			):
				memory.build_order_index += 1
				continue
			if player.minerals < item_def.construction.mineral_cost:
				return
			var builder := _free_builder(workers, issued)
			if builder == null:
				return
			var spot := _building_spot_near_main(state, registry, snapshot, item_def)
			if spot == Vector2i(-1, -1):
				return
			var build := EntityOrder.new()
			build.type = EntityOrder.Type.BUILD
			build.entity_id = builder.id
			build.def_id = item
			build.target_tile = spot
			submit.orders.append(build)
			issued[builder.id] = true
			memory.build_order_index += 1
			return
		# Unit item: needs an idle matching producer + funds.
		var producer := _idle_producer_for(producers, registry, item, issued)
		if producer == null:
			return
		if not _can_afford_unit(player, item_def):
			return
		var train := EntityOrder.new()
		train.type = EntityOrder.Type.TRAIN
		train.entity_id = producer.id
		train.def_id = item
		submit.orders.append(train)
		issued[producer.id] = true
		memory.build_order_index += 1
		return

	# Steady state: keep one producer per mixed unit type, then train
	# the unit furthest below its mix share.
	var mix_units: Array[String] = _sorted_mix_units(config)
	for unit_id in mix_units:
		var producer_def_id := _producer_def_for_unit(registry, unit_id)
		if producer_def_id == "":
			continue
		if (
			_count_of(state, player_id, registry, producer_def_id) == 0
			and not _has_pending_build_of(state, player_id, producer_def_id)
		):
			var producer_def: EntityDef = registry.get_by_id(producer_def_id)
			if producer_def == null or producer_def.construction == null:
				continue
			if player.minerals < producer_def.construction.mineral_cost:
				return
			var builder := _free_builder(workers, issued)
			if builder == null:
				return
			var spot := _building_spot_near_main(state, registry, snapshot, producer_def)
			if spot == Vector2i(-1, -1):
				return
			var build := EntityOrder.new()
			build.type = EntityOrder.Type.BUILD
			build.entity_id = builder.id
			build.def_id = producer_def_id
			build.target_tile = spot
			submit.orders.append(build)
			issued[builder.id] = true
			return
	# Production-bound and rich: add another producer for the heaviest
	# mix unit so the bank converts into army.
	if not mix_units.is_empty():
		var heaviest := mix_units[0]
		for unit_id in mix_units:
			if int(config.unit_mix[unit_id]) > int(config.unit_mix[heaviest]):
				heaviest = unit_id
		var heavy_producer_id := _producer_def_for_unit(registry, heaviest)
		var heavy_producer_def: EntityDef = registry.get_by_id(heavy_producer_id)
		if (
			heavy_producer_def != null
			and heavy_producer_def.construction != null
			and player.minerals >= heavy_producer_def.construction.mineral_cost + 300
			and _idle_producer_for(producers, registry, heaviest, issued) == null
			and not _has_pending_build_of(state, player_id, heavy_producer_id)
		):
			var extra_builder := _free_builder(workers, issued)
			var extra_spot := _building_spot_near_main(
				state, registry, snapshot, heavy_producer_def
			)
			if extra_builder != null and extra_spot != Vector2i(-1, -1):
				var extra := EntityOrder.new()
				extra.type = EntityOrder.Type.BUILD
				extra.entity_id = extra_builder.id
				extra.def_id = heavy_producer_id
				extra.target_tile = extra_spot
				submit.orders.append(extra)
				issued[extra_builder.id] = true

	# Spend down the bank: keep training at every idle producer until
	# funds or producers run out.
	var spendable_minerals: int = player.minerals
	var spendable_gas: int = player.gas
	var spendable_pop: int = player.pop_cap - player.pop_used
	var candidate_mix_units: Array[String] = []
	candidate_mix_units.assign(mix_units)
	while true:
		var deficit_unit: String = _largest_deficit_unit(
			state, player_id, registry, config, candidate_mix_units
		)
		if deficit_unit == "":
			break
		var unit_def: EntityDef = registry.get_by_id(deficit_unit)
		if unit_def == null or unit_def.construction == null:
			candidate_mix_units.erase(deficit_unit)
			continue
		var producer: Entity = _idle_producer_for(producers, registry, deficit_unit, issued)
		if producer == null:
			candidate_mix_units.erase(deficit_unit)
			continue
		var pop_cost: int = unit_def.population.pop_cost if unit_def.population != null else 0
		if (
			spendable_minerals < unit_def.construction.mineral_cost
			or spendable_gas < unit_def.construction.gas_cost
			or spendable_pop < pop_cost
		):
			candidate_mix_units.erase(deficit_unit)
			continue
		var train: EntityOrder = EntityOrder.new()
		train.type = EntityOrder.Type.TRAIN
		train.entity_id = producer.id
		train.def_id = deficit_unit
		submit.orders.append(train)
		issued[producer.id] = true
		spendable_minerals -= unit_def.construction.mineral_cost
		spendable_gas -= unit_def.construction.gas_cost
		spendable_pop -= pop_cost
		candidate_mix_units.assign(mix_units)


# ---------- Army ----------


static func _plan_army(
	state: MatchState,
	_player_id: int,
	registry: EntityRegistry,
	config: AiConfig,
	memory: AiMemory,
	snapshot: Dictionary,
	submit: SubmitTurn,
	issued: Dictionary
) -> void:
	var army: Array[Entity] = snapshot["army"]
	if army.is_empty():
		return
	var staging := _staging_tile(state, snapshot, config)
	var visible_enemies := _known_enemy_units_near(state, registry, memory, army)

	# Micro first: in-contact units focus the lowest-HP visible enemy.
	if not visible_enemies.is_empty():
		var chain: Array[int] = []
		for enemy in visible_enemies:
			chain.append(enemy.id)
			if chain.size() >= 3:
				break
		var in_contact: Array[int] = []
		for unit in army:
			if issued.has(unit.id):
				continue
			var def: EntityDef = registry.get_by_id(unit.current_def_id)
			if def == null or def.combat == null:
				continue
			var attack_range := MechanicsSystem.effective_attack_range(unit, def.combat)
			for enemy in visible_enemies:
				var distance := maxi(
					absi(unit.origin.x - enemy.origin.x), absi(unit.origin.y - enemy.origin.y)
				)
				if distance <= attack_range + 1:
					in_contact.append(unit.id)
					break
		for order in OrderBuilder.fan_out_target(in_contact, chain):
			submit.orders.append(order)
			issued[order.entity_id] = true
		_plan_siege(state, registry, army, visible_enemies, submit, issued)

	# Attack / retreat state machine on army value.
	var army_value: int = snapshot["army_value"]
	var enemy_value := _last_seen_enemy_army_value(registry, memory)
	if memory.attacking:
		if enemy_value > 0 and army_value * 100 < enemy_value * config.retreat_below_enemy_pct:
			memory.attacking = false
	elif army_value >= config.attack_army_value:
		memory.attacking = true

	var remaining: Array[int] = []
	for unit in army:
		if not issued.has(unit.id):
			remaining.append(unit.id)
	if remaining.is_empty():
		return

	if memory.attacking:
		var target := _attack_target(memory)
		# Close-out sweep: nothing known to kill and the army already
		# reached the base guess -> rotate through the map's resource
		# clusters (bases hide near resources; static map knowledge).
		if not _knows_enemy_building(memory) and _army_near(state, remaining, target, 8):
			target = _sweep_waypoint(state, registry, snapshot, memory)
		for order in OrderBuilder.fan_out_attack_move(remaining, target):
			submit.orders.append(order)
			issued[order.entity_id] = true
		return

	# Scout when the enemy has gone unseen for too long.
	if (
		state.turn_index >= config.scout_turn
		and state.turn_index - memory.last_enemy_seen_turn >= config.scout_stale_turns
	):
		var scout_id := remaining[0]
		memory.scout_unit_id = scout_id
		for order in OrderBuilder.fan_out_move([scout_id] as Array[int], memory.enemy_base_guess):
			submit.orders.append(order)
			issued[order.entity_id] = true
			remaining.erase(scout_id)

	# Everyone else holds at staging.
	var to_stage: Array[int] = []
	for unit_id in remaining:
		var unit := state.get_entity_by_id(unit_id)
		if unit == null:
			continue
		var distance := maxi(absi(unit.origin.x - staging.x), absi(unit.origin.y - staging.y))
		if distance > 4:
			to_stage.append(unit_id)
	for order in OrderBuilder.fan_out_move(to_stage, staging):
		submit.orders.append(order)
		issued[order.entity_id] = true


static func _plan_siege(
	_state: MatchState,
	_registry: EntityRegistry,
	army: Array[Entity],
	visible_enemies: Array[Entity],
	submit: SubmitTurn,
	issued: Dictionary
) -> void:
	for unit in army:
		if unit.current_def_id != "tank" or issued.has(unit.id):
			continue
		var sieged := StatusSystem.has_status(unit, "sieged")
		var nearest := 1 << 30
		for enemy in visible_enemies:
			var distance := maxi(
				absi(unit.origin.x - enemy.origin.x), absi(unit.origin.y - enemy.origin.y)
			)
			nearest = mini(nearest, distance)
		if not sieged and nearest <= 6 and nearest >= 2:
			var siege := EntityOrder.new()
			siege.type = EntityOrder.Type.USE_ABILITY
			siege.entity_id = unit.id
			siege.def_id = "siege_mode"
			submit.orders.append(siege)
			issued[unit.id] = true
		elif sieged and nearest > 8:
			var unsiege := EntityOrder.new()
			unsiege.type = EntityOrder.Type.USE_ABILITY
			unsiege.entity_id = unit.id
			unsiege.def_id = "unsiege_mode"
			submit.orders.append(unsiege)
			issued[unit.id] = true


# ---------- Helpers ----------


static func _army_value(army: Array[Entity], registry: EntityRegistry) -> int:
	var value := 0
	for unit in army:
		var def: EntityDef = registry.get_by_id(unit.current_def_id)
		if def != null and def.construction != null:
			value += def.construction.mineral_cost + def.construction.gas_cost
	return value


static func _last_seen_enemy_army_value(registry: EntityRegistry, memory: AiMemory) -> int:
	var value := 0
	for enemy_id in memory.enemy_last_seen:
		var record: Dictionary = memory.enemy_last_seen[enemy_id]
		if record["building"]:
			continue
		var def: EntityDef = registry.get_by_id(record["def_id"])
		if def != null and def.construction != null and def.combat != null:
			value += def.construction.mineral_cost + def.construction.gas_cost
	return value


static func _known_enemy_units_near(
	state: MatchState, registry: EntityRegistry, memory: AiMemory, army: Array[Entity]
) -> Array[Entity]:
	# Freshly-seen enemies only (recorded this turn), sorted by hp then
	# id so focus chains are deterministic and finish wounded targets.
	var out: Array[Entity] = []
	for enemy_id in memory.enemy_last_seen:
		var record: Dictionary = memory.enemy_last_seen[enemy_id]
		if int(record["turn"]) != state.turn_index:
			continue
		var enemy := state.get_entity_by_id(enemy_id)
		if enemy == null or enemy.current_hp <= 0:
			continue
		var def: EntityDef = registry.get_by_id(enemy.current_def_id)
		if def == null:
			continue
		var near := false
		for unit in army:
			if (
				maxi(absi(unit.origin.x - enemy.origin.x), absi(unit.origin.y - enemy.origin.y))
				<= 10
			):
				near = true
				break
		if near:
			out.append(enemy)
	out.sort_custom(
		func(a: Entity, b: Entity) -> bool:
			if a.current_hp != b.current_hp:
				return a.current_hp < b.current_hp
			return a.id < b.id
	)
	return out


static func _knows_enemy_building(memory: AiMemory) -> bool:
	for enemy_id in memory.enemy_last_seen:
		if memory.enemy_last_seen[enemy_id]["building"]:
			return true
	return false


static func _army_near(
	state: MatchState, unit_ids: Array[int], target: Vector2i, radius: int
) -> bool:
	for unit_id in unit_ids:
		var unit := state.get_entity_by_id(unit_id)
		if unit == null:
			continue
		if maxi(absi(unit.origin.x - target.x), absi(unit.origin.y - target.y)) <= radius:
			return true
	return false


# Deterministic patrol over resource-cluster anchors, rotating every
# 8 turns so the army eventually walks the whole economy landscape.
static func _sweep_waypoint(
	state: MatchState, registry: EntityRegistry, snapshot: Dictionary, memory: AiMemory
) -> Vector2i:
	var anchors: Array[Vector2i] = []
	for entity in snapshot["sources"]:
		var def: EntityDef = registry.get_by_id(entity.current_def_id)
		if def == null or def.resource_source == null:
			continue
		var clustered := false
		for anchor in anchors:
			if maxi(absi(anchor.x - entity.origin.x), absi(anchor.y - entity.origin.y)) <= 8:
				clustered = true
				break
		if not clustered:
			anchors.append(entity.origin)
	if anchors.is_empty():
		return memory.enemy_base_guess
	var index := (state.turn_index / 8) % anchors.size()
	return anchors[index]


static func _attack_target(memory: AiMemory) -> Vector2i:
	# Prefer the last-seen enemy building nearest the base guess (kill
	# the base), else the guess itself.
	var best := memory.enemy_base_guess
	var best_distance := 1 << 30
	for enemy_id in memory.enemy_last_seen:
		var record: Dictionary = memory.enemy_last_seen[enemy_id]
		if not record["building"]:
			continue
		var origin: Vector2i = record["origin"]
		var distance := maxi(
			absi(origin.x - memory.enemy_base_guess.x), absi(origin.y - memory.enemy_base_guess.y)
		)
		if distance < best_distance:
			best = origin
			best_distance = distance
	return best


static func _staging_tile(state: MatchState, snapshot: Dictionary, config: AiConfig) -> Vector2i:
	var bases: Array[Entity] = snapshot["bases"]
	if bases.is_empty():
		return Vector2i(state.tile_grid.width / 2, state.tile_grid.height / 2)
	var main: Entity = bases[0]
	var center := Vector2i(state.tile_grid.width / 2, state.tile_grid.height / 2)
	var direction_x := 1 if center.x >= main.origin.x else -1
	return Vector2i(
		clampi(
			main.origin.x + direction_x * config.staging_advance_tiles, 1, state.tile_grid.width - 2
		),
		clampi(main.origin.y + 2, 1, state.tile_grid.height - 2)
	)


static func _nearest_open_source(
	state: MatchState,
	player_id: int,
	registry: EntityRegistry,
	near: Entity,
	assignments: Dictionary
) -> Entity:
	var best: Entity = null
	var best_distance := 1 << 30
	for entity in state.entities_sorted_by_id():
		var def: EntityDef = registry.get_by_id(entity.current_def_id)
		if def == null or def.resource_source == null:
			continue
		if entity.current_resource_amount == 0:
			continue
		if def.resource_source.requires_extractor:
			continue  # geysers need a refinery; rally minerals only
		if not GATHER.source_near_owned_base(state, registry, player_id, entity):
			continue
		var cap := GATHER.source_gatherer_cap(registry, entity)
		if cap <= 0:
			continue
		if GATHER._assigned_gatherer_count_for_source(assignments, entity.id, near.id) >= cap:
			continue
		var distance := maxi(
			absi(entity.origin.x - near.origin.x), absi(entity.origin.y - near.origin.y)
		)
		if (
			distance < best_distance
			or (distance == best_distance and best != null and entity.id < best.id)
		):
			best = entity
			best_distance = distance
	return best


static func _total_gather_slots(
	state: MatchState, player_id: int, registry: EntityRegistry, snapshot: Dictionary
) -> int:
	var slots := 0
	for entity in snapshot["sources"]:
		var def: EntityDef = registry.get_by_id(entity.current_def_id)
		if def == null or def.resource_source == null:
			continue
		if entity.current_resource_amount == 0:
			continue
		if not GATHER.source_near_owned_base(state, registry, player_id, entity):
			continue
		if def.resource_source.requires_extractor:
			# Counts only when covered by an owned refinery.
			if GATHER._find_extractor_at(state, registry, entity, player_id) == null:
				continue
		slots += GATHER.source_gatherer_cap(registry, entity)
	return slots


static func _mix_wants_gas(registry: EntityRegistry, config: AiConfig) -> bool:
	for unit_id in config.unit_mix:
		var def: EntityDef = registry.get_by_id(str(unit_id))
		if def != null and def.construction != null and def.construction.gas_cost > 0:
			return true
	return false


static func _uncovered_geyser_near_base(
	state: MatchState, player_id: int, registry: EntityRegistry, snapshot: Dictionary
) -> Entity:
	for entity in snapshot["sources"]:
		var def: EntityDef = registry.get_by_id(entity.current_def_id)
		if def == null or def.resource_source == null:
			continue
		if not def.resource_source.requires_extractor:
			continue
		if not GATHER.source_near_owned_base(state, registry, player_id, entity):
			continue
		if GATHER._find_extractor_at(state, registry, entity, player_id) != null:
			continue
		return entity
	return null


static func _free_builder(workers: Array[Entity], issued: Dictionary) -> Entity:
	for worker in workers:
		if issued.has(worker.id):
			continue
		if worker.locked_to_building_id >= 0 or worker.pending_build_def_id != "":
			continue
		return worker
	return null


static func _has_pending_base(
	state: MatchState, player_id: int, registry: EntityRegistry, snapshot: Dictionary
) -> bool:
	for building in snapshot["buildings"]:
		var def: EntityDef = registry.get_by_id(building.current_def_id)
		if def != null and def.id == "base" and building.is_constructing:
			return true
	return _has_pending_build_of(state, player_id, "base")


static func _pending_count_of(state: MatchState, player_id: int, def_id: String) -> int:
	var count := 0
	for entity in state.entities_sorted_by_id():
		if entity.owner_player_id != player_id:
			continue
		if entity.pending_build_def_id == def_id:
			count += 1
		elif entity.is_constructing and entity.current_def_id == def_id:
			count += 1
	return count


static func _has_pending_build_of(state: MatchState, player_id: int, def_id: String) -> bool:
	for entity in state.entities_sorted_by_id():
		if entity.owner_player_id != player_id:
			continue
		if entity.pending_build_def_id == def_id:
			return true
		if entity.is_constructing and entity.current_def_id == def_id:
			return true
	return false


static func _count_of(
	state: MatchState, player_id: int, _registry: EntityRegistry, def_id: String
) -> int:
	var count := 0
	for entity in state.entities_sorted_by_id():
		if entity.owner_player_id != player_id or entity.current_hp <= 0:
			continue
		if entity.current_def_id == def_id and not entity.is_constructing:
			count += 1
	return count


static func _producer_def_for_unit(registry: EntityRegistry, unit_id: String) -> String:
	for def in registry.entities:
		if def == null or def.production == null:
			continue
		if def.production.produces.has(unit_id):
			return def.id
	return ""


static func _idle_producer_for(
	producers: Array[Entity], registry: EntityRegistry, unit_id: String, issued: Dictionary
) -> Entity:
	for producer in producers:
		if issued.has(producer.id):
			continue
		var def: EntityDef = registry.get_by_id(producer.current_def_id)
		if def == null or def.production == null:
			continue
		if not def.production.produces.has(unit_id):
			continue
		if producer.production_state == null:
			continue
		if not producer.production_state.active.is_empty():
			continue
		if not producer.production_state.queue.is_empty():
			continue
		return producer
	return null


static func _can_afford_unit(player: PlayerState, def: EntityDef) -> bool:
	if def.construction == null:
		return false
	if player.minerals < def.construction.mineral_cost:
		return false
	if player.gas < def.construction.gas_cost:
		return false
	var pop_cost := def.population.pop_cost if def.population != null else 0
	return player.pop_used + pop_cost <= player.pop_cap


static func _sorted_mix_units(config: AiConfig) -> Array[String]:
	var out: Array[String] = []
	for unit_id in config.unit_mix:
		out.append(str(unit_id))
	out.sort()
	return out


static func _largest_deficit_unit(
	state: MatchState,
	player_id: int,
	registry: EntityRegistry,
	config: AiConfig,
	mix_units: Array[String]
) -> String:
	var total_weight := 0
	var total_count := 0
	var counts: Dictionary = {}
	for unit_id in mix_units:
		total_weight += int(config.unit_mix[unit_id])
		counts[unit_id] = _count_of(state, player_id, registry, unit_id)
		total_count += int(counts[unit_id])
	if total_weight <= 0:
		return ""
	var best := ""
	var best_deficit := -(1 << 30)
	for unit_id in mix_units:
		var weight: int = int(config.unit_mix[unit_id])
		# Deficit in integer math: target share minus actual share,
		# scaled. (count+1 normalizes the empty-army start.)
		var deficit: int = weight * (total_count + 1) - int(counts[unit_id]) * total_weight
		if deficit > best_deficit:
			best = unit_id
			best_deficit = deficit
	return best


static func _building_spot_near_main(
	state: MatchState, _registry: EntityRegistry, snapshot: Dictionary, def: EntityDef
) -> Vector2i:
	var bases: Array[Entity] = snapshot["bases"]
	if bases.is_empty():
		return Vector2i(-1, -1)
	return _clear_spot_near(state, bases[0].origin, def.footprint)


static func _expansion_build_spot(
	state: MatchState,
	player_id: int,
	registry: EntityRegistry,
	snapshot: Dictionary,
	memory: AiMemory
) -> Vector2i:
	# Nearest mineral source that is NOT near an owned base and not at
	# the enemy spawn side; build the base beside it.
	var bases: Array[Entity] = snapshot["bases"]
	if bases.is_empty():
		return Vector2i(-1, -1)
	var main: Entity = bases[0]
	var base_def: EntityDef = registry.get_by_id("base")
	var fp: Vector2i = base_def.footprint if base_def != null else Vector2i(4, 4)
	var best := Vector2i(-1, -1)
	var best_distance := 1 << 30
	for entity in snapshot["sources"]:
		var def: EntityDef = registry.get_by_id(entity.current_def_id)
		if def == null or def.resource_source == null or def.resource_source.requires_extractor:
			continue
		if entity.current_resource_amount == 0:
			continue
		if GATHER.source_near_owned_base(state, registry, player_id, entity):
			continue
		var to_enemy := maxi(
			absi(entity.origin.x - memory.enemy_base_guess.x),
			absi(entity.origin.y - memory.enemy_base_guess.y)
		)
		if to_enemy < 14:
			continue  # don't try to expand into the enemy main
		var distance := maxi(
			absi(entity.origin.x - main.origin.x), absi(entity.origin.y - main.origin.y)
		)
		if distance < best_distance:
			var spot := _clear_spot_near(state, entity.origin, fp)
			if spot != Vector2i(-1, -1):
				best = spot
				best_distance = distance
	return best


# Deterministic outward ring scan for a clear, buildable rect origin.
static func _clear_spot_near(state: MatchState, around: Vector2i, footprint: Vector2i) -> Vector2i:
	for radius in range(2, 9):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var origin := around + Vector2i(dx, dy)
				var rect := Rect2i(origin, footprint)
				if not state.tile_grid.is_rect_in_bounds(rect):
					continue
				if not state.tile_grid.is_rect_clear(rect):
					continue
				if STATE_HELPERS._build_rect_terrain_blocked(state, rect):
					continue
				return origin
	return Vector2i(-1, -1)
