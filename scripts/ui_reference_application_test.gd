extends Node

const MAIN_SCENE = preload("res://scenes/main.tscn")
const CAPTURE_DIR := "res://REPORTS/UI_REFERENCE_APPLICATION_QA"

var failures: Array[String] = []
var main: Control
var host: Control


func _ready() -> void:
	print("UI_REFERENCE_APPLICATION_TEST_START")
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("UI REFERENCE ASSERTION FAILED: " + message)


func _settle(frames := 8) -> void:
	for _frame in range(frames):
		await get_tree().process_frame


func _screen() -> Node:
	return host.get_child(host.get_child_count() - 1) if host != null and host.get_child_count() > 0 else null


func _capture(file_name: String) -> void:
	await _settle(3)
	var image := get_viewport().get_texture().get_image()
	if image == null:
		_check(false, "Viewport capture unavailable for " + file_name)
		return
	var error := image.save_png(ProjectSettings.globalize_path(CAPTURE_DIR.path_join(file_name)))
	_check(error == OK, "Could not save " + file_name)


func _press(button: BaseButton, label: String, allow_disabled := false) -> void:
	_check(button != null, "Missing button " + label)
	if button == null:
		return
	_check(allow_disabled or not button.disabled, label + " unexpectedly disabled")
	if button.disabled:
		return
	button.pressed.emit()
	await _settle()


func _run() -> void:
	print("UI_REFERENCE_APPLICATION_TEST_RUNNING")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
	main = MAIN_SCENE.instantiate()
	add_child(main)
	await _settle()
	host = main.get_node("ScreenHost") as Control
	GameState.new_state(3, false)
	GameState.data["coins"] = 400

	ScreenRouter.go("shop")
	print("UI_REFERENCE_APPLICATION_TEST_SHOP")
	await _settle()
	var shop := _screen()
	_check(shop != null and shop.scene_file_path == "res://scenes/screens/06_shop.tscn", "Canonical Shop was not routed")
	var carrot_slot := shop.find_child("ProductSlot01", true, false) as Control
	var tomato_slot := shop.find_child("ProductSlot02", true, false) as Control
	var carrot_instance := carrot_slot.get_instance_id()
	_check(bool(carrot_slot.get_meta("ui_selected", false)), "Default Shop selection is not visible")
	_check(bool(tomato_slot.get_meta("ui_locked", false)), "Locked Tomato card has no visible state")
	_check(tomato_slot.get_node_or_null("UIStateLockBadge") != null, "Locked Tomato badge missing")
	await _capture("UI_REF_01_SHOP_DEFAULT.png")

	await _press(shop.find_child("SelectProduct_seed_tomato", true, false) as BaseButton, "Tomato select")
	_check(bool(tomato_slot.get_meta("ui_selected", false)), "Shop selection did not move to Tomato")
	_check((shop.find_child("BuySelectedProduct", true, false) as BaseButton).disabled, "Locked Tomato Buy action is enabled")
	await _capture("UI_REF_02_SHOP_SELECTED_LOCKED.png")

	await _press(shop.find_child("SelectProduct_seed_carrot", true, false) as BaseButton, "Carrot select")
	var seeds_before := int(GameState.data["inventory"].get("seed_carrot", 0))
	var coins_before := int(GameState.data.get("coins", 0))
	await _press(shop.find_child("BuySelectedProduct", true, false) as BaseButton, "Buy selected Carrot")
	_check(int(GameState.data["inventory"].get("seed_carrot", 0)) == seeds_before + 3, "Shop purchase did not update inventory")
	_check(int(GameState.data.get("coins", 0)) == coins_before - 12, "Shop purchase did not update coins")
	_check(carrot_slot.get_instance_id() == carrot_instance, "Shop rebuilt its card tree instead of updating in place")
	_check(carrot_slot.find_children("UIStateFrame", "Panel", false, false).size() == 1, "Shop duplicated card-state frame")
	await _capture("UI_REF_03_SHOP_AFTER_BUY.png")

	GameState.data["inventory"]["crop_carrot"] = 2
	GameState.data["inventory"]["medicine"] = 1
	ScreenRouter.go("storage")
	print("UI_REFERENCE_APPLICATION_TEST_STORAGE")
	await _settle()
	var storage := _screen()
	_check(storage != null and storage.scene_file_path == "res://scenes/screens/07_storage.tscn", "Canonical Storage was not routed")
	var seed_card := storage.find_child("StorageCard_seed_carrot", true, false) as Control
	var crop_card := storage.find_child("StorageAllCard_crop_carrot", true, false) as Control
	var crop_instance := crop_card.get_instance_id()
	_check(bool(seed_card.get_meta("ui_selected", false)), "Default Storage selection is not visible")
	await _capture("UI_REF_04_STORAGE_DEFAULT.png")

	await _press(storage.find_child("SelectAll_crop_carrot", true, false) as BaseButton, "Storage Carrot select")
	_check(bool(crop_card.get_meta("ui_selected", false)), "Storage selection did not move to Carrot")
	_check(not (storage.find_child("StorageSellSelected", true, false) as BaseButton).disabled, "Storage Sell is disabled for available crop")
	await _capture("UI_REF_05_STORAGE_SELECTED.png")

	coins_before = int(GameState.data.get("coins", 0))
	await _press(storage.find_child("StorageSellSelected", true, false) as BaseButton, "Sell selected Carrot")
	_check(int(GameState.data["inventory"].get("crop_carrot", 0)) == 1, "Storage sell did not decrement inventory")
	_check(int(GameState.data.get("coins", 0)) > coins_before, "Storage sell did not increment coins")
	_check(crop_card.get_instance_id() == crop_instance, "Storage rebuilt its card tree instead of updating in place")
	_check(crop_card.find_children("UIStateFrame", "Panel", false, false).size() == 1, "Storage duplicated card-state frame")
	await _capture("UI_REF_06_STORAGE_AFTER_SELL.png")

	if failures.is_empty():
		print("UI_REFERENCE_APPLICATION_TEST_PASS")
	else:
		for failure in failures:
			print("UI_REFERENCE_APPLICATION_TEST_FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)
