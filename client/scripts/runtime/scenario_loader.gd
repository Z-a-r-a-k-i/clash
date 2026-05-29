@tool
class_name ScenarioLoader
extends RefCounted

# Builds a LoadedScenario from a ScenarioDef. Pure function — does not
# mutate either input. The returned LoadedScenario carries both:
# - the freshly-built MatchState (ready to feed Resolver.resolve)
# - the effective EntityRegistry (registry_override or canonical, plus
#   any stat_overrides applied on a deep clone)
#
# Plan node 07a. Returning both as a single value matters because
# stat_overrides can patch entity defs (clone-then-mutate); the resolver
# every turn needs the SAME registry the loader used, otherwise it'd
# see the canonical .tres values and the overrides wouldn't take effect.
#
# Usage:
#   var loaded := ScenarioLoader.load(scenario, registry, tunables)
#   Resolver.resolve(loaded.state, ..., loaded.registry, ...)


static func load(
	scenario: ScenarioDef, registry: EntityRegistry, _tunables: Tunables
) -> LoadedScenario:
	if scenario == null or registry == null:
		push_warning("ScenarioLoader.load: scenario or registry is null; returning null.")
		return null

	var base_registry: EntityRegistry = (
		scenario.registry_override if scenario.registry_override != null else registry
	)
	var effective_registry := _apply_stat_overrides(base_registry, scenario.stat_overrides)

	var state := MatchState.new()
	state.turn_index = 0
	state.rng_seed = 0
	state.next_entity_id = 1
	state.match_over = false
	state.winner_player_id = -1

	# Tile grid dimensions come from the scenario itself (plan-08's map
	# data layer will set these). Reject invalid sizes loudly.
	var grid_w: int = scenario.map_width
	var grid_h: int = scenario.map_height
	if grid_w <= 0 or grid_h <= 0:
		push_warning(
			(
				"ScenarioLoader.load: map_width/map_height must be > 0 (got %d x %d); using 50x50 fallback."
				% [grid_w, grid_h]
			)
		)
		grid_w = 50
		grid_h = 50
	state.tile_grid = TileGrid.new(grid_w, grid_h)

	# Two-player init. Plan-04+ already encodes the 0/1 convention.
	state.players = [_make_player(0), _make_player(1)]
	_apply_starting_resources(state, scenario)

	# Process placements.
	for placement in scenario.placements:
		if placement == null:
			continue
		var def: EntityDef = effective_registry.get_by_id(placement.def_id)
		if def == null:
			push_warning(
				(
					"ScenarioLoader: placement references unknown def_id '%s'; skipping."
					% placement.def_id
				)
			)
			continue
		var entity := _instantiate_entity(state, placement, def)
		# Sanitize footprint: missing or non-positive on either axis
		# falls back to a 1x1 cell. Catches malformed defs (e.g. someone
		# leaving `footprint = Vector2i(0, 2)` in a .tres) before they
		# produce an empty/invalid Rect2i.
		var footprint := Vector2i(max(def.footprint.x, 1), max(def.footprint.y, 1))
		var rect := Rect2i(placement.origin, footprint)
		var placed := _place_entity(state, effective_registry, entity, def, rect)
		if not placed:
			push_warning(
				(
					"ScenarioLoader: could not place '%s' at %s (overlap / out-of-bounds); skipping."
					% [placement.def_id, str(placement.origin)]
				)
			)
			continue
		state.entities.append(entity)

	# Auto-account placement pop costs into pop_used and pop_provides
	# into pop_cap. Walks state.entities (only successfully-placed
	# entities) so skipped placements don't get charged.
	_apply_placement_pop_used(state, effective_registry)
	_apply_placement_pop_cap_from_buildings(state, effective_registry)
	if scenario.auto_start_workers_on_minerals:
		_auto_start_workers_on_minerals(state, effective_registry)

	var loaded := LoadedScenario.new()
	loaded.state = state
	loaded.registry = effective_registry
	return loaded


# ---------- Internals ----------


static func _make_player(player_id: int) -> PlayerState:
	var p := PlayerState.new()
	p.player_id = player_id
	return p


static func _apply_starting_resources(state: MatchState, scenario: ScenarioDef) -> void:
	for player_id_key in scenario.starting_resources_per_player:
		var pid := player_id_key as int
		var player := state.get_player(pid)
		if player == null:
			continue
		var resources: Dictionary = scenario.starting_resources_per_player[player_id_key]
		if resources.has("minerals"):
			player.minerals = resources["minerals"]
		if resources.has("gas"):
			player.gas = resources["gas"]
		if resources.has("pop_cap"):
			player.pop_cap = resources["pop_cap"]
		if resources.has("pop_used"):
			player.pop_used = resources["pop_used"]


# Place `entity` on the tile grid, using place_overlapping if the def's
# construction declares a requires_target_tag (refinery-on-geyser).
# Returns true on success.
static func _place_entity(
	state: MatchState, registry: EntityRegistry, entity: Entity, def: EntityDef, rect: Rect2i
) -> bool:
	if def.construction != null and def.construction.requires_target_tag != "":
		var tag: String = def.construction.requires_target_tag
		var target_id: int = _find_target_at_tile(state, registry, rect.position, tag)
		if target_id < 0:
			return false
		var target_rect: Rect2i = state.tile_grid.entity_rect(target_id)
		if target_rect.size.x <= 0 or target_rect.size.y <= 0:
			return false
		rect = Rect2i(target_rect.position, rect.size)
		if target_rect.size != rect.size:
			return false
		entity.origin = rect.position
		# Defensive: every occupant in `rect` must be the target. This
		# is already implied by _find_target_at_tile plus the matched
		# footprint above and TileGrid.place_overlapping's own
		# rect-intersection check, but we make the contract local so a
		# future refactor of either callee can't silently break it.
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			for y in range(rect.position.y, rect.position.y + rect.size.y):
				for occ in state.tile_grid.entities_at(Vector2i(x, y)):
					if occ != target_id:
						return false
		return state.tile_grid.place_overlapping(entity.id, rect, target_id)
	return state.tile_grid.place(entity.id, rect)


# Returns the id of the existing entity at `tile` whose def carries `tag`,
# or -1 if no such target. Kept local to avoid cross-module coupling for
# scenario placement.
static func _find_target_at_tile(
	state: MatchState, registry: EntityRegistry, tile: Vector2i, tag: String
) -> int:
	if state.tile_grid == null or registry == null:
		return -1
	if not state.tile_grid.is_in_bounds(tile):
		return -1
	var matching_ids: Array[int] = []
	for occupant_id in state.tile_grid.entities_at(tile):
		var occupant: Entity = state.get_entity_by_id(occupant_id)
		if occupant == null:
			continue
		var occ_def: EntityDef = registry.get_by_id(_effective_def_id(occupant))
		if occ_def != null and occ_def.tags.has(tag):
			matching_ids.append(occupant.id)
	if matching_ids.size() != 1:
		return -1
	return matching_ids[0]


static func _effective_def_id(entity: Entity) -> String:
	if entity == null:
		return ""
	if entity.current_def_id != "":
		return entity.current_def_id
	return entity.def_id


# After placement, walk the SUCCESSFULLY-PLACED entities and credit
# each player's pop_used by the def's population.pop_cost. Iterates
# state.entities (not scenario.placements) so skipped placements
# (off-grid, overlap) don't get charged. Authors who want a custom
# starting pop_used can pre-set it via starting_resources_per_player;
# the auto-credit adds on top.
static func _apply_placement_pop_used(state: MatchState, registry: EntityRegistry) -> void:
	for entity in state.entities:
		if entity == null:
			continue
		var def: EntityDef = registry.get_by_id(entity.current_def_id)
		if def == null or def.population == null:
			continue
		var player := state.get_player(entity.owner_player_id)
		if player == null:
			continue
		# Buildings provide pop, units cost pop. Tag-driven so we don't
		# misclassify (e.g. a worker has pop_cost AND no building tag).
		if not def.tags.has("building"):
			player.pop_used += def.population.pop_cost


# Buildings placed in a scenario are assumed already-built (not under
# construction) — apply their pop_provides to pop_cap so the player
# can immediately train units up to the expected supply.
static func _apply_placement_pop_cap_from_buildings(
	state: MatchState, registry: EntityRegistry
) -> void:
	for entity in state.entities:
		if entity == null:
			continue
		var def: EntityDef = registry.get_by_id(entity.current_def_id)
		if def == null or def.population == null:
			continue
		if not def.tags.has("building"):
			continue
		var player := state.get_player(entity.owner_player_id)
		if player == null:
			continue
		player.pop_cap += def.population.pop_provides


static func _auto_start_workers_on_minerals(state: MatchState, registry: EntityRegistry) -> void:
	if state == null or registry == null or state.tile_grid == null:
		return
	var mineral_sources := _mineral_sources(state, registry)
	if mineral_sources.is_empty():
		return
	var source_counts: Dictionary[int, int] = {}
	for player in state.players:
		if player == null:
			continue
		_auto_start_player_workers_on_minerals(
			state, registry, player.player_id, mineral_sources, source_counts
		)


static func _auto_start_player_workers_on_minerals(
	state: MatchState,
	registry: EntityRegistry,
	player_id: int,
	mineral_sources: Array[Entity],
	source_counts: Dictionary[int, int]
) -> void:
	for worker in state.entities_sorted_by_id():
		if worker == null or worker.owner_player_id != player_id or worker.current_hp <= 0:
			continue
		var worker_def: EntityDef = registry.get_by_id(worker.current_def_id)
		if worker_def == null or worker_def.gather == null or worker.gather_state == null:
			continue
		var source := _nearest_source_for_worker(
			state, registry, worker, mineral_sources, source_counts
		)
		if source == null:
			continue
		source_counts[source.id] = source_counts.get(source.id, 0) + 1
		_assign_worker_to_source(state, worker, source)


static func _mineral_sources(state: MatchState, registry: EntityRegistry) -> Array[Entity]:
	var sources: Array[Entity] = []
	for entity in state.entities_sorted_by_id():
		# -1 is infinite capacity; only exactly zero is depleted.
		if entity == null or entity.current_resource_amount == 0:
			continue
		var def: EntityDef = registry.get_by_id(entity.current_def_id)
		if def == null or def.resource_source == null:
			continue
		if def.resource_source.resource_type != "minerals":
			continue
		sources.append(entity)
	return sources


static func _nearest_source_for_worker(
	state: MatchState,
	registry: EntityRegistry,
	worker: Entity,
	sources: Array[Entity],
	source_counts: Dictionary[int, int]
) -> Entity:
	var worker_rect: Rect2i = state.tile_grid.entity_rect(worker.id)
	var best: Entity = null
	var best_distance := 2147483647
	for source in sources:
		if source == null:
			continue
		if not _source_has_auto_start_slot(registry, source, source_counts):
			continue
		var source_rect: Rect2i = state.tile_grid.entity_rect(source.id)
		if source_rect.size == Vector2i.ZERO:
			continue
		var distance: int = TileGrid.distance_between_rects(worker_rect, source_rect)
		if _is_better_auto_source(source, distance, best, best_distance):
			best = source
			best_distance = distance
	return best


static func _source_has_auto_start_slot(
	registry: EntityRegistry, source: Entity, source_counts: Dictionary[int, int]
) -> bool:
	var cap: int = GatherSystem.source_gatherer_cap(registry, source)
	if cap <= 0:
		return false
	return source_counts.get(source.id, 0) < cap


static func _is_better_auto_source(
	source: Entity, distance: int, current: Entity, current_distance: int
) -> bool:
	if current == null:
		return true
	if distance < current_distance:
		return true
	return distance == current_distance and source.id < current.id


static func _assign_worker_to_source(state: MatchState, worker: Entity, source: Entity) -> void:
	var gather: GatherState = worker.gather_state
	if gather == null:
		return
	gather.assigned_source_entity_id = source.id
	gather.carrying_resource_type = ""
	gather.carrying_amount = 0
	var worker_rect: Rect2i = state.tile_grid.entity_rect(worker.id)
	var source_rect: Rect2i = state.tile_grid.entity_rect(source.id)
	gather.phase = (
		GatherState.Phase.GATHERING
		if state.tile_grid.are_rects_adjacent(worker_rect, source_rect)
		else GatherState.Phase.MOVING_TO_SOURCE
	)


static func _instantiate_entity(
	state: MatchState, placement: ScenarioPlacement, def: EntityDef
) -> Entity:
	var e := Entity.new()
	e.id = state.allocate_entity_id()
	e.def_id = placement.def_id
	e.current_def_id = placement.def_id
	e.owner_player_id = placement.owner_player_id
	e.origin = placement.origin
	# Layer: explicit override > def's default movement layer > "ground".
	if placement.current_layer != "":
		e.current_layer = placement.current_layer
	elif def.movement != null and def.movement.default_layer != "":
		e.current_layer = def.movement.default_layer
	else:
		e.current_layer = "ground"
	# HP: explicit override > def's max_hp > 0.
	if placement.initial_hp_override >= 0:
		e.current_hp = placement.initial_hp_override
	elif def.health != null:
		e.current_hp = def.health.max_hp
	else:
		e.current_hp = 0
	# Initial hidden flag from the def. EOT will recompute via
	# _recompute_is_hidden using both this and the layer set, but seeding
	# it here means a default_hidden entity placed via a scenario starts
	# correctly hidden on turn 0 (before any EOT runs).
	e.is_hidden = def.default_hidden
	# Capability-paired runtime state.
	if def.production != null:
		e.production_state = ProductionState.new()
	if def.gather != null:
		e.gather_state = GatherState.new()
	if def.resource_source != null:
		e.current_resource_amount = def.resource_source.capacity
	return e


# Builds a new EntityRegistry containing patched copies of any def
# referenced by `overrides`. Defs without overrides are passed through
# by reference (shared, never mutated). Returns the input registry
# unchanged if no overrides apply, avoiding unnecessary clones.
static func _apply_stat_overrides(
	base_registry: EntityRegistry, overrides: Array[ScenarioStatOverride]
) -> EntityRegistry:
	if overrides.is_empty():
		return base_registry
	# Group overrides by entity_def_id so each def is cloned at most once.
	var groups: Dictionary = {}
	for ov in overrides:
		if ov == null or ov.entity_def_id == "":
			continue
		if not groups.has(ov.entity_def_id):
			var bucket: Array[ScenarioStatOverride] = []
			groups[ov.entity_def_id] = bucket
		groups[ov.entity_def_id].append(ov)
	if groups.is_empty():
		return base_registry
	# Track which override entity_def_ids actually matched a registry
	# def, so we can flag typos / orphaned overrides.
	var matched_ids: Dictionary = {}
	var new_reg := EntityRegistry.new()
	new_reg.entities = []
	for def in base_registry.entities:
		if def == null:
			continue
		if groups.has(def.id):
			new_reg.entities.append(
				_clone_and_patch(def, groups[def.id] as Array[ScenarioStatOverride])
			)
			matched_ids[def.id] = true
		else:
			new_reg.entities.append(def)
	new_reg.researches = base_registry.researches.duplicate()
	for ov_id in groups:
		if not matched_ids.has(ov_id):
			push_warning(
				(
					"ScenarioStatOverride: entity_def_id '%s' has no matching def in registry; overrides ignored."
					% ov_id
				)
			)
	return new_reg


static func _clone_and_patch(def: EntityDef, overrides: Array[ScenarioStatOverride]) -> EntityDef:
	var copy: EntityDef = def.duplicate(true) as EntityDef
	for ov in overrides:
		_apply_one_override(copy, ov)
	return copy


# Walks `def` to the named capability sub-resource and writes `field`.
# Drops with a warning on bad capability / missing field — the override
# came from author-controlled data so loud failure helps catch typos.
static func _apply_one_override(def: EntityDef, ov: ScenarioStatOverride) -> void:
	# Renaming the cloned def's id would break later get_by_id lookups
	# inside the loader and the resolver. Reject explicitly.
	if ov.capability == "" and ov.field == "id":
		push_warning(
			(
				"ScenarioStatOverride: refusing to override top-level 'id' on def '%s'."
				% ov.entity_def_id
			)
		)
		return
	var target: Resource = _resolve_capability_target(def, ov.capability)
	if target == null:
		push_warning(
			(
				"ScenarioStatOverride: %s.%s.%s — capability missing on def; skipping."
				% [ov.entity_def_id, ov.capability, ov.field]
			)
		)
		return
	var value: Variant
	match ov.value_kind:
		"int":
			value = ov.value_int
		"float":
			value = ov.value_float
		"string":
			value = ov.value_string
		_:
			push_warning(
				(
					"ScenarioStatOverride: unknown value_kind '%s' on %s.%s.%s; skipping."
					% [ov.value_kind, ov.entity_def_id, ov.capability, ov.field]
				)
			)
			return
	# Validate the field exists before set() — Object.set silently
	# no-ops on missing properties, which would mask author typos.
	if not _has_property(target, ov.field):
		push_warning(
			(
				"ScenarioStatOverride: %s.%s.%s — field missing on capability; skipping."
				% [ov.entity_def_id, ov.capability, ov.field]
			)
		)
		return
	target.set(ov.field, value)


# Walks `obj.get_property_list()` looking for `field`. Used to flag
# typo'd ScenarioStatOverride.field values that would otherwise
# silently no-op via Object.set.
static func _has_property(obj: Object, field: String) -> bool:
	if obj == null or field == "":
		return false
	for entry in obj.get_property_list():
		if entry.get("name", "") == field:
			return true
	return false


# Returns the capability sub-resource named by `capability`, or the def
# itself if `capability` is empty (allowing top-level field overrides).
static func _resolve_capability_target(def: EntityDef, capability: String) -> Resource:
	if capability == "":
		return def
	match capability:
		"health":
			return def.health
		"combat":
			return def.combat
		"movement":
			return def.movement
		"construction":
			return def.construction
		"production":
			return def.production
		"vision":
			return def.vision
		"population":
			return def.population
		"gather":
			return def.gather
		"resource_source":
			return def.resource_source
		"abilities":
			return def.abilities
	return null
