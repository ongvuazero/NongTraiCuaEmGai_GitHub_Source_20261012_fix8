extends Node

# Additive rendered QA: production actions are reached only through pointer input.
# The normal original-schema starting farm is a setup fixture, not earned progress.
# RejectSave denies persistence deterministically; reads use the real isolated service.
const MAIN = preload("res://scenes/main.tscn")
const FarmData = preload("res://scripts/farm_data.gd")
const PixelMap = preload("res://v7/production/field_pixel_map_v2.gd")
const V6 = preload("res://v6/runtime/v6_spec_registry.gd")
const REPORT_ROOT := "res://REPORTS/GDD_CLOSURE_V3/08_SAVE_FAILURE_UI"

class RejectSave:
	extends RefCounted
	var calls := 0
	var read_service: RefCounted

	func save_current_slot(_slot_id: int, _state: Dictionary, _location := "hub") -> Dictionary:
		calls += 1
		return {"ok": false, "message": "Deterministic GUI QA persistence rejection."}

	func get_slot_metadata(slot_id: int) -> Dictionary:
		return read_service.call("get_slot_metadata", slot_id)

	func load_slot(slot_id: int) -> Dictionary:
		return read_service.call("load_slot", slot_id)

	func get_latest_valid_slot() -> int:
		return int(read_service.call("get_latest_valid_slot"))

var failures: Array[String] = []
var checks := 0
var captures: Array[String] = []
var observations: Array[String] = []
var completed_cases: Array[String] = []
var run_root := ""
var capture_root := ""
var host: Control
var screen: Node
var mouse_inside := false
var real_save_service: RefCounted
var reject_save := RejectSave.new()
var changed_emissions := 0
var success_fx_entered := 0


func _ready() -> void:
	var isolated_root := OS.get_environment("MSF_TEST_SAVE_DIR")
	var qa_root := ProjectSettings.globalize_path(isolated_root).replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	var player_root := ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	if isolated_root.is_empty() or not qa_root.contains("gdd_closure_v3") or qa_root == player_root or player_root.begins_with(qa_root + "/"):
		push_error("Persistence GUI QA requires a fresh named gdd_closure_v3 MSF_TEST_SAVE_DIR, separate from and not above player saves.")
		get_tree().quit(2)
		return
	for slot in range(1, 4):
		for suffix in ["", ".tmp", ".bak", ".deleted.bak"]:
			if FileAccess.file_exists(isolated_root.path_join(("my_sisters_farm_slot_%d.save" % slot) + suffix)):
				push_error("Persistence GUI QA refuses occupied saves/backups. Existing test/player files are preserved; supply a fresh directory.")
				get_tree().quit(2)
				return
	if DisplayServer.get_name() == "headless" or QARichFixture.requested() or V6.is_parity_mode():
		push_error("Persistence GUI QA requires rendered normal gameplay, not headless, rich or parity fixtures.")
		get_tree().quit(2)
		return
	get_window().mouse_entered.connect(func() -> void: mouse_inside = true)
	get_window().mouse_exited.connect(func() -> void: mouse_inside = false)
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("PERSISTENCE_FEEDBACK_UI: " + message)


func _settle(frames := 6) -> void:
	for _frame in range(frames): await get_tree().process_frame


func _current_screen() -> Node:
	return host.get_child(host.get_child_count() - 1)


func _route(id: String) -> void:
	# Routing is test setup only. Actions and retries below use actual GUI controls.
	ScreenRouter.go(id)
	await _settle()
	screen = _current_screen()
	_check(ScreenRouter.current_screen == id, "Setup route: " + id)
	_check(screen.scene_file_path == ScreenRouter.SCREENS[id].resource_path, "Canonical scene: " + id)


func _button(name: String) -> BaseButton:
	return screen.find_child(name, true, false) as BaseButton


func _move_pointer(point: Vector2) -> void:
	var viewport := get_viewport()
	if not mouse_inside:
		viewport.notify_mouse_entered()
		mouse_inside = true
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)


func _click(point: Vector2) -> void:
	_move_pointer(point)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		event.position = point
		event.global_position = point
		get_viewport().push_input(event, true)
	await _settle()


func _press_button(button: BaseButton, label: String) -> bool:
	_check(button != null, "Control exists: " + label)
	if button == null: return false
	_check(button.is_visible_in_tree() and not button.disabled, "Visible enabled control: " + label)
	if not button.is_visible_in_tree() or button.disabled: return false
	# Read-only witness; never pressed.emit(), callable.call() or callback fallback.
	var fired := [false]
	var witness := func() -> void: fired[0] = true
	button.pressed.connect(witness, CONNECT_ONE_SHOT)
	await _click(button.get_global_rect().get_center())
	if is_instance_valid(button) and button.pressed.is_connected(witness): button.pressed.disconnect(witness)
	_check(fired[0], "Actual GUI pointer activated: " + label)
	return fired[0]


func _press(name: String) -> bool:
	return await _press_button(_button(name), name)


func _caption(button: BaseButton, label: String) -> String:
	_check(button != null, label + ": button exists for caption")
	if button == null: return ""
	var caption := button.get_node_or_null("Caption") as Label
	_check(caption != null, label + ": caption label exists")
	return caption.text if caption != null else ""


func _capture(name: String) -> void:
	await _settle(2)
	await RenderingServer.frame_post_draw
	var rendered := get_viewport().get_texture().get_image()
	_check(rendered != null, "Rendered image: " + name)
	if rendered == null: return
	_check(rendered.get_size() == Vector2i(1280, 720), "1280x720 capture: " + name)
	var target := capture_root.path_join(name + ".png")
	_check(not FileAccess.file_exists(target), "Capture never overwrites evidence: " + name)
	if FileAccess.file_exists(target): return
	_check(rendered.save_png(ProjectSettings.globalize_path(target)) == OK, "Capture saved: " + name)
	captures.append(target)


func _without_status(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	result.erase("status_text")
	return result


func _without_save_metadata(state: Dictionary) -> Dictionary:
	var result := _without_status(state)
	result.erase("saved_at_unix")
	result.erase("last_screen")
	return result


func _slot_bytes(slot: int) -> PackedByteArray:
	var path := OS.get_environment("MSF_TEST_SAVE_DIR").path_join("my_sisters_farm_slot_%d.save" % slot)
	return FileAccess.get_file_as_bytes(path)


func _assert_failure(before: Dictionary, emissions_before: int, saves_before: int, stored_before: PackedByteArray, label: String) -> void:
	_check(reject_save.calls == saves_before + 1, label + ": one rejected persistence attempt")
	_check(_without_status(GameState.data) == _without_status(before), label + ": all gameplay data rolled back")
	_check(changed_emissions == emissions_before, label + ": no successful changed emission")
	_check(not GameState.status.is_empty(), label + ": actual failure status exists")
	_check(_slot_bytes(1) == stored_before, label + ": stored Slot 1 bytes unchanged")
	observations.append(label + " status: " + GameState.status)


func _visible_error(label: Label, case_name: String) -> void:
	_check(label != null, case_name + ": feedback label exists")
	if label == null: return
	_check(label.is_visible_in_tree(), case_name + ": feedback label visible in tree")
	_check(label.text == GameState.status, case_name + ": visible text is actual save failure, not success/guidance")
	_check(not label.text.is_empty(), case_name + ": feedback not empty")
	_check(label.get_global_rect().intersects(Rect2(Vector2.ZERO, Vector2(1280, 720))), case_name + ": feedback on viewport")


func _on_changed() -> void:
	changed_emissions += 1


func _on_fx_entered(node: Node) -> void:
	if String(node.name).begins_with("FX_") or String(node.name).begins_with("HarvestReward_"):
		success_fx_entered += 1


func _audio_snapshot() -> Dictionary:
	var result: Dictionary = {"window_mode": DisplayServer.window_get_mode()}
	for bus_name in ["Master", "Music", "SFX"]:
		var index := AudioServer.get_bus_index(bus_name)
		_check(index >= 0, "Audio bus exists: " + String(bus_name))
		if index >= 0: result[bus_name] = AudioServer.get_bus_volume_db(index)
	return result


func _assert_audio_unchanged(before: Dictionary) -> void:
	var after := _audio_snapshot()
	for bus_name in ["Master", "Music", "SFX"]:
		_check(is_equal_approx(float(after.get(bus_name, 1000.0)), float(before.get(bus_name, -1000.0))), "Failed Settings apply preserves actual " + String(bus_name) + " audio")
	_check(after["window_mode"] == before["window_mode"], "Failed Settings apply preserves window mode")


func _assert_current_saved(slot: int, label: String) -> void:
	var loaded: Dictionary = real_save_service.call("load_slot", slot)
	_check(bool(loaded.get("ok", false)), label + ": real persisted slot reloads")
	if bool(loaded.get("ok", false)):
		var state = loaded.get("state")
		_check(state is Dictionary, label + ": reloaded state is a Dictionary")
		if state is Dictionary:
			_check(_without_save_metadata(state) == _without_save_metadata(GameState.data), label + ": reloaded original-schema gameplay matches RAM")


func _field_failures() -> void:
	await _route("field")
	var field_root_id := screen.get_instance_id()
	var renderer: Node2D = screen.renderer
	var renderer_id := renderer.get_instance_id()
	var farmer: Node2D = screen.farmer
	var farmer_id := farmer.get_instance_id()
	var build_count := int(screen.get("_world_rebuild_total"))
	var fx_world := renderer.get("fx_world") as Node2D
	fx_world.child_entered_tree.connect(_on_fx_entered)
	await _press("Action_till")
	_check(String(screen.get("_active_tool")) == "till", "GUI selects real TILL tool")
	_check(GameState.field_action_allowed("till", GameState.get_plot(1)), "TILL fixture is a valid mutating action, not disabled validation")
	var before := GameState.data.duplicate(true)
	var stored_before := _slot_bytes(1)
	var emissions_before := changed_emissions
	var saves_before := reject_save.calls
	var fx_before := success_fx_entered
	GameState.save_service = reject_save
	var polygon: PackedVector2Array = PixelMap.visual_interaction_polygon(1)
	var point := Vector2.ZERO
	for vertex in polygon: point += vertex
	point /= polygon.size()
	var area := screen.get_node("EDIT_ME/FieldArea") as Control
	await _click(area.get_global_transform() * point)
	_check(int(screen.qa_last_clicked_plot_id()) == 1, "TILL reaches Plot 1 via actual field polygon pointer")
	_assert_failure(before, emissions_before, saves_before, stored_before, "Field TILL")
	_check(not bool(GameState.get_plot(1).get("is_hoed", false)), "Rejected TILL leaves plot untilled")
	_check(int(GameState.data["energy"]) == int(before["energy"]), "Rejected TILL costs no energy")
	_check(success_fx_entered == fx_before, "Rejected TILL spawns no successful action/reward FX")
	_check(screen.get_instance_id() == field_root_id and screen.renderer.get_instance_id() == renderer_id and screen.farmer.get_instance_id() == farmer_id, "Rejected TILL keeps field screen, renderer and farmer identity")
	_check(int(screen.get("_world_rebuild_total")) == build_count and int(screen.qa_world_rebuilds_per_action()) == 0, "Rejected TILL performs no world rebuild")
	_visible_error(screen.get_node("EDIT_ME/CropInfoPanel/TipText") as Label, "Field TILL")
	await _capture("01_FIELD_TILL_SAVE_REJECTED")
	before = GameState.data.duplicate(true)
	emissions_before = changed_emissions
	saves_before = reject_save.calls
	await _press("Action_advance_day")
	_assert_failure(before, emissions_before, saves_before, stored_before, "Field NEXT DAY")
	_check(int(GameState.data["day"]) == int(before["day"]), "Rejected Field NEXT DAY cannot advance the day")
	_check(success_fx_entered == fx_before, "Rejected Field NEXT DAY spawns no growth/success FX")
	_check(screen.renderer.get_instance_id() == renderer_id and int(screen.get("_world_rebuild_total")) == build_count, "Rejected Field NEXT DAY keeps renderer with no rebuild")
	_visible_error(screen.get_node("EDIT_ME/CropInfoPanel/TipText") as Label, "Field NEXT DAY")
	await _capture("02_FIELD_NEXT_DAY_SAVE_REJECTED")
	# The second Next Day entry point must also show failure, not its success copy.
	await _route("animal")
	before = GameState.data.duplicate(true)
	emissions_before = changed_emissions
	saves_before = reject_save.calls
	await _press("AnimalAdvanceDay")
	_assert_failure(before, emissions_before, saves_before, stored_before, "Animal NEXT DAY")
	_check(int(GameState.data["day"]) == int(before["day"]), "Rejected Animal NEXT DAY cannot advance day")
	_visible_error(screen.get_node("MainContent/AnimalInfoPanel/AnimalFeedbackPanel/FeedbackLabel") as Label, "Animal NEXT DAY")
	completed_cases.append("field_and_animal")


func _settings_failure_and_retry() -> void:
	await _route("settings")
	var settings_root_id := screen.get_instance_id()
	var old_audio := _audio_snapshot()
	# The original new farm does not contain persisted volume keys yet. Read
	# exactly the same defaults as GameState._settings_from_data and Settings.
	var old_volumes := {
		"master": float(GameState.data.get("master_volume", 80.0)),
		"music": float(GameState.data.get("music_volume", 70.0)),
		"sfx": float(GameState.data.get("sfx_volume", 85.0)),
	}
	await _press("Settings_master_Down")
	await _press("Settings_music_Down")
	await _press("Settings_sfx_Down")
	var desired := GameState.settings_draft.duplicate(true)
	for key in ["master", "music", "sfx"]:
		_check(desired.has(key), "Actual Settings draft contains " + key)
		_check(is_equal_approx(float(desired.get(key, -1.0)), float(old_volumes[key]) - 5.0), "Actual Settings volume GUI creates edited " + key + " draft")
	_check(bool(screen.get_meta("settings_draft_dirty", false)), "Settings draft visibly dirty before saving")
	var before := GameState.data.duplicate(true)
	var stored_before := _slot_bytes(1)
	var emissions_before := changed_emissions
	var saves_before := reject_save.calls
	await _press("SettingsApply")
	_assert_failure(before, emissions_before, saves_before, stored_before, "Settings APPLY")
	_assert_audio_unchanged(old_audio)
	_check(GameState.settings_draft == desired, "Rejected Settings APPLY keeps edited draft for retry")
	_check(screen.get_instance_id() == settings_root_id, "Rejected Settings APPLY keeps current screen")
	var apply := _button("SettingsApply")
	_check(apply != null, "Settings retry control exists")
	if apply != null:
		_check(apply.is_visible_in_tree() and not apply.disabled, "Settings retry remains visible and enabled")
		_check(bool(screen.get_meta("settings_draft_dirty", false)), "Settings retry remains dirty")
		var retry_caption := _caption(apply, "Settings retry")
		_check(retry_caption == tr("Retry save"), "Settings Apply caption explicitly offers Retry save")
		_check(apply.tooltip_text == GameState.status, "Settings retry tooltip exposes actual persistence error")
		observations.append("Settings retry caption: " + retry_caption)
		observations.append("Settings retry tooltip: " + apply.tooltip_text)
		# Hover through the viewport so the engine can render its ordinary tooltip.
		_move_pointer(Vector2(4, 4))
		await _settle(2)
		_move_pointer(apply.get_global_rect().get_center())
		await get_tree().create_timer(maxf(0.6, float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5)) + 0.25)).timeout
	await _capture("03_SETTINGS_RETRY_SAVE_ERROR")
	GameState.save_service = real_save_service
	emissions_before = changed_emissions
	await _press("SettingsApply")
	_check(changed_emissions == emissions_before + 1, "Real Settings retry emits successful change exactly once")
	_check(GameState.settings_draft == desired, "Real Settings retry uses exact retained GUI draft")
	for pair in [["Master", "master"], ["Music", "music"], ["SFX", "sfx"]]:
		var bus_name := String(pair[0])
		var key := String(pair[1])
		_check(GameState.data.has(key + "_volume"), "Real Settings retry writes actual persisted " + key + " volume key")
		_check(is_equal_approx(float(GameState.data.get(key + "_volume", -1.0)), float(desired.get(key, -2.0))), "Real Settings retry saves edited " + key)
		var index := AudioServer.get_bus_index(bus_name)
		_check(index >= 0 and is_equal_approx(AudioServer.get_bus_volume_db(index), linear_to_db(float(desired.get(key, 0.0)) / 100.0)), "Real Settings retry applies actual " + bus_name + " audio")
	_check(not bool(screen.get_meta("settings_draft_dirty", true)), "Real Settings retry clears dirty UI state")
	apply = _button("SettingsApply")
	_check(apply != null and apply.disabled, "Real Settings retry returns Apply to saved/disabled state")
	if apply != null:
		_check(_caption(apply, "Settings saved") == tr("Áp dụng"), "Real Settings retry restores normal Apply caption")
		_check(apply.tooltip_text != GameState.status, "Real Settings retry no longer offers failure tooltip")
	_assert_current_saved(1, "Settings retry")
	await _capture("04_SETTINGS_REAL_RETRY_SAVED")
	completed_cases.append("settings")


func _save_slot_button(slot_id: int) -> BaseButton:
	# Canonical Save slots currently have anonymous flat buttons. Resolve the
	# actual button by the source-owned geometry, never by its bound callback.
	var rect: Rect2 = V6.visible_rect(screen.geometry, "SLOT_%d" % slot_id)
	for child in screen.get_children():
		if child is BaseButton:
			var button := child as BaseButton
			if button.position.is_equal_approx(rect.position) and button.size.is_equal_approx(rect.size): return button
	return null


func _select_storage_visible(item_id: String) -> bool:
	var grid := screen.get_node_or_null("MainContent/ItemGrid_5x3")
	_check(grid != null, "Storage grid exists for GUI selection")
	if grid == null: return false
	for slot in grid.get_children():
		if not slot is Control or not slot.is_visible_in_tree(): continue
		for card in slot.find_children("Storage*Card*", "Panel", false, false):
			if not card.is_visible_in_tree() or String(card.get_meta("inventory_item_id", "")) != item_id: continue
			var selectors := slot.find_children("Select*", "Button", true, false)
			_check(not selectors.is_empty(), "Storage actual selector exists: " + item_id)
			if selectors.is_empty(): return false
			var clicked := await _press_button(selectors[0] as BaseButton, "Storage selector " + item_id)
			_check(String(screen.get("selected_item")) == item_id, "Storage pointer selects exact item: " + item_id)
			return clicked
	_check(false, "Storage item is visible in chosen category: " + item_id)
	return false


func _storage_save_failures() -> void:
	# Explicit minimal QA setup, not earned progress: one original core crop
	# permits a real sale and 60 energy permits use of the existing one tonic.
	# No catalog IDs, schema, ownership rules or x999 quantities are invented.
	GameState.save_service = real_save_service
	GameState.data["inventory"]["crop_carrot"] = 1
	GameState.data["energy"] = 60
	observations.append("Storage-only QA fixture: crop_carrot=1, energy=60, original medicine=1; not earned progress.")
	_check(GameState.save("storage"), "Setup minimal Storage checkpoint persists through real isolated service")
	await _route("storage")
	var storage_root_id := screen.get_instance_id()
	await _press("StorageCategory_Crops")
	await _select_storage_visible("crop_carrot")
	_check(int(GameState.data.get("inventory", {}).get("crop_carrot", 0)) == 1, "Storage sale fixture really owns one carrot")
	var before := GameState.data.duplicate(true)
	var stored_before := _slot_bytes(1)
	var emissions_before := changed_emissions
	var saves_before := reject_save.calls
	GameState.save_service = reject_save
	await _press("StorageSellSelected")
	_assert_failure(before, emissions_before, saves_before, stored_before, "Storage core SELL")
	_check(GameState.data.get("inventory", {}) == before.get("inventory", {}), "Rejected core SELL keeps exact inventory")
	_check(int(GameState.data.get("coins", -1)) == int(before.get("coins", -2)), "Rejected core SELL adds no coins")
	_check(int(GameState.data.get("energy", -1)) == int(before.get("energy", -2)), "Rejected core SELL changes no energy")
	_check(screen.get_instance_id() == storage_root_id, "Rejected core SELL keeps Storage screen")
	_visible_error(screen.get_node_or_null("MainContent/StorageFeedbackPanel/FeedbackLabel") as Label, "Storage core SELL")
	await _capture("07_STORAGE_CORE_SELL_SAVE_REJECTED_ONE_CARROT_FIXTURE")
	await _press("StorageCategory_Medicine")
	await _select_storage_visible("medicine")
	_check(int(GameState.data.get("inventory", {}).get("medicine", 0)) == 1 and int(GameState.data.get("energy", 100)) == 60, "Storage tonic fixture has medicine and missing energy")
	before = GameState.data.duplicate(true)
	emissions_before = changed_emissions
	saves_before = reject_save.calls
	await _press("StorageUseSelected")
	_assert_failure(before, emissions_before, saves_before, stored_before, "Storage core TONIC USE")
	_check(GameState.data.get("inventory", {}) == before.get("inventory", {}), "Rejected core TONIC USE consumes no inventory")
	_check(int(GameState.data.get("coins", -1)) == int(before.get("coins", -2)), "Rejected core TONIC USE changes no coins")
	_check(int(GameState.data.get("energy", -1)) == int(before.get("energy", -2)), "Rejected core TONIC USE grants no energy")
	_check(screen.get_instance_id() == storage_root_id, "Rejected core TONIC USE keeps Storage screen")
	_visible_error(screen.get_node_or_null("MainContent/StorageFeedbackPanel/FeedbackLabel") as Label, "Storage core TONIC USE")
	await _capture("08_STORAGE_CORE_TONIC_SAVE_REJECTED_60_ENERGY_FIXTURE")
	GameState.save_service = real_save_service
	completed_cases.append("storage")


func _animal_save_failures_and_retry() -> void:
	# Labelled minimal eligibility fixture, not earned progression: use the
	# configured Cow prerequisite/order count, existing barn/capacity and price.
	# Ownership is obtained only by the actual Adopt GUI action and real retry.
	GameState.save_service = real_save_service
	var cow_definition: Dictionary = GameState.world_config().get("creatures", {}).get("cow", {})
	_check(not cow_definition.is_empty(), "Animal adoption fixture uses configured Cow definition")
	_check(not GameState.data.get("world", {}).get("creatures", {}).has("cow"), "Cow adoption starts genuinely unowned in isolated QA farm")
	GameState.data["orders_done"] = maxi(int(GameState.data.get("orders_done", 0)), int(cow_definition.get("orders", 0)))
	GameState.data["coins"] = maxi(int(GameState.data.get("coins", 0)), int(cow_definition.get("cost", 0)))
	GameState.data["energy"] = 60
	observations.append("Animal-only QA eligibility fixture: Cow configured order prerequisite, at least its authored price, energy=60; existing barn and companion capacity unchanged. Not earned progression; Cow ownership must come from actual GUI Adopt retry.")
	_check(GameState.save("animal"), "Setup eligible Cow checkpoint persists through real isolated service")
	await _route("animal")
	await _press("AnimalSpecies_cow")
	_check(String(screen.get("selected_species")) == "cow", "Actual Cow species GUI selects Cow")
	var animal_root_id: int = screen.get_instance_id()
	var feedback_label := screen.get_node("MainContent/AnimalInfoPanel/AnimalFeedbackPanel/FeedbackLabel") as Label
	var eligibility: Dictionary = GameState.world_action_info("adopt", "cow")
	_check(bool(eligibility.get("ok", false)), "Cow adoption is a valid mutating action before rejecting persistence")
	var before: Dictionary = GameState.data.duplicate(true)
	var stored_before: PackedByteArray = _slot_bytes(1)
	var emissions_before: int = changed_emissions
	var saves_before: int = reject_save.calls
	GameState.save_service = reject_save
	await _press("AnimalAdoptSelected")
	_assert_failure(before, emissions_before, saves_before, stored_before, "Animal eligible Cow ADOPT")
	_check(not GameState.data["world"]["creatures"].has("cow"), "Rejected Adopt grants no Cow ownership")
	_check(int(GameState.data["coins"]) == int(before["coins"]), "Rejected Adopt charges no coins")
	_check(ScreenRouter.current_screen == "animal" and _current_screen().get_instance_id() == animal_root_id, "Rejected Adopt keeps actual Animal screen")
	_visible_error(feedback_label, "Animal eligible Cow ADOPT")
	_check(feedback_label.tooltip_text == GameState.status, "Rejected Adopt tooltip exposes actual persistence error, not eligible guidance")
	var adoption_error: String = GameState.status
	await _capture("09_ANIMAL_ELIGIBLE_COW_ADOPT_SAVE_REJECTED_FIXTURE")
	GameState.save_service = real_save_service
	emissions_before = changed_emissions
	await _press("AnimalAdoptSelected")
	_check(changed_emissions == emissions_before + 1, "Real Adopt retry emits exactly one successful change")
	_check(reject_save.calls == saves_before + 1, "Adopt retry actually uses real SaveService")
	_check(GameState.data["world"]["creatures"].has("cow"), "Real Adopt retry grants actual Cow ownership")
	_check(int(GameState.data["coins"]) == int(before["coins"]) - int(cow_definition.get("cost", 0)), "Real Adopt retry charges exact configured Cow price once")
	_check(GameState.data["inventory"] == before["inventory"] and int(GameState.data["energy"]) == int(before["energy"]), "Real Adopt retry preserves inventory and farm energy")
	_check(ScreenRouter.current_screen == "animal" and _current_screen().get_instance_id() == animal_root_id, "Real Adopt retry keeps actual Animal screen")
	_check(feedback_label.is_visible_in_tree() and feedback_label.text == tr("Đã nhận nuôi %s.") % tr("Bò Đồng Cỏ") and feedback_label.text != adoption_error, "Real Adopt retry shows Cow success rather than stale save error")
	_assert_current_saved(1, "Animal real Cow Adopt retry")
	await _capture("10_ANIMAL_COW_ADOPT_REAL_RETRY_SAVED_FIXTURE")
	if not GameState.data["world"]["creatures"].has("cow"):
		# Keep the final capture/completion guards meaningful if a broken Adopt
		# action fails to supply the creature required by the next fixture.
		return
	# Natural configured disease, matching remedy x1 and unfinished cleanliness
	# are explicit original-schema fixtures. No second animal authority is made.
	var disease: String = String(cow_definition.get("care_disease", ""))
	var medicine_id: String = "medicine_" + disease
	_check(not disease.is_empty() and GameState.world_config().get("items", {}).has(medicine_id), "Cow disease fixture uses its configured disease and matching remedy")
	var cow_state: Dictionary = GameState.data["world"]["creatures"]["cow"]
	cow_state["disease"] = disease
	cow_state["cleanliness"] = 40
	cow_state["happiness"] = 60
	GameState.data["inventory"][medicine_id] = 1
	GameState.data["energy"] = 60
	observations.append("Animal-only disease QA fixture: actual adopted Cow with configured %s disease, cleanliness=40, happiness=60, matching %s=1 and energy=60. Disease/remedy are fixture setup, not earned progression." % [disease, medicine_id])
	_check(GameState.save("animal"), "Setup actual adopted Cow disease checkpoint persists in real isolated service")
	await _route("animal")
	await _press("AnimalSpecies_cow")
	animal_root_id = screen.get_instance_id()
	feedback_label = screen.get_node("MainContent/AnimalInfoPanel/AnimalFeedbackPanel/FeedbackLabel") as Label
	var clean_info: Dictionary = GameState.world_action_info("clean", "cow")
	_check(bool(clean_info.get("ok", false)), "Diseased Cow CLEAN is valid before rejecting persistence")
	before = GameState.data.duplicate(true)
	stored_before = _slot_bytes(1)
	emissions_before = changed_emissions
	saves_before = reject_save.calls
	GameState.save_service = reject_save
	await _press("AnimalAction_clean_animals")
	_assert_failure(before, emissions_before, saves_before, stored_before, "Animal diseased Cow CLEAN")
	_check(String(GameState.data["world"]["creatures"]["cow"].get("disease", "")) == disease and int(GameState.data["world"]["creatures"]["cow"].get("cleanliness", -1)) == 40, "Rejected diseased care preserves disease and exact care meter")
	_check(ScreenRouter.current_screen == "animal" and _current_screen().get_instance_id() == animal_root_id, "Rejected diseased care keeps actual Animal screen")
	_visible_error(feedback_label, "Animal diseased Cow CLEAN")
	_check(feedback_label.tooltip_text == GameState.status, "Diseased care failure tooltip is actual save error, not disease guidance")
	await _capture("11_ANIMAL_DISEASED_COW_CLEAN_SAVE_REJECTED_FIXTURE")
	before = GameState.data.duplicate(true)
	emissions_before = changed_emissions
	saves_before = reject_save.calls
	await _press("AnimalAdvanceDay")
	_assert_failure(before, emissions_before, saves_before, stored_before, "Animal diseased Cow NEXT DAY")
	_check(int(GameState.data["day"]) == int(before["day"]), "Rejected diseased Cow NEXT DAY advances no day")
	_check(ScreenRouter.current_screen == "animal" and _current_screen().get_instance_id() == animal_root_id, "Rejected diseased day keeps actual Animal screen")
	_visible_error(feedback_label, "Animal diseased Cow NEXT DAY")
	_check(feedback_label.tooltip_text == GameState.status, "Diseased Next Day tooltip is actual save error, not disease guidance")
	await _capture("12_ANIMAL_DISEASED_COW_NEXT_DAY_SAVE_REJECTED_FIXTURE")
	var heal_info: Dictionary = GameState.world_action_info("heal", "cow")
	_check(bool(heal_info.get("ok", false)), "Diseased Cow HEAL with actual matching remedy is valid before rejecting persistence")
	before = GameState.data.duplicate(true)
	emissions_before = changed_emissions
	saves_before = reject_save.calls
	await _press("AnimalHealSelected")
	_assert_failure(before, emissions_before, saves_before, stored_before, "Animal diseased Cow HEAL")
	_check(String(GameState.data["world"]["creatures"]["cow"].get("disease", "")) == disease and int(GameState.data["inventory"].get(medicine_id, 0)) == 1, "Rejected Heal preserves disease and consumes no matching remedy")
	_check(int(GameState.data["energy"]) == int(before["energy"]), "Rejected Heal consumes no energy")
	_check(ScreenRouter.current_screen == "animal" and _current_screen().get_instance_id() == animal_root_id, "Rejected Heal keeps actual Animal screen")
	_visible_error(feedback_label, "Animal diseased Cow HEAL")
	_check(feedback_label.tooltip_text == GameState.status, "Rejected Heal tooltip exposes actual persistence error, not disease guidance")
	var healing_error: String = GameState.status
	await _capture("13_ANIMAL_COW_HEAL_SAVE_REJECTED_MATCHING_REMEDY_FIXTURE")
	GameState.save_service = real_save_service
	emissions_before = changed_emissions
	await _press("AnimalHealSelected")
	_check(changed_emissions == emissions_before + 1, "Real Heal retry emits exactly one successful change")
	_check(reject_save.calls == saves_before + 1, "Heal retry actually uses real SaveService")
	_check(String(GameState.data["world"]["creatures"]["cow"].get("disease", "")) == "", "Real Heal retry cures actual Cow disease")
	_check(int(GameState.data["inventory"].get(medicine_id, -1)) == 0, "Real Heal retry consumes exactly one matching remedy")
	_check(int(GameState.data["energy"]) == int(before["energy"]) - 2, "Real Heal retry charges configured heal energy once")
	_check(int(GameState.data["world"]["creatures"]["cow"].get("happiness", -1)) == 70, "Real Heal retry grants only authored Cow happiness")
	for species in before["world"]["creatures"]:
		if String(species) != "cow": _check(GameState.data["world"]["creatures"][species] == before["world"]["creatures"][species], "Real Cow Heal retry leaves other actual species unchanged: " + String(species))
	_check(ScreenRouter.current_screen == "animal" and _current_screen().get_instance_id() == animal_root_id, "Real Heal retry keeps actual Animal screen")
	_check(feedback_label.is_visible_in_tree() and feedback_label.text == tr("Đã dùng đúng thuốc cho %s.") % tr("Bò Đồng Cỏ") and feedback_label.text != healing_error, "Real Heal retry shows actual cure success rather than stale save/disease feedback")
	var heal := _button("AnimalHealSelected")
	_check(heal != null and not heal.is_visible_in_tree(), "Real Heal retry hides cure action after actual disease clears")
	_assert_current_saved(1, "Animal real Cow Heal retry")
	await _capture("14_ANIMAL_COW_HEAL_REAL_RETRY_SAVED_FIXTURE")
	completed_cases.append("animal_failure_priority")


func _save_confirmation_failure_and_retry() -> void:
	GameState.save_mode = "new" # Test setup: same mode selected by New Game.
	await _route("save")
	_check(ScreenRouter.is_canonical_save_root(screen), "Actual canonical Save root")
	_check(not bool(real_save_service.call("get_slot_metadata", 2).get("occupied", true)), "Target Slot 2 is genuinely fresh")
	await _press_button(_save_slot_button(2), "Save Slot 2 card")
	screen = _current_screen()
	_check(GameState.selected_slot == 2, "GUI selects fresh Slot 2")
	_check(int(GameState.data["selected_slot"]) == 1, "Selecting Slot 2 does not replace active Slot 1 farm")
	var before := GameState.data.duplicate(true)
	var old_draft := GameState.settings_draft.duplicate(true)
	var old_audio := _audio_snapshot()
	var stored_before := _slot_bytes(1)
	var save_screen_id := screen.get_instance_id()
	var emissions_before := changed_emissions
	var saves_before := reject_save.calls
	GameState.save_service = reject_save
	await _press("Action_CONFIRM")
	_assert_failure(before, emissions_before, saves_before, stored_before, "Save fresh Slot 2 CONFIRM")
	_check(ScreenRouter.current_screen == "save", "Rejected Save Confirm stays on Save route, not Hub")
	_check(_current_screen().get_instance_id() == save_screen_id, "Rejected Save Confirm keeps Save screen")
	_check(GameState.selected_slot == 2 and int(GameState.data["selected_slot"]) == 1, "Rejected Save Confirm retains selected target and old active farm")
	_check(GameState.settings_draft == old_draft, "Rejected new farm keeps prior Settings draft")
	_assert_audio_unchanged(old_audio)
	_check(not bool(real_save_service.call("get_slot_metadata", 2).get("occupied", true)), "Rejected Save Confirm writes no Slot 2")
	await _capture("05_SAVE_SLOT_2_CONFIRM_REJECTED")
	GameState.save_service = real_save_service
	emissions_before = changed_emissions
	await _press("Action_CONFIRM")
	screen = _current_screen()
	_check(ScreenRouter.current_screen == "hub", "Actual successful Save Confirm retry routes to Hub")
	_check(screen.scene_file_path == ScreenRouter.SCREENS["hub"].resource_path, "Retry enters actual canonical Hub scene")
	_check(changed_emissions == emissions_before + 1, "Successful new farm emits one changed signal")
	_check(GameState.selected_slot == 2 and int(GameState.data["selected_slot"]) == 2, "Successful new farm owns Slot 2")
	_check(int(GameState.data["day"]) == 1 and int(GameState.data["coins"]) == 400 and int(GameState.data["energy"]) == 100, "Retry creates original authored starting farm")
	_check(GameState.data["inventory"] == FarmData.create_initial_state()["inventory"], "Retry uses original inventory, not QA x999 quantities")
	_check(_slot_bytes(1) == stored_before, "New Slot 2 retry preserves original Slot 1 bytes")
	_check(bool(real_save_service.call("get_slot_metadata", 2).get("occupied", false)), "Actual retry persists Slot 2")
	_assert_current_saved(2, "Save Confirm retry")
	await _capture("06_SAVE_SLOT_2_REAL_RETRY_HUB")
	completed_cases.append("save_confirm")


func _run() -> void:
	var run_id := "%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_msec()]
	run_root = REPORT_ROOT.path_join("RUN_" + run_id)
	capture_root = run_root.path_join("CAPTURES")
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(run_root)):
		push_error("Persistence GUI evidence directory already exists; refusing overwrite.")
		get_tree().quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_root)) != OK:
		push_error("Could not create new persistence GUI evidence directory.")
		get_tree().quit(2)
		return
	get_window().size = Vector2i(1280, 720)
	real_save_service = GameState.save_service
	reject_save.read_service = real_save_service
	# Setup only: standard normalized original farm, preserving every known zero
	# inventory key. The tested actions are never invoked by methods/callbacks.
	GameState.data = GameState.normalize_state(FarmData.create_initial_state())
	GameState.data["selected_slot"] = 1
	GameState.selected_slot = 1
	GameState.settings_draft = {"master": 80.0, "music": 70.0, "sfx": 85.0, "fullscreen": false}
	GameState.apply_audio_settings()
	_check(GameState.save("hub"), "Setup normal Slot 1 checkpoint persisted by real isolated service")
	var main := MAIN.instantiate()
	add_child(main)
	host = main.get_node("ScreenHost")
	await _settle()
	UILocale.set_locale("vi")
	await _settle()
	GameState.changed.connect(_on_changed)
	await _field_failures()
	await _settings_failure_and_retry()
	await _storage_save_failures()
	await _animal_save_failures_and_retry()
	await _save_confirmation_failure_and_retry()
	GameState.save_service = real_save_service
	_check(completed_cases == ["field_and_animal", "settings", "storage", "animal_failure_priority", "save_confirm"], "All five GUI test cases reached their explicit completion markers")
	_check(captures.size() == 14, "Fourteen rendered evidence captures completed, including all original eight")
	var result_path := run_root.path_join("PERSISTENCE_FEEDBACK_UI_RESULTS.txt")
	var report := FileAccess.open(result_path, FileAccess.WRITE)
	if report == null:
		push_error("Could not write new persistence GUI results report.")
		get_tree().quit(1)
		return
	var result := "PERSISTENCE_FEEDBACK_UI_TEST_PASS" if failures.is_empty() else "PERSISTENCE_FEEDBACK_UI_TEST_FAIL"
	report.store_line(result)
	report.store_line("Assertions: %d; Captures: %d" % [checks, captures.size()])
	report.store_line("Completed cases: " + str(completed_cases))
	report.store_line("Save root: " + OS.get_environment("MSF_TEST_SAVE_DIR"))
	report.store_line("GUI: Viewport.push_input motion/down/up only; pressed connections are read-only witnesses, never callback invocation.")
	report.store_line("Failure injection: RefCounted RejectSave; metadata and load reads delegate real isolated SaveService; no OS denial, deletion or invalid paths.")
	report.store_line("Original-schema starting farm and labelled Storage/Animal eligibility+disease fixtures; no rich x999 inventory or duplicate gameplay authority. Animal Cow ownership comes from actual GUI Adopt retry.")
	report.store_line("Scope: original Field TILL/Next Day, Animal Next Day, Settings retained draft/audio+retry, Storage core Sell/tonic Use, fresh Slot 2 Confirm+retry; added eligible Cow Adopt rejection+retry, diseased Cow Clean/Next Day feedback, matching Heal rejection+retry.")
	report.store_line("VISUAL REVIEW REQUIRED. Assertions/captures are not a whole-game, art, animation or GDD PASS.")
	for observation in observations: report.store_line("OBSERVATION: " + observation)
	for failure in failures: report.store_line("FAIL: " + failure)
	for path in captures: report.store_line("CAPTURE: " + path)
	report.close()
	print(result)
	print("PERSISTENCE_FEEDBACK_UI_RESULTS: " + ProjectSettings.globalize_path(result_path))
	get_tree().quit(0 if failures.is_empty() else 1)
