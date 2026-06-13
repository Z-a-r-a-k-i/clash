class_name HeadlessTestRunner
extends RefCounted


static func run(root: Window, test_script_path: String, label: String) -> int:
	var script: Script = load(test_script_path) as Script
	if script == null:
		push_error("[%s] could not load %s" % [label, test_script_path])
		return 1
	var runner: Node = Node.new()
	runner.set_script(script)
	root.add_child(runner)
	var passed: int = 0
	var failed: int = 0
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
	print("[%s] %d passed, %d failed" % [label, passed, failed])
	for test_name in fail_names:
		push_error("  failed: %s" % test_name)
	root.remove_child(runner)
	runner.queue_free()
	return 0 if failed == 0 else 1
