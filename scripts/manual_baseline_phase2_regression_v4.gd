extends "res://scripts/phase2_first_session_test.gd"

# Additive runner: execute the original assertions unchanged, but never
# overwrite an earlier phase's screenshots. Only evidence output is redirected.
var v4_capture_root := ""

func _ready() -> void:
	if OS.get_environment("MSF_TEST_SAVE_DIR").is_empty() or not OS.get_environment("MSF_TEST_SAVE_DIR").contains("manual_baseline_repair_v4"):
		push_error("V4 regression requires an isolated named save root.")
		get_tree().quit(2)
		return
	v4_capture_root = "res://REPORTS/MANUAL_BASELINE_REPAIR_V4/REGRESSION/phase2_%d" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(v4_capture_root))
	super._ready()

func _capture(file_name: String) -> void:
	await _settle(3)
	await RenderingServer.frame_post_draw
	var bitmap := get_viewport().get_texture().get_image()
	var path := v4_capture_root.path_join(file_name)
	_assert_true(not FileAccess.file_exists(path), "New evidence must not overwrite earlier capture")
	if FileAccess.file_exists(path): return
	_assert_true(bitmap.save_png(ProjectSettings.globalize_path(path)) == OK, "V4 regression capture: " + path)

