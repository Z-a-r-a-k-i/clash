@tool
extends Node

# AI opponent test suite (plan m1/01). Mirrors the resolver suites'
# runner contract: _all_tests() -> Array of [name, Callable].

const RUSH_MARINES := preload("res://data/ai/rush_marines.tres")
const STRATEGY_PATHS := [
	"res://data/ai/rush_marines.tres",
	"res://data/ai/two_base_tanks.tres",
	"res://data/ai/heli_harass.tres",
]


func _all_tests() -> Array:
	return [
		["ai_strategy_configs_load", _test_strategy_configs_load],
		["ai_plan_turn_is_deterministic", _test_plan_turn_is_deterministic],
		["ai_beats_do_nothing_by_raze", _test_beats_do_nothing],
		["ai_vs_ai_completes_without_stall", _test_ai_vs_ai_completes],
		["ai_is_fog_honest", _test_fog_honest],
	]


func _load_match() -> Dictionary:
	var registry: EntityRegistry = load("res://data/entity_registry.tres")
	var tunables: Tunables = load("res://data/tunables.tres")
	var scenario: ScenarioDef = load("res://data/scenarios/arena_1v1.tres")
	var loaded: LoadedScenario = ScenarioLoader.load(scenario, registry, tunables)
	return {"state": loaded.state, "registry": registry, "tunables": tunables}


func _test_strategy_configs_load() -> bool:
	for path in STRATEGY_PATHS:
		var config: AiConfig = load(path) as AiConfig
		if config == null:
			push_error("strategy failed to load: %s" % path)
			return false
		if config.unit_mix.is_empty():
			push_error("strategy has an empty unit mix: %s" % path)
			return false
	return true


static func _serialize_orders(submit: SubmitTurn) -> String:
	var parts: Array[String] = []
	for order in submit.orders:
		(
			parts
			. append(
				(
					"%d:%d:%s:%s:%d:%s:%s"
					% [
						order.type,
						order.entity_id,
						str(order.target_tile),
						order.def_id,
						order.target_entity_id,
						order.mode,
						str(order.enabled),
					]
				)
			)
		)
	return "|".join(parts)


func _test_plan_turn_is_deterministic() -> bool:
	# Same (state, config, fresh memory) twice -> byte-identical orders,
	# including after a few resolved turns.
	var setup: Dictionary = _load_match()
	var config: AiConfig = RUSH_MARINES
	var state_a: MatchState = setup["state"]
	var state_b: MatchState = state_a.clone()
	var memory_a: AiMemory = AiMemory.new()
	var memory_b: AiMemory = AiMemory.new()
	for turn in range(6):
		var submit_a: SubmitTurn = AiPlayer.plan_turn(
			state_a, 0, setup["registry"], setup["tunables"], config, memory_a
		)
		var submit_b: SubmitTurn = AiPlayer.plan_turn(
			state_b, 0, setup["registry"], setup["tunables"], config, memory_b
		)
		if _serialize_orders(submit_a) != _serialize_orders(submit_b):
			push_error("plan_turn diverged on identical inputs at turn %d" % turn)
			return false
		state_a = (
			Resolver
			. resolve(state_a, submit_a, SubmitTurn.new(), setup["registry"], setup["tunables"])
			. new_state
		)
		state_b = (
			Resolver
			. resolve(state_b, submit_b, SubmitTurn.new(), setup["registry"], setup["tunables"])
			. new_state
		)
	return true


func _test_beats_do_nothing() -> bool:
	var setup: Dictionary = _load_match()
	var config: AiConfig = RUSH_MARINES
	var state: MatchState = setup["state"]
	var memory: AiMemory = AiMemory.new()
	for turn in range(60):
		var submit: SubmitTurn = AiPlayer.plan_turn(
			state, 0, setup["registry"], setup["tunables"], config, memory
		)
		state = (
			Resolver
			. resolve(state, submit, SubmitTurn.new(), setup["registry"], setup["tunables"])
			. new_state
		)
		if state.match_over:
			if state.winner_player_id != 0:
				push_error("AI lost to a do-nothing opponent")
				return false
			return true
	push_error("AI failed to raze a do-nothing opponent within 60 turns")
	return false


func _test_ai_vs_ai_completes() -> bool:
	var setup: Dictionary = _load_match()
	var config_a: AiConfig = RUSH_MARINES
	var config_b: AiConfig = RUSH_MARINES
	var state: MatchState = setup["state"]
	var memory_a: AiMemory = AiMemory.new()
	var memory_b: AiMemory = AiMemory.new()
	var quiet_turns: int = 0
	for turn in range(150):
		var submit_a: SubmitTurn = AiPlayer.plan_turn(
			state, 0, setup["registry"], setup["tunables"], config_a, memory_a
		)
		var submit_b: SubmitTurn = AiPlayer.plan_turn(
			state, 1, setup["registry"], setup["tunables"], config_b, memory_b
		)
		var result: ResolveResult = Resolver.resolve(
			state, submit_a, submit_b, setup["registry"], setup["tunables"]
		)
		state = result.new_state
		quiet_turns = quiet_turns + 1 if result.events.is_empty() else 0
		if quiet_turns >= 15:
			push_error("AI vs AI stalled: 15 consecutive turns without any event")
			return false
		if state.match_over:
			return true
	# A 150-turn mirror draw is acceptable; a stall is not.
	return true


func _test_fog_honest() -> bool:
	# An enemy the AI has never seen must not appear in its memory nor
	# be targeted. Enemy marine far outside every friendly sight circle.
	var setup: Dictionary = _load_match()
	var registry: EntityRegistry = setup["registry"]
	var state: MatchState = setup["state"]
	var hidden: Entity = Entity.new()
	hidden.id = state.allocate_entity_id()
	hidden.def_id = "marine"
	hidden.current_def_id = "marine"
	hidden.owner_player_id = 1
	hidden.origin = Vector2i(32, 55)
	hidden.current_hp = 45
	hidden.current_layer = "ground"
	state.tile_grid.place(hidden.id, Rect2i(hidden.origin, Vector2i.ONE))
	state.entities.append(hidden)
	var config: AiConfig = RUSH_MARINES
	var memory: AiMemory = AiMemory.new()
	var submit: SubmitTurn = AiPlayer.plan_turn(
		state, 0, registry, setup["tunables"], config, memory
	)
	if memory.enemy_last_seen.has(hidden.id):
		push_error("AI memorized an enemy it cannot see")
		return false
	for order in submit.orders:
		if order.target_entity_id == hidden.id and order.type == EntityOrder.Type.TARGET:
			push_error("AI targeted an enemy it cannot see")
			return false
	return true
