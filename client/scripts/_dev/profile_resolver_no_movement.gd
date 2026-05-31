extends SceneTree

const STRESS_SCRIPT := "res://scripts/_dev/test_resolver_stress.gd"


func _init() -> void:
	var script: Script = load(STRESS_SCRIPT) as Script
	if script == null:
		push_error("[profile_resolver_no_movement] could not load %s" % STRESS_SCRIPT)
		quit(1)
		return

	var runner := Node.new()
	runner.set_script(script)
	root.add_child(runner)

	var success: bool = _run_idle_out_of_range(runner)
	if success:
		success = _run_idle_in_auto_attack_range(runner)
	if success:
		success = _run_attack_orders_only(runner)

	root.remove_child(runner)
	runner.queue_free()
	quit(0 if success else 1)


func _run_idle_out_of_range(runner: Node) -> bool:
	var fixture: Dictionary = runner._build_stress_fixture()
	var registry: EntityRegistry = fixture["registry"]
	var unit_def: EntityDef = registry.get_by_id("stress_unit")
	unit_def.combat.attack_range = 3
	return _run_case("idle_out_of_range", fixture["state"], SubmitTurn.new(), SubmitTurn.new(), registry)


func _run_idle_in_auto_attack_range(runner: Node) -> bool:
	var fixture: Dictionary = runner._build_stress_fixture()
	return _run_case(
		"idle_auto_attack_range",
		fixture["state"],
		SubmitTurn.new(),
		SubmitTurn.new(),
		fixture["registry"]
	)


func _run_attack_orders_only(runner: Node) -> bool:
	var fixture: Dictionary = runner._build_stress_fixture()
	var submit_a: SubmitTurn = _filter_attack_orders(fixture["submit_a"])
	var submit_b: SubmitTurn = _filter_attack_orders(fixture["submit_b"])
	return _run_case("attack_orders_only", fixture["state"], submit_a, submit_b, fixture["registry"])


func _run_case(
	label: String,
	state: MatchState,
	submit_a: SubmitTurn,
	submit_b: SubmitTurn,
	registry: EntityRegistry
) -> bool:
	print("[profile_resolver_no_movement] begin %s" % label)
	var start_usec := Time.get_ticks_usec()
	var result: ResolveResult = Resolver.resolve(state, submit_a, submit_b, registry, null)
	if result == null or result.new_state == null:
		push_error("[profile_resolver_no_movement] invalid resolve result for %s" % label)
		return false
	var elapsed_usec := Time.get_ticks_usec() - start_usec
	var event_count := result.events.size()
	print(
		(
			"[profile_resolver_no_movement] case=%s elapsed=%.3fms events=%d"
			% [label, float(elapsed_usec) / 1000.0, event_count]
		)
	)
	return true


func _filter_attack_orders(submit: SubmitTurn) -> SubmitTurn:
	var out := SubmitTurn.new()
	var orders: Array[EntityOrder] = []
	for order in submit.orders:
		if order != null and order.type == EntityOrder.Type.ATTACK:
			orders.append(order)
	out.orders = orders
	return out
