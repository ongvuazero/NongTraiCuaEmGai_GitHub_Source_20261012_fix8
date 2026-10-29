extends SceneTree

const FarmData = preload("res://scripts/farm_data.gd")
const SaveService = preload("res://scripts/save_service.gd")

var failures: Array[String] = []
var test_root := ""


func _initialize() -> void:
	test_root = "user://phase01_v3_tests_%d" % Time.get_ticks_msec()
	OS.set_environment("MSF_TEST_SAVE_DIR", test_root)
	call_deferred("_run")


func _run() -> void:
	var service = SaveService.new(test_root)
	_test_three_independent_slots(service)
	await _test_new_game_and_overwrite(service)
	await _test_mutation_persistence()
	await _test_energy_gates()
	await _test_fertilizer_consumption()
	_test_corrupt_save(service)
	if failures.is_empty():
		print("PHASE01_CORRECTNESS_TEST_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PHASE01_CORRECTNESS_TEST_FAIL count=%d" % failures.size())
		quit(1)


func _test_three_independent_slots(service) -> void:
	for slot_id in range(1, 4):
		var state := FarmData.create_initial_state()
		state["day"] = slot_id + 1
		state["coins"] = slot_id * 111
		state["inventory"]["seed_carrot"] = slot_id
		_check(service.save_current_slot(slot_id, state, "hub")["ok"], "slot %d save failed" % slot_id)
	for slot_id in range(1, 4):
		var loaded: Dictionary = service.load_slot(slot_id)
		_check(loaded["ok"], "slot %d load failed" % slot_id)
		if loaded["ok"]:
			_check(int(loaded["state"]["day"]) == slot_id + 1, "slot %d day contaminated" % slot_id)
			_check(int(loaded["state"]["coins"]) == slot_id * 111, "slot %d coins contaminated" % slot_id)


func _test_new_game_and_overwrite(service) -> void:
	var old_state := FarmData.create_initial_state()
	old_state["day"] = 19
	service.save_current_slot(1, old_state, "field")
	service.delete_slot(2)
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.call("_handle_action", "open_new_game")
	app.call("_select_save_slot", 2)
	app.call("_confirm_save_slot")
	_check(int(app.get("_state")["day"]) == 1, "New Game loaded old progress")
	_check(int(app.get("_state")["selected_slot"]) == 2, "New Game used wrong empty slot")
	_check(int(service.load_slot(1)["state"]["day"]) == 19, "New Game contaminated existing slot")
	app.call("_handle_action", "open_new_game")
	app.call("_select_save_slot", 1)
	app.call("_confirm_save_slot")
	_check(int(service.load_slot(1)["state"]["day"]) == 19, "First overwrite click changed occupied slot")
	app.call("_confirm_save_slot")
	_check(int(service.load_slot(1)["state"]["day"]) == 1, "Confirmed overwrite did not create fresh state")
	app.queue_free()
	await process_frame


func _test_mutation_persistence() -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var state := FarmData.create_initial_state()
	state["selected_slot"] = 3
	app.set("_state", state)
	app.set("_current_screen", "shop")
	app.call("_save_game")
	var before_coins := int(state["coins"])
	app.call("_buy_shop_item", "seed_carrot")
	var service = SaveService.new(test_root)
	var bought: Dictionary = service.load_slot(3)["state"]
	_check(int(bought["coins"]) == before_coins - 12, "Shop purchase was not persisted immediately")
	_check(int(bought["inventory"]["seed_carrot"]) == 9, "Purchased inventory was not persisted")
	state = app.get("_state")
	state["inventory"]["crop_carrot"] = 1
	state["active_order_index"] = 0
	app.set("_state", state)
	app.call("_save_game")
	app.call("_deliver_active_order")
	var delivered: Dictionary = service.load_slot(3)["state"]
	_check(int(delivered["inventory"]["crop_carrot"]) == 0, "Order delivery consumption was not persisted")
	_check(int(delivered["orders_done"]) == 1, "Order delivery completion was not persisted")
	app.queue_free()
	await process_frame


func _test_energy_gates() -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	for action in ["till", "seed", "water", "fertilize", "harvest"]:
		var state := FarmData.create_initial_state()
		state["selected_slot"] = 2
		state["energy"] = int(FarmData.ACTION_ENERGY_COSTS[action]) - 1
		var plot: Dictionary = state["field_plots"][0]
		if action != "till":
			plot["is_hoed"] = true
		if action in ["water", "fertilize", "harvest"]:
			plot["crop"] = "carrot"
		if action == "harvest":
			plot["growth_stage"] = 4
			plot["ready_to_harvest"] = true
		state["field_plots"][0] = plot
		var seeds_before := int(state["inventory"]["seed_carrot"])
		var plot_before := plot.duplicate(true)
		app.set("_state", state)
		app.set("_farmer_action", "idle")
		app.call("_apply_field_action", action)
		var after: Dictionary = app.get("_state")
		_check(after["field_plots"][0] == plot_before, "Low energy mutated field action %s" % action)
		_check(int(after["inventory"]["seed_carrot"]) == seeds_before, "Low energy consumed seed for %s" % action)
		_check(app.get("_farmer_action") == "idle", "Low energy started animation for %s" % action)
	for action in ["feed_animals", "clean_animals", "pet_animals"]:
		var state := FarmData.create_initial_state()
		state["energy"] = int(FarmData.ACTION_ENERGY_COSTS[action]) - 1
		var animal_before: Dictionary = state["animal"].duplicate(true)
		var feed_before := int(state["inventory"]["animal_feed"])
		app.set("_state", state)
		app.set("_farmer_action", "idle")
		app.call("_" + action)
		var after: Dictionary = app.get("_state")
		_check(after["animal"] == animal_before, "Low energy mutated %s" % action)
		_check(int(after["inventory"]["animal_feed"]) == feed_before, "Low energy consumed feed for %s" % action)
		_check(app.get("_farmer_action") == "idle", "Low energy started animation for %s" % action)
	app.queue_free()
	await process_frame


func _test_fertilizer_consumption() -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var state := FarmData.create_initial_state()
	state["selected_slot"] = 1
	app.set("_state", state)
	app.call("_apply_field_action", "till")
	app.call("_apply_field_action", "seed")
	app.call("_apply_field_action", "fertilize")
	app.call("_apply_field_action", "water")
	app.call("_advance_day")
	var plot: Dictionary = app.get("_state")["field_plots"][0]
	_check(int(plot["growth_stage"]) == 2, "Fertilizer did not add exactly one bonus stage")
	_check(not bool(plot["fertilizer_pending"]), "Fertilizer pending flag was not consumed")
	app.call("_apply_field_action", "water")
	app.call("_advance_day")
	plot = app.get("_state")["field_plots"][0]
	_check(int(plot["growth_stage"]) == 3, "Consumed fertilizer repeated on a later day")
	app.queue_free()
	await process_frame


func _test_corrupt_save(service) -> void:
	var path := test_root.path_join("my_sisters_farm_slot_2.save")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("not a Godot Variant save")
	file.close()
	var result: Dictionary = service.load_slot(2)
	_check(not result["ok"], "Corrupt save was accepted")
	_check(FileAccess.file_exists(path), "Corrupt save was not preserved")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
