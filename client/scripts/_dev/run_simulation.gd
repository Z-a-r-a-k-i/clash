extends SceneTree

# AI-vs-AI simulation CLI (plan m1/02). Examples:
#   godot --headless --path client --script scripts/_dev/run_simulation.gd \
#     -- --matrix --matches 20 --seed 1 --out sim_baseline
#   godot ... -- --a rush_marines --b two_base_tanks --matches 6
#   godot ... -- --tune rush_marines --generations 12 --matches 4
# CSVs land in the repo's gitignored logs/<out>/ directory.

const STRATEGIES := ["rush_marines", "two_base_tanks", "heli_harass"]
const DEFAULT_SCENARIO := "res://data/scenarios/arena_1v1.tres"


func _init() -> void:
	var args: Dictionary = _parse_args(OS.get_cmdline_user_args())
	var scenario: String = str(args.get("scenario", DEFAULT_SCENARIO))
	if not _is_valid_scenario(scenario):
		quit(1)
		return
	var matches: int = int(args.get("matches", "20"))
	var max_turns: int = int(args.get("max-turns", "150"))
	if not _is_positive_arg(matches, "--matches") or not _is_positive_arg(max_turns, "--max-turns"):
		quit(1)
		return
	var seed_base: int = int(args.get("seed", "1"))
	var out_name: String = args.get("out", "sim")
	var dump_replays: String = args.get("dump-replays", "none")

	if args.has("tune"):
		quit(0 if _run_tuning(args, scenario, max_turns, seed_base, out_name) else 1)
		return

	var pairings: Array = []
	if args.has("matrix"):
		for a in STRATEGIES:
			for b in STRATEGIES:
				pairings.append([a, b])
	else:
		var strategy_a: String = _validated_strategy(str(args.get("a", "rush_marines")), "--a")
		var strategy_b: String = _validated_strategy(str(args.get("b", "rush_marines")), "--b")
		if strategy_a == "" or strategy_b == "":
			quit(1)
			return
		pairings.append([strategy_a, strategy_b])

	var out_dir: String = ProjectSettings.globalize_path("res://../logs/%s" % out_name)
	var mkdir_error: int = DirAccess.make_dir_recursive_absolute(out_dir)
	if mkdir_error != OK:
		push_error("[simulate] cannot create %s: %s" % [out_dir, error_string(mkdir_error)])
		quit(1)
		return

	var all_rows: Array = []
	var all_samples: Array = []
	var rows_by_pairing: Dictionary = {}
	var ok: bool = true
	for pairing in pairings:
		var a: String = pairing[0]
		var b: String = pairing[1]
		print("[simulate] %s vs %s (%d matches)" % [a, b, matches])
		var batch: Dictionary = SimulationRunner.run_pairing(
			scenario, a, b, matches, max_turns, seed_base
		)
		all_rows.append_array(batch["rows"])
		all_samples.append_array(batch["timeseries"])
		rows_by_pairing["%s|%s" % [a, b]] = batch["rows"]
		if dump_replays == "first_loss" and batch["first_loss_replay"] != null:
			var replay_path: String = "%s/first_loss_%s_vs_%s.tres" % [out_dir, a, b]
			var first_loss_replay: MatchReplay = batch["first_loss_replay"]
			var save_error: int = ResourceSaver.save(first_loss_replay, replay_path)
			if save_error != OK:
				push_error(
					"[simulate] cannot save %s: %s" % [replay_path, error_string(save_error)]
				)
				ok = false
			else:
				print("[simulate]   first loss replay -> %s" % replay_path)

	ok = _write(out_dir + "/matches.csv", SimulationRunner.matches_csv(all_rows)) and ok
	ok = _write(out_dir + "/timeseries.csv", SimulationRunner.timeseries_csv(all_samples)) and ok
	if args.has("matrix"):
		var matrix: String = SimulationRunner.matrix_csv(rows_by_pairing)
		ok = _write(out_dir + "/matrix.csv", matrix) and ok
		print("[simulate] win-rate matrix:\n%s" % matrix)
	if ok:
		print("[simulate] wrote CSVs to %s" % out_dir)
	quit(0 if ok else 1)


# Self-play learning brief: evolve one strategy's parameters against
# the other shipped strategies and report/keep the champion.
func _run_tuning(
	args: Dictionary, scenario: String, max_turns: int, seed_base: int, out_name: String
) -> bool:
	var strategy: String = _validated_strategy(str(args.get("tune", "rush_marines")), "--tune")
	if strategy == "":
		return false
	var generations: int = int(args.get("generations", "10"))
	var matches_per_eval: int = int(args.get("matches", "4"))
	if (
		not _is_positive_arg(generations, "--generations")
		or not _is_positive_arg(matches_per_eval, "--matches")
	):
		return false
	var opponents: Array = []
	for name in STRATEGIES:
		if name != strategy or STRATEGIES.size() == 1:
			opponents.append(name)
	print(
		"[simulate] tuning %s over %d generations vs %s" % [strategy, generations, str(opponents)]
	)
	var out_dir: String = ProjectSettings.globalize_path("res://../logs/%s" % out_name)
	var mkdir_error: int = DirAccess.make_dir_recursive_absolute(out_dir)
	if mkdir_error != OK:
		push_error("[simulate] cannot create %s: %s" % [out_dir, error_string(mkdir_error)])
		return false
	var tuned: Dictionary = SimulationRunner.tune_strategy(
		scenario, strategy, opponents, generations, matches_per_eval, max_turns, seed_base
	)
	var ok: bool = _write(out_dir + "/tuning.csv", SimulationRunner.tuning_csv(tuned["history"]))
	var tuned_path: String = "%s/tuned_%s.tres" % [out_dir, strategy]
	var tuned_config: AiConfig = tuned["config"]
	var save_error: int = ResourceSaver.save(tuned_config, tuned_path)
	if save_error != OK:
		push_error("[simulate] cannot save %s: %s" % [tuned_path, error_string(save_error)])
		ok = false
	else:
		print("[simulate] tuned config -> %s" % tuned_path)
	print(
		(
			"[simulate] champion win rate %.1f%%; params %s"
			% [tuned["win_pct"], str(SimulationRunner._params_of(tuned["config"]))]
		)
	)
	return ok


func _parse_args(args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	var index: int = 0
	while index < args.size():
		var arg: String = args[index]
		if arg.begins_with("--"):
			var key: String = arg.trim_prefix("--")
			if key.contains("="):
				out[key.get_slice("=", 0)] = key.get_slice("=", 1)
			elif index + 1 < args.size() and not args[index + 1].begins_with("--"):
				out[key] = args[index + 1]
				index += 1
			else:
				out[key] = "true"
		index += 1
	return out


func _validated_strategy(raw_name: String, flag_name: String) -> String:
	var name: String = str(raw_name)
	if STRATEGIES.has(name):
		return name
	push_error(
		(
			"[simulate] unknown strategy for %s: %s (expected one of %s)"
			% [flag_name, name, ", ".join(STRATEGIES)]
		)
	)
	return ""


func _is_valid_scenario(path: String) -> bool:
	if not ResourceLoader.exists(path):
		push_error("[simulate] invalid --scenario: %s" % path)
		return false
	var scenario: ScenarioDef = load(path) as ScenarioDef
	if scenario == null:
		push_error("[simulate] --scenario is not a ScenarioDef: %s" % path)
		return false
	return true


func _is_positive_arg(value: int, flag_name: String) -> bool:
	if value > 0:
		return true
	push_error("[simulate] %s must be > 0, got %d" % [flag_name, value])
	return false


func _write(path: String, content: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error(
			"[simulate] cannot write %s: %s" % [path, error_string(FileAccess.get_open_error())]
		)
		return false
	file.store_string(content)
	var write_error: int = file.get_error()
	file.close()
	if write_error != OK:
		push_error("[simulate] cannot write %s: %s" % [path, error_string(write_error)])
		return false
	return true
