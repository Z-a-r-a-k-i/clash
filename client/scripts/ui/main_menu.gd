class_name MainMenu
extends Control

const SOLO_SCENE_PATH := "res://scenes/_dev/dev_play_mode.tscn"
const MULTIPLAYER_SCENE_PATH := "res://scenes/network_lobby.tscn"
const REPLAY_SCENE_PATH := "res://scenes/replay_mode.tscn"
const MENU_WIDTH: float = 360.0
const BUTTON_HEIGHT: float = 44.0

var _initialized: bool = false


func _ready() -> void:
	ensure_initialized()


func ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	anchors_preset = Control.PRESET_FULL_RECT
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0

	var background := ColorRect.new()
	background.name = "Background"
	background.color = Color(0.07, 0.08, 0.09, 1.0)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var root := VBoxContainer.new()
	root.name = "Menu"
	root.custom_minimum_size = Vector2(MENU_WIDTH, 0.0)
	root.add_theme_constant_override("separation", 12)
	center.add_child(root)

	var title := Label.new()
	title.name = "Title"
	title.text = "Clash"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	root.add_child(title)

	var solo_button := _menu_button("Solo", "SoloButton")
	solo_button.pressed.connect(_solo_pressed)
	root.add_child(solo_button)

	var multiplayer_button := _menu_button("Multiplayer", "MultiplayerButton")
	multiplayer_button.pressed.connect(_multiplayer_pressed)
	root.add_child(multiplayer_button)

	var replay_button := _menu_button("Replay", "ReplayButton")
	replay_button.pressed.connect(_replay_pressed)
	root.add_child(replay_button)


func solo_scene_path() -> String:
	return SOLO_SCENE_PATH


func multiplayer_scene_path() -> String:
	return MULTIPLAYER_SCENE_PATH


func replay_scene_path() -> String:
	return REPLAY_SCENE_PATH


func _solo_pressed() -> void:
	_change_scene(SOLO_SCENE_PATH)


func _multiplayer_pressed() -> void:
	_change_scene(MULTIPLAYER_SCENE_PATH)


func _replay_pressed() -> void:
	_change_scene(REPLAY_SCENE_PATH)


func _change_scene(path: String) -> void:
	var err: Error = get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("MainMenu: failed to open %s: %d" % [path, err])


func _menu_button(label: String, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = label
	button.custom_minimum_size = Vector2(MENU_WIDTH, BUTTON_HEIGHT)
	return button
