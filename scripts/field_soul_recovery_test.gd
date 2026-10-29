extends Node

const SCREEN = preload("res://scenes/screens/05_field_gameplay.tscn")
const Geometry = preload("res://v7/runtime/field_projection_v7_2.gd")
const Assets = preload("res://scripts/ui_asset_registry.gd")
const SaveServiceClass = preload("res://scripts/save_service.gd")
const OUTPUT_DIR := "res://REPORTS/FIELD_SOUL_V12_QA"

var failures: Array[String] = []
var screen: Control
var root_window: Window


func _ready() -> void:
	root_window = get_tree().root
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("FIELD SOUL ASSERTION FAILED: " + message)


func _settle(frames := 6) -> void:
	for _frame in range(frames):
		await get_tree().process_frame


func _capture(file_name: String) -> void:
	await _settle(2)
	var image := root_window.get_texture().get_image()
	_check(image != null, "Viewport capture unavailable for " + file_name)
	if image != null:
		_check(image.get_size() == Vector2i(1280, 720), "Capture is not 1280x720: " + file_name)
		_check(image.save_png(OUTPUT_DIR.path_join(file_name)) == OK, "Could not save " + file_name)


func _actor() -> Node:
	return screen.get_node_or_null("EDIT_ME/FieldArea/WorldRenderer/V73FieldRenderer/FieldCropDepthWorld/RuntimeFarmerAtEditableAnchor")


func _animation_name() -> String:
	var actor := _actor()
	return actor.current_animation_name() if actor != null and actor.has_method("current_animation_name") else ""


func _label_text(path: String) -> String:
	var label := screen.get_node_or_null(path) as Label
	return label.text if label != null else ""


func _check_english_production_ui() -> void:
	_check(_label_text("EDIT_ME/FieldLabel/FieldTitle") == "FARM", "Field header is not the production title")
	_check(not (screen.get_node("EDIT_ME/FieldLabel/FieldSubtitle") as Label).visible, "Retired Field subtitle is still visible")
	_check(_label_text("EDIT_ME/FieldBackButton/Caption") == "BACK", "Back button is not English")
	var captions := {
		"EDIT_ME/BottomActionHUD/ToolGroup/Action_till/Caption": "TILL",
		"EDIT_ME/BottomActionHUD/ToolGroup/Action_seed/Caption": "PLANT",
		"EDIT_ME/BottomActionHUD/ToolGroup/Action_water/Caption": "WATER",
		"EDIT_ME/BottomActionHUD/ToolGroup/Action_fertilize/Caption": "FERTILIZE",
		"EDIT_ME/BottomActionHUD/Action_harvest/Caption": "HARVEST",
		"EDIT_ME/BottomActionHUD/Action_advance_day/Caption": "NEXT DAY",
	}
	for path in captions:
		_check(_label_text(path) == captions[path], "Action caption mismatch: " + path)
	_check(_label_text("EDIT_ME/BottomActionHUD/ToolGroup/Action_seed/SeedPickerAnchor/SeedPickerGroup/Title") == "CHOOSE SEED", "Seed Picker title is not English")
	_check(_label_text("EDIT_ME/TopHUD/HUD_DaySeasonLabel").begins_with("DAY "), "Day HUD is not English")
	_check(_label_text("EDIT_ME/TopHUD/HUD_DaySeasonLabel").contains("SPRING"), "Season HUD is not English")
	_check(_label_text("EDIT_ME/TopHUD/HUD_CoinValue").begins_with("COINS"), "Coin HUD is not English")
	_check(_label_text("EDIT_ME/TopHUD/HUD_EnergyValue").begins_with("ENERGY"), "Energy HUD is not English")
	_check(screen.call("_locked_crop_tooltip", "tomato") == "Complete The First Order to unlock Tomato.", "Tomato lock message is not English")
	_check(screen.call("_locked_crop_tooltip", "pumpkin") == "Complete A New Crop to unlock Pumpkin.", "Pumpkin lock message is not English")
	var visible_copy := "%s\n%s\n%s\n%s" % [
		_label_text("EDIT_ME/FieldLabel/FieldTitle"),
		_label_text("EDIT_ME/FieldLabel/FieldSubtitle"),
		_label_text("EDIT_ME/CropInfoPanel/LifecycleLabel"),
		_label_text("EDIT_ME/CropInfoPanel/DetailLabel"),
	]
	for retired_word in ["GỢI Ý", "Cà rốt", "Chưa cuốc", "Ngày mới", "Thu hoạch"]:
		_check(not visible_copy.contains(retired_word), "Vietnamese Field copy remains visible: " + retired_word)


func _expect_action(action: String, expected_animation: String, capture_name := "") -> void:
	screen.call("qa_trigger_action", action)
	await _settle(3)
	_check(_animation_name() == expected_animation, "%s did not trigger %s animation" % [action, expected_animation])
	if not capture_name.is_empty():
		await _capture(capture_name)
	await _settle(62)
	_check(_animation_name() == "idle", "%s did not return to idle" % action)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	root_window.size = Vector2i(1280, 720)
	GameState.save_service = SaveServiceClass.new("user://field_soul_recovery_test")
	GameState.new_state(1, false)
	GameState.data["energy"] = 100
	GameState.data["inventory"]["seed_carrot"] = 9
	GameState.data["selected_plot"] = 1
	var state_before_scene: Dictionary = GameState.data.duplicate(true)

	screen = SCREEN.instantiate()
	root_window.add_child(screen)
	await _settle(10)
	_check(GameState.data == state_before_scene, "Visual-only Field initialization changed gameplay state")
	_check(screen.scene_file_path == "res://scenes/screens/05_field_gameplay.tscn", "Canonical Field scene did not load")
	_check(GameState.data.get("field_plots", []).size() == 12, "Current 12-plot runtime was not preserved")
	_check_english_production_ui()
	_check(_label_text("EDIT_ME/CropInfoPanel/DetailLabel").contains("TIP   Select a plot, then press TILL."), "Initial Till guidance is not English")

	var renderer := screen.get_node_or_null("EDIT_ME/FieldArea/WorldRenderer/V73FieldRenderer")
	_check(renderer != null, "Runtime Field renderer is missing")
	if renderer != null:
		_check(renderer.get_node("FieldBedWorld").get_child_count() == 12, "Runtime does not present 12 plot beds")
	for plot_id in range(1, 13):
		var coord := Geometry.grid_coord(plot_id)
		_check(Geometry.hit_test_plot(Geometry.cell_center(coord.x, coord.y)) == plot_id, "Plot hit-test mismatch for %d" % plot_id)

	var actor := _actor()
	_check(actor != null, "Runtime farmer actor is missing")
	var animated_sprite := actor.get_node_or_null("CanonicalFarmerAnimatedSprite") as AnimatedSprite2D if actor != null else null
	_check(animated_sprite != null, "Farmer is not using AnimatedSprite2D")
	for action_name in ["idle", "hoe", "plant", "water", "fertilize", "harvest"]:
		var frames := Assets.farmer_frames(action_name)
		_check(frames != null and frames.get_frame_count(action_name) == 10, "%s frames are missing" % action_name)
	_check(_animation_name() == "idle", "Farmer did not enter idle animation")

	var crop_panel := screen.get_node("EDIT_ME/CropInfoPanel") as Control
	var bottom_hud := screen.get_node("EDIT_ME/BottomActionHUD") as Control
	var back := screen.get_node("EDIT_ME/FieldBackButton") as Control
	var title := screen.get_node("EDIT_ME/FieldLabel") as Control
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(1280, 720))
	_check(viewport_rect.encloses(crop_panel.get_global_rect()), "CropInfoPanel leaves the viewport")
	_check(viewport_rect.encloses(bottom_hud.get_global_rect()), "BottomActionHUD leaves the viewport")
	_check(crop_panel.size.x <= 193.0 and crop_panel.size.y <= 343.0, "CropInfoPanel does not match the V2 pixel map")
	_check(bottom_hud.size.y <= 109.0, "BottomActionHUD does not match the V2 pixel map")
	_check(not back.get_global_rect().intersects(title.get_global_rect()), "Back button and Field title overlap")
	_check(not crop_panel.get_global_rect().intersects(Rect2(Vector2(214, 268), Vector2(740, 290))), "Context panel obstructs projected field")
	_check(screen.get_node("EDIT_ME/TopHUD/HUD_DragonEnergyChip").visible == false, "Fake Long Qi chip remains visible on Field")
	var selected_coord := Geometry.grid_coord(1)
	var crop_anchor := Geometry.crop_anchor(selected_coord.x, selected_coord.y)
	_check(actor.position.distance_to(crop_anchor) >= 48.0, "Farmer does not stand beside the selected plot")
	_check(bool(actor.get_meta("visual_beside_plot", false)), "Farmer visual/logical anchors were not separated")
	for button_path in ["EDIT_ME/BottomActionHUD/ToolGroup/Action_till", "EDIT_ME/BottomActionHUD/ToolGroup/Action_seed", "EDIT_ME/BottomActionHUD/ToolGroup/Action_water", "EDIT_ME/BottomActionHUD/ToolGroup/Action_fertilize", "EDIT_ME/BottomActionHUD/Action_harvest", "EDIT_ME/BottomActionHUD/Action_advance_day", "EDIT_ME/FieldBackButton"]:
		var button := screen.get_node(button_path) as BaseButton
		_check(button.visible and button.mouse_filter != Control.MOUSE_FILTER_IGNORE and button.size.x >= 40.0 and button.size.y >= 40.0, "Action control is not practically clickable: " + button_path)

	await _capture("AFTER_V12_01_EMPTY.png")
	await _capture("AFTER_V12_02_SELECTED.png")

	# An invalid action must leave gameplay unchanged and never fake a success animation.
	var invalid_before: Dictionary = GameState.data.duplicate(true)
	screen.call("qa_trigger_action", "harvest")
	await _settle(5)
	_check(GameState.data == invalid_before, "Invalid harvest changed gameplay state")
	_check(_animation_name() == "idle", "Invalid action played a success animation")

	await _expect_action("till", "hoe")
	_check(_label_text("EDIT_ME/CropInfoPanel/DetailLabel").contains("TIP   Press PLANT, choose Carrot, then select a plot."), "Plant guidance is not English")
	await _capture("AFTER_V12_03_TILLED.png")

	screen.call("_toggle_seed_popup")
	await _settle(3)
	var popup := screen.get_node("EDIT_ME/BottomActionHUD/ToolGroup/Action_seed/SeedPickerAnchor/SeedPickerGroup") as Control
	_check(popup.visible, "Seed Picker did not open")
	_check(viewport_rect.encloses(popup.get_global_rect()), "Seed Picker leaves the viewport")
	_check(popup.size.x >= 250.0 and popup.size.y >= 100.0, "Seed Picker remains too small")
	for crop in ["carrot", "tomato", "pumpkin"]:
		var caption := popup.get_node("Seed_%s/Caption" % crop) as Label
		_check(caption != null and caption.text.contains(crop.to_upper()), "Seed Picker does not name " + crop)
	_check((popup.get_node("Seed_tomato/Caption") as Label).text.contains("LOCKED"), "Tomato locked state is not visible")
	_check((popup.get_node("Seed_pumpkin/Caption") as Label).text.contains("LOCKED"), "Pumpkin locked state is not visible")
	await _capture("AFTER_V12_08_SEED_PICKER.png")
	screen.call("_close_seed_popup")
	GameState.select_seed("carrot")
	await _settle(5)
	await _expect_action("seed", "plant")
	_check(_label_text("EDIT_ME/CropInfoPanel/DetailLabel").contains("TIP   Press WATER."), "Water guidance is not English")
	var planted_crop := screen.get_node_or_null("EDIT_ME/FieldArea/WorldRenderer/V73FieldRenderer/FieldCropDepthWorld/Crop_01_carrot")
	_check(planted_crop != null and planted_crop.get_node_or_null("ProductionCrop") != null and planted_crop.get_node_or_null("FrontSoilLip") != null, "Planted carrot is not composed as crop-only plus front soil lip")
	await _capture("AFTER_V12_04_PLANTED.png")

	await _capture("STRIP_WATER_1.png")
	screen.call("qa_trigger_action", "water")
	await _settle(2)
	_check(_animation_name() == "water", "Water did not trigger its animation")
	await _capture("STRIP_WATER_2.png")
	await _settle(7)
	await _capture("STRIP_WATER_3.png")
	await _settle(10)
	await _capture("STRIP_WATER_4.png")
	await _settle(48)
	_check(_animation_name() == "idle", "Water did not return to idle")
	await _capture("STRIP_WATER_5.png")
	await _capture("AFTER_V12_07_WET_SOIL.png")
	_check(_label_text("EDIT_ME/CropInfoPanel/DetailLabel").contains("TIP   Press NEXT DAY. Water again tomorrow."), "Next Day guidance is not English")
	await _expect_action("fertilize", "fertilize")
	screen.call("_on_advance_day_pressed")
	await _settle(12)
	_check(int(GameState.data["field_plots"][0]["growth_stage"]) >= 2, "Crop did not grow after watered/fertilized day advance")
	var growing_crop := screen.get_node_or_null("EDIT_ME/FieldArea/WorldRenderer/V73FieldRenderer/FieldCropDepthWorld/Crop_01_carrot")
	_check(growing_crop != null and growing_crop.get_node_or_null("ProductionCrop") != null and growing_crop.get_node_or_null("FrontSoilLip") != null, "Growing carrot lost the production crop/soil-lip layering")
	await _capture("AFTER_V12_05_GROWING.png")

	while not bool(GameState.data["field_plots"][0]["ready_to_harvest"]):
		if not bool(GameState.data["field_plots"][0]["watered_today"]):
			screen.call("qa_trigger_action", "water")
			await _settle(65)
		screen.call("_on_advance_day_pressed")
		await _settle(24)
	_check(bool(GameState.data["field_plots"][0]["ready_to_harvest"]), "Carrot never reached harvest-ready state")
	_check(_label_text("EDIT_ME/CropInfoPanel/LifecycleLabel") == "READY TO HARVEST", "Ready state is not English")
	_check(_label_text("EDIT_ME/CropInfoPanel/DetailLabel").contains("TIP   Carrot is ready. Press HARVEST."), "Harvest guidance is not English")
	await _capture("AFTER_V12_06_READY.png")
	await _capture("AFTER_V12_09_FULL_UI.png")

	var carrots_before := int(GameState.data["inventory"].get("crop_carrot", 0))
	await _capture("STRIP_HARVEST_1.png")
	screen.call("qa_trigger_action", "harvest")
	await _settle(2)
	_check(_animation_name() == "harvest", "Harvest did not trigger harvest animation")
	await _capture("STRIP_HARVEST_2.png")
	var reward_node := screen.get_node_or_null("EDIT_ME/FieldArea/WorldRenderer/V73FieldRenderer/FieldFXWorld/HarvestReward_01")
	_check(reward_node != null, "Harvest reward feedback is missing")
	if reward_node != null:
		var reward_label := reward_node.get_node_or_null("RewardQuantityLabel") as Label
		_check(reward_label != null and reward_label.text == "+1 Carrot", "Harvest reward copy is not '+1 Carrot'")
		_check(reward_node.get_node_or_null("RewardCropIcon") != null, "Harvest reward crop icon is missing")
		_check(reward_node.get_node_or_null("RewardBacking") != null, "Harvest reward backing is missing")
	await _capture("AFTER_V12_10_HARVEST_REWARD.png")
	await _settle(7)
	await _capture("STRIP_HARVEST_3.png")
	await _settle(7)
	await _capture("STRIP_HARVEST_4.png")
	await _settle(52)
	_check(_animation_name() == "idle", "Harvest did not return to idle")
	await _capture("STRIP_HARVEST_5.png")
	_check(int(GameState.data["inventory"].get("crop_carrot", 0)) == carrots_before + 1, "Harvest reward quantity is not the real +1 inventory mutation")
	_check(_label_text("EDIT_ME/CropInfoPanel/DetailLabel").contains("TIP   Carrot is in Storage. Open Orders to complete your first order."), "Post-harvest Order guidance is not English")

	if failures.is_empty():
		print("FIELD_SOUL_RECOVERY_TEST_PASS")
		get_tree().quit(0)
	else:
		print("FIELD_SOUL_RECOVERY_TEST_FAIL: ", failures)
		get_tree().quit(1)
