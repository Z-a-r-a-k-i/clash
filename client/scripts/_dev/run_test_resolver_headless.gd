extends SceneTree

const TEST_SCRIPT := "res://scripts/_dev/test_resolver.gd"


func _init() -> void:
	var script := load(TEST_SCRIPT)
	if script == null:
		push_error("[test_resolver_headless] could not load %s" % TEST_SCRIPT)
		quit(1)
		return

	var selected := _selected_tests()
	var runner := Node.new()
	runner.set_script(script)

	var passed := 0
	var failed := 0
	var skipped := 0
	var fail_names: Array[String] = []

	for test_pair in runner._all_tests():
		var test_name: String = test_pair[0]
		if not selected.is_empty() and not selected.has(test_name):
			skipped += 1
			continue
		var fn: Callable = test_pair[1]
		var ok: bool = fn.call()
		if ok:
			passed += 1
		else:
			failed += 1
			fail_names.append(test_name)

	print("[test_resolver_headless] %d passed, %d failed, %d skipped" % [passed, failed, skipped])
	for test_name in fail_names:
		push_error("  failed: %s" % test_name)
	quit(0 if failed == 0 else 1)


func _selected_tests() -> Array[String]:
	var selected: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if arg == "":
			continue
		selected.append(arg)
	return selected
