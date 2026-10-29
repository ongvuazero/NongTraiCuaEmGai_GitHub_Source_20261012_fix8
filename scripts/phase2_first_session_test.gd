extends Node

const MAIN_SCENE = preload("res://scenes/main.tscn")
const FarmData = preload("res://scripts/farm_data.gd")
const CAPTURE_DIR := "res://REPORTS/PHASE2_QA"

var failures: Array[String] = []
var main: Control
var host: Control


func _ready() -> void:
	call_deferred("_run")


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("PHASE2 ASSERTION FAILED: " + message)


func _settle(frames := 9) -> void:
	for _frame in range(frames):
		await get_tree().process_frame


func _screen() -> Node:
	if host == null or host.get_child_count() == 0:
		return null
	return host.get_child(host.get_child_count() - 1)


func _route(route_id: String) -> Node:
	ScreenRouter.go(route_id)
	await _settle()
	_assert_true(ScreenRouter.current_screen == route_id, "Expected route %s, got %s" % [route_id, ScreenRouter.current_screen])
	return _screen()


func _capture(file_name: String) -> void:
	await _settle(3)
	var image := get_viewport().get_texture().get_image()
	if image == null:
		_assert_true(false, "Viewport capture unavailable for " + file_name)
		return
	var error := image.save_png(ProjectSettings.globalize_path(CAPTURE_DIR.path_join(file_name)))
	_assert_true(error == OK, "Could not save " + file_name)


func _press(button: BaseButton, label: String) -> void:
	_assert_true(button != null, "Missing control: " + label)
	if button == null:
		return
	_assert_true(not button.disabled, "Control disabled unexpectedly: " + label)
	if button.disabled:
		return
	button.pressed.emit()
	await _settle()


func _field_detail(screen: Node) -> String:
	var label := screen.get_node("EDIT_ME/CropInfoPanel/TipText") as Label
	return "TIP   " + label.text


func _storage_feedback(screen: Node) -> String:
	var panel := screen.find_child("StorageFeedbackPanel", true, false)
	if panel == null:
		return ""
	for child in panel.get_children():
		if child is Label:
			return (child as Label).text
	return ""


func _grow_carrot_backend(plot_id: int) -> void:
	GameState.select_plot(plot_id)
	_assert_true(GameState.select_seed("carrot"), "Could not select Carrot for replacement harvest")
	var plot := GameState.get_plot(plot_id)
	if not bool(plot.get("is_hoed", false)):
		_assert_true(GameState.apply_field_action("till"), "Could not till replacement plot")
	_assert_true(GameState.apply_field_action("seed"), "Could not plant replacement Carrot")
	var max_stage := int(FarmData.CROP_DEFINITIONS["carrot"]["max_stage"])
	for _stage in range(max_stage):
		GameState.select_plot(plot_id)
		_assert_true(GameState.apply_field_action("water"), "Could not water replacement Carrot")
		GameState.advance_day()
	GameState.select_plot(plot_id)
	_assert_true(GameState.apply_field_action("harvest"), "Could not harvest replacement Carrot")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
	get_window().size = Vector2i(1280, 720)
	main = MAIN_SCENE.instantiate()
	get_tree().root.add_child(main)
	await _settle(10)
	host = main.get_node("ScreenHost") as Control

	GameState.new_state(1, true)
	_assert_true(int(GameState.data.get("orders_done", -1)) == 0, "01 fresh game orders_done must be 0")

	var screen := await _route("hub")
	var first_panel := screen.find_child("FirstSessionOrderPanel", true, false) as Control
	var first_body := screen.find_child("FirstSessionOrderBody", true, false) as Label
	_assert_true(first_panel != null and first_panel.visible, "02 Home existing order_panel is not visible")
	_assert_true(first_body != null and first_body.text == tr("Vào Ruộng để trồng\nCà rốt đầu tiên."), "03 Home guidance does not direct player to Field")
	await _capture("01_HOME_FIRST_SESSION.png")

	screen = await _route("field")
	_assert_true(_field_detail(screen).contains(tr("Select a plot, then press TILL.")), "05 untouched plot lacks Till guidance")
	await _capture("02_FIELD_TILL_HINT.png")

	var till := screen.get_node("EDIT_ME/BottomActionHUD/ToolGroup/Action_till") as BaseButton
	await _press(till, "Field / Till")
	screen.call("qa_trigger_plot_click", 1)
	await _settle()
	_assert_true(_field_detail(screen).contains(tr("Press PLANT, choose Carrot, then select a plot.")), "06 tilled plot lacks Plant Carrot guidance")
	await _capture("03_FIELD_PLANT_HINT.png")

	var seed_action := screen.get_node("EDIT_ME/BottomActionHUD/ToolGroup/Action_seed") as BaseButton
	await _press(seed_action, "Field / Seed")
	var carrot := screen.get_node("EDIT_ME/BottomActionHUD/ToolGroup/Action_seed/SeedPickerAnchor/SeedPickerGroup/Seed_carrot") as BaseButton
	await _press(carrot, "Field / Carrot")
	screen.call("qa_trigger_plot_click", 1)
	await _settle(12)
	_assert_true(String(GameState.get_plot(1).get("crop", "")) == "carrot", "07 Carrot was not planted through current Field UI")
	_assert_true(_field_detail(screen).contains(tr("Press WATER.")), "07 planted Carrot lacks Water guidance")
	await _capture("04_FIELD_WATER_HINT.png")

	var water := screen.get_node("EDIT_ME/BottomActionHUD/ToolGroup/Action_water") as BaseButton
	await _press(water, "Field / Water")
	screen.call("qa_trigger_plot_click", 1)
	await _settle()
	_assert_true(_field_detail(screen).contains(tr("Press NEXT DAY. Water again tomorrow.")), "08 watered Carrot lacks Next Day guidance")
	await _capture("05_FIELD_NEXT_DAY_HINT.png")

	var max_stage := int(FarmData.CROP_DEFINITIONS["carrot"]["max_stage"])
	for stage_index in range(max_stage):
		if stage_index > 0:
			water = screen.get_node("EDIT_ME/BottomActionHUD/ToolGroup/Action_water") as BaseButton
			await _press(water, "Field / Water next growth day")
			screen.call("qa_trigger_plot_click", 1)
			await _settle()
		var next_day := screen.get_node("EDIT_ME/BottomActionHUD/Action_advance_day") as BaseButton
		await _press(next_day, "Field / Next Day")
	_assert_true(bool(GameState.get_plot(1).get("ready_to_harvest", false)), "09 Carrot did not reach ready state")
	_assert_true(_field_detail(screen).contains(tr("Carrot is ready. Press HARVEST.")), "09 ready Carrot lacks Harvest guidance")
	await _capture("06_FIELD_HARVEST_HINT.png")

	var harvest := screen.get_node("EDIT_ME/BottomActionHUD/Action_harvest") as BaseButton
	await _press(harvest, "Field / Harvest")
	screen.call("qa_trigger_plot_click", 1)
	await _settle()
	_assert_true(int(GameState.data["inventory"].get("crop_carrot", 0)) == 1, "10 harvested Carrot did not enter Storage")
	_assert_true(_field_detail(screen).contains(tr("Carrot is in Storage. Open Orders to complete your first order.")), "10 post-harvest guidance does not point to first Order")
	await _capture("07_FIELD_AFTER_HARVEST_HINT.png")

	screen = await _route("storage")
	var carrot_slot := screen.get_node("MainContent/ItemGrid_5x3/ItemSlot04")
	var carrot_selectors := carrot_slot.find_children("Select*", "Button", true, false)
	_assert_true(not carrot_selectors.is_empty(), "11 Storage Carrot selector is missing")
	if not carrot_selectors.is_empty():
		await _press(carrot_selectors[0] as BaseButton, "Storage / Select Carrot")
	var safety_text := tr("Cà rốt dùng cho Đơn đầu tiên. Hãy giữ lại ít nhất 1 củ.")
	_assert_true(_storage_feedback(screen).contains(safety_text), "11 Storage Carrot safety message is missing")
	var sell := screen.find_child("StorageSellSelected", true, false) as BaseButton
	_assert_true(sell != null and not sell.disabled, "12 selling is incorrectly locked")
	var coins_before_sell := int(GameState.data.get("coins", 0))
	await _capture("08_STORAGE_FIRST_CARROT.png")
	await _press(sell, "Storage / Sell Carrot")
	_assert_true(int(GameState.data["inventory"].get("crop_carrot", -1)) == 0, "12 selling did not remove Carrot")
	_assert_true(int(GameState.data.get("coins", 0)) == coins_before_sell + 40, "12 selling did not grant Carrot value")

	await _grow_carrot_backend(1)
	_assert_true(int(GameState.data["inventory"].get("crop_carrot", 0)) >= 1, "13 no Carrot retained for Order 1")
	screen = await _route("quest")
	_assert_true(GameState.can_submit_active_order(), "13 Order 1 is not ready")
	await _capture("09_ORDER1.png")
	var submit := screen.find_child("SubmitActiveOrder", true, false) as BaseButton
	await _press(submit, "Orders / Submit Order 1")
	_assert_true(int(GameState.data.get("orders_done", -1)) == 1, "14 orders_done did not become 1")

	screen = await _route("hub")
	first_panel = screen.find_child("FirstSessionOrderPanel", true, false) as Control
	_assert_true(first_panel != null and not first_panel.visible, "16 Home first-session panel remains visible after Order 1")
	await _capture("10_HOME_AFTER_ORDER1.png")

	screen = await _route("field")
	var post_order_tip := _field_detail(screen)
	var first_session_lines := ["Select a plot, then press TILL.", "Press PLANT, choose Carrot", "Press WATER.", "Press NEXT DAY", "Carrot is ready", "Open Orders to complete your first order."]
	for line in first_session_lines:
		_assert_true(not post_order_tip.contains(tr(line)), "17 Field first-session guidance remains after Order 1: " + line)
	screen = await _route("storage")
	screen.call("_select_item", "crop_carrot")
	await _settle()
	_assert_true(not _storage_feedback(screen).contains(safety_text), "18 Storage safety guidance remains after Order 1")

	_assert_true(GameState.load_slot(1), "19 reload same save failed")
	_assert_true(int(GameState.data.get("orders_done", -1)) == 1, "20 Order 1 progress did not persist")
	screen = await _route("hub")
	first_panel = screen.find_child("FirstSessionOrderPanel", true, false) as Control
	_assert_true(first_panel != null and not first_panel.visible, "20 guidance returned after reload")

	if failures.is_empty():
		print("PHASE2_FIRST_SESSION_TEST_PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			print("PHASE2_FIRST_SESSION_TEST_FAIL: " + failure)
		get_tree().quit(1)
