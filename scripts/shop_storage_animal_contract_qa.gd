extends Node

# QA contract only. Every interaction below enters the actual Godot GUI pointer
# pipeline. Rich, empty and illness states are labelled fixtures, not earned play.
const MAIN = preload("res://scenes/main.tscn")
const WORLD_RULES = preload("res://scripts/world_systems.gd")
const ROOT := "res://REPORTS/GDD_CORRECTION_V2"
const CAPTURES := ROOT + "/CAPTURES"
const RESULTS := ROOT + "/06_QA/SHOP_STORAGE_ANIMAL_RESULTS.txt"
const CLEAN_STORAGE_BOARD := "res://assets/canonical_v2/03_ART_RUNTIME_READY/UI/PANELS/right_detail_panel_9slice.png"
const SELECTED_TAB_ART := "res://assets/canonical_v2/03_ART_RUNTIME_READY/UI/SHARED_BUTTONS/primary_medium/default.png"
const INACTIVE_TAB_ART := "res://assets/canonical_v2/03_ART_RUNTIME_READY/UI/TITLE_SAVE_HOME/title_button_frame_default.png"

var failures: Array[String] = []
var checks := 0
var host: Control
var screen: Node
var mouse_inside := false


func _ready() -> void:
	var isolated_root := OS.get_environment("MSF_TEST_SAVE_DIR")
	var qa_root := ProjectSettings.globalize_path(isolated_root).replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	var player_root := ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	if isolated_root.is_empty() or qa_root == player_root:
		push_error("Set MSF_TEST_SAVE_DIR to a separate QA directory before this test. Player saves must not be used.")
		get_tree().quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("This test requires rendered GUI and 1280x720 screenshots; headless is not visual proof.")
		get_tree().quit(2)
		return
	get_window().mouse_entered.connect(func() -> void: mouse_inside = true)
	get_window().mouse_exited.connect(func() -> void: mouse_inside = false)
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("GDD_CONTRACT: " + message)


func _settle(frames := 8) -> void:
	for _frame in range(frames):
		await get_tree().process_frame


func _route(id: String) -> Node:
	ScreenRouter.go(id)
	await _settle()
	screen = host.get_child(host.get_child_count() - 1)
	_check(ScreenRouter.current_screen == id, "Route: " + id)
	_check(screen.scene_file_path == ScreenRouter.SCREENS[id].resource_path, "Canonical scene: " + id)
	return screen


func _button(node_name: String) -> BaseButton:
	return screen.find_child(node_name, true, false) as BaseButton


func _click(point: Vector2) -> void:
	var viewport := get_viewport()
	if not mouse_inside:
		viewport.notify_mouse_entered()
		mouse_inside = true
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		event.position = point
		event.global_position = point
		viewport.push_input(event, true)
	await _settle()


func _press(node_name: String) -> bool:
	var button := _button(node_name)
	_check(button != null, "Control exists: " + node_name)
	if button == null: return false
	_check(button.is_visible_in_tree() and not button.disabled, "Visible usable control: " + node_name)
	if not button.is_visible_in_tree() or button.disabled: return false
	var fired := [false]
	button.pressed.connect(func() -> void: fired[0] = true, CONNECT_ONE_SHOT)
	await _click(button.get_global_rect().get_center())
	_check(fired[0], "Pointer activated: " + node_name)
	return fired[0]


func _capture(name: String) -> void:
	await _settle(2)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(image.get_size() == Vector2i(1280, 720), "1280x720 capture: " + name)
	_check(image.save_png(ProjectSettings.globalize_path(CAPTURES.path_join(name + ".png"))) == OK, "Saved screenshot: " + name)


func _within(child: Control, parent: Control, label: String, inset := 0.0) -> void:
	_check(child != null and parent != null, "Bounds nodes exist: " + label)
	if child == null or parent == null: return
	var outer := parent.get_global_rect().grow(-inset)
	var inner := child.get_global_rect()
	_check(outer.encloses(inner), "Serialized bounds inside parent: " + label)


func _tab_source_contract(selected_name: String, first_name: String) -> void:
	var selected := _button(selected_name) as TextureButton
	_check(selected != null, "Selected tab is painted TextureButton: " + selected_name)
	if selected != null:
		_check(selected.texture_normal != null and selected.texture_normal.resource_path == SELECTED_TAB_ART, "Selected tab uses approved green source, not tint only: " + selected_name)
	if first_name == selected_name: return
	var inactive := _button(first_name) as TextureButton
	_check(inactive != null, "First tab remains a painted inactive control: " + first_name)
	if inactive != null:
		_check(inactive.texture_normal != null and inactive.texture_normal.resource_path == INACTIVE_TAB_ART, "Inactive first tab uses approved cream source: " + first_name)


func _storage_frame_contract() -> void:
	_tab_source_contract("StorageCategory_" + String(screen.get("category")), "StorageCategory_All")
	_check(screen.find_children("Background", "TextureRect", true, false).size() == 1, "Storage has one canonical background")
	var boards := screen.find_children("StorageBoardArt", "", true, false)
	_check(boards.size() == 1, "Storage has one canonical board node")
	var board := screen.get_node_or_null("Header/StorageBoardArt") as NinePatchRect
	_check(board != null, "Storage board uses clean stretchable NinePatchRect, not baked category wells")
	if board != null:
		_check(board.texture != null and board.texture.resource_path == CLEAN_STORAGE_BOARD, "Storage board source is exact approved clean runtime panel, not a source sheet")
	for visual in screen.find_children("*", "TextureRect", true, false) + screen.find_children("*", "NinePatchRect", true, false):
		var texture := visual.get("texture") as Texture2D
		_check(texture == null or not texture.resource_path.ends_with("/storage_board.png"), "Old baked Storage board is not assigned directly: " + String(visual.name))
	var grid := screen.get_node_or_null("MainContent/ItemGrid_5x3")
	_check(grid != null, "Canonical Storage grid")
	if grid == null: return
	var first_rects: Dictionary = {}
	for slot in grid.get_children():
		if not slot is Control: continue
		# Direct children only: nested quantity-badge panels are not item cards.
		var cards := slot.find_children("Storage*Card*", "Panel", false, false)
		for card_node in cards:
			var card := card_node as Panel
			if card == null or not card.is_visible_in_tree(): continue
			var cells := slot.find_children("Art_storage_cell", "TextureRect", false, false)
			_check(cells.size() == 1, "One painted cell surface: " + String(slot.name))
			_check(card.get_theme_stylebox("panel") is StyleBoxEmpty, "No duplicate solid card frame: " + String(card.name))
			first_rects[String(slot.name)] = (slot as Control).get_global_rect()
	for _refresh_index in range(2):
		GameState.changed.emit()
		await _settle()
	for slot_name in first_rects:
		var slot := grid.get_node_or_null(slot_name) as Control
		_check(slot != null and slot.get_global_rect() == first_rects[slot_name], "Stable Storage position on refresh: " + slot_name)


func _storage_selected_check() -> void:
	var grid := screen.get_node_or_null("MainContent/ItemGrid_5x3")
	if grid == null: return
	# Selection must survive refresh, not just be correct on the click frame.
	for _refresh_index in range(2):
		GameState.changed.emit()
		await _settle()
	var selected_cards := 0
	for node in grid.find_children("Storage*Card*", "Panel", true, false):
		if not node.is_visible_in_tree() or not bool(node.get_meta("ui_selected", false)): continue
		selected_cards += 1
		var marker := node.get_node_or_null("UISelectedCheck") as Label
		_check(marker != null and marker.visible and marker.text == "✓", "Storage selection remains a check, not an item-name duplicate")
	_check(selected_cards == 1, "Exactly one selected Storage card")
	var selected_item := String(screen.get("selected_item"))
	_check(selected_item == "crop_carrot", "Actual selected Storage item remains carrot after refresh")


func _storage_category_contract() -> void:
	var grid := screen.get_node_or_null("MainContent/ItemGrid_5x3")
	if grid == null: return
	for definition in [["All", 10], ["Seeds", 3], ["Crops", 3], ["Other", 4]]:
		await _press("StorageCategory_" + String(definition[0]))
		_check(String(screen.get("category")) == String(definition[0]), "Storage category changes through real pointer")
		_tab_source_contract("StorageCategory_" + String(definition[0]), "StorageCategory_All")
		var visible_slots := 0
		for slot in grid.get_children():
			if slot is Control and slot.is_visible_in_tree(): visible_slots += 1
		_check(visible_slots == int(definition[1]), "Unused Storage cells hidden for " + String(definition[0]))
	await _press("StorageCategory_All")
	_tab_source_contract("StorageCategory_All", "StorageCategory_All")


func _animal_feedback_contract(locale: String) -> void:
	var info := screen.get_node_or_null("MainContent/AnimalInfoPanel") as Control
	var panel := screen.get_node_or_null("MainContent/AnimalInfoPanel/AnimalFeedbackPanel") as Control
	var label := screen.get_node_or_null("MainContent/AnimalInfoPanel/AnimalFeedbackPanel/FeedbackLabel") as Label
	_within(panel, info, "Animal feedback panel")
	_within(label, panel, "Animal feedback label")
	if label != null:
		_check(not label.text.is_empty(), "Animal illness feedback is visible")
		_check(not label.tooltip_text.is_empty() or not panel.tooltip_text.is_empty(), "Long illness explanation available via tooltip")
		_check(label.get_line_count() <= 3, "Illness visible copy uses no more than three lines")
		_check(label.get_minimum_size().y <= label.size.y + 1.0, "Illness label fits measured vertical extent")
	var name_label := screen.find_child("AnimalNameLabel", true, false) as Label
	if name_label != null:
		_check(name_label.text.to_lower().contains("bò") if locale == "vi" else name_label.text.to_lower().contains("cow"), "Selected cow name follows current locale")


func _animal_full_bars() -> void:
	for prefix in ["Hunger", "Cleanliness", "Happiness"]:
		var bar := screen.find_child(prefix + "Bar", true, false) as Control
		var fill: Control = null
		if bar != null: fill = bar.get_node_or_null("ProgressFill") as Control
		_within(fill, bar, prefix + " fill at 100%", 3.0)
		if bar != null and fill != null:
			_check(fill.size.x > 0 and fill.size.x <= bar.size.x - 6.0, "100% bar retains painted border: " + prefix)


func _run_shop(locale: String) -> void:
	await _route("shop")
	_tab_source_contract("Tab_Seeds", "Tab_Seeds")
	await _capture(locale + "_01_SHOP_SEEDS")
	var shop_id := screen.get_instance_id()
	await _press("Tab_Food")
	_check(ScreenRouter.current_screen == "shop" and screen.get_instance_id() == shop_id, "Food tab stays in canonical Shop")
	_check(String(screen.get("active_category")) == "food", "Food category is real UI state")
	_check(String(screen.get("selected_product")) == "animal_feed", "Food detail selects visible farm food")
	_tab_source_contract("Tab_Food", "Tab_Seeds")
	await _capture(locale + "_02_SHOP_FOOD")
	for definition in [["Tab_Expansion", "expansion", "03_SHOP_EXPANSION"], ["Tab_Rare", "rare", "04_SHOP_RARE"]]:
		await _press(String(definition[0]))
		_check(ScreenRouter.current_screen == "shop", "Shop " + String(definition[1]) + " never routes to dashboard")
		_check(screen.get_instance_id() == shop_id, "Same Shop screen remains visible: " + String(definition[1]))
		_check(String(screen.get("active_category")) == String(definition[1]), "Current Shop category: " + String(definition[1]))
		_tab_source_contract(String(definition[0]), "Tab_Seeds")
		_check(_button("BuySelectedProduct") != null, "Shop local purchase action remains present")
		await _capture(locale + "_" + String(definition[2]))


func _run_fresh(locale: String) -> void:
	GameState.new_state(1, false)
	await _run_shop(locale)
	await _route("storage")
	await _storage_frame_contract()
	await _storage_category_contract()
	await _press("SelectAll_crop_carrot")
	await _storage_selected_check()
	await _capture(locale + "_05_STORAGE_FRESH")
	await _route("animal")
	_check(String(screen.get("selected_species")) == "cloud_chicken", "Fresh barn starts on owned chicken")
	_tab_source_contract("AnimalSpecies_chicken", "AnimalSpecies_chicken")
	await _capture(locale + "_06_ANIMAL_CHICKEN")
	var before := GameState.data.duplicate(true)
	await _press("AnimalSpecies_cow")
	_check(ScreenRouter.current_screen == "animal" and String(screen.get("selected_species")) == "cow", "Locked cow preview stays in Animal")
	_tab_source_contract("AnimalSpecies_cow", "AnimalSpecies_chicken")
	for action in ["feed_animals", "clean_animals", "pet_animals", "collect"]:
		var button := _button("AnimalAction_" + action)
		_check(button != null and button.disabled, "Locked cow care is disabled: " + action)
	var adopt := _button("AnimalAdoptSelected")
	_check(adopt != null and adopt.disabled, "Fresh cow adopt correctly reports existing prerequisites")
	_check(GameState.data == before, "Previewing locked cow does not grant ownership or mutate farm")
	await _capture(locale + "_07_ANIMAL_COW_LOCKED")


func _run_rich(locale: String) -> void:
	QARichFixture.apply()
	# Keep the labelled x999 inventory within the real warehouse limit. The
	# ten main Storage items and cow-specific test supplies remain rich; other
	# fixture stacks are empty instead of weakening the gameplay capacity rule.
	var retained_stacks := ["seed_carrot", "seed_tomato", "seed_pumpkin", "crop_carrot", "crop_tomato", "crop_pumpkin", "animal_feed", "medicine", "egg", "dragon_treat", "cow_feed", "milk", "medicine_fatigue"]
	for item in GameState.data.inventory:
		GameState.data.inventory[item] = 999 if item in retained_stacks else 0
	# The rich fixture otherwise already owns every dragon and egg. Make only
	# this offer eligible; never weaken the existing duplicate-purchase rules.
	var water_definition: Dictionary = GameState.world_config().eggs.water_egg
	GameState.data.inventory["water_egg"] = 0
	GameState.data.world.incubators.erase("water_egg")
	GameState.data.world.creatures.erase(String(water_definition.species))
	GameState.changed.emit()
	_check(WORLD_RULES.inventory_stacks(GameState.data) < WORLD_RULES.inventory_capacity(GameState.data), "Labelled rare purchase fixture has free capacity under existing warehouse rules")
	var egg_eligibility := GameState.world_action_info("buy_egg", "water_egg")
	_check(bool(egg_eligibility.get("ok", false)), "Labelled rare purchase fixture satisfies existing authority: " + String(egg_eligibility.get("reason", "")))
	await _route("shop")
	await _press("Tab_Rare")
	_tab_source_contract("Tab_Rare", "Tab_Seeds")
	await _press("SelectProduct_water_egg")
	var before_egg := int(GameState.data.inventory.get("water_egg", 0))
	var before_coins := int(GameState.data.coins)
	var price := int(GameState.world_config().eggs.water_egg.cost)
	await _press("BuySelectedProduct")
	_check(ScreenRouter.current_screen == "shop", "Rare egg purchase remains within Shop")
	_check(int(GameState.data.inventory.get("water_egg", 0)) == before_egg + 1 and int(GameState.data.coins) == before_coins - price, "Actual Shop rare purchase delegates exact egg rules")
	await _capture(locale + "_08_SHOP_RARE_PURCHASE_FIXTURE")
	await _route("storage")
	await _storage_frame_contract()
	await _press("SelectAll_crop_carrot")
	await _storage_selected_check()
	await _capture(locale + "_09_STORAGE_999_FIXTURE")
	await _route("animal")
	await _press("AnimalSpecies_cow")
	_check(String(screen.get("selected_species")) == "cow", "Owned cow selected with real pointer")
	_tab_source_contract("AnimalSpecies_cow", "AnimalSpecies_chicken")
	await _capture(locale + "_10_ANIMAL_COW_FIXTURE")
	var chicken_before: Dictionary = GameState.data.world.creatures.cloud_chicken.duplicate(true)
	var legacy_chicken_before: Dictionary = GameState.data.animal.duplicate(true)
	var chicken_food_before := int(GameState.data.inventory.get("animal_feed", 0))
	var grain_before := int(GameState.data.inventory.get("grain_feed", 0))
	var cow_before: Dictionary = GameState.data.world.creatures.cow.duplicate(true)
	var cow_food_before := int(GameState.data.inventory.get("cow_feed", 0))
	var energy_before := int(GameState.data.energy)
	await _press("AnimalAction_feed_animals")
	_check(int(GameState.data.inventory.get("cow_feed", 0)) == cow_food_before - 1, "Selected cow consumes exactly its own cow_feed")
	_check(int(GameState.data.world.creatures.cow.fullness) == mini(100, int(cow_before.fullness) + 30), "Selected cow fullness matches existing world food rule")
	await _press("AnimalAction_clean_animals")
	await _press("AnimalAction_pet_animals")
	_check(int(GameState.data.world.creatures.cow.cleanliness) == mini(100, int(cow_before.cleanliness) + 30), "Cow clean action updates cow")
	_check(int(GameState.data.world.creatures.cow.happiness) == mini(100, int(cow_before.happiness) + 25), "Cow pet action updates cow")
	_check(int(GameState.data.energy) == energy_before - 5, "Cow three care actions spend existing 2+2+1 energy")
	_check(GameState.data.world.creatures.cloud_chicken == chicken_before and GameState.data.animal == legacy_chicken_before, "Cow care does not mutate chicken meters/products")
	_check(int(GameState.data.inventory.get("animal_feed", 0)) == chicken_food_before and int(GameState.data.inventory.get("grain_feed", 0)) == grain_before, "Cow care never consumes chicken food")
	await _capture(locale + "_11_ANIMAL_COW_AFTER_CARE")
	# AnimalAdvanceDay is a hidden compatibility stub, not a player control.
	# Use the actual visible sidebar on Storage, then return through its Animal
	# button and select the cow again through the real GUI.
	await _route("storage")
	var day_before := int(GameState.data.day)
	await _press("LeftNav_RestNextDay")
	_check(int(GameState.data.day) == day_before + 1, "Visible sidebar Next Day advances exactly one day")
	await _press("LeftNav_animal")
	screen = host.get_child(host.get_child_count() - 1)
	_check(ScreenRouter.current_screen == "animal" and screen.scene_file_path == ScreenRouter.SCREENS.animal.resource_path, "Visible sidebar returns to canonical Animal")
	await _press("AnimalSpecies_cow")
	_tab_source_contract("AnimalSpecies_cow", "AnimalSpecies_chicken")
	_check(int(GameState.data.world.creatures.cow.products_ready) > 0, "Healthy cow produces actual milk on Next Day")
	var milk_before := int(GameState.data.inventory.get("milk", 0))
	var eggs_before := int(GameState.data.inventory.get("egg", 0))
	var ready := int(GameState.data.world.creatures.cow.products_ready)
	var chicken_before_collect: Dictionary = GameState.data.world.creatures.cloud_chicken.duplicate(true)
	await _press("AnimalAction_collect")
	_check(int(GameState.data.inventory.get("milk", 0)) == milk_before + ready, "Cow collection grants only its own milk")
	_check(int(GameState.data.inventory.get("egg", 0)) == eggs_before and GameState.data.world.creatures.cloud_chicken == chicken_before_collect, "Cow milk collection does not harvest chicken eggs")
	await _capture(locale + "_12_ANIMAL_MILK_COLLECTED")
	var snapshot := GameState.data.duplicate(true)
	# Deliberately no explicit GameState.save() before reload.
	_check(GameState.load_slot(3), "Gameplay autosave reloads same rich QA slot without final manual save")
	_check(GameState.data.inventory == snapshot.inventory and int(GameState.data.coins) == int(snapshot.coins), "Cow/Shop inventory and coin autosave restore exactly")
	_check(GameState.data.world.creatures.cow == snapshot.world.creatures.cow, "Cow care/product state restores exactly")
	await _route("animal")
	await _press("AnimalSpecies_cow")
	_tab_source_contract("AnimalSpecies_cow", "AnimalSpecies_chicken")
	await _capture(locale + "_13_ANIMAL_RELOADED")
	# Explicit source/layout fixture, not earned disease or growth evidence.
	GameState.data.world.creatures.cow.disease = "fatigue"
	for key in ["fullness", "cleanliness", "happiness"]: GameState.data.world.creatures.cow[key] = 100
	GameState.changed.emit()
	await _settle()
	_animal_feedback_contract(locale)
	_animal_full_bars()
	await _capture(locale + "_14_ANIMAL_DISEASE_FULL_BARS_FIXTURE")
	# Chicken disease remains world-owned even though care meters are legacy.
	# This guards the real regression caught by the full integration suite.
	await _press("AnimalSpecies_chicken")
	GameState.data.world.creatures.cloud_chicken.disease = "fatigue"
	GameState.changed.emit()
	await _settle()
	var chicken_feedback := screen.get_node("MainContent/AnimalInfoPanel/AnimalFeedbackPanel/FeedbackLabel") as Label
	_check(chicken_feedback.text == tr("Đang bệnh: %s\nDùng %s.") % [tr("fatigue"), tr("Restorative Tonic")], "Chicken feedback reads world-owned disease and matching medicine")
	_check(chicken_feedback.tooltip_text == tr("Gà Mây bị %s, ngừng đẻ trứng.\nMở Bộ sưu tập → dùng thuốc đúng bệnh.") % tr("fatigue"), "Chicken retains complete disease-care directions in tooltip")
	_within(chicken_feedback, chicken_feedback.get_parent() as Control, "Chicken disease feedback")
	await _capture(locale + "_16_ANIMAL_CHICKEN_DISEASE_FIXTURE")
	await _route("storage")
	for item in GameState.data.inventory: GameState.data.inventory[item] = 0
	GameState.changed.emit()
	await _settle()
	await _storage_frame_contract()
	await _capture(locale + "_15_STORAGE_EMPTY_FIXTURE")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURES))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT + "/06_QA"))
	get_window().size = Vector2i(1280, 720)
	var main := MAIN.instantiate()
	add_child(main)
	host = main.get_node("ScreenHost")
	await _settle()
	for locale in ["vi", "en"]:
		UILocale.set_locale(locale)
		await _settle()
		await _run_fresh(locale)
		await _run_rich(locale)
	var report := FileAccess.open(RESULTS, FileAccess.WRITE)
	report.store_line("SHOP_STORAGE_ANIMAL_CONTRACT_QA_PASS" if failures.is_empty() else "SHOP_STORAGE_ANIMAL_CONTRACT_QA_FAIL")
	report.store_line("Assertions: %d" % checks)
	report.store_line("Save root: " + OS.get_environment("MSF_TEST_SAVE_DIR"))
	report.store_line("GUI: Viewport.push_input; no signal fallback for purchase/care/navigation.")
	report.store_line("Fixtures: Rich currency/ownership; x999 limited to ten main Storage items + cow_feed/milk/medicine_fatigue, other stacks empty; water egg/species/incubator absent for eligible purchase. Disease/full-bars and empty inventory are labelled explicitly.")
	report.store_line("VISUAL REVIEW: REQUIRED. Bounds/logic assertions do not approve art or full-screen usability.")
	for failure in failures: report.store_line(failure)
	report.close()
	print("SHOP_STORAGE_ANIMAL_CONTRACT_QA_PASS" if failures.is_empty() else "SHOP_STORAGE_ANIMAL_CONTRACT_QA_FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)
