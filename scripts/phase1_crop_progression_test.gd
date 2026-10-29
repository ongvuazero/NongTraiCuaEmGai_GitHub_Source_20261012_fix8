extends Node

const MAIN_SCENE = preload("res://scenes/main.tscn")
const FarmData = preload("res://scripts/farm_data.gd")
const CAPTURE_DIR := "res://REPORTS/PHASE1_QA"

var failures: Array[String] = []
var main: Control
var host: Control


func _ready() -> void:
	call_deferred("_run")


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("PHASE1 ASSERTION FAILED: " + message)


func _settle(frames := 7) -> void:
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
	await _settle(9)


func _open_seed_picker(screen: Node) -> Control:
	var action := screen.get_node("EDIT_ME/BottomActionHUD/ToolGroup/Action_seed") as BaseButton
	await _press(action, "Field / Gieo")
	var popup := screen.get_node("EDIT_ME/BottomActionHUD/ToolGroup/Action_seed/SeedPickerAnchor/SeedPickerGroup") as Control
	_assert_true(popup.visible, "Seed picker did not open")
	return popup


func _grow_and_harvest(crop_id: String, plot_ids: Array[int]) -> void:
	_assert_true(GameState.select_seed(crop_id), "Could not select unlocked crop " + crop_id)
	for plot_id in plot_ids:
		GameState.select_plot(plot_id)
		if not bool(GameState.get_plot(plot_id).get("is_hoed", false)):
			_assert_true(GameState.apply_field_action("till"), "Could not till Plot %d" % plot_id)
		_assert_true(GameState.apply_field_action("seed"), "Could not plant %s on Plot %d" % [crop_id, plot_id])
	var max_stage := int(FarmData.CROP_DEFINITIONS[crop_id]["max_stage"])
	for _stage in range(max_stage):
		for plot_id in plot_ids:
			GameState.select_plot(plot_id)
			_assert_true(GameState.apply_field_action("water"), "Could not water Plot %d" % plot_id)
		GameState.advance_day()
	for plot_id in plot_ids:
		GameState.select_plot(plot_id)
		_assert_true(bool(GameState.get_plot(plot_id).get("ready_to_harvest", false)), "%s not ready on Plot %d" % [crop_id, plot_id])
		_assert_true(GameState.apply_field_action("harvest"), "Could not harvest %s on Plot %d" % [crop_id, plot_id])


func _submit_visible_order(ready_capture: String, complete_capture: String, expected_done: int) -> void:
	var screen := await _route("quest")
	_assert_true(GameState.can_submit_active_order(), "Active order %d is not ready" % expected_done)
	await _capture(ready_capture)
	var submit := screen.find_child("SubmitActiveOrder", true, false) as BaseButton
	await _press(submit, "Orders / Submit")
	_assert_true(int(GameState.data.get("orders_done", -1)) == expected_done, "orders_done did not become %d" % expected_done)
	await _capture(complete_capture)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
	get_window().size = Vector2i(1280, 720)
	main = MAIN_SCENE.instantiate()
	get_tree().root.add_child(main)
	await _settle(10)
	host = main.get_node("ScreenHost") as Control

	# Old-save compatibility: preserve owned locked seeds, but normalize an invalid locked selection.
	var old_save := FarmData.create_initial_state()
	old_save["orders_done"] = 0
	old_save["selected_seed"] = "tomato"
	old_save["inventory"]["seed_tomato"] = 11
	old_save["inventory"]["seed_pumpkin"] = 7
	var normalized := GameState.normalize_state(old_save)
	_assert_true(int(normalized["inventory"]["seed_tomato"]) == 11, "Old save Tomato seeds were deleted")
	_assert_true(int(normalized["inventory"]["seed_pumpkin"]) == 7, "Old save Pumpkin seeds were deleted")
	_assert_true(String(normalized["selected_seed"]) == "carrot", "Locked old-save selection was not safely normalized to Carrot")

	# Fresh save assertions 01-11.
	GameState.new_state(1, true)
	_assert_true(int(GameState.data.get("orders_done", -1)) == 0, "01 orders_done must start at 0")
	_assert_true(int(GameState.data["inventory"].get("seed_carrot", -1)) == 6, "02 seed_carrot must start at 6")
	_assert_true(int(GameState.data["inventory"].get("seed_tomato", -1)) == 0, "03 seed_tomato must start at 0")
	_assert_true(int(GameState.data["inventory"].get("seed_pumpkin", -1)) == 0, "04 seed_pumpkin must start at 0")
	_assert_true(GameState.is_crop_unlocked("carrot"), "05 Carrot must be unlocked")
	_assert_true(not GameState.is_crop_unlocked("tomato"), "06 Tomato must be locked")
	_assert_true(not GameState.is_crop_unlocked("pumpkin"), "07 Pumpkin must be locked")
	var selected_before := String(GameState.data.get("selected_seed", ""))
	_assert_true(not GameState.select_seed("tomato") and String(GameState.data.get("selected_seed", "")) == selected_before, "08 Tomato selection bypassed lock")
	_assert_true(not GameState.select_seed("pumpkin") and String(GameState.data.get("selected_seed", "")) == selected_before, "09 Pumpkin selection bypassed lock")
	var coins_before_locked_buy := int(GameState.data.get("coins", 0))
	_assert_true(not GameState.buy("seed_tomato") and int(GameState.data.get("coins", 0)) == coins_before_locked_buy, "10 Tomato purchase bypassed lock")
	_assert_true(not GameState.buy("seed_pumpkin") and int(GameState.data.get("coins", 0)) == coins_before_locked_buy, "11 Pumpkin purchase bypassed lock")

	# Screenshot 01: current Storage proves new-game inventory is Carrot-only.
	var screen := await _route("storage")
	await _capture("01_NEW_GAME_CARROT_ONLY.png")

	# Screenshot 02: current attached Field picker shows Tomato/Pumpkin disabled.
	GameState.select_plot(1)
	_assert_true(GameState.apply_field_action("till"), "Could not prepare initial field plot")
	screen = await _route("field")
	var popup := await _open_seed_picker(screen)
	var tomato_button := popup.get_node("Seed_tomato") as BaseButton
	var pumpkin_button := popup.get_node("Seed_pumpkin") as BaseButton
	_assert_true(tomato_button.disabled, "Field Tomato button is not locked")
	_assert_true(pumpkin_button.disabled, "Field Pumpkin button is not locked")
	_assert_true(tomato_button.tooltip_text == tr("Complete The First Order to unlock Tomato."), "Tomato Field tooltip mismatch")
	_assert_true(pumpkin_button.tooltip_text == tr("Complete A New Crop to unlock Pumpkin."), "Pumpkin Field tooltip mismatch")
	await _capture("02_SEED_PICKER_TOMATO_LOCKED.png")

	# Screenshot 03: current Shop card/detail blocks Tomato purchase.
	screen = await _route("shop")
	var select_tomato := screen.find_child("SelectProduct_seed_tomato", true, false) as BaseButton
	await _press(select_tomato, "Shop / Select Tomato")
	var buy_detail := screen.find_child("BuySelectedProduct", true, false) as BaseButton
	_assert_true(buy_detail.disabled, "Shop Tomato buy control is not locked")
	_assert_true(buy_detail.tooltip_text == tr("Hoàn thành Đơn đầu tiên để mở khóa."), "Tomato Shop feedback mismatch")
	await _capture("03_SHOP_TOMATO_LOCKED.png")

	# Assertions 12-19: Carrot -> Order 1 -> Tomato unlock and purchase.
	await _grow_and_harvest("carrot", [1])
	_assert_true(int(GameState.data["inventory"].get("crop_carrot", 0)) >= 1, "12 Carrot harvest missing")
	var coins_before_order1 := int(GameState.data.get("coins", 0))
	await _submit_visible_order("04_ORDER1_READY.png", "05_ORDER1_COMPLETE.png", 1)
	_assert_true(int(GameState.data.get("coins", 0)) == coins_before_order1 + 70, "Order 1 coin reward incorrect")
	_assert_true(GameState.is_crop_unlocked("tomato"), "15 Tomato did not unlock")
	_assert_true(int(GameState.data["inventory"].get("seed_tomato", 0)) == 3, "16 Tomato reward seeds incorrect")
	_assert_true(GameState.select_seed("tomato"), "17 Tomato cannot be selected after unlock")
	_assert_true(not GameState.is_crop_unlocked("pumpkin"), "19 Pumpkin unlocked too early")

	# Screenshot 06: Field picker refreshes Tomato enabled while Pumpkin stays locked.
	screen = await _route("field")
	popup = await _open_seed_picker(screen)
	tomato_button = popup.get_node("Seed_tomato") as BaseButton
	pumpkin_button = popup.get_node("Seed_pumpkin") as BaseButton
	_assert_true(not tomato_button.disabled and pumpkin_button.disabled, "Field unlock state after Order 1 is wrong")
	await _capture("06_TOMATO_UNLOCKED.png")

	# Assertion 18 through actual current Shop UI.
	screen = await _route("shop")
	select_tomato = screen.find_child("SelectProduct_seed_tomato", true, false) as BaseButton
	await _press(select_tomato, "Shop / Select unlocked Tomato")
	var tomato_seeds_before_buy := int(GameState.data["inventory"].get("seed_tomato", 0))
	var coins_before_tomato_buy := int(GameState.data.get("coins", 0))
	await _press(screen.find_child("BuySelectedProduct", true, false) as BaseButton, "Shop / Buy unlocked Tomato")
	_assert_true(int(GameState.data["inventory"].get("seed_tomato", 0)) == tomato_seeds_before_buy + 3, "18 Tomato buy quantity incorrect")
	_assert_true(int(GameState.data.get("coins", 0)) == coins_before_tomato_buy - 16, "18 Tomato buy price incorrect")

	# Assertions 20-26: grow two Tomato -> Order 2 -> Pumpkin unlock and purchase.
	await _grow_and_harvest("tomato", [1, 2])
	_assert_true(int(GameState.data["inventory"].get("crop_tomato", 0)) >= 2, "20 Tomato harvest quantity insufficient")
	var coins_before_order2 := int(GameState.data.get("coins", 0))
	await _submit_visible_order("07_ORDER2_READY.png", "08_ORDER2_COMPLETE.png", 2)
	_assert_true(int(GameState.data.get("coins", 0)) == coins_before_order2 + 120, "Order 2 coin reward incorrect")
	_assert_true(GameState.is_crop_unlocked("pumpkin"), "23 Pumpkin did not unlock")
	_assert_true(int(GameState.data["inventory"].get("seed_pumpkin", 0)) == 2, "24 Pumpkin reward seeds incorrect")
	_assert_true(GameState.select_seed("pumpkin"), "25 Pumpkin cannot be selected after unlock")

	# Screenshot 09: all Field seed buttons enabled.
	screen = await _route("field")
	popup = await _open_seed_picker(screen)
	_assert_true(not (popup.get_node("Seed_carrot") as BaseButton).disabled, "Carrot unexpectedly locked")
	_assert_true(not (popup.get_node("Seed_tomato") as BaseButton).disabled, "Tomato unexpectedly locked")
	_assert_true(not (popup.get_node("Seed_pumpkin") as BaseButton).disabled, "Pumpkin still locked")
	await _capture("09_PUMPKIN_UNLOCKED.png")

	# Assertion 26 through current Shop UI.
	screen = await _route("shop")
	var select_pumpkin := screen.find_child("SelectProduct_seed_pumpkin", true, false) as BaseButton
	await _press(select_pumpkin, "Shop / Select unlocked Pumpkin")
	var pumpkin_seeds_before_buy := int(GameState.data["inventory"].get("seed_pumpkin", 0))
	var coins_before_pumpkin_buy := int(GameState.data.get("coins", 0))
	await _press(screen.find_child("BuySelectedProduct", true, false) as BaseButton, "Shop / Buy unlocked Pumpkin")
	_assert_true(int(GameState.data["inventory"].get("seed_pumpkin", 0)) == pumpkin_seeds_before_buy + 2, "26 Pumpkin buy quantity incorrect")
	_assert_true(int(GameState.data.get("coins", 0)) == coins_before_pumpkin_buy - 22, "26 Pumpkin buy price incorrect")

	# Assertions 27-32: Pumpkin -> Order 3 -> complete progression.
	await _grow_and_harvest("pumpkin", [1])
	_assert_true(int(GameState.data["inventory"].get("crop_pumpkin", 0)) >= 1, "27 Pumpkin harvest missing")
	var coins_before_order3 := int(GameState.data.get("coins", 0))
	await _submit_visible_order("10_ORDER3_READY.png", "11_ORDER3_COMPLETE.png", 3)
	_assert_true(int(GameState.data.get("coins", 0)) == coins_before_order3 + 200, "Order 3 coin reward incorrect")
	_assert_true(GameState.is_crop_unlocked("carrot") and GameState.is_crop_unlocked("tomato") and GameState.is_crop_unlocked("pumpkin"), "30 All crops must remain unlocked")
	_assert_true(GameState.status == tr("Đã hoàn thành mục tiêu nông trại đầu tiên!"), "Order 3 completion status mismatch")
	_assert_true(int(GameState.data.get("coins", 0)) == 752, "31 Final coins incorrect")
	var expected_inventory: Dictionary = GameState.data["inventory"].duplicate(true)
	_assert_true(int(expected_inventory.get("seed_carrot", 0)) == 8, "32 Final Carrot seed inventory incorrect")
	_assert_true(int(expected_inventory.get("seed_tomato", 0)) == 4, "32 Final Tomato seed inventory incorrect")
	_assert_true(int(expected_inventory.get("seed_pumpkin", 0)) == 3, "32 Final Pumpkin seed inventory incorrect")
	_assert_true(int(expected_inventory.get("crop_carrot", -1)) == 0 and int(expected_inventory.get("crop_tomato", -1)) == 0 and int(expected_inventory.get("crop_pumpkin", -1)) == 0, "32 Completed-order crop inventory incorrect")

	# Assertions 33-38: prove normal order autosave, with NO explicit final save.
	var expected_coins := int(GameState.data.get("coins", 0))
	var expected_orders := int(GameState.data.get("orders_done", 0))
	GameState.data["coins"] = -999
	GameState.data["orders_done"] = 0
	GameState.data["inventory"]["seed_carrot"] = -99
	_assert_true(GameState.load_slot(1), "34 Reload same slot failed")
	_assert_true(int(GameState.data.get("orders_done", -1)) == expected_orders, "35 orders_done did not persist")
	_assert_true(GameState.is_crop_unlocked("carrot") and GameState.is_crop_unlocked("tomato") and GameState.is_crop_unlocked("pumpkin"), "36 unlock state did not persist")
	_assert_true(GameState.data.get("inventory", {}) == expected_inventory, "37 inventory did not persist from autosave")
	_assert_true(int(GameState.data.get("coins", -1)) == expected_coins, "38 coins did not persist from autosave")
	screen = await _route("quest")
	await _capture("12_RELOAD_PROGRESSION.png")

	if failures.is_empty():
		print("PHASE1_CROP_PROGRESSION_TEST_PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			print("PHASE1_CROP_PROGRESSION_TEST_FAIL: " + failure)
		get_tree().quit(1)
