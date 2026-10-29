extends Node

# Rendered input proof only. Rich adoption prerequisites are labelled fixtures;
# real actions still pass through the canonical UI and existing authorities.
const MAIN = preload("res://scenes/main.tscn")
const ANIMAL = preload("res://scenes/screens/09_animal.tscn")
const RULES = preload("res://scripts/world_systems.gd")
const FarmData = preload("res://scripts/farm_data.gd")
const REPORT_ROOT := "res://REPORTS/MANUAL_BASELINE_REPAIR_V4/ANIMAL"
const TABS := {"cloud_chicken": "AnimalSpecies_chicken", "cow": "AnimalSpecies_cow", "duck": "AnimalSpecies_duck", "pig": "AnimalSpecies_pig"}
const TARGETS := {"cloud_chicken": "ChickenVisual01", "cow": "CowVisual", "duck": "DuckVisual", "pig": "PigVisual"}
const FOODS := {"cloud_chicken": "animal_feed", "cow": "cow_feed", "duck": "duck_feed", "pig": "pig_feed"}
const PRODUCTS := {"cloud_chicken": "egg", "cow": "milk", "duck": "duck_egg", "pig": "truffle"}
const ACTIONS := {"feed_animals": "feed", "clean_animals": "clean", "pet_animals": "pet", "collect": "collect"}

class RejectSave:
	extends RefCounted
	func save_current_slot(_slot: int, _data: Dictionary, _location := "hub") -> Dictionary:
		return {"ok": false, "message": "Deterministic Animal V4 save rejection."}

var failures: Array[String] = []
var checks := 0
var captures: Array[String] = []
var run_root := ""
var host: Control
var screen: Node
var mouse_inside := false
var authored_rects: Dictionary = {}


func _ready() -> void:
	var save_root := OS.get_environment("MSF_TEST_SAVE_DIR")
	var absolute := ProjectSettings.globalize_path(save_root).replace("\\", "/").simplify_path().to_lower()
	var player := ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path().to_lower()
	if save_root.is_empty() or not absolute.contains("manual_baseline_repair_v4") or absolute == player or player.begins_with(absolute + "/"):
		push_error("Animal V4 QA requires a fresh manual_baseline_repair_v4 isolated test-save directory.")
		get_tree().quit(2)
		return
	for slot in range(1, 4):
		for suffix in ["", ".tmp", ".bak", ".deleted.bak"]:
			if FileAccess.file_exists(save_root.path_join(("my_sisters_farm_slot_%d.save" % slot) + suffix)):
				push_error("Animal V4 QA refuses occupied saves/backups.")
				get_tree().quit(2)
				return
	if DisplayServer.get_name() == "headless":
		push_error("Animal V4 needs rendered pointer input and real viewport captures.")
		get_tree().quit(2)
		return
	get_window().mouse_entered.connect(func() -> void: mouse_inside = true)
	get_window().mouse_exited.connect(func() -> void: mouse_inside = false)
	call_deferred("_run")


func _check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
		push_error("MANUAL_ANIMAL_V4: " + detail)


func _settle(frames := 5) -> void:
	for _frame in range(frames): await get_tree().process_frame


func _node(name: String) -> Node:
	return screen.find_child(name, true, false)


func _click(point: Vector2) -> void:
	if not mouse_inside:
		get_viewport().notify_mouse_entered()
		mouse_inside = true
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		event.position = point
		event.global_position = point
		get_viewport().push_input(event, true)
	await _settle()


func _press(name: String) -> void:
	var button := _node(name) as BaseButton
	_check(button != null, "Named control exists: " + name)
	if button == null: return
	_check(button.is_visible_in_tree() and not button.disabled, "Visible usable control: " + name)
	if not button.is_visible_in_tree() or button.disabled: return
	var observed := [false]
	var witness := func() -> void: observed[0] = true
	button.pressed.connect(witness, CONNECT_ONE_SHOT)
	await _click(button.get_global_rect().get_center())
	if is_instance_valid(button) and button.pressed.is_connected(witness): button.pressed.disconnect(witness)
	_check(observed[0], "Actual GUI click activates signal: " + name)


func _route_animal() -> void:
	ScreenRouter.go("animal")
	await _settle()
	screen = host.get_child(host.get_child_count() - 1)
	_check(ScreenRouter.current_screen == "animal" and screen.scene_file_path == ANIMAL.resource_path, "Current canonical Animal route")


func _capture(name: String) -> void:
	await _settle(2)
	await RenderingServer.frame_post_draw
	var bitmap := get_viewport().get_texture().get_image()
	_check(bitmap.get_size() == Vector2i(1280, 720), "Actual viewport dimensions: " + name)
	var path := run_root.path_join(name + ".png")
	_check(not FileAccess.file_exists(path), "Evidence never overwritten: " + name)
	if FileAccess.file_exists(path): return
	_check(bitmap.save_png(ProjectSettings.globalize_path(path)) == OK, "Rendered capture saved: " + name)
	captures.append(path)


func _result() -> Label:
	return _node("CareActionResult") as Label


func _expected(before: Dictionary, species: String, action: String) -> Dictionary:
	var expected := before.duplicate(true)
	if species != "cloud_chicken":
		var outcome: Dictionary = RULES.act(expected, String(ACTIONS[action]), species)
		_check(bool(outcome.get("ok", false)), "Current world care preflight: " + species + "/" + action)
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


func _care(species: String, action: String) -> void:
	var before := GameState.data.duplicate(true)
	var expected := _expected(before, species, action)
	await _press("AnimalAction_" + action)
	_check(GameState.data.inventory == expected.inventory, "Exact food/product quantity: " + species + "/" + action)
	_check(GameState.data.animal == expected.animal and GameState.data.world.creatures == expected.world.creatures, "Only selected creature changes: " + species + "/" + action)
	_check(int(GameState.data.energy) == int(expected.energy) and int(GameState.data.coins) == int(expected.coins), "Unchanged economy/current care cost: " + species + "/" + action)
	_check(_result().is_visible_in_tree() and _result().text == UILocale.translate_message(String(screen.get("feedback"))), "Immediate result before moving pointer/selection: " + species + "/" + action)
	var snapshot := GameState.data.duplicate(true)
	_check(GameState.load_slot(GameState.selected_slot), "Reload normal action autosave without final manual save")
	if _gameplay_snapshot(GameState.data) != _gameplay_snapshot(snapshot):
		for key in snapshot:
			if key not in ["saved_at_unix", "last_screen", "status_text"] and snapshot[key] != GameState.data.get(key):
				print("ANIMAL_RELOAD_DIFF ", key, " BEFORE=", var_to_str(snapshot[key]), " AFTER=", var_to_str(GameState.data.get(key)))
	_check(_gameplay_snapshot(GameState.data) == _gameplay_snapshot(snapshot), "Exact action autosave restores selected species/inventory/energy (excluding save metadata and presentation status)")
	await _settle()


func _gameplay_snapshot(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	# SaveService appends location/time metadata, while failure feedback changes
	# status_text. None is creature/inventory/energy/progression authority.
	for key in ["saved_at_unix", "last_screen", "status_text"]: result.erase(key)
	# Fresh-state schema omits this compatibility HUD alias. Load normalizes it
	# from the existing world wallet; compare its value, not key absence.
	result["long_khi"] = int(result.get("long_khi", result.get("world", {}).get("dragon_energy", 0)))
	return result


func _geometry_contract() -> void:
	for name in authored_rects:
		var live := _node(String(name)) as Control
		_check(live != null and live.get_global_rect() == authored_rects[name], "User serialized geometry preserved: " + String(name))
	_check(not (_node("MainContent") as CanvasItem).visible and not (_node("FooterActions") as CanvasItem).visible, "User-hidden dashboard/footer remain hidden")
	_check((_node("CareActionResult") as Control).mouse_filter == Control.MOUSE_FILTER_PASS and (_node("CareFoodAndProduct") as Control).mouse_filter == Control.MOUSE_FILTER_PASS, "Full result/food tooltip can receive hover without swallowing button input")
	for name in ["FeedStationVisual", "Art_animal_feed", "FeedStationVisualLabel", "AnimalYardSignLabel"]:
		_check(_node(name) == null, "User-deleted support node not recreated: " + name)
	for name in ["CowVisual", "ChickenVisual01", "DuckVisual", "PigVisual", "AnimalCareContext", "AnimalSpeciesStrip", "AnimalNavigation"]:
		var node := _node(name) as Control
		var original := node.position
		node.position += Vector2(20, 11)
		var edited := node.position
		GameState.changed.emit()
		await _settle()
		_check(node.position == edited, "Manual live position survives state refresh: " + name)
		node.position = original


func _run_locale(locale: String, slot: int) -> void:
	UILocale.set_locale(locale)
	_check(GameState.new_state(slot, false), "Fresh isolated state")
	await _route_animal()
	await _geometry_contract()
	_check(not (_node("AnimalCareContext") as CanvasItem).visible, "Context starts closed, not a permanent dashboard")
	await _click((_node("ChickenVisual01") as Control).get_global_rect().get_center())
	_check((_node("AnimalCareContext") as CanvasItem).is_visible_in_tree(), "Actual chicken body opens care menu")
	await _capture(locale + "_01_CHICKEN_DIRECT_CONTEXT")
	await _care("cloud_chicken", "feed_animals")
	await _capture(locale + "_02_CHICKEN_FED_IMMEDIATE")
	var untouched := GameState.data.duplicate(true)
	await _click(Vector2(1190, 350))
	_check(not (_node("AnimalCareContext") as CanvasItem).visible and GameState.data == untouched, "Outside click closes without consuming action/item")
	await _press("AnimalSpecies_cow")
	_check(String(screen.get("selected_species")) == "cow", "Species selectors remain accessible without old dashboard")
	_check((_node("AnimalAdoptSelected") as Control).is_visible_in_tree(), "Locked cow shows contextual adoption")
	_check((_node("AnimalAction_feed_animals") as BaseButton).disabled, "Unowned care stays locked by current authority")
	await _capture(locale + "_03_LOCKED_COW_PREVIEW")
	# Adoption eligibility fixture, not a claim of earned game progression.
	GameState.data.orders_done = 3
	GameState.data.coins = 100000
	GameState.data.world.buildings.barn = 2
	for food in FOODS.values(): GameState.data.inventory[food] = 10
	GameState.changed.emit()
	await _settle()
	for species in ["cow", "duck", "pig"]:
		await _press(String(TABS[species]))
		await _press("AnimalAdoptSelected")
		_check(GameState.data.world.creatures.has(species), "Current configured adoption through UI: " + String(species))
	for species in TABS:
		await _press(String(TABS[species]))
		var target := _node(String(TARGETS[species])) as Control
		_check(target.is_visible_in_tree() and target.mouse_filter == Control.MOUSE_FILTER_STOP, "Actual selected body is an interactive target: " + String(species))
		await _press("AnimalCareClose")
		await _click(target.get_global_rect().get_center())
		_check((_node("AnimalCareContext") as CanvasItem).is_visible_in_tree(), "Body opens selected species care: " + String(species))
		if species != "cloud_chicken": await _care(String(species), "feed_animals")
		await _care(String(species), "clean_animals")
		await _care(String(species), "pet_animals")
		await _capture(locale + "_04_" + String(species).to_upper() + "_CARED")
	await _press("AnimalAdvanceDay")
	for species in TABS:
		await _press(String(TABS[species]))
		await _care(String(species), "collect")
		var item := String(PRODUCTS[species])
		_check(_result().text.contains("×") and _result().text.contains(str(int(GameState.data.inventory[item]))), "Collected result includes real amount and storage total: " + item)
		await _capture(locale + "_05_" + String(species).to_upper() + "_PRODUCT_RESULT")
	await _press("AnimalSpecies_cow")
	var before_reject := GameState.data.duplicate(true)
	var save_service: RefCounted = GameState.save_service
	GameState.save_service = RejectSave.new()
	await _press("AnimalAction_clean_animals")
	_check(_gameplay_snapshot(GameState.data) == _gameplay_snapshot(before_reject), "Rejected save does not commit care/inventory/energy")
	_check(_result().text == UILocale.translate_message(GameState.status), "Save error is visible immediately, not a fake success")
	await _capture(locale + "_06_SAVE_REJECTION_RESULT")
	GameState.save_service = save_service
	await _press("AnimalBackToHub")
	_check(ScreenRouter.current_screen == "hub", "Visible Back returns current Home")


func _run() -> void:
	run_root = REPORT_ROOT.path_join("RUN_%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_msec()])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(run_root))
	get_window().size = Vector2i(1280, 720)
	var authored := ANIMAL.instantiate()
	for name in ["CowVisual", "ChickenVisual01", "ChickenVisual02", "DuckVisual", "PigVisual", "TopHUD", "AnimalYard", "Background"]:
		var node := authored.find_child(name, true, false) as Control
		authored_rects[name] = node.get_global_rect()
	authored.free()
	var main := MAIN.instantiate()
	add_child(main)
	host = main.get_node("ScreenHost")
	await _settle()
	await _run_locale("vi", 1)
	await _run_locale("en", 2)
	var result := {"status": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "failures": failures, "captures": captures, "fixtures": "Rich orders/coins/barn/foods are test prerequisites only; no entity, growth or animation invented."}
	var report := FileAccess.open(run_root.path_join("RESULT.json"), FileAccess.WRITE)
	if report != null: report.store_string(JSON.stringify(result, "\t"))
	print("MANUAL_ANIMAL_BINDING_V4_TEST_PASS" if failures.is_empty() else "MANUAL_ANIMAL_BINDING_V4_TEST_FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)
