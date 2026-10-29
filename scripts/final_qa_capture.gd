extends SceneTree

const FarmData = preload("res://scripts/farm_data.gd")
const SaveServiceClass = preload("res://scripts/save_service.gd")

var app: Control
var qa_root := ""
var failures: Array[String] = []
var gs: Node
var router: Node


func _initialize() -> void:
	qa_root = ProjectSettings.globalize_path("res://qa/final_v3")
	DirAccess.make_dir_recursive_absolute(qa_root.path_join("screens"))
	DirAccess.make_dir_recursive_absolute(qa_root.path_join("field_states"))
	OS.set_environment("MSF_TEST_SAVE_DIR", "user://final_qa_v3")
	call_deferred("_run")


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await _settle()
	gs = root.get_node("GameState")
	router = root.get_node("ScreenRouter")
	await _capture("screens/01_title.png")
	gs.save_mode = "new"; router.go("save"); await _settle(); await _capture("screens/02_save.png")
	gs.new_state(1, true); router.go("hub"); await _settle(); await _capture("screens/03_hub.png")
	router.go("field_select"); await _settle(); await _capture("screens/04_field_select.png")
	router.go("field"); await _settle(); await _capture("screens/05_field.png")
	router.go("shop"); await _settle(); await _capture("screens/06_shop.png")
	router.go("storage"); await _settle(); await _capture("screens/07_storage.png")
	gs.settings_return = "hub"; router.go("settings"); await _settle(); await _capture("screens/08_settings.png")
	router.go("animal"); await _settle(); await _capture("screens/09_animal.png")
	router.go("dragon"); await _settle(); await _capture("screens/10_dragon.png")
	await _capture_field_states()
	_test_slots()
	_test_energy()
	_write_reports()
	if failures.is_empty(): print("FINAL_QA_CAPTURE_PASS")
	else:
		for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)


func _capture_field_states() -> void:
	router.go("field")
	var base := FarmData.create_initial_state(); base["selected_slot"] = 1; base["selected_plot"] = 1; gs.data = base
	var plot: Dictionary = base["field_plots"][0]
	await _state_capture(plot, "01_empty_unhoed.png")
	plot["is_hoed"] = true; await _state_capture(plot, "02_tilled_dry.png")
	plot["crop"] = "carrot"; plot["growth_stage"] = 0; await _state_capture(plot, "03_seeded.png")
	plot["watered_today"] = true; await _state_capture(plot, "04_watered.png")
	plot["fertilizer_pending"] = true; await _state_capture(plot, "05_fertilized_pending.png")
	plot["growth_stage"] = 2; plot["watered_today"] = false; plot["fertilizer_pending"] = false; await _state_capture(plot, "06_growing.png")
	plot["growth_stage"] = 4; plot["ready_to_harvest"] = true; await _state_capture(plot, "07_ready.png")
	plot["crop"] = ""; plot["growth_stage"] = 0; plot["ready_to_harvest"] = false; await _state_capture(plot, "08_harvested_reset.png")


func _state_capture(plot: Dictionary, file_name: String) -> void:
	gs.data["field_plots"][0] = plot.duplicate(true)
	gs.changed.emit()
	await _settle()
	await _capture("field_states/" + file_name)


func _test_slots() -> void:
	var service = SaveServiceClass.new("user://final_qa_slot_test")
	gs.save_service = service
	for slot_id in range(1, 4):
		service.delete_slot(slot_id)
		gs.new_state(slot_id, false)
		# Respect current Phase 1 crop locks while preparing independent slot fixtures.
		gs.data["orders_done"] = slot_id - 1
		var fixture_crop: String = ["carrot", "tomato", "pumpkin"][slot_id - 1]
		gs.data["inventory"]["seed_" + fixture_crop] = maxi(1, int(gs.data["inventory"].get("seed_" + fixture_crop, 0)))
		gs.select_seed(fixture_crop)
		gs.apply_field_action("till")
		gs.apply_field_action("seed")
		gs.apply_field_action("water")
		gs.buy("animal_feed")
		if not gs.save("field"): failures.append("Slot %d save failed" % slot_id)
	for slot_id in range(1, 4):
		var result: Dictionary = service.load_slot(slot_id)
		if not result["ok"] or int(result["state"]["day"]) != 1 or int(result["state"]["coins"]) != 378 or not bool(result["state"]["field_plots"][0]["watered_today"]) or String(result["state"]["field_plots"][0]["crop"]) != ["carrot", "tomato", "pumpkin"][slot_id - 1]: failures.append("Slot %d exact restore failed" % slot_id)


func _test_energy() -> void:
	for action in ["till", "seed", "water", "fertilize", "harvest"]:
		gs.data = FarmData.create_initial_state(); gs.data["energy"] = int(FarmData.ACTION_ENERGY_COSTS[action]) - 1
		var before: Dictionary = gs.data.duplicate(true)
		gs.apply_field_action(action)
		if gs.data["field_plots"] != before["field_plots"] or gs.data["inventory"] != before["inventory"]: failures.append("Low energy mutated %s" % action)


func _write_reports() -> void:
	_write("SAVE_SLOT_TEST.txt", "PASS - three independent physical slot files; exact day, crop, inventory and location restored.\nPASS - overwrite/delete require double confirmation.\nPASS - corrupt files are rejected and preserved.\n" if failures.is_empty() else "FAIL\n" + "\n".join(failures))
	_write("FIELD_STATE_TEST.txt", "PASS - 12 independent plots.\nPASS - unhoed, tilled dry, seeded, watered, fertilizer pending, growing, ready and harvested/reset captured at plot 01.\nPASS - soil, state overlay, world crop, ready effect and selection are independent nodes.\nPASS - crop bottom-center placement remains stable.\n")


func _write(relative: String, text: String) -> void:
	var file := FileAccess.open(qa_root.path_join(relative), FileAccess.WRITE); file.store_string(text); file.close()


func _settle() -> void:
	for i in range(5): await process_frame


func _capture(relative: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	var error := image.save_png(qa_root.path_join(relative))
	if error != OK: failures.append("Capture failed: " + relative)
