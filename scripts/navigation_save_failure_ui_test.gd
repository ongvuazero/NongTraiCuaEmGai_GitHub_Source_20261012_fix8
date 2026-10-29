extends Node

# Additive rendered QA for the remaining Next Day entry points. Production
# actions and their retries use Viewport.push_input, never bound callbacks.
const MAIN = preload("res://scenes/main.tscn")
const FarmData = preload("res://scripts/farm_data.gd")
const PersistenceFeedbackQA = preload("res://scripts/persistence_feedback_ui_test.gd")
const V6 = preload("res://v6/runtime/v6_spec_registry.gd")
const REPORT_ROOT := "res://REPORTS/GDD_CLOSURE_V3/09_NAVIGATION_SAVE_FAILURE_UI"
const BASE_ROUTES := ["shop", "storage", "settings"]
const WORLD_ROUTES := ["islands", "craft", "creatures", "events"]

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
# Reuse the same deterministic RefCounted rejection service as the existing
# persistence UI test. Its metadata/load operations read the real QA slot.
var reject_save := PersistenceFeedbackQA.RejectSave.new()
var changed_emissions := 0


func _ready() -> void:
	var isolated_root := OS.get_environment("MSF_TEST_SAVE_DIR")
	var qa_root := ProjectSettings.globalize_path(isolated_root).replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	var player_root := ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	if isolated_root.is_empty() or not qa_root.contains("gdd_closure_v3") or qa_root == player_root or player_root.begins_with(qa_root + "/"):
		push_error("Navigation GUI QA requires a fresh named gdd_closure_v3 MSF_TEST_SAVE_DIR, separate from and not above player saves.")
		get_tree().quit(2)
		return
	for slot in range(1, 4):
		for suffix in ["", ".tmp", ".bak", ".deleted.bak"]:
			if FileAccess.file_exists(isolated_root.path_join(("my_sisters_farm_slot_%d.save" % slot) + suffix)):
				push_error("Navigation GUI QA refuses occupied saves/backups. Supply a fresh directory; existing files are preserved.")
				get_tree().quit(2)
				return
	if DisplayServer.get_name() == "headless" or QARichFixture.requested() or V6.is_parity_mode():
		push_error("Navigation GUI QA requires rendered normal gameplay, not headless, rich or parity fixtures.")
		get_tree().quit(2)
		return
	get_window().mouse_entered.connect(func() -> void: mouse_inside = true)
	get_window().mouse_exited.connect(func() -> void: mouse_inside = false)
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("NAVIGATION_SAVE_FAILURE_UI: " + message)


func _settle(frames := 6) -> void:
	for _frame in range(frames): await get_tree().process_frame


func _current_screen() -> Node:
	return host.get_child(host.get_child_count() - 1)


func _route(id: String) -> void:
	# Canonical routing is setup only. The tested day changes use real controls.
	ScreenRouter.go(id)
	await _settle()
	screen = _current_screen()
	_check(ScreenRouter.current_screen == id, "Setup route: " + id)
	_check(screen.scene_file_path == ScreenRouter.SCREENS[id].resource_path, "Canonical scene: " + id)
	if id in WORLD_ROUTES:
		_check(String(screen.get("section")) == id, "Shared World scene binds actual section: " + id)


func _button(name: String) -> BaseButton:
	return screen.find_child(name, true, false) as BaseButton


func _caption(button: BaseButton, label: String) -> String:
	_check(button != null, label + ": button exists for caption")
	if button == null: return ""
	var caption := button.find_child("Caption", true, false) as Label
	_check(caption != null, label + ": caption label exists")
	return caption.text if caption != null else ""


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


func _press(name: String, label: String) -> bool:
	var button := _button(name)
	_check(button != null, label + ": actual control exists")
	if button == null: return false
	_check(button.is_visible_in_tree() and not button.disabled, label + ": actual control visible and enabled")
	if not button.is_visible_in_tree() or button.disabled: return false
	_check(Rect2(Vector2.ZERO, Vector2(1280, 720)).has_point(button.get_global_rect().get_center()), label + ": pointer target lies on viewport")
	# A read-only signal witness proves the engine activated the GUI control.
	var fired := [false]
	var witness := func() -> void: fired[0] = true
	button.pressed.connect(witness, CONNECT_ONE_SHOT)
	await _click(button.get_global_rect().get_center())
	if is_instance_valid(button) and button.pressed.is_connected(witness): button.pressed.disconnect(witness)
	_check(fired[0], label + ": pointer activates actual GUI")
	return fired[0]


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
	var saved := rendered.save_png(ProjectSettings.globalize_path(target)) == OK
	_check(saved, "Capture saved: " + name)
	if saved: captures.append(target)


func _without_status(state: Dictionary) -> Dictionary:
	var result: Dictionary = state.duplicate(true)
	result.erase("status_text")
	return result


func _without_save_metadata(state: Dictionary) -> Dictionary:
	var result: Dictionary = _without_status(state)
	result.erase("saved_at_unix")
	result.erase("last_screen")
	return result


func _files_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for slot in range(1, 4):
		for suffix in ["", ".tmp", ".bak", ".deleted.bak"]:
			var name: String = ("my_sisters_farm_slot_%d.save" % slot) + String(suffix)
			var path: String = OS.get_environment("MSF_TEST_SAVE_DIR").path_join(name)
			var exists := FileAccess.file_exists(path)
			result[name] = {"exists": exists, "bytes": FileAccess.get_file_as_bytes(path) if exists else PackedByteArray()}
	return result


func _feedback_label(route: String) -> Label:
	if route == "shop": return screen.get_node_or_null("MainContent/ShopFeedbackPanel/FeedbackLabel") as Label
	if route == "storage": return screen.get_node_or_null("MainContent/StorageFeedbackPanel/FeedbackLabel") as Label
	if route in WORLD_ROUTES: return screen.get_node_or_null("MainPanel/Feedback") as Label
	if route == "dragon": return screen.find_child("DragonActionFeedback", true, false) as Label
	return null # Settings has no feedback panel; its actual navigation tooltip is the surface.


func _visible_feedback(label: Label, expected: String, case_name: String) -> void:
	_check(label != null, case_name + ": feedback label exists")
	if label == null: return
	_check(label.is_visible_in_tree(), case_name + ": feedback visible in tree")
	_check(label.text == expected and not label.text.is_empty(), case_name + ": actual feedback text matches outcome")
	_check(label.get_global_rect().intersects(Rect2(Vector2.ZERO, Vector2(1280, 720))), case_name + ": feedback on viewport")
	if String(label.name) == "DragonActionFeedback":
		var background := label.get_node_or_null("DragonFeedbackBackground") as Panel
		_check(background != null, case_name + ": approved feedback background exists")
		if background != null:
			_check(background.is_visible_in_tree(), case_name + ": feedback background visible")
			_check(background.get_global_rect().is_equal_approx(label.get_global_rect()), case_name + ": opaque feedback background covers label bounds")
			_check(background.mouse_filter == Control.MOUSE_FILTER_IGNORE and background.show_behind_parent, case_name + ": feedback background is behind text and non-interactive")
			var style := background.get_theme_stylebox("panel") as StyleBoxFlat
			_check(style != null and style.bg_color.a >= 0.95, case_name + ": existing cream scene panel style has an opaque readable center")
			observations.append(case_name + " background bounds: " + str(background.get_global_rect()))


func _assert_current_saved(label: String) -> void:
	var loaded: Dictionary = real_save_service.call("load_slot", 1)
	_check(bool(loaded.get("ok", false)), label + ": real Slot 1 reloads")
	if not bool(loaded.get("ok", false)): return
	var stored: Variant = loaded.get("state")
	_check(stored is Dictionary, label + ": persisted original-schema state is Dictionary")
	if stored is Dictionary:
		_check(_without_save_metadata(stored) == _without_save_metadata(GameState.data), label + ": persisted gameplay matches RAM without explicit final save")


func _on_changed() -> void:
	changed_emissions += 1


func _day_case(route: String, index: int) -> void:
	await _route(route)
	var name: String = "LeftNav_RestNextDay" if route in BASE_ROUTES else "DragonSectionSecondary" if route == "dragon" else "WorldNextDay"
	if route == "settings":
		await _press("Settings_master_Down", "Settings creates actual unsaved volume draft")
		_check(bool(screen.get_meta("settings_draft_dirty", false)), "Settings day fixture has a dirty GUI draft")
	if route == "dragon":
		_check(int(screen.get("active_section")) == 0, "Dragon uses actual hatchery section")
		var secondary: Dictionary = screen.get("_secondary_spec")
		_check(String(secondary.get("action", "")) == "advance_day", "Dragon actual secondary specification is Next Day")
	var root_id := screen.get_instance_id()
	var before: Dictionary = GameState.data.duplicate(true)
	var selected_before: int = GameState.selected_slot
	var draft_before: Dictionary = GameState.settings_draft.duplicate(true)
	var files_before: Dictionary = _files_snapshot()
	var emissions_before := changed_emissions
	var saves_before: int = reject_save.calls
	GameState.save_service = reject_save
	await _press(name, route + " rejected Next Day")
	_check(reject_save.calls == saves_before + 1, route + ": one rejected persistence attempt")
	_check(_without_status(GameState.data) == _without_status(before), route + ": all gameplay rolls back")
	_check(int(GameState.data.get("day", -1)) == int(before.get("day", -2)), route + ": failed Next Day does not advance")
	_check(changed_emissions == emissions_before, route + ": failed Next Day emits no successful changed signal")
	_check(GameState.selected_slot == selected_before and GameState.settings_draft == draft_before, route + ": failure preserves selected slot and settings draft")
	_check(_files_snapshot() == files_before, route + ": every slot/save/tmp/bak/deleted backup byte is unchanged")
	_check(ScreenRouter.current_screen == route and _current_screen().get_instance_id() == root_id, route + ": failure preserves actual canonical screen")
	var failure_text: String = GameState.status
	_check(not failure_text.is_empty(), route + ": actual persistence error exists")
	if route in BASE_ROUTES:
		var button := _button(name)
		_check(button != null and button.tooltip_text == failure_text, route + ": navigation tooltip exposes actual save error")
		_check(_caption(button, route + " failed navigation") == tr("Retry save"), route + ": navigation caption offers Retry save")
		if route == "settings" and button != null:
			_move_pointer(Vector2(4, 4))
			await _settle(2)
			_move_pointer(button.get_global_rect().get_center())
			await get_tree().create_timer(maxf(0.6, float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5)) + 0.25)).timeout
	if route != "settings": _visible_feedback(_feedback_label(route), failure_text, route + " failed Next Day")
	observations.append(route + " failure: " + failure_text)
	await _capture("%02d_%s_NEXT_DAY_SAVE_REJECTED" % [index * 2 - 1, route.to_upper()])
	GameState.save_service = real_save_service
	emissions_before = changed_emissions
	await _press(name, route + " real Next Day retry")
	_check(reject_save.calls == saves_before + 1, route + ": retry actually uses real SaveService")
	_check(int(GameState.data.get("day", -1)) == int(before.get("day", -2)) + 1, route + ": real retry advances exactly one day")
	_check(int(GameState.data.get("energy", -1)) == 100, route + ": real retry restores farm energy")
	_check(changed_emissions == emissions_before + 1, route + ": real retry emits exactly one successful change")
	_check(GameState.selected_slot == selected_before and GameState.settings_draft == draft_before, route + ": real day retry preserves settings draft and selected slot")
	_check(ScreenRouter.current_screen == route and _current_screen().get_instance_id() == root_id, route + ": real retry keeps actual canonical screen")
	var success_text: String = tr("Đã sang ngày mới. Kiểm tra tiến độ trứng và chăm sóc rồng.") if route == "dragon" else tr("New day. Changes autosaved.")
	_check(success_text != failure_text, route + ": success feedback is distinct from rejected persistence text")
	if route in BASE_ROUTES:
		var button := _button(name)
		_check(button != null and button.tooltip_text == success_text, route + ": navigation tooltip reports actual success, not stale error")
		_check(_caption(button, route + " saved navigation") == tr("Nghỉ / Ngày mới"), route + ": real retry restores normal navigation caption")
	if route != "settings": _visible_feedback(_feedback_label(route), success_text, route + " real Next Day retry")
	_assert_current_saved(route + " retry")
	observations.append(route + " retry: " + success_text)
	await _capture("%02d_%s_NEXT_DAY_REAL_RETRY_SAVED" % [index * 2, route.to_upper()])
	completed_cases.append(route)


func _run() -> void:
	var run_id := "%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_msec()]
	run_root = REPORT_ROOT.path_join("RUN_" + run_id)
	capture_root = run_root.path_join("CAPTURES")
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(run_root)):
		push_error("Navigation GUI evidence directory already exists; refusing overwrite.")
		get_tree().quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_root)) != OK:
		push_error("Could not create new navigation GUI evidence directory.")
		get_tree().quit(2)
		return
	get_window().size = Vector2i(1280, 720)
	real_save_service = GameState.save_service
	reject_save.read_service = real_save_service
	GameState.data = GameState.normalize_state(FarmData.create_initial_state())
	GameState.data["selected_slot"] = 1
	GameState.selected_slot = 1
	GameState.settings_draft = {"master": 80.0, "music": 70.0, "sfx": 85.0, "fullscreen": false}
	GameState.apply_audio_settings()
	# Minimal labelled eligibility fixture: expose the production hatchery Next
	# Day control. This does not claim the player earned the island unlock.
	GameState.data["world"]["unlocked_islands"]["dragon"] = true
	observations.append("Original-schema QA fixture: Dragon Island unlocked solely to expose actual hatchery Next Day; not earned progression. No items, creatures, coins, capacities or schema added.")
	_check(GameState.save("hub"), "Setup normal original-schema Slot 1 checkpoint persists in isolated service")
	var main := MAIN.instantiate()
	add_child(main)
	host = main.get_node("ScreenHost")
	await _settle()
	UILocale.set_locale("vi")
	await _settle()
	GameState.changed.connect(_on_changed)
	var routes: Array[String] = ["shop", "storage", "settings", "islands", "craft", "creatures", "events", "dragon"]
	for index in range(routes.size()): await _day_case(routes[index], index + 1)
	GameState.save_service = real_save_service
	_check(completed_cases == routes, "All eight GUI failure/retry cases reached explicit completion markers")
	_check(captures.size() == 16, "All sixteen failure/retry rendered evidence captures completed")
	var result_path := run_root.path_join("NAVIGATION_SAVE_FAILURE_UI_RESULTS.txt")
	var report := FileAccess.open(result_path, FileAccess.WRITE)
	if report == null:
		push_error("Could not write new navigation GUI results report.")
		get_tree().quit(1)
		return
	var result := "NAVIGATION_SAVE_FAILURE_UI_TEST_PASS" if failures.is_empty() else "NAVIGATION_SAVE_FAILURE_UI_TEST_FAIL"
	report.store_line(result)
	report.store_line("Assertions: %d; Captures: %d" % [checks, captures.size()])
	report.store_line("Completed cases: " + str(completed_cases))
	report.store_line("Save root: " + OS.get_environment("MSF_TEST_SAVE_DIR"))
	report.store_line("GUI: Viewport.push_input motion/down/up only; pressed connections are read-only witnesses. No production callback/action invocation.")
	report.store_line("Failure injection: reused RefCounted RejectSave with real isolated metadata/load reads; no OS denial, deletion, invalid paths or player saves.")
	report.store_line("Scope: Base Shop/Storage/Settings sidebar Next Day, World islands/craft/creatures/events Next Day, Dragon hatchery Next Day; all reject and then retry through actual GUI.")
	report.store_line("VISUAL REVIEW REQUIRED. Assertion PASS is limited to these routes; no whole-game, earned progression, juvenile lifecycle, animation, overlay or GDD PASS.")
	for observation in observations: report.store_line("OBSERVATION: " + observation)
	for failure in failures: report.store_line("FAIL: " + failure)
	for path in captures: report.store_line("CAPTURE: " + path)
	report.close()
	print(result)
	print("NAVIGATION_SAVE_FAILURE_UI_RESULTS: " + ProjectSettings.globalize_path(result_path))
	get_tree().quit(0 if failures.is_empty() else 1)
