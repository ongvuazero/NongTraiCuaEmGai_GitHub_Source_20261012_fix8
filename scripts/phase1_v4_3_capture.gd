extends SceneTree

var output_dir := ""


func _initialize() -> void:
	output_dir = ProjectSettings.globalize_path("res://qa/v4_phase1_3")
	DirAccess.make_dir_recursive_absolute(output_dir)
	OS.set_environment("MSF_TEST_SAVE_DIR", "user://v4_phase1_3_capture")
	call_deferred("_run")


func _run() -> void:
	var app: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	for i in range(5):
		await process_frame
	var gs := root.get_node("GameState")
	var router := root.get_node("ScreenRouter")
	gs.new_state(1, true)
	router.go("hub")
	for i in range(6):
		await process_frame
	var image := root.get_texture().get_image()
	var error := image.save_png(output_dir.path_join("03_hub_v4_3.png"))
	if error != OK:
		push_error("Capture failed: 03_hub_v4_3.png")
		quit(1)
	print("V4_PHASE1_3_CAPTURE_PASS")
	quit(0)
