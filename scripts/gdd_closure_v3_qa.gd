extends Node

# Additive V3 integration QA. Production callbacks are activated only by GUI input.
# Registry/catalog and rich ownership are labelled fixtures, never earned progress.
const MAIN = preload("res://scenes/main.tscn")
const RULES = preload("res://scripts/world_systems.gd")
const WORLD_DATA = preload("res://scripts/world_data.gd")
const ASSETS = preload("res://scripts/ui_asset_registry.gd")
const REPORT_ROOT := "res://REPORTS/GDD_CLOSURE_V3/06_QA"
const SELECTED_TAB_ART := "res://assets/canonical_v2/03_ART_RUNTIME_READY/UI/SHARED_BUTTONS/primary_medium/default.png"
const INACTIVE_TAB_ART := "res://assets/canonical_v2/03_ART_RUNTIME_READY/UI/TITLE_SAVE_HOME/title_button_frame_default.png"
const CLEAN_STORAGE_BOARD := "res://assets/canonical_v2/03_ART_RUNTIME_READY/UI/PANELS/right_detail_panel_9slice.png"
const CATEGORIES := ["All", "Seeds", "Crops", "Food", "Medicine", "Eggs", "Materials", "Other"]
const SPECIES_TABS := {"cloud_chicken": "AnimalSpecies_chicken", "cow": "AnimalSpecies_cow", "duck": "AnimalSpecies_duck", "pig": "AnimalSpecies_pig"}
const FOODS := {"cloud_chicken": "animal_feed", "cow": "cow_feed", "duck": "duck_feed", "pig": "pig_feed"}
const PRODUCTS := {"cloud_chicken": "egg", "cow": "milk", "duck": "duck_egg", "pig": "truffle"}
const SPECIES_NAMES := {"cloud_chicken": "Gà Mây", "cow": "Bò Đồng Cỏ", "duck": "Vịt Mây", "pig": "Heo Củ"}
const CARE_ACTIONS := {"feed_animals": "feed", "clean_animals": "clean", "pet_animals": "pet", "collect": "collect"}

var failures: Array[String] = []
var checks := 0
var captures: Array[String] = []
var notes: Array[String] = []
var run_root := ""
var capture_root := ""
var host: Control
var screen: Node
var mouse_inside := false


func _ready() -> void:
	var isolated_root := OS.get_environment("MSF_TEST_SAVE_DIR")
	var qa_root := ProjectSettings.globalize_path(isolated_root).replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	var player_root := ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	# Require a dedicated named fresh root; an ancestor of player saves is unsafe too.
	if isolated_root.is_empty() or qa_root == player_root or player_root.begins_with(qa_root + "/") or not qa_root.contains("gdd_closure_v3"):
		push_error("V3 QA requires a fresh MSF_TEST_SAVE_DIR containing gdd_closure_v3, separate from and not above player saves.")
		get_tree().quit(2)
		return
	for slot in range(1, 4):
		for suffix in ["", ".tmp", ".bak", ".deleted.bak"]:
			if FileAccess.file_exists(isolated_root.path_join(("my_sisters_farm_slot_%d.save" % slot) + suffix)):
				push_error("V3 QA refuses occupied saves, temporary files or backups. Supply a fresh test directory; prior test/player files are preserved.")
				get_tree().quit(2)
				return
	if DisplayServer.get_name() == "headless":
		push_error("V3 QA requires rendered GUI captures; headless output is not visual evidence.")
		get_tree().quit(2)
		return
	get_window().mouse_entered.connect(func() -> void: mouse_inside = true)
	get_window().mouse_exited.connect(func() -> void: mouse_inside = false)
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("GDD_CLOSURE_V3: " + message)


func _settle(frames := 6) -> void:
	for _frame in range(frames): await get_tree().process_frame


func _current_screen() -> Node:
	return host.get_child(host.get_child_count() - 1)


func _route(id: String) -> void:
	ScreenRouter.go(id)
	await _settle()
	screen = _current_screen()
	_check(ScreenRouter.current_screen == id, "Route: " + id)
	_check(screen.scene_file_path == ScreenRouter.SCREENS[id].resource_path, "Canonical serialized scene: " + id)


func _button(name: String) -> BaseButton:
	return screen.find_child(name, true, false) as BaseButton


func _page_size() -> int:
	var runtime_script: Script = screen.get_script()
	return int(runtime_script.get_script_constant_map().get("PAGE_SIZE", 0)) if runtime_script != null else 0


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


func _press_button(button: BaseButton, label: String) -> bool:
	_check(button != null, "Control exists: " + label)
	if button == null: return false
	_check(button.is_visible_in_tree() and not button.disabled, "Visible usable control: " + label)
	if not button.is_visible_in_tree() or button.disabled: return false
	var fired := [false]
	var witness := func() -> void: fired[0] = true
	button.pressed.connect(witness, CONNECT_ONE_SHOT)
	await _click(button.get_global_rect().get_center())
	if is_instance_valid(button) and button.pressed.is_connected(witness): button.pressed.disconnect(witness)
	_check(fired[0], "Actual GUI pointer activated: " + label)
	return fired[0]


func _press(name: String) -> bool:
	return await _press_button(_button(name), name)


func _disabled_noop(name: String, label: String) -> void:
	var button := _button(name)
	_check(button != null, "Disabled control exists: " + label)
	if button == null: return
	_check(button.is_visible_in_tree() and button.disabled, "Unavailable action visibly disabled: " + label)
	if not button.is_visible_in_tree() or not button.disabled: return
	var before := GameState.data.duplicate(true)
	await _click(button.get_global_rect().get_center())
	_check(GameState.data == before, "Disabled GUI click cannot mutate save state: " + label)


func _capture(name: String) -> void:
	await _settle(2)
	await RenderingServer.frame_post_draw
	var rendered := get_viewport().get_texture().get_image()
	_check(rendered != null, "Rendered capture exists: " + name)
	if rendered == null: return
	_check(rendered.get_size() == Vector2i(1280, 720), "1280x720 capture: " + name)
	var target := capture_root.path_join(name + ".png")
	_check(not FileAccess.file_exists(target), "Prior capture never overwritten: " + name)
	if FileAccess.file_exists(target): return
	_check(rendered.save_png(ProjectSettings.globalize_path(target)) == OK, "Capture saved: " + name)
	captures.append(target)


func _within(child: Control, parent: Control, label: String, inset := 0.0) -> void:
	_check(child != null and parent != null, "Bounds nodes exist: " + label)
	if child != null and parent != null:
		_check(parent.get_global_rect().grow(-inset).encloses(child.get_global_rect()), "Child fits authored parent: " + label)


func _tab_contract(selected_name: String, all_names: Array) -> void:
	for node_name in all_names:
		var tab := _button(String(node_name)) as TextureButton
		_check(tab != null, "Painted category/species tab: " + String(node_name))
		if tab == null: continue
		var expected := SELECTED_TAB_ART if String(node_name) == selected_name else INACTIVE_TAB_ART
		_check(tab.texture_normal != null and tab.texture_normal.resource_path == expected, "Actual selected/inactive tab source: " + String(node_name))


func _same_ids(actual: Array, expected: Array, label: String) -> void:
	var actual_sorted := actual.duplicate()
	var expected_sorted := expected.duplicate()
	actual_sorted.sort()
	expected_sorted.sort()
	_check(actual_sorted == expected_sorted, label)
	var unique: Array = []
	for id in actual:
		if not unique.has(id): unique.append(id)
	_check(unique.size() == actual.size(), "No duplicate IDs: " + label)


func _expected_catalog() -> Array:
	var result: Array = []
	for entry in FarmData.INVENTORY_CATALOG:
		if not result.has(String(entry["id"])): result.append(String(entry["id"]))
	var config := GameState.world_config()
	for table in ["items", "eggs"]:
		for id in config.get(table, {}):
			if not result.has(String(id)): result.append(String(id))
	for id in GameState.data.get("inventory", {}):
		if not result.has(String(id)): result.append(String(id))
	return result


func _expected_category(id: String) -> String:
	var config := GameState.world_config()
	if config.get("eggs", {}).has(id) or id in ["egg", "duck_egg"]: return "Eggs"
	if id.begins_with("seed_"): return "Seeds"
	if id.begins_with("crop_"): return "Crops"
	if id == "animal_feed": return "Food"
	if id == "medicine": return "Medicine"
	var group := String(config.get("items", {}).get(id, {}).get("group", ""))
	if group in ["Herb", "Animal Product"]: return "Crops"
	if group in ["Food", "Treat"]: return "Food"
	if group == "Medicine": return "Medicine"
	if group in ["Material", "Creature Material"]: return "Materials"
	return "Other"


func _expected_category_items(category: String) -> Array:
	var result: Array = []
	for id in _expected_catalog():
		if category == "All" or _expected_category(String(id)) == category: result.append(id)
	return result


func _amount(id: String) -> int:
	return GameState.dragon_energy() if id == "dragon_energy" else int(GameState.data.inventory.get(id, 0))


func _storage_card(slot: Node) -> Panel:
	var cards := slot.find_children("Storage*Card*", "Panel", false, false)
	return cards[0] as Panel if not cards.is_empty() else null


func _visible_storage_ids() -> Array:
	var result: Array = []
	var grid := screen.get_node_or_null("MainContent/ItemGrid_5x3")
	if grid == null: return result
	for slot in grid.get_children():
		if not slot is Control or not slot.is_visible_in_tree(): continue
		var card := _storage_card(slot)
		if card != null: result.append(String(card.get_meta("inventory_item_id", "")))
	return result


func _storage_surface_contract() -> void:
	_check(screen.find_children("Background", "TextureRect", true, false).size() == 1, "Storage has one canonical background")
	_check(screen.find_children("StorageBoardArt", "", true, false).size() == 1, "Storage has one canonical board")
	var board := screen.get_node_or_null("Header/StorageBoardArt") as NinePatchRect
	_check(board != null and board.texture != null and board.texture.resource_path == CLEAN_STORAGE_BOARD, "Storage clean stretchable board source")
	for node in screen.find_children("*", "TextureRect", true, false) + screen.find_children("*", "NinePatchRect", true, false):
		var texture := node.get("texture") as Texture2D
		_check(texture == null or not texture.resource_path.ends_with("/storage_board.png"), "No old baked Storage wells: " + String(node.name))
	for node in screen.find_children("*Craft*", "BaseButton", true, false) + screen.find_children("*craft*", "BaseButton", true, false):
		_check(not node.is_visible_in_tree(), "Storage has no Craft banner/shortcut action: " + String(node.name))


func _storage_page_contract(expected_ids: Array) -> void:
	var grid := screen.get_node_or_null("MainContent/ItemGrid_5x3")
	_check(grid != null, "Canonical Storage slot grid")
	if grid == null: return
	var observed: Array = []
	var positions: Dictionary = {}
	for slot in grid.get_children():
		if not slot is Control: continue
		var card := _storage_card(slot)
		if not slot.is_visible_in_tree():
			_check(card == null or not card.is_visible_in_tree(), "Unused slot hides full group: " + String(slot.name))
			continue
		_check(card != null and card.is_visible_in_tree(), "Visible slot has visible item card: " + String(slot.name))
		if card == null: continue
		var id := String(card.get_meta("inventory_item_id", ""))
		_check(not id.is_empty() and expected_ids.has(id), "Visible card is a real current catalog item: " + id)
		observed.append(id)
		positions[String(slot.name)] = (slot as Control).get_global_rect()
		_check(slot.find_children("Art_storage_cell", "TextureRect", false, false).size() == 1, "One painted cell per item: " + id)
		_check(card.get_theme_stylebox("panel") is StyleBoxEmpty, "No duplicate solid card frame: " + id)
		var quantity := card.find_child(String(card.name) + "SurfaceLabel", true, false) as Label
		_check(quantity != null and quantity.text == "× %d" % _amount(id), "Exact quantity for visible item/wallet: " + id)
		var art := card.find_children("*", "TextureRect", true, false)
		if not art.is_empty():
			var artwork := art[0] as TextureRect
			_check(artwork.visible == ASSETS.ITEM_ICONS.has(id), "Artwork only when actual ID is mapped: " + id)
			_check(ASSETS.ITEM_ICONS.has(id) or artwork.texture == null, "Unmapped item never gets medicine fallback: " + id)
			if ASSETS.ITEM_ICONS.has(id):
				_check(artwork.texture != null and artwork.texture.resource_path == String(ASSETS.ITEM_ICONS[id]), "Mapped inventory image loads exact approved path: " + id)
	_same_ids(observed, expected_ids, "Page contains exactly current category items; no phantom cells")
	for _refresh_index in range(2):
		GameState.changed.emit()
		await _settle()
	for slot_name in positions:
		var slot := grid.get_node_or_null(String(slot_name)) as Control
		_check(slot != null and slot.get_global_rect() == positions[slot_name], "Storage geometry stable after refresh: " + String(slot_name))


func _storage_selection_contract(id: String) -> void:
	_check(String(screen.get("selected_item")) == id, "Storage selection follows pointer: " + id)
	for _refresh_index in range(2):
		GameState.changed.emit()
		await _settle()
	var selected_count := 0
	for card in screen.get_node("MainContent/ItemGrid_5x3").find_children("Storage*Card*", "Panel", true, false):
		if not card.is_visible_in_tree() or not bool(card.get_meta("ui_selected", false)): continue
		selected_count += 1
		_check(String(card.get_meta("inventory_item_id", "")) == id, "Selected card matches detail ID")
		var checkmark := card.get_node_or_null("UISelectedCheck") as Label
		_check(checkmark != null and checkmark.visible and checkmark.text == "✓", "Selection remains a distinct check after refresh")
	_check(selected_count == 1, "Exactly one selected visible inventory card")


func _select_storage_visible(id: String) -> bool:
	var grid := screen.get_node("MainContent/ItemGrid_5x3")
	for slot in grid.get_children():
		if not slot is Control or not slot.is_visible_in_tree(): continue
		var card := _storage_card(slot)
		if card == null or String(card.get_meta("inventory_item_id", "")) != id: continue
		var selectors := slot.find_children("Select*", "Button", true, false)
		_check(not selectors.is_empty(), "Real Storage selector for " + id)
		if selectors.is_empty(): return false
		var clicked := await _press_button(selectors[0] as BaseButton, "Storage selector " + id)
		if clicked: await _storage_selection_contract(id)
		return clicked
	_check(false, "Item is actually visible before selection: " + id)
	return false


func _select_storage(id: String) -> bool:
	await _press("StorageCategory_All")
	var expected := _expected_catalog()
	var page_size := _page_size()
	_check(page_size > 0, "Storage has positive current page size")
	if page_size <= 0: return false
	var pages := maxi(1, ceili(float(expected.size()) / page_size))
	for page in range(pages):
		if _visible_storage_ids().has(id): return await _select_storage_visible(id)
		if page + 1 < pages: await _press("StorageNextPage")
	_check(false, "Current catalog item reachable by real Storage pages: " + id)
	return false


func _walk_storage_catalog(locale: String, fixture_label: String) -> void:
	await _route("storage")
	var instance_id := screen.get_instance_id()
	_storage_surface_contract()
	var expected := _expected_catalog()
	var actual: Array = screen.call("_all_item_ids")
	_same_ids(actual, expected, "Storage catalog covers FarmData + world items + dragon eggs + loaded IDs")
	var tab_names: Array = []
	for category in CATEGORIES: tab_names.append("StorageCategory_" + String(category))
	var page_size := _page_size()
	_check(page_size > 0, "Storage page size is positive")
	if page_size <= 0: return
	for category in CATEGORIES:
		await _press("StorageCategory_" + String(category))
		_check(screen.get_instance_id() == instance_id and ScreenRouter.current_screen == "storage", "Category filters same canonical Storage")
		_check(String(screen.get("category")) == String(category), "Real category state: " + String(category))
		_tab_contract("StorageCategory_" + String(category), tab_names)
		var category_ids := _expected_category_items(String(category))
		var pages := maxi(1, ceili(float(category_ids.size()) / page_size))
		var all_seen: Array = []
		for page in range(pages):
			_check(int(screen.get("page_index")) == page, "Real Storage page state")
			var expected_page := category_ids.slice(page * page_size, (page + 1) * page_size)
			await _storage_page_contract(expected_page)
			var visible := _visible_storage_ids()
			all_seen.append_array(visible)
			if not visible.is_empty(): await _select_storage_visible(String(visible[-1]))
			await _capture("%s_STORAGE_%s_%s_PAGE_%02d" % [locale, fixture_label, category, page + 1])
			var previous := _button("StoragePreviousPage")
			var next := _button("StorageNextPage")
			_check(previous != null and previous.disabled == (page == 0), "Previous-page boundary follows actual category length")
			_check(next != null and next.disabled == (page + 1 == pages), "Next-page boundary follows actual category length")
			if page + 1 < pages: await _press("StorageNextPage")
		_same_ids(all_seen, category_ids, "All current " + String(category) + " items reachable through GUI pages")
	await _press("StorageCategory_All")


func _fixture_rich() -> void:
	GameState.new_state(3, false)
	var config := GameState.world_config()
	GameState.data.coins = 999999
	GameState.data.energy = 100
	GameState.data.orders_done = 8
	GameState.data.world.dragon_energy = 20
	GameState.data.long_khi = 20
	for island in config.get("islands", {}): GameState.data.world.unlocked_islands[island] = true
	for building in config.get("buildings", {}): GameState.data.world.buildings[building] = int(config.buildings[building].get("max_level", 1))
	for id in _expected_catalog():
		if id != "dragon_energy": GameState.data.inventory[id] = 0
	GameState.data.inventory.erase("dragon_energy")
	for id in ["crop_carrot", "milk", "medicine", "ancient_fruit", "animal_feed", "grain_feed", "cow_feed", "duck_feed", "pig_feed", "medicine_fatigue", "medicine_cold", "medicine_fever", "stone"]:
		GameState.data.inventory[id] = 3
	GameState.data.inventory.crop_carrot = 999
	for meter in ["fullness", "cleanliness", "happiness"]: GameState.data.animal[meter] = 50
	GameState.data.animal.eggs_ready = 0
	RULES.sync_chicken(GameState.data)
	GameState.changed.emit()
	_check(RULES.inventory_stacks(GameState.data) < RULES.inventory_capacity(GameState.data), "Rich labelled fixture leaves actual warehouse capacity")


func _autosave_reload(snapshot: Dictionary, label: String) -> void:
	# No explicit save here: only the preceding actual gameplay action may persist.
	_check(GameState.load_slot(3), "Actual action autosaved QA slot before reload: " + label)
	_check(GameState.data.inventory == snapshot.inventory, "Inventory autosave restores exactly: " + label)
	for key in ["coins", "energy", "day"]: _check(int(GameState.data[key]) == int(snapshot[key]), key + " autosave restores exactly: " + label)
	for key in ["creatures", "utility", "incubators", "dragon_energy"]:
		_check(GameState.data.world.get(key) == snapshot.world.get(key), "World " + key + " autosave restores exactly: " + label)
	_check(GameState.data.animal == snapshot.animal, "Legacy chicken autosave restores exactly: " + label)
	await _settle()


func _shop_art_and_pages(locale: String, fixture_label: String) -> void:
	await _route("shop")
	var instance_id := screen.get_instance_id()
	var tabs := [["Tab_Seeds", "seeds"], ["Tab_Food", "food"], ["Tab_Medicine", "medicine"], ["Tab_Expansion", "expansion"], ["Tab_Rare", "rare"]]
	var names: Array = []
	for tab in tabs: names.append(String(tab[0]))
	var missing_captured := false
	for tab in tabs:
		await _press(String(tab[0]))
		_check(screen.get_instance_id() == instance_id and ScreenRouter.current_screen == "shop", "Shop tab is same-screen category; never Craft/collection shortcut")
		_check(String(screen.get("active_category")) == String(tab[1]), "Shop real category: " + String(tab[1]))
		_tab_contract(String(tab[0]), names)
		var offers: Array = screen.call("_category_shop_items")
		var page_size := _page_size()
		if page_size <= 0:
			_check(false, "Shop positive page size")
			continue
		var pages := maxi(1, ceili(float(offers.size()) / page_size))
		var seen: Array = []
		for page in range(pages):
			var visible_offers: Array = screen.call("_visible_shop_items")
			var expected_ids: Array = []
			for item in visible_offers: expected_ids.append(String(item["id"]))
			var visible_ids: Array = []
			for index in range(1, 9):
				var slot := screen.find_child("ProductSlot%02d" % index, true, false) as Control
				if slot == null or not slot.is_visible_in_tree(): continue
				var id := String(slot.get_meta("shop_product_id", ""))
				visible_ids.append(id)
				var artwork := slot.get_node_or_null("ProductArtwork") as TextureRect
				var missing := slot.get_node_or_null("ArtworkUnavailable") as Label
				var has_art := ASSETS.ITEM_ICONS.has(id)
				_check(artwork != null and artwork.visible == has_art, "Shop art visibility follows exact ID: " + id)
				if has_art:
					_check(artwork != null and artwork.texture != null and artwork.texture.resource_path == String(ASSETS.ITEM_ICONS[id]), "Mapped Shop image loads exact approved path: " + id)
				if not has_art:
					_check(artwork == null or artwork.texture == null, "Shop missing icon has no false medicine fallback: " + id)
					_check(missing != null and missing.visible and not missing.text.is_empty(), "Shop missing icon is clearly text-only: " + id)
					if not missing_captured:
						await _press("SelectProduct_" + id)
						await _capture(locale + "_SHOP_" + fixture_label + "_MISSING_ICON_" + id)
						missing_captured = true
			_same_ids(visible_ids, expected_ids, "Shop no phantom product slots")
			seen.append_array(visible_ids)
			if page == 0: await _capture(locale + "_SHOP_" + fixture_label + "_" + String(tab[1]).to_upper())
			if page + 1 < pages: await _press("ShopNextPage")
		var offer_ids: Array = []
		for offer in offers: offer_ids.append(String(offer["id"]))
		_same_ids(seen, offer_ids, "Every Shop offer reachable through real pages: " + String(tab[1]))
		_check(_button("BuySelectedProduct") != null, "Shop local action remains available")
	if not missing_captured:
		notes.append(locale + ": Shop has no current unmapped offer; no missing-art fixture was invented.")
		await _capture(locale + "_SHOP_" + fixture_label + "_NO_UNMAPPED_OFFERS")


func _shop_select(tab_name: String, id: String) -> bool:
	await _press(tab_name)
	var offers: Array = screen.call("_category_shop_items")
	var size := _page_size()
	if size <= 0: return false
	for page in range(maxi(1, ceili(float(offers.size()) / size))):
		var selector := _button("SelectProduct_" + id)
		if selector != null and selector.is_visible_in_tree(): return await _press("SelectProduct_" + id)
		if page + 1 < ceili(float(offers.size()) / size): await _press("ShopNextPage")
	_check(false, "Shop offer reachable through pages: " + id)
	return false


func _run_shop_transactions(locale: String) -> void:
	await _route("shop")
	await _shop_select("Tab_Seeds", "seed_carrot")
	var before := GameState.data.duplicate(true)
	var core_definition: Dictionary = {}
	for entry in FarmData.SHOP_ITEMS:
		if String(entry.id) == "seed_carrot": core_definition = entry
	await _press("BuySelectedProduct")
	_check(int(GameState.data.coins) == int(before.coins) - int(core_definition.price), "Core seed GUI purchase exact coins")
	_check(_amount("seed_carrot") == int(before.inventory.get("seed_carrot", 0)) + int(core_definition.amount), "Core seed GUI purchase exact bundle")
	_check(ScreenRouter.current_screen == "shop", "Core purchase stays in Shop")
	await _autosave_reload(GameState.data.duplicate(true), "core seed GUI purchase")
	await _shop_select("Tab_Food", "duck_feed")
	before = GameState.data.duplicate(true)
	var expected := before.duplicate(true)
	var outcome: Dictionary = RULES.act(expected, "buy_item", "duck_feed")
	_check(bool(outcome.get("ok", false)), "Eligible world food fixture")
	await _press("BuySelectedProduct")
	_check(GameState.data.inventory == expected.inventory and int(GameState.data.coins) == int(expected.coins), "World food GUI purchase exact existing authority")
	await _autosave_reload(GameState.data.duplicate(true), "world food GUI purchase")
	# A lower existing barn level is an explicit upgrade-eligibility fixture.
	GameState.data.world.buildings.barn = 1
	GameState.changed.emit()
	await _shop_select("Tab_Expansion", "barn")
	expected = GameState.data.duplicate(true)
	outcome = RULES.act(expected, "build", "barn")
	_check(bool(outcome.get("ok", false)), "Barn upgrade fixture satisfies existing level/material conditions")
	await _press("BuySelectedProduct")
	_check(GameState.data.world.buildings == expected.world.buildings and GameState.data.inventory == expected.inventory and int(GameState.data.coins) == int(expected.coins), "Expansion GUI applies exact existing upgrade level/material/coin rule")
	_check(ScreenRouter.current_screen == "shop", "Expansion purchase stays in Shop")
	await _autosave_reload(GameState.data.duplicate(true), "Shop barn upgrade")
	GameState.data.world.creatures.erase("water_dragon")
	GameState.data.world.incubators.erase("water_egg")
	GameState.data.inventory.water_egg = 0
	GameState.changed.emit()
	await _shop_select("Tab_Rare", "water_egg")
	expected = GameState.data.duplicate(true)
	outcome = RULES.act(expected, "buy_egg", "water_egg")
	_check(bool(outcome.get("ok", false)), "Rare egg fixture satisfies real capacity/prerequisites")
	await _press("BuySelectedProduct")
	_check(GameState.data.inventory == expected.inventory and int(GameState.data.coins) == int(expected.coins), "Rare egg GUI purchase exact price and quantity")
	_check(ScreenRouter.current_screen == "shop", "Rare purchase stays in Shop")
	await _autosave_reload(GameState.data.duplicate(true), "rare egg GUI purchase")
	await _capture(locale + "_SHOP_REAL_PURCHASES_FIXTURE")
	var fixture_coins := int(GameState.data.coins)
	GameState.data.coins = 0
	GameState.changed.emit()
	await _shop_select("Tab_Seeds", "seed_carrot")
	await _disabled_noop("BuySelectedProduct", "insufficient coins")
	GameState.data.coins = fixture_coins
	GameState.changed.emit()


func _run_storage_transactions(locale: String) -> void:
	await _route("storage")
	await _select_storage("crop_carrot")
	var before := GameState.data.duplicate(true)
	await _press("StorageSellSelected")
	_check(_amount("crop_carrot") == int(before.inventory.crop_carrot) - 1, "Core Storage sell consumes one selected crop")
	_check(int(GameState.data.coins) == int(before.coins) + int(FarmData.CROP_DEFINITIONS.carrot.sell_value), "Core Storage sell gives exact crop coins")
	await _autosave_reload(GameState.data.duplicate(true), "core Storage sale")
	await _select_storage("milk")
	var expected := GameState.data.duplicate(true)
	var outcome: Dictionary = RULES.act(expected, "sell_item", "milk")
	_check(bool(outcome.get("ok", false)), "World milk sale fixture eligible")
	await _press("StorageSellSelected")
	_check(GameState.data.inventory == expected.inventory and int(GameState.data.coins) == int(expected.coins), "World Storage sale consumes own product and exact coins")
	await _autosave_reload(GameState.data.duplicate(true), "world Storage sale")
	GameState.data.energy = 40
	GameState.changed.emit()
	await _select_storage("medicine")
	before = GameState.data.duplicate(true)
	await _press("StorageUseSelected")
	_check(_amount("medicine") == int(before.inventory.medicine) - 1 and int(GameState.data.energy) == mini(100, int(before.energy) + 25), "Core tonic use gives 25 farm energy and consumes one")
	_check(GameState.data.world.creatures == before.world.creatures, "Core energy tonic does not cure or change creatures")
	await _autosave_reload(GameState.data.duplicate(true), "core Storage tonic use")
	await _select_storage("ancient_fruit")
	expected = GameState.data.duplicate(true)
	outcome = RULES.act(expected, "convert_fruit", "ancient_fruit")
	_check(bool(outcome.get("ok", false)), "World fruit conversion fixture eligible")
	await _press("StorageUseSelected")
	_check(GameState.data.inventory == expected.inventory and GameState.dragon_energy() == int(expected.world.dragon_energy), "World Storage use converts fruit into one authoritative wallet")
	_check(not GameState.data.inventory.has("dragon_energy"), "No phantom second Dragon Energy inventory stack")
	await _autosave_reload(GameState.data.duplicate(true), "world Storage fruit use")
	await _select_storage("water_egg")
	expected = GameState.data.duplicate(true)
	outcome = RULES.act(expected, "incubate", "water_egg")
	_check(bool(outcome.get("ok", false)), "World egg incubation fixture eligible")
	await _press("StorageUseSelected")
	_check(GameState.data.inventory == expected.inventory and GameState.data.world.incubators == expected.world.incubators, "Egg use starts exact current incubation, never grants instant dragon")
	await _autosave_reload(GameState.data.duplicate(true), "world Storage egg incubation")
	await _select_storage("dragon_energy")
	expected = GameState.data.duplicate(true)
	outcome = RULES.act(expected, "dragon_blessing", "dragon_energy")
	_check(bool(outcome.get("ok", false)), "Wallet use fixture eligible for existing altar blessing")
	await _press("StorageUseSelected")
	_check(GameState.dragon_energy() == int(expected.world.dragon_energy) and int(GameState.data.energy) == int(expected.energy), "Wallet action uses existing blessing price/energy")
	await _autosave_reload(GameState.data.duplicate(true), "world wallet blessing")
	for id in ["cow_feed", "medicine_fatigue", "stone"]:
		await _select_storage(id)
		await _disabled_noop("StorageUseSelected", "no implicit creature/recipe target: " + id)
	_check(ScreenRouter.current_screen == "storage", "Inventory actions remain in current Storage")
	await _capture(locale + "_STORAGE_REAL_SELL_USE_FIXTURE")


func _animal_art_contract(species: String) -> String:
	_check(String(screen.get("selected_species")) == species and ScreenRouter.current_screen == "animal", "Species selection remains in canonical Animal: " + species)
	var name_label := screen.find_child("AnimalNameLabel", true, false) as Label
	_check(name_label != null and name_label.text == tr(String(SPECIES_NAMES[species])), "Selected species name follows current locale: " + species)
	_check(String(screen.call("_food_id")) == String(FOODS[species]) and String(screen.call("_product_id")) == String(PRODUCTS[species]), "Selected species detail binds its own food and output: " + species)
	var food_label := screen.find_child("AnimalFoodLabel", true, false) as Label
	var output_label := screen.find_child("AnimalOutputLabel", true, false) as Label
	_check(food_label != null and food_label.text.contains(String(screen.call("_item_name", String(FOODS[species])))), "Visible species food label matches selected data")
	_check(output_label != null and output_label.text.contains(String(screen.call("_item_name", String(PRODUCTS[species])))), "Visible species output label matches selected data")
	_tab_contract(String(SPECIES_TABS[species]), SPECIES_TABS.values())
	var backgrounds: Dictionary = screen.get("species_background_paths")
	var portraits: Dictionary = screen.get("species_portrait_paths")
	var background_path := String(backgrounds.get(species, ""))
	var portrait_path := String(portraits.get(species, ""))
	_check(not background_path.is_empty() and ResourceLoader.exists(background_path), "Exact separate species environment exists: " + species)
	_check(not portrait_path.is_empty() and ResourceLoader.exists(portrait_path), "Correct species portrait/WORLD source exists: " + species)
	var background := screen.get_node_or_null("Background") as TextureRect
	_check(background != null and background.texture != null and background.texture.resource_path == background_path, "Current species uses its own serialized art binding: " + species)
	var portrait := screen.find_child("Art_chicken_idle", true, false) as TextureRect
	_check(portrait != null and portrait.texture != null and portrait.texture.resource_path == portrait_path, "Information portrait matches selected actual species: " + species)
	var station_food := screen.find_child("Art_animal_feed", true, false) as TextureRect
	_check(station_food != null and station_food.texture != null and station_food.texture.resource_path == String(ASSETS.ITEM_ICONS["animal_feed"]), "Chicken station uses whole current reviewed food source, not clipped authored placeholder")
	_check(station_food != null and station_food.visible == (species == "cloud_chicken"), "Chicken food artwork never represents another species' diet")
	for id in ["cow", "duck", "pig"]:
		var name := String(id).capitalize() + "Visual"
		var visual := screen.find_child(name, true, false) as CanvasItem
		_check(visual != null and visual.visible == (species == id), "Only selected species WORLD body visible: " + name)
	for name in ["ChickenVisual01", "ChickenVisual02"]:
		var visual := screen.find_child(name, true, false) as CanvasItem
		_check(visual != null and visual.visible == (species == "cloud_chicken"), "Chicken body only on chicken page")
	for name in ["SheepVisual", "ChickVisual01", "ChickVisual02", "ChickVisual03"]:
		var visual := screen.find_child(name, true, false) as CanvasItem
		_check(visual == null or not visual.visible, "No unrelated sheep/unsupported baby sprite presented as independent entity")
	return background_path


func _animal_feedback_bars_contract() -> void:
	var info := screen.get_node_or_null("MainContent/AnimalInfoPanel") as Control
	var panel := screen.get_node_or_null("MainContent/AnimalInfoPanel/AnimalFeedbackPanel") as Control
	var label := screen.get_node_or_null("MainContent/AnimalInfoPanel/AnimalFeedbackPanel/FeedbackLabel") as Label
	_within(panel, info, "Animal feedback panel")
	_within(label, panel, "Animal feedback label")
	if label != null:
		_check(not label.text.is_empty() and not label.tooltip_text.is_empty(), "Animal visible copy and full tooltip")
		_check(label.get_line_count() <= 3 and label.get_minimum_size().y <= label.size.y + 1, "Animal feedback fits three lines without vertical overflow")
	for prefix in ["Hunger", "Cleanliness", "Happiness"]:
		var bar := screen.find_child(prefix + "Bar", true, false) as Control
		var fill := bar.get_node_or_null("ProgressFill") as Control if bar != null else null
		_within(fill, bar, prefix + " 100% fill", 3.0)
		if fill != null and bar != null:
			_check(fill.size.x > 0 and fill.size.x <= bar.size.x - 6, "Full meter preserves painted border: " + prefix)


func _run_fresh_locks(locale: String) -> void:
	GameState.new_state(1, false)
	await _shop_art_and_pages(locale, "FRESH")
	await _shop_select("Tab_Seeds", "seed_tomato")
	await _disabled_noop("BuySelectedProduct", "fresh crop progression lock")
	await _shop_select("Tab_Seeds", "seed_mint")
	await _disabled_noop("BuySelectedProduct", "fresh herb island lock")
	await _route("animal")
	var animal_id := screen.get_instance_id()
	var backgrounds: Array = []
	for species in SPECIES_TABS:
		if species != "cloud_chicken": await _press(String(SPECIES_TABS[species]))
		var before := GameState.data.duplicate(true)
		var background_path := _animal_art_contract(String(species))
		backgrounds.append(background_path)
		_check(screen.get_instance_id() == animal_id, "All four tabs retain same Animal scene instance")
		if species != "cloud_chicken":
			for action in CARE_ACTIONS:
				await _disabled_noop("AnimalAction_" + String(action), "unowned " + String(species) + " " + String(action))
			await _disabled_noop("AnimalAdoptSelected", "fresh progression blocks " + String(species) + " adoption")
		_check(GameState.data == before, "Viewing/disabled care never grants species or changes farm")
		await _capture(locale + "_ANIMAL_FRESH_" + String(species).to_upper())
	var unique_backgrounds: Array = []
	for path in backgrounds:
		if not unique_backgrounds.has(path): unique_backgrounds.append(path)
	_check(unique_backgrounds.size() == SPECIES_TABS.size(), "Four species have distinct background paths, no shared chicken yard")
	await _press("AnimalSpecies_chicken")
	GameState.data.energy = 0
	GameState.changed.emit()
	await _settle()
	for action in ["feed_animals", "clean_animals", "pet_animals"]:
		await _disabled_noop("AnimalAction_" + String(action), "zero farm energy blocks chicken care")
	await _capture(locale + "_ANIMAL_ZERO_ENERGY_FIXTURE")


func _expected_animal_action(before: Dictionary, species: String, action: String) -> Dictionary:
	var expected := before.duplicate(true)
	if species != "cloud_chicken":
		var outcome: Dictionary = RULES.act(expected, String(CARE_ACTIONS[action]), species)
		_check(bool(outcome.get("ok", false)), "Species care fixture eligible by existing authority: " + species + ":" + action)
		return expected
	if action == "collect":
		expected.inventory.egg = int(expected.inventory.get("egg", 0)) + int(expected.animal.eggs_ready)
		expected.animal.eggs_ready = 0
	else:
		expected.energy = int(expected.energy) - int(FarmData.ACTION_ENERGY_COSTS[action])
		match action:
			"feed_animals":
				expected.inventory.animal_feed = int(expected.inventory.animal_feed) - 1
				expected.animal.fullness = mini(100, int(expected.animal.fullness) + 25)
			"clean_animals": expected.animal.cleanliness = mini(100, int(expected.animal.cleanliness) + 25)
			"pet_animals": expected.animal.happiness = mini(100, int(expected.animal.happiness) + 20)
	RULES.sync_chicken(expected)
	return expected


func _care_action(species: String, action: String) -> void:
	var before := GameState.data.duplicate(true)
	var expected := _expected_animal_action(before, species, action)
	await _press("AnimalAction_" + action)
	_check(GameState.data.inventory == expected.inventory, "Only correct food/product quantity changes: " + species + ":" + action)
	_check(int(GameState.data.energy) == int(expected.energy) and int(GameState.data.coins) == int(expected.coins), "Existing care energy and no phantom coins: " + species + ":" + action)
	_check(GameState.data.world.creatures == expected.world.creatures, "Selected creature care/output exact; other creatures isolated: " + species + ":" + action)
	_check(GameState.data.animal == expected.animal, "Legacy chicken isolated/synchronized correctly: " + species + ":" + action)
	await _autosave_reload(GameState.data.duplicate(true), species + ":" + action)


func _run_species_actions(locale: String) -> void:
	await _route("animal")
	for species in ["cow", "duck", "pig"]:
		await _press(String(SPECIES_TABS[species]))
		var before := GameState.data.duplicate(true)
		var expected := before.duplicate(true)
		var outcome: Dictionary = RULES.act(expected, "adopt", String(species))
		_check(bool(outcome.get("ok", false)), "Real adoption prerequisites/capacity fixture: " + String(species))
		await _press("AnimalAdoptSelected")
		_check(GameState.data.world.creatures == expected.world.creatures, "Adopt adds only selected configured species: " + String(species))
		_check(int(GameState.data.coins) == int(expected.coins) and GameState.data.inventory == expected.inventory, "Adoption exact configured coins; no free inventory")
		_check(GameState.data.animal == before.animal, "Non-chicken adoption leaves legacy chicken untouched")
		await _autosave_reload(GameState.data.duplicate(true), String(species) + " adoption")
	for species in SPECIES_TABS:
		await _press(String(SPECIES_TABS[species]))
		_animal_art_contract(String(species))
		for action in ["feed_animals", "clean_animals", "pet_animals"]:
			await _care_action(String(species), String(action))
		await _capture(locale + "_ANIMAL_OWNED_AFTER_CARE_" + String(species).to_upper())
		var food := String(FOODS[species])
		var before_food := int(GameState.data.inventory.get(food, 0))
		var before_grain := int(GameState.data.inventory.get("grain_feed", 0))
		GameState.data.inventory[food] = 0
		# Explicit incompatibility fixture, leaving other species foods available.
		if species == "cloud_chicken":
			# Chicken grain is genuinely compatible in world rules; do not label it
			# incompatible while verifying this screen's preserved legacy food path.
			GameState.data.inventory.grain_feed = 0
			GameState.data.animal.fullness = 50
			RULES.sync_chicken(GameState.data)
		else: GameState.data.world.creatures[species].fullness = 50
		GameState.changed.emit()
		await _settle()
		await _disabled_noop("AnimalAction_feed_animals", "other foods cannot feed " + String(species))
		GameState.data.inventory[food] = before_food
		GameState.data.inventory.grain_feed = before_grain
		GameState.changed.emit()
		await _settle()
	# Actual visible utility controls target these species; no direct utility mutation.
	for species in ["duck", "pig"]:
		await _press(String(SPECIES_TABS[species]))
		var expected := GameState.data.duplicate(true)
		var outcome: Dictionary = RULES.act(expected, "assign_utility", String(species))
		_check(bool(outcome.get("ok", false)), "Utility assignment eligible: " + String(species))
		await _press("AnimalUtilitySelected")
		_check(GameState.data.world.utility == expected.world.utility, "Utility GUI targets selected species")
		await _autosave_reload(GameState.data.duplicate(true), String(species) + " utility")
	# Named planted-bed fixture supplies an actual target for the duck's daily
	# watering rule. No gameplay assertion describes this plant as earned.
	var utility_plot: Dictionary = GameState.data.field_plots[0]
	utility_plot["is_hoed"] = true
	utility_plot["crop"] = "carrot"
	utility_plot["growth_stage"] = 0
	utility_plot["ready_to_harvest"] = false
	utility_plot["watered_today"] = false
	utility_plot["fertilizer_pending"] = false
	GameState.data.field_plots[0] = utility_plot
	await _route("storage")
	var day_before := int(GameState.data.day)
	var stone_before := _amount("stone")
	var ready_before: Dictionary = {}
	for species in SPECIES_TABS: ready_before[species] = int(GameState.data.world.creatures[species].products_ready)
	await _press("LeftNav_RestNextDay")
	_check(int(GameState.data.day) == day_before + 1, "Actual sidebar advances exactly one day")
	_check(_amount("stone") == stone_before + 1, "Assigned cared pig uses existing daily stone utility")
	_check(bool(GameState.data.field_plots[0].watered_today) and int(GameState.data.field_plots[0].last_watered_day) == int(GameState.data.day), "Assigned cared duck waters the actual planted fixture at next day")
	await _press("LeftNav_animal")
	screen = _current_screen()
	_check(screen.scene_file_path == ScreenRouter.SCREENS.animal.resource_path, "Actual sidebar returns canonical Animal")
	for species in SPECIES_TABS:
		await _press(String(SPECIES_TABS[species]))
		_check(int(GameState.data.world.creatures[species].products_ready) == int(ready_before[species]) + 1, "Cared species creates only its own daily product")
		await _care_action(String(species), "collect")
		await _capture(locale + "_ANIMAL_PRODUCT_COLLECTED_" + String(species).to_upper())
	# Disease and full meters are named fixtures, not evidence of earned sickness.
	for species in SPECIES_TABS:
		await _press(String(SPECIES_TABS[species]))
		var disease := String(GameState.world_config().creatures[species].care_disease)
		GameState.data.world.creatures[species].disease = disease
		if species == "cloud_chicken":
			for meter in ["fullness", "cleanliness", "happiness"]: GameState.data.animal[meter] = 100
			RULES.sync_chicken(GameState.data)
		else:
			for meter in ["fullness", "cleanliness", "happiness"]: GameState.data.world.creatures[species][meter] = 100
		GameState.changed.emit()
		await _settle()
		_animal_feedback_bars_contract()
		var label := screen.get_node("MainContent/AnimalInfoPanel/AnimalFeedbackPanel/FeedbackLabel") as Label
		_check(label.text.contains(tr(disease)), "Disease label reads selected world disease, including legacy chicken")
		await _capture(locale + "_ANIMAL_DISEASE_FULL_BARS_" + String(species).to_upper() + "_FIXTURE")
		var medicine := "medicine_" + disease
		var matching_before := _amount(medicine)
		GameState.data.inventory[medicine] = 0
		GameState.changed.emit()
		await _settle()
		await _disabled_noop("AnimalHealSelected", "energy tonic and other remedies cannot cure " + disease)
		GameState.data.inventory[medicine] = matching_before
		GameState.changed.emit()
		await _settle()
		var expected := GameState.data.duplicate(true)
		var outcome: Dictionary = RULES.act(expected, "heal", String(species))
		_check(bool(outcome.get("ok", false)), "Matching cure fixture eligible: " + medicine)
		await _press("AnimalHealSelected")
		_check(GameState.data.inventory == expected.inventory and GameState.data.world.creatures == expected.world.creatures, "Heal consumes matching medicine and changes only selected disease")
		await _autosave_reload(GameState.data.duplicate(true), String(species) + " matching heal")


func _run() -> void:
	var run_id := "%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_msec()]
	run_root = REPORT_ROOT.path_join("RUN_" + run_id)
	capture_root = run_root.path_join("CAPTURES")
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(run_root)):
		_check(false, "Run evidence directory already exists; refusing any overwrite")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_root))
	get_window().size = Vector2i(1280, 720)
	var main := MAIN.instantiate()
	add_child(main)
	host = main.get_node("ScreenHost")
	await _settle()
	for locale in ["vi", "en"]:
		UILocale.set_locale(locale)
		await _settle()
		await _run_fresh_locks(locale)
		_fixture_rich()
		await _settle()
		await _walk_storage_catalog(locale, "CATALOG_RICH")
		await _shop_art_and_pages(locale, "RICH")
		await _run_shop_transactions(locale)
		await _run_storage_transactions(locale)
		await _run_species_actions(locale)
		# Honest empty inventory still displays catalog item names with zero quantities.
		for id in GameState.data.inventory: GameState.data.inventory[id] = 0
		GameState.data.world.dragon_energy = 0
		GameState.data.long_khi = 0
		GameState.changed.emit()
		await _route("storage")
		_storage_surface_contract()
		await _select_storage("crop_carrot")
		await _disabled_noop("StorageSellSelected", "empty core crop cannot sell")
		await _select_storage("medicine")
		await _disabled_noop("StorageUseSelected", "empty energy tonic cannot use")
		await _storage_page_contract(_expected_catalog().slice(0, _page_size()))
		await _capture(locale + "_STORAGE_EMPTY_FIXTURE")
	var result_path := run_root.path_join("GDD_CLOSURE_V3_QA_RESULTS.txt")
	var report := FileAccess.open(result_path, FileAccess.WRITE)
	if report == null:
		push_error("Could not write new QA result report.")
		get_tree().quit(1)
		return
	report.store_line("GDD_CLOSURE_V3_QA_PASS" if failures.is_empty() else "GDD_CLOSURE_V3_QA_FAIL")
	report.store_line("Assertions: %d; Captures: %d" % [checks, captures.size()])
	report.store_line("Save root: " + OS.get_environment("MSF_TEST_SAVE_DIR"))
	report.store_line("GUI: Viewport.push_input mouse motion/down/up; no pressed.emit, callback call or selector-method fallback.")
	report.store_line("Fresh locks and labelled rich/zero/disease/full-meter fixtures; world/core authority and autosave reload tested.")
	report.store_line("Scope: current commerce/inventory/four species only. Old tests remain unchanged and must run separately where their catalog assumptions remain applicable.")
	report.store_line("VISUAL REVIEW REQUIRED. Captures/geometry do not certify animation continuity, juvenile growth, art approval or entire GDD.")
	for note in notes: report.store_line("NOTE: " + note)
	for failure in failures: report.store_line("FAIL: " + failure)
	for path in captures: report.store_line("CAPTURE: " + path)
	report.close()
	print("GDD_CLOSURE_V3_QA_PASS" if failures.is_empty() else "GDD_CLOSURE_V3_QA_FAIL")
	print("GDD_CLOSURE_V3_RESULTS: " + ProjectSettings.globalize_path(result_path))
	get_tree().quit(0 if failures.is_empty() else 1)

