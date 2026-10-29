extends Node

const MAIN_SCENE = preload("res://scenes/main.tscn")
const Geometry = preload("res://v7/runtime/field_projection_v7_2.gd")
const FarmData = preload("res://scripts/farm_data.gd")
const SCREEN_PATHS := {
	"title": "res://scenes/screens/title_screen.tscn",
	"save": "res://scenes/screens/save_slot_screen.tscn",
	"hub": "res://scenes/screens/home_hub_screen.tscn",
	"field_select": "res://scenes/screens/04_field_select.tscn",
	"field": "res://scenes/screens/05_field_gameplay.tscn",
	"storage": "res://scenes/screens/07_storage.tscn",
	"shop": "res://scenes/screens/06_shop.tscn",
}
const CAPTURE_DIR := "res://REPORTS/PHASE0_QA"

var failures: Array[String] = []
var main: Control
var host: Control
var starting_coins := 0
var starting_carrot_seeds := 0


func _ready() -> void:
	call_deferred("_run")


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("PHASE0 ASSERTION FAILED: " + message)


func _settle(frames := 6) -> void:
	for _frame in range(frames):
		await get_tree().process_frame


func _screen() -> Node:
	if host == null or host.get_child_count() == 0:
		return null
	return host.get_child(host.get_child_count() - 1)


func _assert_route(route_id: String) -> Node:
	await _settle()
	var screen := _screen()
	_assert_true(ScreenRouter.current_screen == route_id, "Route expected %s, got %s" % [route_id, ScreenRouter.current_screen])
	_assert_true(screen != null, "Route %s did not instantiate a screen" % route_id)
	if screen != null:
		_assert_true(screen.scene_file_path == String(SCREEN_PATHS[route_id]), "Route %s instantiated %s instead of %s" % [route_id, screen.scene_file_path, SCREEN_PATHS[route_id]])
	return screen


func _capture(file_name: String) -> void:
	await _settle(3)
	var image := get_viewport().get_texture().get_image()
	var path := CAPTURE_DIR.path_join(file_name)
	var error := image.save_png(ProjectSettings.globalize_path(path))
	_assert_true(error == OK, "Could not save screenshot %s" % path)


func _direct_buttons(node: Node) -> Array[BaseButton]:
	var result: Array[BaseButton] = []
	for child in node.get_children():
		if child is BaseButton:
			result.append(child as BaseButton)
	return result


func _press(button: BaseButton, label: String) -> void:
	_assert_true(button != null, "Missing UI control: " + label)
	if button == null:
		return
	_assert_true(not button.disabled, "UI control disabled unexpectedly: " + label)
	if button.disabled:
		return
	button.pressed.emit()
	await _settle(8)


func _field_click_plot(screen: Node, plot_id: int) -> void:
	# V11+ Field uses one canonical polygon-input path and exposes this QA hook.
	# The previous synthetic _unhandled_input call targeted the retired input path.
	screen.call("qa_trigger_plot_click", plot_id)
	await _settle(8)


func _find_title_button(screen: Node, ordinal: int) -> BaseButton:
	var buttons := _direct_buttons(screen)
	buttons.sort_custom(func(a: BaseButton, b: BaseButton) -> bool: return a.position.y < b.position.y)
	return buttons[ordinal] if ordinal >= 0 and ordinal < buttons.size() else null


func _find_home_nav_button(screen: Node, ordinal: int) -> BaseButton:
	var buttons := _direct_buttons(screen)
	return buttons[ordinal] if ordinal >= 0 and ordinal < buttons.size() else null


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
	get_window().size = Vector2i(1280, 720)
	main = MAIN_SCENE.instantiate()
	get_tree().root.add_child(main)
	await _settle(10)
	host = main.get_node("ScreenHost") as Control

	# TITLE -> NEW GAME
	var screen := await _assert_route("title")
	await _capture("01_TITLE.png")
	var new_game := _find_title_button(screen, 1)
	await _press(new_game, "Title / New Game")

	# SAVE SLOT -> HOME
	screen = await _assert_route("save")
	await _capture("02_SAVE.png")
	var slot_buttons := _direct_buttons(screen).filter(func(button: BaseButton) -> bool: return not button.name.begins_with("Action_"))
	_assert_true(not slot_buttons.is_empty(), "Save screen has no selectable slot hit target")
	if not slot_buttons.is_empty():
		await _press(slot_buttons[0], "Save / Slot 1")
		screen = await _assert_route("save")
	var confirm := screen.find_child("Action_CONFIRM", true, false) as BaseButton
	await _press(confirm, "Save / Confirm")
	screen = await _assert_route("hub")
	await _capture("03_HOME.png")

	# Fresh-state assertions.
	_assert_true(int(GameState.data.get("selected_slot", 0)) == 1, "Fresh game did not select slot 1")
	starting_coins = int(GameState.data.get("coins", -1))
	starting_carrot_seeds = int(GameState.data.get("inventory", {}).get("seed_carrot", -1))
	_assert_true(starting_coins >= 0, "Starting coin value missing")
	_assert_true(starting_carrot_seeds > 0, "Starting carrot seed amount missing or zero")

	# HOME -> FIELD SELECT -> FIELD using visible buttons.
	var home_field := _find_home_nav_button(screen, 0)
	await _press(home_field, "Home / Field")
	screen = await _assert_route("field_select")
	await _capture("04_FIELD_SELECT.png")
	_assert_true(screen.find_child("BackToHub", true, false) != null, "Field Select / Back is missing")
	var enter_field := screen.find_child("EnterField", true, false) as BaseButton
	await _press(enter_field, "Field Select / Enter Field")
	screen = await _assert_route("field")
	_assert_true(screen.scene_file_path != "res://scenes/screens/field_screen.tscn", "Legacy Field scene was routed")
	await _capture("05_FIELD_EMPTY.png")

	# Plot selection and Till through current visible field controls.
	await _field_click_plot(screen, 1)
	_assert_true(int(GameState.data.get("selected_plot", 0)) == 1, "Projected click did not select Plot 1")
	var till := screen.get_node("EDIT_ME/BottomActionHUD/ToolGroup/Action_till") as BaseButton
	await _press(till, "Field / Till")
	await _field_click_plot(screen, 1)
	_assert_true(bool(GameState.get_plot(1).get("is_hoed", false)), "Till did not hoe Plot 1")

	# Open attached seed picker, select Carrot, then click the plot to plant.
	var seed_action := screen.get_node("EDIT_ME/BottomActionHUD/ToolGroup/Action_seed") as BaseButton
	await _press(seed_action, "Field / Seed")
	var seed_popup := screen.get_node("EDIT_ME/BottomActionHUD/ToolGroup/Action_seed/SeedPickerAnchor/SeedPickerGroup") as Control
	_assert_true(seed_popup.visible, "Seed picker did not open")
	var carrot_seed := seed_popup.get_node("Seed_carrot") as BaseButton
	await _press(carrot_seed, "Field / Carrot seed")
	_assert_true(String(GameState.data.get("selected_seed", "")) == "carrot", "Carrot seed was not selected")
	_assert_true(not seed_popup.visible, "Seed picker did not close after selection")
	await _field_click_plot(screen, 1)
	await _settle(12)
	var plot: Dictionary = GameState.get_plot(1)
	_assert_true(String(plot.get("crop", "")) == "carrot", "Clicking Plot 1 with Gieo active did not plant carrot")
	_assert_true(int(GameState.data["inventory"].get("seed_carrot", -1)) == starting_carrot_seeds - 1, "Carrot seed count did not decrease by one")
	await _capture("06_FIELD_CARROT_PLANTED.png")

	# Water and advance with visible controls until ready.
	var water := screen.get_node("EDIT_ME/BottomActionHUD/ToolGroup/Action_water") as BaseButton
	await _press(water, "Field / Water")
	await _field_click_plot(screen, 1)
	_assert_true(bool(GameState.get_plot(1).get("watered_today", false)), "Water did not mark Plot 1 watered")
	var next_day := screen.get_node("EDIT_ME/BottomActionHUD/Action_advance_day") as BaseButton
	var safety := 0
	while not bool(GameState.get_plot(1).get("ready_to_harvest", false)) and safety < 8:
		await _press(next_day, "Field / Next Day")
		if bool(GameState.get_plot(1).get("ready_to_harvest", false)):
			break
		water = screen.get_node("EDIT_ME/BottomActionHUD/ToolGroup/Action_water") as BaseButton
		await _press(water, "Field / Water next growth day")
		await _field_click_plot(screen, 1)
		next_day = screen.get_node("EDIT_ME/BottomActionHUD/Action_advance_day") as BaseButton
		safety += 1
	_assert_true(bool(GameState.get_plot(1).get("ready_to_harvest", false)), "Carrot never became harvestable")
	await _capture("07_FIELD_CARROT_READY.png")

	# Harvest.
	var crop_before_harvest := int(GameState.data["inventory"].get("crop_carrot", 0))
	var harvest := screen.get_node("EDIT_ME/BottomActionHUD/Action_harvest") as BaseButton
	_assert_true(not harvest.disabled, "Harvest control is disabled for ready carrot")
	await _press(harvest, "Field / Harvest")
	await _field_click_plot(screen, 1)
	plot = GameState.get_plot(1)
	_assert_true(int(GameState.data["inventory"].get("crop_carrot", 0)) == crop_before_harvest + 1, "Harvest did not increase crop_carrot inventory")
	_assert_true(String(plot.get("crop", "x")).is_empty(), "Harvest did not clear crop from Plot 1")
	_assert_true(int(plot.get("growth_stage", -1)) == 0 and not bool(plot.get("ready_to_harvest", true)), "Harvest did not reset Plot 1 growth/ready state")
	await _capture("08_FIELD_AFTER_HARVEST.png")

	# Back from Field -> Field Select -> Home, then Home -> Storage.
	var field_back := screen.get_node("EDIT_ME/FieldBackButton") as BaseButton
	await _press(field_back, "Field / Back")
	screen = await _assert_route("field_select")
	var back_hub := screen.find_child("BackToHub", true, false) as BaseButton
	await _press(back_hub, "Field Select / Back")
	screen = await _assert_route("hub")
	var home_storage := _find_home_nav_button(screen, 2)
	await _press(home_storage, "Home / Storage")
	screen = await _assert_route("storage")

	# Storage quantity, selection, sell, coin refresh.
	var carrot_card := screen.find_child("StorageAllCard_crop_carrot", true, false) as Control
	_assert_true(carrot_card != null and carrot_card.visible, "Storage carrot card is not visible")
	var carrot_select := screen.find_child("SelectAll_crop_carrot", true, false) as BaseButton
	await _press(carrot_select, "Storage / Select carrot")
	_assert_true(String(screen.get("selected_item")) == "crop_carrot", "Storage did not select crop_carrot")
	await _capture("09_STORAGE_CARROT.png")
	var coins_before_sell := int(GameState.data.get("coins", 0))
	var carrots_before_sell := int(GameState.data["inventory"].get("crop_carrot", 0))
	var sell := screen.find_child("StorageSellSelected", true, false) as BaseButton
	await _press(sell, "Storage / Sell carrot")
	var carrot_sell_value := int(FarmData.CROP_DEFINITIONS["carrot"]["sell_value"])
	_assert_true(int(GameState.data["inventory"].get("crop_carrot", 0)) == carrots_before_sell - 1, "Sell did not decrease carrot inventory")
	_assert_true(int(GameState.data.get("coins", 0)) == coins_before_sell + carrot_sell_value, "Sell did not increase coins by carrot sell value")
	var storage_coin := screen.find_child("HUD_CoinValue", true, false) as Label
	_assert_true(storage_coin != null and storage_coin.text == str(int(GameState.data.get("coins", 0))), "Storage coin HUD did not refresh")
	await _capture("10_STORAGE_AFTER_SELL.png")

	# Storage -> Shop via visible left navigation; buy carrot seeds.
	var storage_to_shop := screen.find_child("LeftNav_shop", true, false) as BaseButton
	await _press(storage_to_shop, "Storage / Shop navigation")
	screen = await _assert_route("shop")
	await _capture("11_SHOP.png")
	var coins_before_buy := int(GameState.data.get("coins", 0))
	var seeds_before_buy := int(GameState.data["inventory"].get("seed_carrot", 0))
	var buy_carrot := screen.find_child("BuySelectedProduct", true, false) as BaseButton
	await _press(buy_carrot, "Shop / Buy selected carrot seed")
	var carrot_shop_item: Dictionary = {}
	for item in FarmData.SHOP_ITEMS:
		if String(item.get("id", "")) == "seed_carrot":
			carrot_shop_item = item
			break
	_assert_true(int(GameState.data["inventory"].get("seed_carrot", 0)) == seeds_before_buy + int(carrot_shop_item.get("amount", 0)), "Shop buy did not refresh carrot seed quantity")
	_assert_true(int(GameState.data.get("coins", 0)) == coins_before_buy - int(carrot_shop_item.get("price", 0)), "Shop buy did not decrease/refresh coins")

	# Shop -> Hub, record exact persisted state, then Continue/Load through UI.
	var shop_back := screen.find_child("ShopBackToHub", true, false) as BaseButton
	await _press(shop_back, "Shop / Back to Hub")
	screen = await _assert_route("hub")
	var expected_day := int(GameState.data.get("day", 0))
	var expected_coins := int(GameState.data.get("coins", 0))
	var expected_inventory: Dictionary = GameState.data.get("inventory", {}).duplicate(true)
	var expected_plot: Dictionary = GameState.get_plot(1).duplicate(true)
	_assert_true(GameState.save("hub"), "Explicit final slot save failed")
	ScreenRouter.go("title")
	screen = await _assert_route("title")
	var continue_button := _find_title_button(screen, 0)
	await _press(continue_button, "Title / Continue")
	screen = await _assert_route("save")
	confirm = screen.find_child("Action_CONFIRM", true, false) as BaseButton
	await _press(confirm, "Save / Load Confirm")
	screen = await _assert_route("hub")
	_assert_true(int(GameState.data.get("day", -1)) == expected_day, "Reload did not preserve day")
	_assert_true(int(GameState.data.get("coins", -1)) == expected_coins, "Reload did not preserve coins")
	_assert_true(GameState.data.get("inventory", {}) == expected_inventory, "Reload did not preserve exact inventory")
	_assert_true(GameState.get_plot(1) == expected_plot, "Reload did not preserve exact Plot 1 state")
	await _capture("12_RELOADED_SAVE.png")

	# Explicit canonical route-instantiation proof for the required route chain.
	for route_id in ["title", "save", "hub", "field_select", "field", "storage", "shop", "hub"]:
		ScreenRouter.go(route_id)
		await _assert_route(route_id)

	if failures.is_empty():
		print("CURRENT_CORE_LOOP_TEST_PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			print("CURRENT_CORE_LOOP_TEST_FAIL: " + failure)
		get_tree().quit(1)
