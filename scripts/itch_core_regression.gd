extends "res://scripts/current_core_loop_test.gd"

var current_capture_root := ""

func _ready() -> void:
	if not OS.get_environment("MSF_TEST_SAVE_DIR").contains("itch_ui_recovery"):
		push_error("Current regression needs an isolated itch_ui_recovery save directory")
		get_tree().quit(2)
		return
	current_capture_root = "res://REPORTS/ITCH_UI_RECOVERY_20261005/REGRESSION/core_%d" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(current_capture_root))
	super._ready()

func _capture(file_name: String) -> void:
	await _settle(3)
	await RenderingServer.frame_post_draw
	var bitmap := get_viewport().get_texture().get_image()
	var path := current_capture_root.path_join(file_name)
	_assert_true(not FileAccess.file_exists(path), "Fresh capture path: " + path)
	if not FileAccess.file_exists(path):
		_assert_true(bitmap.save_png(ProjectSettings.globalize_path(path)) == OK, "Capture: " + path)
