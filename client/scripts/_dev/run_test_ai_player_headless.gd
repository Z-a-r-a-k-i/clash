extends SceneTree

const TEST_SCRIPT := "res://scripts/_dev/test_ai_player.gd"
const HEADLESS_TEST_RUNNER := preload("res://scripts/_dev/headless_test_runner.gd")


func _init() -> void:
	quit(HEADLESS_TEST_RUNNER.run(root, TEST_SCRIPT, "test_ai_player"))
