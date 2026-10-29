extends SceneTree

var output_dir := ""
var app: Control
var gs: Node
var router: Node


func _initialize() -> void:
	output_dir = ProjectSettings.globalize_path("res://qa/v4_phase1")
	DirAccess.make_dir_recursive_absolute(output_dir)
	OS.set_environment("MSF_TEST_SAVE_DIR", "user://v4_phase1_capture")
	call_deferred("_run")


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await _settle()
	gs = root.get_node("GameState")
	router = root.get_node("ScreenRouter")
	await _capture("01_title_v4.png")
	gs.save_mode = "new"
	router.go("save")
	await _settle()
	await _capture("02_save_v4.png")
	gs.new_state(1, true)
	router.go("hub")
	await _settle()
	await _capture("03_hub_v4.png")
	print("V4_PHASE1_CAPTURE_PASS")
	quit(0)


func _settle() -> void:
	for i in range(5): await process_frame


func _capture(file_name: String) -> void:
	var image := root.get_texture().get_image()
	var error := image.save_png(output_dir.path_join(file_name))
	if error != OK:
		push_error("Capture failed: " + file_name)
		quit(1)
