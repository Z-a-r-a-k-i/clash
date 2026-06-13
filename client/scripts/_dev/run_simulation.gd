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
	var args := _parse_args(OS.get_cmdline_user_args())
	var scenario: String = args.get("scenario", DEFAULT_SCENARIO)
	var matches: int = int(args.get("matches", "20"))
	var max_turns: int = int(args.get("max-turns", "150"))
	var seed_base: int = int(args.get("seed", "1"))
	var out_name: String = args.get("out", "sim")
	var dump_replays: String = args.get("dump-replays", "none")

	if args.has("tune"):
		_run_tuning(args, scenario, max_turns, seed_base, out_name)
		return

	var pairings: Array = []
	if args.has("matrix"):
		for a in STRATEGIES:
			for b in STRATEGIES:
				pairings.append([a, b])
	else:
		pairings.append([args.get("a", "rush_marines"), args.get("b", "rush_marines")])

	var out_dir := ProjectSettings.globalize_path("res://../logs/%s" % out_name)
	DirAccess.make_dir_recursive_absolute(out_dir)

	var all_rows: Array = []
	var all_samples: Array = []
	var rows_by_pairing: Dictionary = {}
	for pairing in pairings:
		var a: String = pairing[0]
		var b: String = pairing[1]
		print("[simulate] %s vs %s (%d matches)" % [a, b, matches])
		var batch := SimulationRunner.run_pairing(scenario, a, b, matches, max_turns, seed_base)
		all_rows.append_array(batch["rows"])
		all_samples.append_array(batch["timeseries"])
		rows_by_pairing["%s|%s" % [a, b]] = batch["rows"]
		if dump_replays == "first_loss" and batch["first_loss_replay"] != null:
			var replay_path := "%s/first_loss_%s_vs_%s.tres" % [out_dir, a, b]
			ResourceSaver.save(batch["first_loss_replay"], replay_path)
			print("[simulate]   first loss replay -> %s" % replay_path)

	_write(out_dir + "/matches.csv", SimulationRunner.matches_csv(all_rows))
	_write(out_dir + "/timeseries.csv", SimulationRunner.timeseries_csv(all_samples))
	if args.has("matrix"):
		var matrix := SimulationRunner.matrix_csv(rows_by_pairing)
		_write(out_dir + "/matrix.csv", matrix)
		print("[simulate] win-rate matrix:\n%s" % matrix)
	print("[simulate] wrote CSVs to %s" % out_dir)
	quit(0)


# Self-play learning brief: evolve one strategy's parameters against
# the other shipped strategies and report/keep the champion.
func _run_tuning(
	args: Dictionary, scenario: String, max_turns: int, seed_base: int, out_name: String
) -> void:
	var strategy: String = args.get("tune", "rush_marines")
	var generations: int = int(args.get("generations", "10"))
	var matches_per_eval: int = int(args.get("matches", "4"))
	var opponents: Array = []
	for name in STRATEGIES:
		if name != strategy or STRATEGIES.size() == 1:
			opponents.append(name)
	print(
		"[simulate] tuning %s over %d generations vs %s" % [strategy, generations, str(opponents)]
	)
	var out_dir := ProjectSettings.globalize_path("res://../logs/%s" % out_name)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var tuned := SimulationRunner.tune_strategy(
		scenario, strategy, opponents, generations, matches_per_eval, max_turns, seed_base
	)
	_write(out_dir + "/tuning.csv", SimulationRunner.tuning_csv(tuned["history"]))
	var tuned_path := "%s/tuned_%s.tres" % [out_dir, strategy]
	ResourceSaver.save(tuned["config"], tuned_path)
	print(
		(
			"[simulate] champion win rate %.1f%%; params %s"
			% [tuned["win_pct"], str(SimulationRunner._params_of(tuned["config"]))]
		)
	)
	print("[simulate] tuned config -> %s" % tuned_path)
	quit(0)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	var index := 0
	while index < args.size():
		var arg := args[index]
		if arg.begins_with("--"):
			var key := arg.trim_prefix("--")
			if key.contains("="):
				out[key.get_slice("=", 0)] = key.get_slice("=", 1)
			elif index + 1 < args.size() and not args[index + 1].begins_with("--"):
				out[key] = args[index + 1]
				index += 1
			else:
				out[key] = "true"
		index += 1
	return out


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[simulate] cannot write %s" % path)
		return
	file.store_string(content)
	file.close()
