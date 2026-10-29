extends Node

const FIELD_SCENE = preload("res://scenes/screens/05_field_gameplay.tscn")
const PixelMap = preload("res://v7/production/field_pixel_map_v2.gd")
const REPORT_DIR := "res://REPORTS/ITCH_UI_RECOVERY_20261005/FIELD"
const BUTTONS := {
	"till": "EDIT_ME/BottomActionHUD/ToolGroup/Action_till",
	"seed": "EDIT_ME/BottomActionHUD/ToolGroup/Action_seed",
	"water": "EDIT_ME/BottomActionHUD/ToolGroup/Action_water",
	"fertilize": "EDIT_ME/BottomActionHUD/ToolGroup/Action_fertilize",
	"harvest": "EDIT_ME/BottomActionHUD/Action_harvest",
	"advance_day": "EDIT_ME/BottomActionHUD/Action_advance_day",
}

var failures: Array[String] = []
var screen: Node
var authored_transforms := {}
var toolbar_results: Array[Dictionary] = []
var plot_results: Array[Dictionary] = []
var _rebuild_baseline := 0
var _qa_locale := ""
var _run_dir := REPORT_DIR


func _ready() -> void:
	call_deferred("_run")


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("ITCH FIELD TOOLBAR ASSERTION FAILED: " + message)


func _settle(frames := 3) -> void:
	for _frame in range(frames):
		await get_tree().process_frame


func _rendered_frame() -> Image:
	await _settle(2)
	# Process frames advance input and scene state, but do not guarantee that
	# a visibility change has reached this viewport's rendered texture.
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _capture(file_name: String) -> Image:
	var frame := await _rendered_frame()
	_assert_true(not frame.is_empty(), "Rendered capture is empty: " + file_name)
	if not frame.is_empty():
		_assert_true(frame.save_png(ProjectSettings.globalize_path(_run_dir.path_join(file_name))) == OK, "Cannot save " + file_name)
	return frame


func _button(action: String) -> TextureButton:
	return screen.get_node(BUTTONS[action]) as TextureButton


func _snapshot(action: String) -> Dictionary:
	return screen.call("qa_toolbar_response", BUTTONS[action])


func _point(action: String) -> Vector2:
	var button := _button(action)
	return button.get_global_transform_with_canvas() * (button.size * 0.5)


func _mouse(point: Vector2, down: bool, device := 0) -> void:
	if down and device == 0:
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		Input.parse_input_event(motion)
		await get_tree().process_frame
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.device = device
	Input.parse_input_event(event)
	await _settle(2)


func _touch(point: Vector2, down: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.pressed = down
	event.index = 0
	event.canceled = canceled
	Input.parse_input_event(event)
	await _settle(2)


func _pointer(point: Vector2, down: bool, mode: String) -> void:
	if mode == "touch":
		await _touch(point, down)
	else:
		await _mouse(point, down)


func _action_fx_count() -> int:
	var renderer: Node = screen.get("renderer")
	var fx_world: Node = renderer.get("fx_world")
	var count := 0
	for child in fx_world.get_children():
		if String(child.name).begins_with("FX_"):
			count += 1
	return count


func _visible_difference(first: Image, second: Image, rect: Rect2i) -> int:
	if first.is_empty() or second.is_empty():
		return 0
	var bounded := rect.intersection(Rect2i(Vector2i.ZERO, first.get_size()))
	var changed := 0
	for y in range(bounded.position.y, bounded.end.y):
		for x in range(bounded.position.x, bounded.end.x):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.12:
				changed += 1
	return changed


func _check_authored_transforms() -> void:
	for action in BUTTONS:
		var button := _button(action)
		var before: Dictionary = authored_transforms[action]
		_assert_true(button.get_transform() == before["transform"], action + " authored transform drifted")
		_assert_true(Vector4(button.offset_left, button.offset_top, button.offset_right, button.offset_bottom) == before["offsets"], action + " authored offsets drifted")
		_assert_true(button.get_node("ToolbarResponse").scale == Vector2.ONE, action + " response scale drifted")


func _test_toolbar_choice(action: String, mode: String) -> void:
	var point := _point(action)
	var before: Dictionary = GameState.data.duplicate(true)
	var before_tool := String(screen.get("_active_tool"))
	var fx_before := _action_fx_count()
	var response_before := int(_snapshot(action)["response_count"])
	var pressed_callbacks := [0]
	var count_pressed := func() -> void: pressed_callbacks[0] += 1
	_button(action).pressed.connect(count_pressed)
	await _pointer(point, true, mode)
	var down := _snapshot(action)
	_assert_true(bool(down["active"]) and bool(down["pressed"]), mode + " " + action + " has no down response")
	_assert_true(int(down["response_count"]) == response_before + 1, mode + " " + action + " produced duplicate down response")
	_assert_true(int(pressed_callbacks[0]) == 0, mode + " " + action + " dispatched a callback on down")
	_assert_true(GameState.data == before, mode + " " + action + " committed on pointer down")
	_assert_true(String(screen.get("_active_tool")) == before_tool, mode + " " + action + " selected before release")
	var response := _button(action).get_node("ToolbarResponse") as Control
	response.set_process(false)
	var active_image := await _capture("%s_%s_ACTIVE.png" % [mode.to_upper(), action.to_upper()])
	response.visible = false
	var comparison := await _rendered_frame()
	response.visible = true
	response.set_process(true)
	var visible_delta := _visible_difference(active_image, comparison, Rect2i(_button(action).get_global_rect().grow(16.0)))
	_assert_true(visible_delta > 30, mode + " " + action + " active response is not visibly rendered")
	await _pointer(point, false, mode)
	if mode == "touch":
		# Exercise a renderer/browser that also supplies emulated mouse input.
		# NEXT DAY must remain a single commit, not advance twice for one tap.
		await _mouse(point, true, -1)
		await _mouse(point, false, -1)
	if action == "advance_day":
		_assert_true(int(GameState.data.get("day", 0)) == int(before.get("day", 0)) + 1, mode + " NEXT DAY did not advance exactly once")
		_assert_true(int(GameState.data.get("energy", 0)) == 100, mode + " NEXT DAY did not restore energy")
		_assert_true(String(screen.get("_active_tool")).is_empty(), "NEXT DAY retained a plot tool")
	else:
		_assert_true(GameState.data == before, mode + " " + action + " choosing a tool changed farm data")
		_assert_true(String(screen.get("_active_tool")) == action, mode + " " + action + " did not select on release")
		_assert_true(_action_fx_count() == fx_before, mode + " " + action + " choosing a tool fabricated bed VFX")
	await get_tree().create_timer(0.68).timeout
	var settled := _snapshot(action)
	_assert_true(not bool(settled["active"]) and not bool(settled["pressed"]), mode + " " + action + " did not settle")
	_assert_true(bool(settled["badge_visible"]), mode + " " + action + " has no persistent badge")
	var expected_badge := "Đã chọn" if _qa_locale == "vi" else "Selected"
	if action == "advance_day":
		expected_badge = ("Ngày %d" if _qa_locale == "vi" else "Day %d") % int(GameState.data.get("day", 1))
	_assert_true(String(settled["badge_text"]) == expected_badge, mode + " " + action + " badge translation does not match " + _qa_locale)
	if action != "advance_day":
		_assert_true(bool(settled["selected"]), mode + " " + action + " lost stationary selection")
		if mode == "mouse":
			_assert_true(bool(settled["hovered"]), action + " stationary mouse did not exercise hover")
		_assert_true(_button(action).get_node("ToolStateFrame").get_theme_stylebox("panel") == screen.get("tool_selected_style"), mode + " " + action + " stationary hover hid selection")
	_assert_true(int(settled["response_count"]) == response_before + 1, mode + " " + action + " produced duplicate response")
	_assert_true(int(pressed_callbacks[0]) == 1, mode + " " + action + " did not dispatch exactly one pressed callback")
	_button(action).pressed.disconnect(count_pressed)
	_assert_true(int(screen.get("_world_rebuild_total")) == _rebuild_baseline, mode + " " + action + " rebuilt Field")
	_check_authored_transforms()
	await _capture("%s_%s_PERSISTENT.png" % [mode.to_upper(), action.to_upper()])
	toolbar_results.append({"action": action, "input": mode, "active_frame": true, "acknowledgement_count": int(settled["response_count"]) - response_before, "pressed_callbacks": int(pressed_callbacks[0]), "visible_delta_pixels": visible_delta, "persistent_badge": settled["badge_text"], "farm_commit": action == "advance_day", "full_rebuilds": int(screen.get("_world_rebuild_total")) - _rebuild_baseline, "authored_transforms_unchanged": true})


func _plot_point(plot_id: int) -> Vector2:
	var polygon := PixelMap.visual_interaction_polygon(plot_id)
	var center := Vector2.ZERO
	for vertex in polygon:
		center += vertex
	center /= float(polygon.size())
	var field_area := screen.get_node("EDIT_ME/FieldArea") as Control
	return field_area.get_global_transform_with_canvas() * center


func _test_actual_plot_fx(action: String) -> void:
	if action == "till":
		await _touch(_point(action), true)
		await _touch(_point(action), false)
	else:
		await _mouse(_point(action), true)
		await _mouse(_point(action), false)
	if action == "seed":
		var seed := screen.get_node("EDIT_ME/BottomActionHUD/ToolGroup/Action_seed/SeedPickerAnchor/SeedPickerGroup/Seed_carrot") as TextureButton
		var seed_point := seed.get_global_transform_with_canvas() * (seed.size * 0.5)
		await _mouse(seed_point, true)
		await _mouse(seed_point, false)
	if action == "harvest":
		# Only the fixture prepares maturity; production economy is untouched.
		GameState.data["field_plots"][0]["growth_stage"] = int(FarmData.CROP_DEFINITIONS["carrot"]["max_stage"])
		GameState.data["field_plots"][0]["ready_to_harvest"] = true
		var fixture_renderer: Node = screen.get("renderer")
		fixture_renderer.call("update_plot", GameState.get_plot(1), 1)
		screen.call("_populate_field_gameplay_ui")
	var point := _plot_point(1)
	# An immediate emulated plot tap after touch tool selection must work;
	# suppressing all emulated events for a time window would drop this action.
	var pointer_device := -1 if action == "till" else 0
	await _mouse(point, true, pointer_device)
	await _mouse(point, false, pointer_device)
	await get_tree().create_timer(0.06).timeout
	var renderer: Node = screen.get("renderer")
	var fx_world: Node2D = renderer.get("fx_world")
	var effect := fx_world.get_node_or_null("FX_%s_01" % action) as Node2D
	_assert_true(effect != null, action + " actual plot action did not create approved VFX")
	if effect == null:
		return
	var visual: Sprite2D = effect.get("visual")
	_assert_true(effect.position.is_equal_approx(PixelMap.visual_crop_anchor(1)), action + " plot VFX anchor moved")
	_assert_true(visual.visible and visual.modulate.a > 0.5 and visual.texture != null, action + " plot VFX is invisible")
	var bed_world: Node2D = renderer.get("bed_world")
	_assert_true(fx_world.z_index > bed_world.z_index, action + " plot VFX is below selected soil")
	visual.set_meta("qa_original_visible", visual.visible)
	effect.set_process(false)
	var active_image := await _capture("PLOT_%s_APPROVED_VFX_ACTIVE.png" % action.to_upper())
	visual.visible = false
	var comparison := await _rendered_frame()
	visual.visible = true
	effect.set_process(true)
	var anchor: Vector2 = (screen.get_node("EDIT_ME/FieldArea") as Control).get_global_transform_with_canvas() * PixelMap.visual_crop_anchor(1)
	var visible_delta := _visible_difference(active_image, comparison, Rect2i(Vector2i(anchor - Vector2(65, 90)), Vector2i(130, 105)))
	_assert_true(visible_delta > 10, action + " approved plot VFX did not appear in rendered frame")
	_assert_true(int(screen.call("qa_world_rebuilds_per_action")) == 0, action + " plot action rebuilt Field")
	plot_results.append({"action": action, "plot": 1, "active_effect_frame": int(effect.get("frame_index")), "visible_delta_pixels": visible_delta, "approved_sheet": String((effect.get("source_sheet") as Texture2D).resource_path), "above_selected_soil": true, "anchor": str(effect.position), "full_rebuilds": 0})
	await get_tree().create_timer(0.58).timeout


func _test_canceled_touch_and_unavailable() -> void:
	var before: Dictionary = GameState.data.duplicate(true)
	var before_tool := String(screen.get("_active_tool"))
	await _touch(_point("water"), true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(20, 690)
	Input.parse_input_event(drag)
	await _settle(2)
	await _touch(drag.position, false, true)
	_assert_true(GameState.data == before and String(screen.get("_active_tool")) == before_tool, "Canceled touch selected or committed")
	GameState.data["energy"] = 0
	screen.call("_populate_field_gameplay_ui")
	before = GameState.data.duplicate(true)
	for mode in ["mouse", "touch"]:
		await _pointer(_point("till"), true, mode)
		_assert_true(bool(_snapshot("till")["failure"]), mode + " disabled tool has no failure response")
		_assert_true(String(_snapshot("till")["badge_text"]) == ("Không thể dùng" if _qa_locale == "vi" else "Unavailable"), mode + " unavailable badge translation does not match " + _qa_locale)
		await _pointer(_point("till"), false, mode)
		_assert_true(GameState.data == before, mode + " disabled tool changed farm data")
		_assert_true(String(screen.get("_active_tool")) == before_tool, mode + " disabled tool changed selected tool")
		await _capture("%s_DISABLED_TOOL_FAILURE.png" % mode.to_upper())
	_assert_true(_action_fx_count() == 0, "Disabled tool fabricated plot action effects")
	GameState.data["energy"] = 100
	screen.call("_populate_field_gameplay_ui")
	await _mouse(_point("water"), true)
	await _mouse(_point("water"), false)
	await _mouse(_plot_point(1), true)
	await _mouse(_plot_point(1), false)
	_assert_true(bool(screen.get("_feedback_is_error")) and bool(_snapshot("water")["failure"]), "Invalid plot action lost failure feedback")
	_assert_true(_action_fx_count() == 0, "Invalid plot action fabricated approved VFX")
	await _capture("INVALID_PLOT_FAILURE.png")
	_check_authored_transforms()


func _run() -> void:
	# This QA instantiates Field directly, so perform the locale initialization
	# normally owned by main before any localized screen or badge is built.
	UILocale.initialize()
	var requested_locale := OS.get_environment("MSF_QA_LOCALE")
	if requested_locale in ["vi", "en"]:
		TranslationServer.set_locale(requested_locale)
	_qa_locale = UILocale.current_locale()
	_run_dir = REPORT_DIR.path_join(_qa_locale)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_run_dir))
	get_window().size = Vector2i(1280, 720)
	GameState.new_state(1, false)
	GameState.data["energy"] = 100
	GameState.data["inventory"]["seed_carrot"] = 20
	screen = FIELD_SCENE.instantiate()
	# Snapshot the serialized geometry before any runtime build.
	for action in BUTTONS:
		var button := screen.get_node(BUTTONS[action]) as TextureButton
		authored_transforms[action] = {"transform": button.get_transform(), "offsets": Vector4(button.offset_left, button.offset_top, button.offset_right, button.offset_bottom)}
	add_child(screen)
	await _settle(14)
	_rebuild_baseline = int(screen.get("_world_rebuild_total"))
	_check_authored_transforms()
	for mode in ["mouse", "touch"]:
		for action in BUTTONS:
			await _test_toolbar_choice(action, mode)
	for action in ["till", "seed", "water", "fertilize", "harvest"]:
		await _test_actual_plot_fx(action)
	await _test_canceled_touch_and_unavailable()
	_assert_true(int(screen.get("_world_rebuild_total")) == _rebuild_baseline, "Toolbar/plot regression caused a full Field rebuild")
	var report := {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"locale": _qa_locale,
		"report_directory": _run_dir,
		"capture_sync": "RenderingServer.frame_post_draw before every viewport read",
		"selected_day_unavailable_badge_translations_checked": true,
		"input_route": "Input.parse_input_event / native mouse down-up / explicit screen touch down-up",
		"toolbar": toolbar_results,
		"plot_action_vfx": plot_results,
		"all_six_buttons_mouse_and_touch": toolbar_results.size() == 12,
		"tool_selection_commits": 0,
		"next_day_single_commit_per_tap": true,
		"canceled_touch_and_disabled_input_checked": true,
		"invalid_plot_does_not_emit_success_vfx": true,
		"authored_transforms_unchanged": true,
		"world_rebuilds_after_initial_build": int(screen.get("_world_rebuild_total")) - _rebuild_baseline,
		"failures": failures,
	}
	var report_file := FileAccess.open(_run_dir.path_join("TOOLBAR_RESPONSE_QA.json"), FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.close()
	else:
		_assert_true(false, "Cannot write Field toolbar report")
	print("FIELD_TOOLBAR_RESPONSE_TEST_%s" % ("PASS" if failures.is_empty() else "FAIL"))
	print("FIELD_TOOLBAR_QA_LOCALE=" + _qa_locale)
	print("FIELD_TOOLBAR_SELECTION_COMMITS=0")
	print("FIELD_TOOLBAR_FULL_REBUILDS=%d" % (int(screen.get("_world_rebuild_total")) - _rebuild_baseline))
	get_tree().quit(0 if failures.is_empty() else 1)
