extends SceneTree

const TEST_SCRIPT := "res://scripts/_dev/test_network_live.gd"

var _runner: Node = null


func _init() -> void:
	var script: Script = load(TEST_SCRIPT) as Script
	if script == null:
		push_error("[test_network_live_headless] could not load %s" % TEST_SCRIPT)
		quit(1)
		return
	_runner = Node.new()
	_runner.set_script(script)
	if not _runner.has_method("_run_all_async") or not _runner.has_signal("finished"):
		push_error(
			(
				"[test_network_live_headless] test runner contract missing "
				+ "_run_all_async or finished signal"
			)
		)
		quit(1)
		return
	_runner.connect("finished", Callable(self, "_on_finished"))
	root.add_child(_runner)
	_runner.call_deferred("_run_all_async")


func _on_finished(failed: int) -> void:
	if _runner != null:
		root.remove_child(_runner)
		_runner.queue_free()
	_runner = null
	quit(0 if failed == 0 else 1)
