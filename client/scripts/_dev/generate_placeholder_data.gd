extends SceneTree

# One-shot generator for the M0 placeholder data set. CLI-only:
#
#   godot --headless --path client --script scripts/_dev/generate_placeholder_data.gd
#
# This script INTENTIONALLY does NOT auto-fire from the editor. A
# previous version was `@tool extends Node` and ran via _enter_tree on
# scene open, which destroyed manually-enriched .tres files (plan-06
# attack modifiers, real HP values, construction defs) every time the
# editor reopened a saved tab containing the generator scene. That class
# of bug should never recur — entity .tres are now hand-authored canon,
# this generator is a recovery tool only, and the only way to invoke it
# is via the CLI command above (no scene trigger).
#
# WARNING: running this WILL OVERWRITE every entity .tres in
# `client/data/entities/` and `client/data/abilities/` with the values
# encoded below. Only run it intentionally to bootstrap from scratch.
# The hand-authored entities have richer data than what this generator
# encodes (see plan-06 + plan-07a additions); use git to restore them
# afterwards if you only wanted to regenerate a subset.

const DATA_ROOT := "res://data"


func _init() -> void:
	var count := 0
	count += _gen_abilities()
	count += _gen_units()
	count += _gen_buildings()
	count += _gen_neutrals()
	count += _gen_tunables()
	count += _gen_registry()
	print("[generate_placeholder_data] Generated %d resources, done." % count)
	quit(0)


# ---------- Abilities ----------


func _gen_abilities() -> int:
	var saved := 0

	# Siege mode: 1-tick cast, applies the indefinite "sieged" status
	# (plan node 14 — siege is status-driven, not a def swap).
	var siege := AbilityDef.new()
	siege.id = "siege_mode"
	siege.display_name = "Siege Mode"
	siege.target_type = "self"
	siege.target_range = 0
	siege.cooldown_turns = 0
	siege.cast_time_turns = 1
	var sieged := StatusEffect.new()
	sieged.status_id = "sieged"
	sieged.duration_turns = StatusEffect.INDEFINITE
	sieged.blocks_move = true
	sieged.damage_override = 40
	sieged.attack_range_override = 6
	sieged.sprite_key = "siege_tank"
	var siege_effect := StatusApplyEffect.new()
	siege_effect.status = sieged
	siege.effect = siege_effect
	saved += int(_save(siege, "%s/abilities/siege_mode.tres" % DATA_ROOT))

	# Unsiege mode: clears the "sieged" status.
	var unsiege := AbilityDef.new()
	unsiege.id = "unsiege_mode"
	unsiege.display_name = "Unsiege Mode"
	unsiege.target_type = "self"
	unsiege.target_range = 0
	unsiege.cooldown_turns = 0
	unsiege.cast_time_turns = 1
	var unsiege_effect := StatusClearEffect.new()
	unsiege_effect.status_id = "sieged"
	unsiege.effect = unsiege_effect
	saved += int(_save(unsiege, "%s/abilities/unsiege_mode.tres" % DATA_ROOT))

	return saved


# ---------- Units ----------


func _gen_units() -> int:
	var saved := 0
	# Marine — light infantry, ground, can hit ground + flying.
	# Anti-air specialist: +50% vs "flying" (counter triangle: marine > heli).
	var marine := EntityDef.new()
	marine.id = "marine"
	marine.display_name = "Marine"
	marine.footprint = Vector2i(1, 1)
	marine.tags = ["light", "biological", "ground"]
	marine.health = _health(45)
	marine.combat = _combat(18, 3, ["ground", "flying"], [_modifier("flying", 150)])
	marine.movement = _movement(4, "ground")
	marine.vision = _vision(4)
	marine.population = _pop_cost(1)
	marine.construction = _construction(2, 100, 0, "barracks")
	saved += int(_save(marine, "%s/entities/units/marine.tres" % DATA_ROOT))

	# Tank — heavy ground, hit ground only, big damage at long range. Siege ability.
	var tank := EntityDef.new()
	tank.id = "tank"
	tank.display_name = "Tank"
	tank.footprint = Vector2i(2, 2)
	tank.tags = ["heavy", "mechanical", "ground"]
	tank.health = _health(175)
	tank.combat = _combat(30, 3, ["ground"], [])
	tank.movement = _movement(3, "ground")
	tank.vision = _vision(5)
	tank.population = _pop_cost(3)
	tank.construction = _construction(4, 150, 125, "factory")
	tank.abilities = _abilities([_ability_ref("siege_mode"), _ability_ref("unsiege_mode")])
	saved += int(_save(tank, "%s/entities/units/tank.tres" % DATA_ROOT))

	# Helicopter — flying, mid stats, hit ground + flying.
	# Tank hunter: +50% vs "heavy" (counter triangle: heli > tank).
	var heli := EntityDef.new()
	heli.id = "helicopter"
	heli.display_name = "Helicopter"
	heli.footprint = Vector2i(1, 1)
	heli.tags = ["light", "mechanical", "flying"]
	heli.health = _health(140)
	heli.combat = _combat(25, 3, ["ground", "flying"], [_modifier("heavy", 150)])
	heli.movement = _movement(5, "flying")
	heli.vision = _vision(4)
	heli.population = _pop_cost(3)
	heli.construction = _construction(4, 150, 100, "starport")
	saved += int(_save(heli, "%s/entities/units/helicopter.tres" % DATA_ROOT))

	# Worker — gathers, builds, weak combat.
	var worker := EntityDef.new()
	worker.id = "worker"
	worker.display_name = "Worker"
	worker.footprint = Vector2i(1, 1)
	worker.tags = ["worker", "light", "biological", "ground"]
	worker.health = _health(40)
	worker.combat = _combat(10, 2, ["ground"], [])
	worker.movement = _movement(2, "ground")
	worker.vision = _vision(4)
	worker.population = _pop_cost(1)
	worker.construction = _construction(2, 50, 0, "base")
	worker.gather = _gather(10, 50, ["minerals", "gas"])
	saved += int(_save(worker, "%s/entities/units/worker.tres" % DATA_ROOT))

	return saved


# ---------- Buildings ----------


func _gen_buildings() -> int:
	var saved := 0
	# Base — the home; provides population, trains workers.
	var base := EntityDef.new()
	base.id = "base"
	base.display_name = "Base"
	base.footprint = Vector2i(4, 4)
	base.tags = ["building", "base", "structure", "ground"]
	base.health = _health(1000)
	base.vision = _vision(5)
	base.population = _pop_provides(15)
	base.construction = _construction(5, 400, 0, "worker")
	var base_prod := ProductionDef.new()
	base_prod.produces = ["worker"]
	base_prod.queue_capacity = 1
	base_prod.rally_offset = Vector2i(0, 4)
	base.production = base_prod
	saved += int(_save(base, "%s/entities/buildings/base.tres" % DATA_ROOT))

	# Refinery — built on a gas geyser; lets workers extract gas.
	var refinery := EntityDef.new()
	refinery.id = "refinery"
	refinery.display_name = "Refinery"
	refinery.footprint = Vector2i(2, 2)
	refinery.tags = ["building", "refinery", "structure", "ground", "extractor"]
	refinery.health = _health(300)
	refinery.vision = _vision(4)
	var refinery_construction := _construction(3, 75, 0, "worker")
	refinery_construction.requires_target_tag = "gas_geyser"
	refinery.construction = refinery_construction
	saved += int(_save(refinery, "%s/entities/buildings/refinery.tres" % DATA_ROOT))

	# Barracks — trains marines.
	var barracks := EntityDef.new()
	barracks.id = "barracks"
	barracks.display_name = "Barracks"
	barracks.footprint = Vector2i(3, 3)
	barracks.tags = ["building", "barracks", "structure", "ground"]
	barracks.health = _health(600)
	barracks.vision = _vision(4)
	barracks.construction = _construction(3, 150, 0, "worker")
	var barracks_prod := ProductionDef.new()
	barracks_prod.produces = ["marine"]
	barracks_prod.queue_capacity = 1
	barracks_prod.rally_offset = Vector2i(0, 3)
	barracks.production = barracks_prod
	saved += int(_save(barracks, "%s/entities/buildings/barracks.tres" % DATA_ROOT))

	# Factory — trains tanks.
	var factory := EntityDef.new()
	factory.id = "factory"
	factory.display_name = "Factory"
	factory.footprint = Vector2i(3, 3)
	factory.tags = ["building", "factory", "structure", "ground"]
	factory.health = _health(800)
	factory.vision = _vision(4)
	factory.construction = _construction(4, 150, 100, "worker")
	var factory_prod := ProductionDef.new()
	factory_prod.produces = ["tank"]
	factory_prod.queue_capacity = 1
	factory_prod.rally_offset = Vector2i(0, 3)
	factory_prod.researches = ["siege_mode_research"]
	factory.production = factory_prod
	saved += int(_save(factory, "%s/entities/buildings/factory.tres" % DATA_ROOT))

	# Starport — trains helicopters.
	var starport := EntityDef.new()
	starport.id = "starport"
	starport.display_name = "Starport"
	starport.footprint = Vector2i(3, 3)
	starport.tags = ["building", "starport", "structure", "ground"]
	starport.health = _health(800)
	starport.vision = _vision(4)
	starport.construction = _construction(5, 150, 100, "worker")
	var starport_prod := ProductionDef.new()
	starport_prod.produces = ["helicopter"]
	starport_prod.queue_capacity = 1
	starport_prod.rally_offset = Vector2i(0, 3)
	starport.production = starport_prod
	saved += int(_save(starport, "%s/entities/buildings/starport.tres" % DATA_ROOT))

	return saved


# ---------- Neutrals ----------


func _gen_neutrals() -> int:
	var saved := 0
	# Mineral patch — passive resource source, no extractor needed.
	var patch := EntityDef.new()
	patch.id = "mineral_patch"
	patch.display_name = "Mineral Patch"
	patch.footprint = Vector2i(1, 1)
	patch.tags = ["neutral", "resource_source", "minerals"]
	var patch_source := ResourceSourceDef.new()
	patch_source.resource_type = "minerals"
	patch_source.yield_per_worker_per_turn = 1
	patch_source.capacity = 1500
	patch_source.requires_extractor = false
	patch_source.max_gatherers = 2
	patch.resource_source = patch_source
	saved += int(_save(patch, "%s/entities/neutrals/mineral_patch.tres" % DATA_ROOT))

	# Golden mineral patch — same shape as mineral_patch but with a higher
	# capacity (60% boost, matching SC2 gold:standard ratio). Used as a
	# contested neutral objective on mvp_map.
	var gold_patch := EntityDef.new()
	gold_patch.id = "mineral_patch_gold"
	gold_patch.display_name = "Golden Mineral Patch"
	gold_patch.footprint = Vector2i(1, 1)
	gold_patch.tags = ["neutral", "resource_source", "minerals", "golden"]
	var gold_patch_source := ResourceSourceDef.new()
	gold_patch_source.resource_type = "minerals"
	gold_patch_source.yield_per_worker_per_turn = 2
	gold_patch_source.capacity = 2400
	gold_patch_source.requires_extractor = false
	gold_patch_source.max_gatherers = 2
	gold_patch.resource_source = gold_patch_source
	saved += int(_save(gold_patch, "%s/entities/neutrals/mineral_patch_gold.tres" % DATA_ROOT))

	# Gas geyser — needs a refinery to extract.
	var geyser := EntityDef.new()
	geyser.id = "gas_geyser"
	geyser.display_name = "Gas Geyser"
	geyser.footprint = Vector2i(2, 2)
	geyser.tags = ["neutral", "resource_source", "gas", "gas_geyser"]
	var geyser_source := ResourceSourceDef.new()
	geyser_source.resource_type = "gas"
	geyser_source.yield_per_worker_per_turn = 1
	geyser_source.capacity = -1
	geyser_source.requires_extractor = true
	geyser_source.max_gatherers = 3
	geyser.resource_source = geyser_source
	saved += int(_save(geyser, "%s/entities/neutrals/gas_geyser.tres" % DATA_ROOT))

	return saved


# ---------- Tunables ----------


func _gen_tunables() -> int:
	var t := Tunables.new()
	t.map_width = 50
	t.map_height = 50
	t.tile_pixel_size = 32
	t.pop_cap = 50
	t.starting_workers = 4
	t.starting_minerals = 50
	t.starting_gas = 0
	t.default_turn_timer_ms = 30000
	t.mineral_patch_yield_per_worker_per_turn = 1
	t.mineral_patch_capacity = 1500
	t.gas_geyser_yield_per_worker_per_turn = 1
	t.gas_geyser_capacity = -1
	t.worker_carry_amount = 5
	t.layers_implying_hidden = ["burrowed"]
	return int(_save(t, "%s/tunables.tres" % DATA_ROOT))


# ---------- Registry ----------


func _gen_registry() -> int:
	var registry := EntityRegistry.new()
	var entity_paths := [
		"%s/entities/units/marine.tres" % DATA_ROOT,
		"%s/entities/units/tank.tres" % DATA_ROOT,
		"%s/entities/units/helicopter.tres" % DATA_ROOT,
		"%s/entities/units/worker.tres" % DATA_ROOT,
		"%s/entities/buildings/base.tres" % DATA_ROOT,
		"%s/entities/buildings/refinery.tres" % DATA_ROOT,
		"%s/entities/buildings/barracks.tres" % DATA_ROOT,
		"%s/entities/buildings/factory.tres" % DATA_ROOT,
		"%s/entities/buildings/starport.tres" % DATA_ROOT,
		"%s/entities/neutrals/mineral_patch.tres" % DATA_ROOT,
		"%s/entities/neutrals/mineral_patch_gold.tres" % DATA_ROOT,
		"%s/entities/neutrals/gas_geyser.tres" % DATA_ROOT,
	]
	var research_paths := [
		"%s/researches/siege_mode_research.tres" % DATA_ROOT,
	]
	var entities: Array[EntityDef] = []
	var researches: Array[ResearchDef] = []
	var missing_any := false
	for path in entity_paths:
		var def: EntityDef = load(path)
		if def != null:
			entities.append(def)
		else:
			push_error("Could not load %s for registry" % path)
			missing_any = true
	for path in research_paths:
		var research: ResearchDef = load(path)
		if research != null:
			researches.append(research)
		else:
			push_error("Could not load %s for registry" % path)
			missing_any = true
	if missing_any:
		# Refuse to save a truncated registry — silent partial state would
		# surface later as resolver lookup failures, much harder to debug.
		push_error("EntityRegistry generation aborted due to missing entity definitions.")
		return 0
	registry.entities = entities
	registry.researches = researches
	return int(_save(registry, "%s/entity_registry.tres" % DATA_ROOT))


# ---------- Helpers ----------


func _save(res: Resource, path: String) -> bool:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("Failed to save %s (error %d)" % [path, err])
		return false
	print("  saved %s" % path)
	return true


func _health(max_hp: int) -> HealthDef:
	var h := HealthDef.new()
	h.max_hp = max_hp
	return h


func _combat(
	damage: int, range_tiles: int, target_layers: Array[String], modifiers: Array[AttackModifier]
) -> CombatDef:
	var c := CombatDef.new()
	c.damage = damage
	c.attack_range = range_tiles
	c.target_layers = target_layers
	c.attack_modifiers = modifiers
	return c


func _modifier(target_tag: String, damage_mult_pct: int) -> AttackModifier:
	var m := AttackModifier.new()
	m.target_tag = target_tag
	m.damage_mult_pct = damage_mult_pct
	return m


func _movement(speed: int, layer: String) -> MovementDef:
	var m := MovementDef.new()
	m.speed_tiles_per_turn = speed
	m.default_layer = layer
	if layer == "ground":
		# Cliffs block ground movement (plan/m1/03); flying crosses freely.
		m.impassable_terrain_tags = ["cliff"]
	return m


func _vision(sight: int) -> VisionDef:
	var v := VisionDef.new()
	v.sight_radius = sight
	v.detection_radius = 0
	return v


func _pop_cost(cost: int) -> PopulationDef:
	var p := PopulationDef.new()
	p.pop_cost = cost
	p.pop_provides = 0
	return p


func _pop_provides(provides: int) -> PopulationDef:
	var p := PopulationDef.new()
	p.pop_cost = 0
	p.pop_provides = provides
	return p


func _construction(turns: int, minerals: int, gas: int, built_by: String) -> ConstructionDef:
	var c := ConstructionDef.new()
	c.build_time_turns = turns
	c.mineral_cost = minerals
	c.gas_cost = gas
	c.built_by_tag = built_by
	return c


func _gather(per_turn: int, carry: int, types: Array[String]) -> GatherDef:
	var g := GatherDef.new()
	g.gather_per_turn = per_turn
	g.carry_amount = carry
	g.accepts_resource_types = types
	return g


func _abilities(refs: Array[AbilityDef]) -> AbilitiesDef:
	# Defensive: drop any null entries so the saved AbilitiesDef never carries
	# a null. _ability_ref already guarantees non-null on success, but if the
	# caller composes refs from another source we want a second safety net.
	var clean: Array[AbilityDef] = []
	for r in refs:
		if r != null:
			clean.append(r)
	var a := AbilitiesDef.new()
	a.abilities = clean
	return a


func _ability_ref(id: String) -> AbilityDef:
	# Generator order matters: abilities are saved before entities, so the
	# .tres files for siege_mode / unsiege_mode exist by the time we
	# build units. If load() ever returns null it's a bug in the generator's
	# ordering — fail loud and substitute a default-constructed placeholder
	# so the rest of the run continues and we don't propagate null into
	# AbilitiesDef.abilities[].
	var path := "%s/abilities/%s.tres" % [DATA_ROOT, id]
	var ability: AbilityDef = load(path)
	if ability == null:
		push_error("Could not load ability '%s'; using placeholder" % path)
		ability = AbilityDef.new()
		ability.id = id
		ability.display_name = id
	return ability
