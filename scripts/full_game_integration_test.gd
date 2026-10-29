extends Node

# Real routed controls are exercised through synthetic Godot pointer events.
# These exercise GUI hit routing; they are not native human/OS mouse clicks.
# Earned-chain state is obtained from ordinary gameplay. Late-system fixture
# tests inject prerequisites explicitly and are reported separately.
const MAIN_SCENE = preload("res://scenes/main.tscn")
const FarmDataClass = preload("res://scripts/farm_data.gd")
const PixelMap = preload("res://v7/production/field_pixel_map_v2.gd")
const WorldDataClass = preload("res://scripts/world_data.gd")
const CAPTURE_DIR := "res://REPORTS/FULL_GAME_QA"
const RESULT_PATH := "res://REPORTS/FULL_GAME_INTEGRATION_RESULTS.txt"

var failures: Array[String] = []
var evidence: Array[String] = []
var assertions := 0
var main: Control
var host: Control
var cfg: Dictionary = {}
var _late_ui_state: Dictionary = {}
var _viewport_mouse_inside := false


func _ready() -> void:
	# Keep synthetic viewport entry in sync with actual window enter/exit.
	# Re-notifying an already-entered viewport on every click produces warnings.
	get_window().mouse_entered.connect(func() -> void: _viewport_mouse_inside = true)
	get_window().mouse_exited.connect(func() -> void: _viewport_mouse_inside = false)
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error("FULL GAME ASSERTION FAILED: " + message)


func _note(message: String) -> void:
	evidence.append(message)
	print("FULL_GAME_EVIDENCE: " + message)


func _settle(frames := 3) -> void:
	for _frame in range(frames):
		await get_tree().process_frame


func _screen() -> Node:
	return host.get_child(host.get_child_count() - 1) if host != null and host.get_child_count() > 0 else null


func _route(route: String) -> Node:
	ScreenRouter.go(route)
	await _settle(8)
	var screen := _screen()
	_check(ScreenRouter.current_screen == route, "Route did not enter " + route)
	_check(screen != null, "Route has no screen: " + route)
	if screen != null and ScreenRouter.SCREENS.has(route):
		_check(screen.scene_file_path == ScreenRouter.SCREENS[route].resource_path, "Noncanonical scene for " + route)
	return screen


func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless" or OS.get_environment("MSF_QA_CAPTURE") == "0":
		return
	await _settle(3)
	var image := get_viewport().get_texture().get_image()
	_check(image != null, "Capture unavailable: " + name)
	if image != null:
		_check(image.save_png(ProjectSettings.globalize_path(CAPTURE_DIR.path_join(name))) == OK, "Capture could not be saved: " + name)


func _press(button: BaseButton, label: String) -> bool:
	_check(button != null, "Missing visible control: " + label)
	if button == null:
		return false
	_check(button.is_visible_in_tree(), "Invisible control: " + label)
	_check(not button.disabled, "Unexpected disabled control: " + label)
	if button.disabled or not button.is_visible_in_tree():
		return false
	_check(not button.get_signal_connection_list("pressed").is_empty(), "No pressed callback: " + label)
	var ancestor := button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			(ancestor as ScrollContainer).ensure_control_visible(button)
		ancestor = ancestor.get_parent()
	await _settle(2)
	# Scroll/layout requests must reach the rendered canvas before hit testing.
	# Waiting is synchronization, not a retry or a fallback signal activation.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var observed := [false]
	button.pressed.connect(func() -> void: observed[0] = true, CONNECT_ONE_SHOT)
	var click_point := button.get_global_rect().get_center()
	await _mouse_click(click_point)
	await _settle(6)
	_check(bool(observed[0]), "Pointer hit did not activate visible button: " + label)
	if not bool(observed[0]):
		_note("POINTER FAILURE: %s; point=%s; rect=%s; visible=%s; disabled=%s; hovered=%s" % [label, click_point, button.get_global_rect(), button.is_visible_in_tree(), button.disabled, button.is_hovered()])
	return bool(observed[0])


func _mouse_click(point: Vector2) -> void:
	# Inject one coherent click into this viewport's actual GUI input pipeline.
	# Input.parse_input_event does not move the OS cursor; frame-separated input
	# allowed external mouse-exit/motion to interleave and invalidate GUI hover.
	# No retry, pressed-signal emission, or GameState action fallback is used.
	var viewport := get_viewport()
	if not _viewport_mouse_inside:
		viewport.notify_mouse_entered()
		_viewport_mouse_inside = true
	var motion := InputEventMouseMotion.new()
	motion.button_mask = 0
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.pressed = true
	down.position = point
	down.global_position = point
	viewport.push_input(down, true)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.button_mask = 0
	up.pressed = false
	up.position = point
	up.global_position = point
	viewport.push_input(up, true)
	await _settle(1)


func _data_snapshot() -> Dictionary:
	var snapshot: Dictionary = GameState.data.duplicate(true)
	# Status text is feedback; failed actions may explain why they were rejected.
	snapshot.erase("status_text")
	# SaveService adds envelope metadata to the disk payload, not gameplay data.
	snapshot.erase("saved_at_unix")
	snapshot.erase("last_screen")
	return snapshot


func _reject(action: String, id := "") -> void:
	var before := _data_snapshot()
	_check(not GameState.world_action(action, id, false), "Invalid action succeeded: %s/%s" % [action, id])
	_check(_data_snapshot() == before, "Rejected action changed persistent gameplay state: %s/%s" % [action, id])


func _world_press(route: String, group: String, id: String, action: String) -> bool:
	var screen := _screen() if ScreenRouter.current_screen == route else await _route(route)
	if screen == null:
		return false
	_check(screen.has_method("select_entry"), "World screen does not expose selection binding")
	if not screen.has_method("select_entry"):
		return false
	# Selection is programmatic to isolate the visible action callback. This is
	# never described as a native human mouse click or complete usability test.
	screen.call("select_entry", group, id)
	await _settle(3)
	var node_name := "WorldAction_%s_%s" % [action, id.replace(":", "_")]
	return await _press(screen.find_child(node_name, true, false) as BaseButton, node_name)


func _field_tool(action: String) -> void:
	var screen := _screen()
	var path := "EDIT_ME/BottomActionHUD/Action_%s" % action if action == "harvest" or action == "advance_day" else "EDIT_ME/BottomActionHUD/ToolGroup/Action_%s" % action
	await _press(screen.get_node_or_null(path) as BaseButton, "Field / " + action)


func _field_click(plot_id: int) -> void:
	var screen := _screen()
	var polygon := PixelMap.visual_interaction_polygon(plot_id)
	var center := Vector2.ZERO
	for vertex in polygon:
		center += vertex
	center /= maxf(1.0, float(polygon.size()))
	var area := screen.get_node("EDIT_ME/FieldArea") as Control
	screen.call("qa_reset_last_clicked_plot")
	await _mouse_click(area.get_global_transform() * center)
	await _settle(2)
	_check(int(screen.call("qa_last_clicked_plot_id")) == plot_id, "Real GUI pointer hit wrong Field plot %d" % plot_id)
	_check(int(screen.call("qa_world_rebuilds_per_action")) == 0, "Field full rebuild per action regressed")


func _grow_carrots(count: int, till_first: bool) -> void:
	await _route("field")
	if till_first:
		await _field_tool("till")
		for plot_id in range(1, count + 1):
			await _field_click(plot_id)
	await _field_tool("seed")
	var seed := _screen().get_node_or_null("EDIT_ME/BottomActionHUD/ToolGroup/Action_seed/SeedPickerAnchor/SeedPickerGroup/Seed_carrot") as BaseButton
	await _press(seed, "Field / choose Carrot")
	for plot_id in range(1, count + 1):
		await _field_click(plot_id)
		_check(String(GameState.get_plot(plot_id).get("crop", "")) == "carrot", "Carrot was not planted on plot %d" % plot_id)
	var safety := 0
	while not bool(GameState.get_plot(1).get("ready_to_harvest", false)) and safety < 10:
		await _field_tool("water")
		for plot_id in range(1, count + 1):
			if not bool(GameState.get_plot(plot_id).get("ready_to_harvest", false)):
				await _field_click(plot_id)
		await _field_tool("advance_day")
		safety += 1
	_check(bool(GameState.get_plot(1).get("ready_to_harvest", false)), "Earned Carrots failed to become ready")
	await _capture("02_EARNED_CARROTS_READY.png")
	await _field_tool("harvest")
	for plot_id in range(1, count + 1):
		await _field_click(plot_id)
		_check(String(GameState.get_plot(plot_id).get("crop", "x")).is_empty(), "Harvest did not reset plot %d" % plot_id)


func _earned_chain() -> void:
	_note("EARNED CHAIN: fresh slot 3; no inventory/coin/progression injection.")
	GameState.new_state(3, true)
	await _route("title")
	var title_buttons: Array[BaseButton] = []
	for child in _screen().get_children():
		if child is BaseButton:
			title_buttons.append(child)
	title_buttons.sort_custom(func(a: BaseButton, b: BaseButton) -> bool: return a.position.y < b.position.y)
	_check(title_buttons.size() >= 2, "Title New Game button unavailable")
	if title_buttons.size() >= 2:
		await _press(title_buttons[1], "Title / New Game")
	_check(ScreenRouter.current_screen == "save", "New Game did not open current Save")
	var slot_buttons: Array[BaseButton] = []
	for child in _screen().get_children():
		if child is BaseButton and not child.name.begins_with("Action_"):
			slot_buttons.append(child)
	_check(slot_buttons.size() >= 3, "Save slot 3 button unavailable")
	if slot_buttons.size() >= 3:
		await _press(slot_buttons[2], "Save / slot 3")
	await _press(_screen().find_child("Action_CONFIRM", true, false) as BaseButton, "Save / confirm")
	if ScreenRouter.current_screen == "save":
		await _press(_screen().find_child("Action_CONFIRM", true, false) as BaseButton, "Save / confirm overwrite isolated test slot")
	_check(ScreenRouter.current_screen == "hub", "Save confirm did not enter Home")
	_check(int(GameState.data.get("selected_slot", 0)) == 3, "Fresh game selected wrong isolated slot")
	_check(int(GameState.data.get("coins", -1)) == 400, "Approved fresh coins changed")
	_check(int(GameState.data.get("energy", -1)) == 100, "Approved fresh energy changed")
	_check(GameState.data["field_plots"].size() == 12, "Approved 12 plots changed")
	_check(int(GameState.data["inventory"].get("seed_carrot", -1)) == 6, "Approved initial Carrot seeds changed")
	_check(not GameState.is_crop_unlocked("tomato") and not GameState.is_crop_unlocked("pumpkin"), "Fresh crop progression unlocked early")
	await _capture("01_EARNED_NEW_GAME.png")
	await _grow_carrots(6, true)
	_check(int(GameState.data["inventory"].get("crop_carrot", 0)) == 6, "Earned harvest quantity mismatch")
	await _route("quest")
	await _press(_screen().find_child("SubmitActiveOrder", true, false) as BaseButton, "Orders / earned first order")
	_check(int(GameState.data.get("orders_done", 0)) == 1, "Earned Order 1 did not complete")
	_check(GameState.is_crop_unlocked("tomato"), "Earned Order 1 did not unlock Tomato")
	await _capture("03_EARNED_ORDER1_COMPLETE.png")
	await _route("storage")
	await _press(_screen().find_child("SelectAll_crop_carrot", true, false) as BaseButton, "Storage / select Carrot")
	for _sale in range(5):
		await _press(_screen().find_child("StorageSellSelected", true, false) as BaseButton, "Storage / earned Carrot sale")
	_check(int(GameState.data["inventory"].get("crop_carrot", -1)) == 0, "Earned Carrot sales failed")
	await _world_press("islands", "islands", "botanical", "unlock_island")
	_check(bool(GameState.world_state().get("unlocked_islands", {}).get("botanical", false)), "Earned Botanical unlock failed")
	await _capture("04_EARNED_BOTANICAL_UNLOCK.png")
	await _world_press("craft", "buildings", "alchemy", "build")
	_check(int(GameState.world_state().get("buildings", {}).get("alchemy", 0)) >= 1, "Earned Alchemy bench failed")
	await _world_press("craft", "items", "seed_mint", "buy_item")
	await _world_press("craft", "gardens", "mint", "plant_garden")
	var garden_safety := 0
	while not bool(GameState.world_state().get("gardens", {}).get("mint", {}).get("ready", false)) and garden_safety < 12:
		await _world_press("craft", "gardens", "mint", "water_garden")
		GameState.advance_day()
		await _settle(6)
		garden_safety += 1
	_check(bool(GameState.world_state().get("gardens", {}).get("mint", {}).get("ready", false)), "Earned Mint failed to grow from water/day actions")
	await _capture("05_EARNED_MINT_READY.png")
	await _world_press("craft", "gardens", "mint", "harvest_garden")
	_check(int(GameState.data["inventory"].get("mint", 0)) > 0, "Earned herb harvest failed")
	await _route("shop")
	await _press(_screen().find_child("SelectProduct_seed_carrot", true, false) as BaseButton, "Shop / Carrot selection")
	await _press(_screen().find_child("BuySelectedProduct", true, false) as BaseButton, "Shop / earned Carrot seed purchase")
	await _grow_carrots(3, false)
	var feed_before := int(GameState.data["inventory"].get("grain_feed", 0))
	await _world_press("craft", "recipes", "grain_feed", "craft")
	_check(int(GameState.data["inventory"].get("grain_feed", 0)) > feed_before, "Earned craft failed to create species food")
	await _capture("06_EARNED_CRAFT_COMPLETE.png")
	var before := _data_snapshot()
	_check(GameState.load_slot(3), "Earned-chain reload failed")
	_check(_data_snapshot() == before, "Normal gameplay autosave did not restore exact earned state")
	_note("EARNED CHAIN complete: 9 Carrots grown, Order 1, 5 sales, Botanical unlock, Alchemy, seeded/watered/grown/harvested Mint, crafted grain feed; reload without final save.")


func _fixture_new_game(label: String) -> void:
	_note("FIXTURE: " + label)
	GameState.new_state(3, false)
	GameState.data["coins"] = 100000
	GameState.data["orders_done"] = 3
	GameState.data["active_order_index"] = 0
	GameState.changed.emit()


func _empty_fixture_inventory() -> void:
	# Current valid saves contain all canonical base keys. Use zero quantities,
	# not missing keys; missing legacy keys deliberately receive load defaults.
	var inventory: Dictionary = FarmDataClass.create_initial_state()["inventory"].duplicate(true)
	for item in inventory: inventory[item] = 0
	GameState.data["inventory"] = inventory


func _negative_and_old_save_suite() -> void:
	_fixture_new_game("invalid-action rejection and legacy save normalization")
	GameState.data["orders_done"] = 0
	_reject("not_a_world_action", "missing")
	_reject("unlock_island", "missing")
	_reject("build", "missing")
	_reject("buy_item", "missing")
	_reject("craft", "missing")
	_reject("adopt", "missing")
	_reject("feed", "missing")
	_reject("incubate", "missing")
	_reject("claim_hatch", "missing")
	_reject("claim_event", "missing")
	_reject("unlock_island", "botanical")
	_reject("buy_egg", "water_egg")
	_reject("plant_garden", "mint")
	var before := _data_snapshot()
	for group in ["islands", "buildings", "creatures", "gardens", "recipes", "eggs", "events"]:
		for id in cfg.get(group, {}):
			GameState.world_action_info("unlock_island" if group == "islands" else "adopt", String(id))
	_check(_data_snapshot() == before, "UI eligibility queries mutated persistent state")
	var legacy: Dictionary = FarmDataClass.create_initial_state()
	legacy.erase("world")
	legacy["save_version"] = 2
	legacy["coins"] = 987
	legacy["energy"] = 32
	legacy["day"] = 19
	legacy["orders_done"] = 0
	legacy["long_khi"] = 7
	legacy["inventory"]["seed_tomato"] = 9
	legacy["inventory"]["seed_pumpkin"] = 7
	legacy["field_plots"][4]["crop"] = "carrot"
	legacy["field_plots"][4]["is_hoed"] = true
	legacy["field_plots"][4]["growth_stage"] = 2
	var save_result: Dictionary = GameState.save_service.save_current_slot(2, legacy, "field")
	_check(bool(save_result.get("ok", false)), "Legacy fixture could not be written into isolated slot 2")
	_check(GameState.load_slot(2), "Existing old slot failed to load after world extension")
	_check(int(GameState.data.get("coins", 0)) == 987 and int(GameState.data.get("energy", 0)) == 32, "Legacy coins/energy changed in migration")
	_check(int(GameState.data.get("day", 0)) == 19, "Legacy day changed in migration")
	_check(GameState.data.get("field_plots", []) == legacy["field_plots"], "Legacy plot data changed in migration")
	_check(GameState.data.get("inventory", {}).get("seed_tomato", 0) == 9 and GameState.data.get("inventory", {}).get("seed_pumpkin", 0) == 7, "Legacy player's locked crop seeds were deleted")
	_check(not GameState.select_seed("tomato", false) and not GameState.select_seed("pumpkin", false), "Old owned seeds bypassed crop progression locks")
	_check(not GameState.world_state().is_empty(), "Legacy save did not receive default world state")
	_check(GameState.dragon_energy() == 7 and int(GameState.world_state().get("dragon_energy", 0)) == 7, "Legacy top-level Long Khi was lost instead of migrated into the world wallet")
	_check(GameState.world_action("clean", "cloud_chicken", false), "Migrated Cloud Chicken state is not playable")
	var migrated := _data_snapshot()
	_check(GameState.load_slot(2), "Migrated gameplay autosave could not be reloaded")
	_check(_data_snapshot() == migrated, "Migrated normal gameplay autosave did not roundtrip exact state")
	_note("NEGATIVE/OLD SAVE: unknown/locked actions rejected without persistent state changes; pure eligibility queries; old day/coins/energy/plots/owned locked seeds preserved; migration autosave reload exact.")


func _verify_dragon_hud(expected: int) -> void:
	_check(GameState.dragon_energy() == expected, "Canonical Dragon Energy accessor does not match actual wallet")
	_check(int(GameState.data.get("long_khi", -1)) == expected, "Legacy wallet alias is stale after actual meta action")
	var screen := await _route("shop")
	var value := screen.find_child("HUD_DragonEnergyValue", true, false) as Label
	_check(value != null and value.text == str(expected), "Current Shop HUD is not bound to real Dragon Energy")
	await _route("hub")
	var home_match := false
	for label in _screen().find_children("*", "Label", true, false):
		if label.text == tr("Long Khí\n%d") % expected: home_match = true
	_check(home_match, "Current Home HUD is not bound to real Dragon Energy")
	await _route("islands")
	var world_value := _screen().get_node("WorldHUD/HUD_DragonEnergyValue") as Label
	_check(world_value != null and world_value.text == str(expected), "Current World HUD is not bound to real Dragon Energy")


func _shop_category_binding_suite() -> void:
	var screen := await _route("shop")
	await _press(screen.find_child("Tab_Food", true, false) as BaseButton, "Shop / Food tab")
	_check(String(screen.get("selected_product")) == "animal_feed", "Food tab left hidden seed selected")
	var panel := screen.find_child("ProductDetailPanel", true, false)
	var label := panel.find_child("ProductNameLabel", true, false) as Label
	_check(label != null and label.text == tr("Cloud Chicken Feed"), "Food tab detail does not identify its actual species-specific food")
	var description := panel.find_child("ProductDescriptionLabel", true, false) as Label
	_check(description != null and description.text == tr("Compatible food for Cloud Chicken only. Other species need their own food."), "Food detail conceals species-specific compatibility")
	var quantity := int(GameState.data["inventory"].get("animal_feed", 0))
	var coins := int(GameState.data["coins"])
	await _press(screen.find_child("BuySelectedProduct", true, false) as BaseButton, "Shop / buy Food tab item")
	_check(int(GameState.data["inventory"].get("animal_feed", 0)) == quantity + 2 and int(GameState.data["coins"]) == coins - 22, "Food tab Buy did not purchase the displayed item")
	await _press(screen.find_child("Tab_Medicine", true, false) as BaseButton, "Shop / Medicine tab")
	_check(String(screen.get("selected_product")) == "medicine", "Medicine tab left hidden food/seed selected")
	_check(label.text == tr("Energy Tonic"), "Medicine tab detail does not identify its actual energy tonic")
	_check(description != null and description.text == tr("Restores 25 farm energy when used from Storage. Does not cure creature disease."), "Medicine detail wrongly implies a universal creature cure")
	quantity = int(GameState.data["inventory"].get("medicine", 0))
	coins = int(GameState.data["coins"])
	await _press(screen.find_child("BuySelectedProduct", true, false) as BaseButton, "Shop / buy Medicine tab item")
	_check(int(GameState.data["inventory"].get("medicine", 0)) == quantity + 1 and int(GameState.data["coins"]) == coins - 28, "Medicine tab Buy did not purchase the displayed item")
	_note("SHOP BINDING: Food and Medicine tabs select/show/buy the same visible item; no stale hidden seed purchase.")


func _open_late_world_fixture() -> void:
	_fixture_new_game("late-game prerequisites: 100000 coins, 8 completed orders, explicit unlock materials; no claim this is earned pacing")
	GameState.data["orders_done"] = 8
	for item in {"ancient_fruit": 2, "mint": 20, "lavender": 20, "medicine_cold": 4, "dragon_crystal": 50, "stone": 99, "ice_shard": 20, "ember": 20, "snake_scale": 20}:
		GameState.data["inventory"][item] = {"ancient_fruit": 2, "mint": 20, "lavender": 20, "medicine_cold": 4, "dragon_crystal": 50, "stone": 99, "ice_shard": 20, "ember": 20, "snake_scale": 20}[item]
	_check(cfg.get("islands", {}).size() == 7, "GDD seven island definitions missing")
	for id in ["botanical", "dragon", "monster", "ice", "lava", "snake"]:
		var coins_before := int(GameState.data["coins"])
		_check(GameState.world_action("unlock_island", id, false), "Island could not be unlocked: " + id)
		_check(bool(GameState.world_state()["unlocked_islands"].get(id, false)), "Island unlock state missing: " + id)
		_check(int(GameState.data["coins"]) == coins_before - int(cfg["islands"][id]["cost"]), "Island payment wrong: " + id)
		_reject("unlock_island", id)
	_check(int(GameState.world_state()["buildings"].get("dragon_altar", 0)) == 1, "Dragon island did not establish altar")
	_check(int(GameState.data["inventory"].get("ancient_fruit", 0)) == 1, "Dragon altar did not consume exactly one fruit")
	for id in cfg["buildings"]:
		if id == "dragon_altar": continue
		var max_level := int(cfg["buildings"][id]["max_level"])
		while int(GameState.world_state()["buildings"].get(id, 0)) < max_level:
			_check(GameState.world_action("build", String(id), false), "Building upgrade failed: " + String(id))
			if not GameState.world_action_info("build", String(id)).get("ok", false): break
		_check(int(GameState.world_state()["buildings"].get(id, 0)) == max_level, "Building max level unreachable: " + String(id))
		_reject("build", String(id))
	_check(GameState.world_inventory_capacity() == 50, "Warehouse did not increase 20-stack capacity to 50")
	for id in cfg["islands"]:
		var item := String(cfg["islands"][id]["gather_item"])
		var before := int(GameState.data["inventory"].get(item, 0))
		_check(GameState.world_action("gather", String(id), false), "Unlocked island gather failed: " + String(id))
		_check(int(GameState.data["inventory"].get(item, 0)) == before + mini(3, int(cfg["islands"][id]["gather_amount"]) + 1), "Island gather/warehouse yield incorrect: " + String(id))
		_reject("gather", String(id))
	var energy_before := int(GameState.world_state()["dragon_energy"])
	_check(GameState.world_action("convert_fruit", "ancient_fruit", false), "Extra ancient fruit sink failed")
	_check(int(GameState.world_state()["dragon_energy"]) == energy_before + 5, "Fruit conversion reward not exact")
	_reject("convert_fruit", "ancient_fruit")
	await _verify_dragon_hud(energy_before + 5)
	await _shop_category_binding_suite()
	_note("FIXTURE ISLANDS/BUILDINGS: 7 islands, all upgrade levels, exact unlock spend, already-open rejection, daily gather limits, 20->50 storage capacity, extra-fruit recurring sink.")


func _garden_recipe_suite() -> void:
	GameState.data["energy"] = 100
	for id in cfg["gardens"]:
		_check(GameState.world_action("buy_item", String(cfg["gardens"][id]["seed"]), false), "Herb seed purchase failed: " + String(id))
		_check(GameState.world_action("plant_garden", String(id), false), "Herb planting failed: " + String(id))
		_reject("plant_garden", String(id))
	var dry_before: Dictionary = GameState.world_state()["gardens"].duplicate(true)
	GameState.advance_day(false)
	for id in cfg["gardens"]:
		_check(int(GameState.world_state()["gardens"][id]["growth"]) == int(dry_before[id]["growth"]), "Unwatered herb grew: " + String(id))
	for _day in range(6):
		for id in cfg["gardens"]:
			if not bool(GameState.world_state()["gardens"][id]["ready"]):
				_check(GameState.world_action("water_garden", String(id), false), "Herb watering failed: " + String(id))
				_reject("water_garden", String(id))
		GameState.advance_day(false)
	for id in cfg["gardens"]:
		_check(bool(GameState.world_state()["gardens"][id]["ready"]), "Herb did not reach ready stage: " + String(id))
		var item := String(cfg["gardens"][id]["item"])
		var before := int(GameState.data["inventory"].get(item, 0))
		_check(GameState.world_action("harvest_garden", String(id), false), "Herb harvest failed: " + String(id))
		_check(int(GameState.data["inventory"].get(item, 0)) == before + 3, "Garden upgrade yield wrong: " + String(id))
		_check(not GameState.world_state()["gardens"].has(id), "Herb garden did not reset after harvest: " + String(id))
		_reject("harvest_garden", String(id))
	for id in cfg["recipes"]:
		# Isolated ingredient fixture per recipe prevents inventory-capacity and
		# previously earned outputs from concealing consumption/reward errors.
		var recipe: Dictionary = cfg["recipes"][id]
		_empty_fixture_inventory()
		for item in recipe["ingredients"]:
			GameState.data["inventory"][item] = int(recipe["ingredients"][item])
		var coins_before := int(GameState.data["coins"])
		_check(GameState.world_action("craft", String(id), false), "Configured recipe could not be crafted: " + String(id))
		_check(int(GameState.data["coins"]) == coins_before - int(recipe["coins"]), "Recipe coin cost wrong: " + String(id))
		for item in recipe["ingredients"]:
			_check(int(GameState.data["inventory"].get(item, 0)) == 0, "Recipe ingredients not consumed exactly: %s/%s" % [id, item])
		if int(recipe["days"]) > 0:
			_reject("claim_craft", String(id))
			_reject("craft", String(id))
			for _day in range(int(recipe["days"])): GameState.advance_day(false)
			_check(GameState.world_action("claim_craft", String(id), false), "Queued recipe could not be claimed: " + String(id))
			_reject("claim_craft", String(id))
		_check(int(GameState.data["inventory"].get(String(recipe["output"]), 0)) == int(recipe["amount"]), "Recipe output not exact: " + String(id))
	_note("FIXTURE BOTANICAL/CRAFT: all 5 herbs reject dry growth/double watering; all 28 recipes consume exact ingredients/cost and grant exact output; timed queues cannot claim early/twice.")


func _set_creature_care(species: String, fullness := 60, clean := 60, happiness := 60, disease := "") -> void:
	var state: Dictionary = GameState.data["world"]["creatures"][species]
	state["fullness"] = fullness
	state["cleanliness"] = clean
	state["happiness"] = happiness
	state["disease"] = disease
	state["neglect_days"] = 0
	state["products_ready"] = 0
	if species == "cloud_chicken":
		GameState.data["animal"] = {"fullness": fullness, "cleanliness": clean, "happiness": happiness, "eggs_ready": 0}


func _egg_creature_suite() -> void:
	_empty_fixture_inventory()
	GameState.data["world"]["dragon_energy"] = 99
	for id in cfg["eggs"]:
		var egg: Dictionary = cfg["eggs"][id]
		var coins_before := int(GameState.data["coins"])
		var energy_before := int(GameState.world_state()["dragon_energy"])
		_check(GameState.world_action("buy_egg", String(id), false), "Elemental egg purchase failed: " + String(id))
		_check(int(GameState.data["coins"]) == coins_before - int(egg["cost"]), "Egg coin cost wrong: " + String(id))
		_check(int(GameState.world_state()["dragon_energy"]) == energy_before - int(egg["energy_cost"]), "Egg meta cost wrong: " + String(id))
		_reject("buy_egg", String(id))
		_check(GameState.world_action("incubate", String(id), false), "Egg incubation failed: " + String(id))
		_check(int(GameState.data["inventory"].get(id, 0)) == 0, "Incubation did not consume egg: " + String(id))
		_reject("claim_hatch", String(id))
		var safety := 0
		while not bool(GameState.world_state()["incubators"].get(id, {}).get("ready", false)) and safety < 8:
			GameState.advance_day(false)
			safety += 1
		_check(GameState.world_action("claim_hatch", String(id), false), "Egg hatch failed: " + String(id))
		_check(GameState.world_state()["creatures"].has(String(egg["species"])), "Hatch did not create expected species: " + String(id))
		_check(not GameState.world_state()["incubators"].has(id), "Hatch did not clear incubator: " + String(id))
		_reject("claim_hatch", String(id))
	for species in cfg["creatures"]:
		var definition: Dictionary = cfg["creatures"][species]
		if String(definition["kind"]) != "dragon" and species != "cloud_chicken":
			_check(GameState.world_action("adopt", String(species), false), "Animal/fish/monster adoption failed: " + String(species))
		_reject("adopt", String(species))
	for species in cfg["creatures"]:
		var definition: Dictionary = cfg["creatures"][species]
		GameState.data["energy"] = 100
		var wrong_food := "duck_feed" if definition["food"] != "duck_feed" else "pig_feed"
		_empty_fixture_inventory()
		GameState.data["inventory"]["medicine"] = 5
		GameState.data["inventory"][wrong_food] = 5
		_set_creature_care(String(species), 50, 50, 50)
		_reject("feed", String(species))
		var food := String(definition["food"])
		GameState.data["inventory"][food] = 2
		_check(GameState.world_action("feed", String(species), false), "Species food did not work: " + String(species))
		_check(int(GameState.data["inventory"][food]) == 1, "Species food consumption not exact: " + String(species))
		_check(GameState.world_action("clean", String(species), false), "Creature clean failed: " + String(species))
		_check(GameState.world_action("pet", String(species), false), "Creature pet failed: " + String(species))
		GameState.data["world"]["creatures"][species]["disease"] = String(definition["care_disease"])
		_reject("heal", String(species))
		var medicine := "medicine_" + String(definition["care_disease"])
		GameState.data["inventory"][medicine] = 1
		_check(GameState.world_action("heal", String(species), false), "Correct disease-specific medicine failed: " + String(species))
		_check(String(GameState.world_state()["creatures"][species]["disease"]).is_empty() and int(GameState.data["inventory"][medicine]) == 0, "Disease treatment state/consumption wrong: " + String(species))
		_check(GameState.world_action("assign_utility", String(species), false), "Healthy companion utility assignment failed: " + String(species))
		_check(String(GameState.world_state()["utility"].get(String(definition["utility"]), "")) == species, "Utility points at wrong species: " + String(species))
		_check(GameState.world_action("unassign_utility", String(species), false), "Utility removal failed: " + String(species))
		GameState.data["world"]["dragon_energy"] = 0
		var coins_before := int(GameState.data["coins"])
		GameState.advance_day(false)
		var ready := int(GameState.world_state()["creatures"][species]["products_ready"])
		_check(ready == 1, "Healthy creature did not produce one bounded product: " + String(species))
		var product := String(definition["product"])
		var before := int(GameState.world_state()["dragon_energy"]) if product == "dragon_energy" else int(GameState.data["inventory"].get(product, 0))
		_check(GameState.world_action("collect", String(species), false), "Creature output collection failed: " + String(species))
		var after := int(GameState.world_state()["dragon_energy"]) if product == "dragon_energy" else int(GameState.data["inventory"].get(product, 0))
		_check(after == before + 1, "Creature output quantity wrong: " + String(species))
		_check(int(GameState.data["coins"]) == coins_before, "Creature utility printed unrequested money: " + String(species))
		_reject("collect", String(species))
	_note("FIXTURE CREATURES: all 8 elemental eggs purchased/incubated/hatched through actual actions; all 20 species correctly reject wrong food and generic medicine, consume correct food/cure, produce one bounded product, assign/unassign utility.")


func _utility_season_event_suite() -> void:
	_empty_fixture_inventory()
	GameState.data["inventory"]["seed_carrot"] = 6
	GameState.data["energy"] = 100
	GameState.data["field_plots"] = FarmDataClass.create_initial_state()["field_plots"]
	GameState.data["world"]["utility"] = {}
	_set_creature_care("water_dragon", 100, 100, 100)
	_check(GameState.select_seed("carrot", false), "Utility test cannot select Carrot")
	for plot_id in range(1, 4):
		_check(GameState.apply_field_action_on_plot(plot_id, "till", false), "Utility test till failed")
		_check(GameState.apply_field_action_on_plot(plot_id, "seed", false), "Utility test plant failed")
	_check(GameState.world_action("assign_utility", "water_dragon", false), "Water Dragon assignment failed")
	GameState.advance_day(false)
	_check(bool(GameState.get_plot(1)["watered_today"]) and bool(GameState.get_plot(2)["watered_today"]) and not bool(GameState.get_plot(3)["watered_today"]), "Water Dragon did not respect two-plot watering cap")
	GameState.advance_day(false)
	_check(int(GameState.get_plot(1)["growth_stage"]) == 1 and int(GameState.get_plot(3)["growth_stage"]) == 0, "Water utility did not feed real crop growth")
	GameState.world_action("unassign_utility", "water_dragon", false)
	_set_creature_care("golem", 100, 100, 100)
	_check(GameState.world_action("assign_utility", "golem", false), "Golem gather assignment failed")
	var stones := int(GameState.data["inventory"].get("stone", 0))
	GameState.advance_day(false)
	_check(int(GameState.data["inventory"].get("stone", 0)) == stones + 1, "Golem did not gather exactly one building stone")
	GameState.world_action("unassign_utility", "golem", false)
	_set_creature_care("slime", 100, 100, 100)
	_check(GameState.world_action("assign_utility", "slime", false), "Slime seed recovery assignment failed")
	var seeds := int(GameState.data["inventory"].get("seed_mint", 0))
	GameState.advance_day(false)
	_check(int(GameState.data["inventory"].get("seed_mint", 0)) == seeds + 1, "Slime did not recover one medicinal seed")
	GameState.world_action("unassign_utility", "slime", false)
	_set_creature_care("snake", 100, 100, 100)
	_set_creature_care("duck", 0, 0, 20)
	GameState.data["world"]["creatures"]["duck"]["neglect_days"] = 2
	_check(GameState.world_action("assign_utility", "snake", false), "Serpent health utility assignment failed")
	GameState.advance_day(false)
	_check(String(GameState.world_state()["creatures"]["duck"]["disease"]).is_empty(), "Serpent did not prevent neglect disease")
	GameState.world_action("unassign_utility", "snake", false)
	GameState.advance_day(false)
	_check(String(GameState.world_state()["creatures"]["duck"]["disease"]) == "cold", "Unprotected neglect did not create the species disease")
	GameState.data["world"]["utility"] = {}
	GameState.data["world"]["buildings"]["forge"] = 0
	GameState.data["world"]["incubators"] = {"water_egg": {"progress": 0, "required": 4, "ready": false, "started_day": int(GameState.data["day"])}}
	GameState.advance_day(false)
	_check(int(GameState.world_state()["incubators"]["water_egg"]["progress"]) == 1, "Baseline incubation speed wrong")
	GameState.data["world"]["buildings"]["forge"] = 1
	GameState.advance_day(false)
	_check(int(GameState.world_state()["incubators"]["water_egg"]["progress"]) == 3, "Lava Forge did not add one bounded incubation progress")
	GameState.data["world"]["incubators"] = {}
	for pair in [[28, "spring", "summer"], [56, "summer", "autumn"], [84, "autumn", "winter"], [112, "winter", "spring"]]:
		GameState.data["day"] = pair[0]
		_check(GameState.current_season() == pair[1], "Season boundary before tick wrong")
		GameState.advance_day(false)
		_check(GameState.current_season() == pair[2], "Real advance-day failed to change season")
	GameState.data["day"] = 1
	GameState.data["world"]["buildings"]["icehouse"] = 0
	_set_creature_care("cloud_chicken", 80, 80, 80)
	GameState.advance_day(false)
	_check(int(GameState.data["animal"]["fullness"]) == 72 and int(GameState.data["animal"]["cleanliness"]) == 74, "Spring decay effects wrong")
	GameState.data["day"] = 29
	_set_creature_care("cloud_chicken", 80, 80, 80)
	GameState.advance_day(false)
	_check(int(GameState.data["animal"]["fullness"]) == 70, "Summer did not increase water/care demand")
	GameState.data["day"] = 85
	_set_creature_care("cloud_chicken", 80, 80, 80)
	GameState.advance_day(false)
	_check(int(GameState.data["animal"]["cleanliness"]) == 72, "Winter did not change care cost")
	GameState.data["world"]["buildings"]["icehouse"] = 1
	_set_creature_care("cloud_chicken", 80, 80, 80)
	GameState.advance_day(false)
	_check(int(GameState.data["animal"]["fullness"]) == 74 and int(GameState.data["animal"]["cleanliness"]) == 74, "Icehouse did not preserve care meters by two")
	GameState.data["world"]["claimed_events"] = []
	for id in cfg["events"]:
		var event: Dictionary = cfg["events"][id]
		var stat := String(event["stat"])
		if stat in ["day", "orders_done"]: GameState.data[stat] = int(event["target"])
		else: GameState.data["world"]["stats"][stat] = int(event["target"])
		for item in event.get("ingredients", {}): GameState.data["inventory"][item] = int(event["ingredients"][item])
		var coins_before := int(GameState.data["coins"])
		_check(GameState.world_action("claim_event", String(id), false), "Eligible event claim failed: " + String(id))
		_check(int(GameState.data["coins"]) == coins_before + int(event["coins"]), "Event coins wrong: " + String(id))
		_check(id in GameState.world_state()["claimed_events"], "Event claim was not recorded: " + String(id))
		_reject("claim_event", String(id))
	_note("FIXTURE UTILITIES/SEASONS/EVENTS: actual bounded watering feeds current crop growth; Golem stone/Slime seeds/Serpent disease protection; Forge incubation acceleration; four season boundaries via advance_day; Summer/Winter care effects; Icehouse preservation; all 10 event claims exact and nonrepeatable.")


func _treat_blessing_and_barn_suite() -> void:
	_empty_fixture_inventory()
	GameState.data["inventory"]["dragon_treat"] = 1
	GameState.data["energy"] = 50
	GameState.data["world"]["dragon_energy"] = 10
	_set_creature_care("water_dragon", 50, 60, 50)
	await _world_press("creatures", "creatures", "water_dragon", "treat")
	var dragon: Dictionary = GameState.world_state()["creatures"]["water_dragon"]
	_check(int(GameState.data["inventory"].get("dragon_treat", -1)) == 0, "Dragon Cake was not consumed by its current visible action")
	_check(int(dragon["happiness"]) == 75 and int(dragon["fullness"]) == 50, "Dragon Cake does not give exactly happiness-only feedback")
	_check(int(GameState.data["energy"]) == 49, "Dragon Cake care energy cost wrong")
	GameState.data["inventory"]["dragon_treat"] = 1
	_reject("treat", "cloud_chicken")
	GameState.data["energy"] = 60
	await _world_press("craft", "items", "dragon_energy", "dragon_blessing")
	_check(GameState.dragon_energy() == 5 and int(GameState.data["energy"]) == 80, "Dragon Blessing did not consume 5 meta energy and recover 20 normal energy")
	_reject("dragon_blessing", "dragon_energy")
	GameState.advance_day(false)
	_reject("dragon_blessing", "dragon_energy") # 100-energy next morning.
	GameState.data["energy"] = 70
	await _world_press("craft", "items", "dragon_energy", "dragon_blessing")
	_check(GameState.dragon_energy() == 0 and int(GameState.data["energy"]) == 90, "Next-day Dragon Blessing did not repeat with exact bounded spend")
	GameState.advance_day(false)
	GameState.data["energy"] = 50
	_reject("dragon_blessing", "dragon_energy") # Insufficient meta resource.
	GameState.data["world"]["dragon_energy"] = 5
	GameState.data["world"]["unlocked_islands"]["dragon"] = false
	_reject("dragon_blessing", "dragon_energy")
	GameState.data["world"]["unlocked_islands"]["dragon"] = true
	_set_creature_care("cloud_chicken", 60, 60, 60, "fatigue")
	GameState.changed.emit()
	var screen := await _route("animal")
	var message := screen.get_node_or_null("MainContent/AnimalInfoPanel/AnimalFeedbackPanel/FeedbackLabel") as Label
	if message != null:
		_note("BARN ACTUAL FEEDBACK: %s / TOOLTIP: %s" % [message.text.replace("\n", " | "), message.tooltip_text.replace("\n", " | ")])
	_check(message != null and message.tooltip_text == tr("Gà Mây bị %s, ngừng đẻ trứng.\nMở Bộ sưu tập → dùng thuốc đúng bệnh.") % tr("fatigue") and message.text == tr("Đang bệnh: %s\nDùng %s.") % [tr("fatigue"), tr("Restorative Tonic")], "Barn concealed current disease or did not direct to matching medicine")
	await _press(screen.find_child("AnimalCollectionAccess", true, false) as BaseButton, "Barn / Collection disease-care access")
	_check(ScreenRouter.current_screen == "creatures", "Barn medicine guidance route did not open collection")
	_note("LATE FEEDBACK/SINKS: visible Dragon Cake consumes one item, +25 happiness only, 1 energy, rejects non-dragon; visible Dragon Blessing costs5 for20 energy, once per day, rejects full-energy/insufficient-resource/locked-island cases; Barn exposes real disease and matching-medicine Collection route.")


func _pity_capacity_and_persistence_suite() -> void:
	_fixture_new_game("12 actual harvests for fruit guarantee; zero rare-item injection")
	GameState.data["inventory"]["seed_carrot"] = 20
	GameState.data["world"]["long_vein"] = 0
	GameState.data["world"]["stats"]["harvest"] = 0
	for _harvest in range(12):
		if not bool(GameState.get_plot(1)["is_hoed"]):
			_check(GameState.apply_field_action_on_plot(1, "till", false), "Pity-loop till failed")
		_check(GameState.apply_field_action_on_plot(1, "seed", false), "Pity-loop seed failed")
		while not bool(GameState.get_plot(1)["ready_to_harvest"]):
			_check(GameState.apply_field_action_on_plot(1, "water", false), "Pity-loop water failed")
			GameState.advance_day(false)
		_check(GameState.apply_field_action_on_plot(1, "harvest", false), "Pity-loop harvest failed")
	_check(int(GameState.world_state()["stats"]["harvest"]) == 12, "Real harvest counter does not match actual harvests")
	_check(int(GameState.data["inventory"].get("ancient_fruit", 0)) >= 1, "12 actual harvests did not guarantee an Ancient Dragon Fruit")
	_check(int(GameState.world_state()["long_vein"]) < 12, "Pity counter failed to reset after fruit")
	GameState.data["coins"] = 1000
	_empty_fixture_inventory()
	for index in range(20): GameState.data["inventory"]["qa_existing_stack_%d" % index] = 1
	_check(GameState.world_inventory_capacity() == 20, "Initial capacity not 20 distinct stacks")
	_reject("buy_item", "grain_feed")
	GameState.data["inventory"].erase("qa_existing_stack_19")
	_check(GameState.world_action("buy_item", "grain_feed", false), "Freeing a stack did not enable purchase")
	_check(GameState.world_action("buy_item", "grain_feed", false), "Existing stack quantity incorrectly blocked at capacity")
	var before := _data_snapshot()
	_check(GameState.load_slot(3), "Final normal-game autosave reload failed")
	_check(_data_snapshot() == before, "Exact world/state restore failed without explicit final save")
	_note("FIXTURE PITY/CAPACITY: 12 genuinely grown/harvested crops guarantee fruit; full 20-stack inventory rejects a new stack atomically; existing-stack purchase allowed; autosave roundtrip assertion evaluated (final result determines PASS).")


func _new_routes_and_ui_suite() -> void:
	for route in ["title", "save", "hub", "field_select", "field", "shop", "storage", "quest", "islands", "craft", "creatures", "events", "animal", "dragon", "settings"]:
		await _route(route)
		await _capture("UI_%s_CURRENT.png" % route.to_upper())
		_check(_screen().scene_file_path == ScreenRouter.SCREENS[route].resource_path, "Wrong routed UI scene: " + route)
	await _route("islands")
	await _press(_screen().find_child("WorldRoute_craft", true, false) as BaseButton, "World / Workshop route")
	_check(ScreenRouter.current_screen == "craft", "World Workshop route button failed")
	await _press(_screen().find_child("WorldRoute_creatures", true, false) as BaseButton, "World / Companions route")
	_check(ScreenRouter.current_screen == "creatures", "World Companion route button failed")
	await _press(_screen().find_child("WorldRoute_events", true, false) as BaseButton, "World / Calendar route")
	_check(ScreenRouter.current_screen == "events", "World Calendar route button failed")
	await _press(_screen().find_child("WorldBackHome", true, false) as BaseButton, "World / Home")
	_check(ScreenRouter.current_screen == "hub", "World Home return failed")
	# Restore the explicitly labelled late-system fixture, not the earned state.
	# Captures show mechanisms reached by validated actions above, with injected
	# prerequisite resources clearly called out rather than hidden as player work.
	GameState.data = _late_ui_state.duplicate(true)
	GameState.changed.emit()
	await _route("islands")
	_screen().call("select_entry", "islands", "ice")
	await _capture("LATE_FIXTURE_01_ICE_ISLAND_UNLOCKED.png")
	var recipe: Dictionary = cfg["recipes"]["rainbow_egg"]
	for item in recipe["ingredients"]:
		GameState.data["inventory"][item] = int(recipe["ingredients"][item])
	GameState.data["coins"] = maxi(1000, int(GameState.data["coins"]))
	await _world_press("craft", "recipes", "rainbow_egg", "craft")
	await _capture("LATE_FIXTURE_02_QUEUED_RAINBOW_EGG_RECIPE.png")
	_set_creature_care("water_dragon", 50, 60, 60)
	GameState.data["inventory"]["aquatic_feed"] = 2
	GameState.data["energy"] = 100
	await _world_press("creatures", "creatures", "water_dragon", "feed")
	await _capture("LATE_FIXTURE_03_WATER_DRAGON_CARE.png")
	var energy_before := GameState.dragon_energy()
	GameState.advance_day()
	await _world_press("creatures", "creatures", "water_dragon", "collect")
	await _verify_dragon_hud(energy_before + 1)
	await _route("dragon")
	await _capture("LATE_FIXTURE_04_DRAGON_UNLOCKED.png")
	_note("VISIBLE UI: new world-route buttons activated through Godot GUI mouse events; existing Animal/Dragon/Settings canonical scenes render; snapshots are evidence, not commercial visual PASS.")
	_note("LATE VISUAL FIXTURES: Ice Island unlocked, queued Rainbow Egg recipe, owned Water Dragon fed with its own food, canonical Dragon unlocked; prerequisite resources are labelled fixture setup.")


func _write_results() -> void:
	var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write full-game QA results")
		return
	file.store_line("FULL_GAME_INTEGRATION_TEST_%s" % ("PASS" if failures.is_empty() else "FAIL"))
	file.store_line("ASSERTIONS: %d" % assertions)
	file.store_line("VISIBLE CONTROL METHOD: Viewport.notify_mouse_entered + synchronous Viewport.push_input motion/down/up in local viewport coordinates at visible button or canonical plot polygon center; programmatic World list selection before action hit. No retries or signal fallback.")
	file.store_line("NATIVE HUMAN CLICK / COMMERCIAL VISUAL APPROVAL: NOT CLAIMED")
	file.store_line("ISOLATED SAVE ROOT: " + OS.get_environment("MSF_TEST_SAVE_DIR"))
	for line in evidence:
		file.store_line(line)
	for failure in failures:
		file.store_line("FAIL: " + failure)
	file.close()


func _run() -> void:
	if OS.get_environment("MSF_TEST_SAVE_DIR").is_empty():
		push_error("Set MSF_TEST_SAVE_DIR to an isolated QA directory before running. User saves must not be overwritten.")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
	get_window().size = Vector2i(1280, 720)
	main = MAIN_SCENE.instantiate()
	get_tree().root.add_child(main)
	await _settle(10)
	host = main.get_node("ScreenHost") as Control
	cfg = GameState.world_config()
	_check(not cfg.is_empty(), "World config empty or unreadable")
	await _earned_chain()
	_negative_and_old_save_suite()
	await _open_late_world_fixture()
	_garden_recipe_suite()
	_egg_creature_suite()
	await _treat_blessing_and_barn_suite()
	_utility_season_event_suite()
	_late_ui_state = GameState.data.duplicate(true)
	_pity_capacity_and_persistence_suite()
	await _new_routes_and_ui_suite()
	_write_results()
	if failures.is_empty():
		print("FULL_GAME_INTEGRATION_TEST_PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			print("FULL_GAME_INTEGRATION_TEST_FAIL: " + failure)
		get_tree().quit(1)

