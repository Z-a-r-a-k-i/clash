extends SceneTree

const TEST_SCRIPT := "res://scripts/_dev/test_resolver_stress.gd"


func _init() -> void:
	var script: Script = load(TEST_SCRIPT) as Script
	if script == null:
		push_error("[test_resolver_stress_headless] could not load %s" % TEST_SCRIPT)
		quit(1)
		return

	var runner: Node = Node.new()
	runner.set_script(script)
	root.add_child(runner)

	var passed := 0
	var failed := 0
	var fail_names: Array[String] = []
	for test_pair in runner._all_tests():
		var test_name: String = test_pair[0]
		var fn: Callable = test_pair[1]
		var ok: bool = fn.call()
		if ok:
			passed += 1
		else:
			failed += 1
			fail_names.append(test_name)

	print("[test_resolver_stress_headless] %d passed, %d failed" % [passed, failed])
	for test_name in fail_names:
		push_error("  failed: %s" % test_name)
	root.remove_child(runner)
	runner.queue_free()
	quit(0 if failed == 0 else 1)
