class_name SimulationRunner
extends RefCounted

# AI-vs-AI batch simulation core (plan m1/02). Pure logic so tests can
# drive it in-process; run_simulation.gd is the CLI wrapper. Matches are
# deterministic for a given seed: the AI itself is seedless-pure, so
# per-match variation comes from side swaps and a seed-derived jitter of
# the attack threshold applied here in the runner.

const STRATEGY_DIR := "res://data/ai"
const STALL_QUIET_TURNS := 15

const _REGISTRY := preload("res://data/entity_registry.tres")
const _TUNABLES := preload("res://data/tunables.tres")

# Strategy-tuning search space (see "Strategy tuning" section below).
const TUNABLE_PARAMS := [
	"attack_army_value",
	"worker_margin",
	"expand_mineral_buffer",
	"staging_advance_tiles",
	"scout_turn",
]
const _PARAM_STEPS := {
	"attack_army_value": 150,
	"worker_margin": 1,
	"expand_mineral_buffer": 100,
	"staging_advance_tiles": 2,
	"scout_turn": 2,
}
const _PARAM_MIN := {
	"attack_army_value": 200,
	"worker_margin": 0,
	"expand_mineral_buffer": 0,
	"staging_advance_tiles": 2,
	"scout_turn": 1,
}
const _PARAM_MAX := {
	"attack_army_value": 3000,
	"worker_margin": 5,
	"expand_mineral_buffer": 600,
	"staging_advance_tiles": 16,
	"scout_turn": 16,
}


static func strategy_path(name: String) -> String:
	return "%s/%s.tres" % [STRATEGY_DIR, name]


# Runs one match; returns {"row": Dictionary, "timeseries": Array of
# Dictionary, "replay": MatchReplay}.
static func run_match(
	scenario_path: String, strategy_a: String, strategy_b: String, seed_value: int, max_turns: int
) -> Dictionary:
	var registry: EntityRegistry = _REGISTRY
	var tunables: Tunables = _TUNABLES
	var scenario: ScenarioDef = load(scenario_path)
	var loaded := ScenarioLoader.load(scenario, registry, tunables)
	var state: MatchState = loaded.state

	var config_a := _variant_config(strategy_a, seed_value)
	var config_b := _variant_config(strategy_b, seed_value + 1)
	var memory_a := AiMemory.new()
	var memory_b := AiMemory.new()

	var replay := MatchReplay.new()
	replay.initial_session = SavedSession.new()
	replay.initial_session.state = state.clone()
	replay.initial_session.registry = registry
	replay.frames = []

	var row: Dictionary = {
		"strategy_a": strategy_a,
		"strategy_b": strategy_b,
		"seed": seed_value,
		"winner": -1,
		"end_turn": 0,
		"end_reason": "turn_cap",
		"first_attack_turn": -1,
		"first_base_kill_turn": -1,
		"max_army_turn_a": -1,
		"max_army_turn_b": -1,
		"units_lost_a": 0,
		"units_lost_b": 0,
		"avg_resolve_ms": 0.0,
	}
	var first_production: Dictionary = {}
	var timeseries: Array = []
	var quiet_turns := 0
	var resolve_usec_total := 0

	for turn in range(max_turns):
		var submit_a := AiPlayer.plan_turn(state, 0, registry, tunables, config_a, memory_a)
		var submit_b := AiPlayer.plan_turn(state, 1, registry, tunables, config_b, memory_b)
		var frame := ReplayTurnFrame.new()
		frame.turn_index = state.turn_index
		frame.submit_a = submit_a
		frame.submit_b = submit_b
		replay.frames.append(frame)

		var pre_state := state
		var resolve_start := Time.get_ticks_usec()
		var result := Resolver.resolve(state, submit_a, submit_b, registry, tunables)
		resolve_usec_total += Time.get_ticks_usec() - resolve_start
		state = result.new_state

		_record_events(result.events, pre_state, registry, row, first_production, turn)
		timeseries.append(_sample_turn(state, registry, strategy_a, strategy_b, seed_value, turn))
		for player_id in [0, 1]:
			var key := "max_army_turn_a" if player_id == 0 else "max_army_turn_b"
			var player := state.get_player(player_id)
			if int(row[key]) < 0 and player != null and player.pop_used >= player.pop_cap:
				row[key] = turn

		quiet_turns = quiet_turns + 1 if result.events.is_empty() else 0
		row["end_turn"] = turn
		if quiet_turns >= STALL_QUIET_TURNS:
			row["end_reason"] = "stall"
			break
		if state.match_over:
			row["winner"] = state.winner_player_id
			row["end_reason"] = "raze"
			break
	row["avg_resolve_ms"] = (float(resolve_usec_total) / 1000.0 / float(int(row["end_turn"]) + 1))
	for key in first_production:
		row[key] = first_production[key]
	return {"row": row, "timeseries": timeseries, "replay": replay}


# Runs a batch of matches for one pairing; sides swap on odd matches so
# the deterministic AI still produces a distribution.
static func run_pairing(
	scenario_path: String,
	strategy_a: String,
	strategy_b: String,
	matches: int,
	max_turns: int,
	seed_base: int
) -> Dictionary:
	var rows: Array = []
	var timeseries: Array = []
	var first_loss_replay: MatchReplay = null
	for index in range(matches):
		var swapped := index % 2 == 1
		var first := strategy_b if swapped else strategy_a
		var second := strategy_a if swapped else strategy_b
		var outcome := run_match(scenario_path, first, second, seed_base + index * 17, max_turns)
		var row: Dictionary = outcome["row"]
		row["match_index"] = index
		row["sides_swapped"] = swapped
		# Normalize the winner back into A-perspective for the matrix.
		var winner: int = int(row["winner"])
		if winner >= 0:
			row["winner_strategy"] = second if (winner == 1) != swapped else first
			if swapped and winner >= 0:
				row["winner"] = 1 - winner
		else:
			row["winner_strategy"] = ""
		if first_loss_replay == null and row["winner_strategy"] == strategy_b:
			first_loss_replay = outcome["replay"]
		rows.append(row)
		timeseries.append_array(outcome["timeseries"])
	return {"rows": rows, "timeseries": timeseries, "first_loss_replay": first_loss_replay}


static func matches_csv(rows: Array, include_timing: bool = true) -> String:
	# include_timing=false drops the wall-clock column so seeded runs
	# can be byte-compared.
	var columns := [
		"strategy_a",
		"strategy_b",
		"match_index",
		"sides_swapped",
		"seed",
		"winner",
		"winner_strategy",
		"end_turn",
		"end_reason",
		"first_attack_turn",
		"first_base_kill_turn",
		"first_barracks_turn",
		"first_factory_turn",
		"first_starport_turn",
		"max_army_turn_a",
		"max_army_turn_b",
		"units_lost_a",
		"units_lost_b",
	]
	if include_timing:
		columns.append("avg_resolve_ms")
	var lines: Array[String] = [",".join(columns)]
	for row in rows:
		var cells: Array[String] = []
		for column in columns:
			cells.append(str(row.get(column, "")))
		lines.append(",".join(cells))
	return "\n".join(lines) + "\n"


static func timeseries_csv(samples: Array) -> String:
	var columns := [
		"strategy_a",
		"strategy_b",
		"seed",
		"turn",
		"minerals_0",
		"gas_0",
		"income_0",
		"workers_0",
		"bases_0",
		"pop_0",
		"army_value_0",
		"minerals_1",
		"gas_1",
		"income_1",
		"workers_1",
		"bases_1",
		"pop_1",
		"army_value_1",
	]
	var lines: Array[String] = [",".join(columns)]
	for sample in samples:
		var cells: Array[String] = []
		for column in columns:
			cells.append(str(sample.get(column, "")))
		lines.append(",".join(cells))
	return "\n".join(lines) + "\n"


static func matrix_csv(rows_by_pairing: Dictionary) -> String:
	var lines: Array[String] = ["strategy_a,strategy_b,matches,a_wins,b_wins,draws,a_win_pct"]
	for pairing in rows_by_pairing:
		var rows: Array = rows_by_pairing[pairing]
		var a_wins := 0
		var b_wins := 0
		var draws := 0
		var strategy_a := ""
		var strategy_b := ""
		for row in rows:
			strategy_a = row["strategy_a"] if not bool(row["sides_swapped"]) else row["strategy_b"]
			strategy_b = row["strategy_b"] if not bool(row["sides_swapped"]) else row["strategy_a"]
			var winner_strategy: String = row.get("winner_strategy", "")
			if winner_strategy == "":
				draws += 1
			elif winner_strategy == strategy_a:
				a_wins += 1
			else:
				b_wins += 1
		var total: int = rows.size()
		var pct: float = 100.0 * float(a_wins) / float(maxi(total, 1))
		lines.append(
			"%s,%s,%d,%d,%d,%d,%.1f" % [strategy_a, strategy_b, total, a_wins, b_wins, draws, pct]
		)
	return "\n".join(lines) + "\n"


# ---------- Strategy tuning (self-play learning) ----------
# Deterministic hill-climb over a strategy's numeric parameters,
# evaluated by win rate against an opponent pool. "Learning" here is
# evolutionary self-play: mutate the champion, keep whichever wins
# more. Seeded RNG only (reproducible runs).


static func tune_strategy(
	scenario_path: String,
	strategy: String,
	opponents: Array,
	generations: int,
	matches_per_eval: int,
	max_turns: int,
	seed_value: int
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var champion: AiConfig = (load(strategy_path(strategy)) as AiConfig).duplicate(true)
	var champion_score := _evaluate_config(
		scenario_path, champion, opponents, matches_per_eval, max_turns, seed_value
	)
	var history: Array = [
		{"generation": 0, "win_pct": champion_score, "params": _params_of(champion)}
	]
	for generation in range(1, generations + 1):
		var challenger: AiConfig = champion.duplicate(true)
		# Mutate 1-2 parameters by one step in a random direction.
		var mutations := 1 + (rng.randi() % 2)
		for m in range(mutations):
			var param: String = TUNABLE_PARAMS[rng.randi() % TUNABLE_PARAMS.size()]
			var step: int = int(_PARAM_STEPS[param]) * (1 if rng.randi() % 2 == 0 else -1)
			var value: int = int(challenger.get(param)) + step
			challenger.set(param, clampi(value, int(_PARAM_MIN[param]), int(_PARAM_MAX[param])))
		var challenger_score := _evaluate_config(
			scenario_path,
			challenger,
			opponents,
			matches_per_eval,
			max_turns,
			seed_value + generation * 101
		)
		if challenger_score > champion_score:
			champion = challenger
			champion_score = challenger_score
		(
			history
			. append(
				{
					"generation": generation,
					"win_pct": champion_score,
					"challenger_pct": challenger_score,
					"params": _params_of(champion),
				}
			)
		)
	return {"config": champion, "win_pct": champion_score, "history": history}


static func tuning_csv(history: Array) -> String:
	var lines: Array[String] = ["generation,win_pct,challenger_pct," + ",".join(TUNABLE_PARAMS)]
	for entry in history:
		var cells: Array[String] = [
			str(entry["generation"]),
			str(entry["win_pct"]),
			str(entry.get("challenger_pct", "")),
		]
		var params: Dictionary = entry["params"]
		for param in TUNABLE_PARAMS:
			cells.append(str(params.get(param, "")))
		lines.append(",".join(cells))
	return "\n".join(lines) + "\n"


static func _params_of(config: AiConfig) -> Dictionary:
	var out: Dictionary = {}
	for param in TUNABLE_PARAMS:
		out[param] = config.get(param)
	return out


# Win percentage of `config` across the opponent pool, alternating
# sides each match.
static func _evaluate_config(
	scenario_path: String,
	config: AiConfig,
	opponents: Array,
	matches_per_eval: int,
	max_turns: int,
	_seed_value: int
) -> float:
	var registry: EntityRegistry = _REGISTRY
	var tunables: Tunables = _TUNABLES
	var wins := 0
	var total := 0
	for opponent_name in opponents:
		var opponent: AiConfig = load(strategy_path(str(opponent_name))) as AiConfig
		for index in range(matches_per_eval):
			var swapped := index % 2 == 1
			var scenario: ScenarioDef = load(scenario_path)
			var state: MatchState = ScenarioLoader.load(scenario, registry, tunables).state
			var memory_a := AiMemory.new()
			var memory_b := AiMemory.new()
			var config_a: AiConfig = opponent if swapped else config
			var config_b: AiConfig = config if swapped else opponent
			var quiet := 0
			for turn in range(max_turns):
				var submit_a := AiPlayer.plan_turn(state, 0, registry, tunables, config_a, memory_a)
				var submit_b := AiPlayer.plan_turn(state, 1, registry, tunables, config_b, memory_b)
				var result := Resolver.resolve(state, submit_a, submit_b, registry, tunables)
				state = result.new_state
				quiet = quiet + 1 if result.events.is_empty() else 0
				if quiet >= STALL_QUIET_TURNS or state.match_over:
					break
			total += 1
			var config_player := 1 if swapped else 0
			if state.match_over:
				if state.winner_player_id == config_player:
					wins += 100
			else:
				# Turn-cap draw: score dominance so the tuner still gets
				# a gradient (50 = even, +/-40 swing from army value and
				# base advantage at the end state).
				wins += _dominance_score(state, registry, config_player)
	if total == 0:
		return 0.0
	return float(wins) / float(total)


# 10..90 score for `player_id`'s position in a drawn end state.
static func _dominance_score(state: MatchState, registry: EntityRegistry, player_id: int) -> int:
	var own_value := 0
	var enemy_value := 0
	var own_bases := 0
	var enemy_bases := 0
	for entity in state.entities_sorted_by_id():
		if entity.owner_player_id < 0 or entity.current_hp <= 0:
			continue
		var def: EntityDef = registry.get_by_id(entity.current_def_id)
		if def == null:
			continue
		var mine := entity.owner_player_id == player_id
		if def.combat != null and def.movement != null and def.construction != null:
			var value := def.construction.mineral_cost + def.construction.gas_cost
			if mine:
				own_value += value
			else:
				enemy_value += value
		if def.id == "base" and not entity.is_constructing:
			if mine:
				own_bases += 1
			else:
				enemy_bases += 1
	var score := 50
	score += clampi((own_value - enemy_value) / 100, -30, 30)
	score += clampi((own_bases - enemy_bases) * 5, -10, 10)
	return clampi(score, 10, 90)


# ---------- Internals ----------


static func _variant_config(strategy: String, seed_value: int) -> AiConfig:
	var base: AiConfig = load(strategy_path(strategy)) as AiConfig
	var config: AiConfig = base.duplicate(true)
	# Seed-derived jitter (+/-10%) so deterministic AIs still explore a
	# spread of timings across a batch.
	var jitter_pct: int = 90 + (absi(seed_value) * 7) % 21
	config.attack_army_value = maxi(100, config.attack_army_value * jitter_pct / 100)
	config.seed = seed_value
	return config


static func _record_events(
	events: Array[ResolverEvent],
	pre_state: MatchState,
	registry: EntityRegistry,
	row: Dictionary,
	first_production: Dictionary,
	turn: int
) -> void:
	for event in events:
		match event.type:
			ResolverEvent.Type.ENTITY_DAMAGED:
				if int(row["first_attack_turn"]) < 0:
					row["first_attack_turn"] = turn
			ResolverEvent.Type.ENTITY_DESTROYED:
				var dead := pre_state.get_entity_by_id(event.target_id)
				if dead == null:
					continue
				var def: EntityDef = registry.get_by_id(dead.current_def_id)
				if def == null:
					continue
				if def.id == "base" and int(row["first_base_kill_turn"]) < 0:
					row["first_base_kill_turn"] = turn
				if def.movement != null:
					var key := "units_lost_a" if dead.owner_player_id == 0 else "units_lost_b"
					row[key] = int(row[key]) + 1
			ResolverEvent.Type.BUILD_COMPLETED:
				var landmark := "first_%s_turn" % event.def_id
				if (
					["barracks", "factory", "starport"].has(event.def_id)
					and not first_production.has(landmark)
				):
					first_production[landmark] = turn


static func _sample_turn(
	state: MatchState,
	registry: EntityRegistry,
	strategy_a: String,
	strategy_b: String,
	seed_value: int,
	turn: int
) -> Dictionary:
	var sample: Dictionary = {
		"strategy_a": strategy_a,
		"strategy_b": strategy_b,
		"seed": seed_value,
		"turn": turn,
	}
	var income: Dictionary = {0: 0, 1: 0}
	var workers: Dictionary = {0: 0, 1: 0}
	var bases: Dictionary = {0: 0, 1: 0}
	var army_value: Dictionary = {0: 0, 1: 0}
	for entity in state.entities_sorted_by_id():
		var owner := entity.owner_player_id
		if owner != 0 and owner != 1:
			continue
		if entity.current_hp <= 0:
			continue
		var def: EntityDef = registry.get_by_id(entity.current_def_id)
		if def == null:
			continue
		if def.id == "worker":
			workers[owner] = int(workers[owner]) + 1
		elif def.id == "base" and not entity.is_constructing:
			bases[owner] = int(bases[owner]) + 1
		if def.combat != null and def.construction != null and def.movement != null:
			army_value[owner] = (
				int(army_value[owner]) + def.construction.mineral_cost + def.construction.gas_cost
			)
		if (
			def.id == "worker"
			and entity.gather_state != null
			and entity.gather_state.phase == GatherState.Phase.GATHERING
		):
			income[owner] = int(income[owner]) + 2
	for player_id in [0, 1]:
		var player := state.get_player(player_id)
		sample["minerals_%d" % player_id] = player.minerals if player != null else 0
		sample["gas_%d" % player_id] = player.gas if player != null else 0
		sample["income_%d" % player_id] = income[player_id]
		sample["workers_%d" % player_id] = workers[player_id]
		sample["bases_%d" % player_id] = bases[player_id]
		sample["pop_%d" % player_id] = player.pop_used if player != null else 0
		sample["army_value_%d" % player_id] = army_value[player_id]
	return sample
