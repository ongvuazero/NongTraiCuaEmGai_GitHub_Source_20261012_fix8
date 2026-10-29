extends Node

# Rendered pointer regression. No production action callbacks are invoked directly.
# Setup resets only a fresh isolated QA save root; RejectSave is an explicit fixture.
const MAIN = preload("res://scenes/main.tscn")
const FIELD = preload("res://scenes/screens/05_field_gameplay.tscn")
const PixelMap = preload("res://v7/production/field_pixel_map_v2.gd")
const V6 = preload("res://v6/runtime/v6_spec_registry.gd")
const REPORT_ROOT := "res://REPORTS/MANUAL_BASELINE_REPAIR_V4/FIELD"
const TOOLS := "EDIT_ME/BottomActionHUD/ToolGroup/Action_"
const POPUP := TOOLS + "seed/SeedPickerAnchor/SeedPickerGroup"
const GEOMETRY_PATHS := [
	"EDIT_ME/FieldArea", "EDIT_ME/CropInfoPanel", "EDIT_ME/CropInfoPanel/CropTitle",
	"EDIT_ME/CropInfoPanel/CropPreview", "EDIT_ME/CropInfoPanel/LifecycleLabel",
	"EDIT_ME/CropInfoPanel/DetailLabel", "EDIT_ME/CropInfoPanel/StatNames",
	"EDIT_ME/CropInfoPanel/StatValues", "EDIT_ME/CropInfoPanel/TipHeading",
	"EDIT_ME/CropInfoPanel/TipText", "EDIT_ME/BottomActionHUD",
	TOOLS + "till", TOOLS + "seed", TOOLS + "water", TOOLS + "fertilize",
	"EDIT_ME/BottomActionHUD/Action_harvest", "EDIT_ME/BottomActionHUD/Action_advance_day",
	POPUP,
]

class RejectSave:
	extends RefCounted
	var calls: int = 0

	func save_current_slot(_slot_id: int, _state: Dictionary, _location := "hub") -> Dictionary:
		calls += 1
		return {"ok": false, "message": "Deterministic Field V4 QA persistence rejection."}

var failures: Array[String] = []
var checks: int = 0
var captures: Array[String] = []
var completed: Array[String] = []
var host: Control
var screen: Node
var run_root: String = ""
var capture_root: String = ""
var mouse_inside: bool = false
var pointer_events: int = 0
var last_pointer: Vector2 = Vector2.ZERO
var screen_identity: int = 0
var renderer_identity: int = 0
var rebuild_baseline: int = 0
var success_fx_entered: int = 0
var real_save_service: RefCounted
var authored_geometry: Array[Dictionary] = []
var expected_geometry: Array[Dictionary] = []
var capture_prefix: String = ""
var hidden_detail_observations: Array[Dictionary] = []
var hidden_detail_sizes_seen: Array[String] = []


func _ready() -> void:
	var isolated: String = OS.get_environment("MSF_TEST_SAVE_DIR")
	var qa_root: String = ProjectSettings.globalize_path(isolated).replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	var player: String = ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	if isolated.is_empty() or not qa_root.contains("manual_baseline_repair_v4") or qa_root == player or player.begins_with(qa_root + "/") or qa_root.begins_with(player + "/"):
		push_error("Manual Field QA requires a fresh named manual_baseline_repair_v4 MSF_TEST_SAVE_DIR outside player saves and their ancestors.")
		get_tree().quit(2)
		return
	for slot in range(1, 4):
		for suffix in ["", ".tmp", ".bak", ".deleted.bak"]:
			if FileAccess.file_exists(isolated.path_join(("my_sisters_farm_slot_%d.save" % slot) + String(suffix))):
				push_error("Manual Field QA refuses occupied saves/tmp/backups; no files are removed.")
				get_tree().quit(2)
				return
	if DisplayServer.get_name() == "headless" or QARichFixture.requested() or V6.is_parity_mode():
		push_error("Manual Field QA requires rendered normal gameplay, not headless/rich/parity.")
		get_tree().quit(2)
		return
	get_window().mouse_entered.connect(func() -> void: mouse_inside = true)
	get_window().mouse_exited.connect(func() -> void: mouse_inside = false)
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("MANUAL_FIELD_FEEDBACK_V4: " + message)


func _settle(frames: int = 8) -> void:
	for _frame in range(frames): await get_tree().process_frame


func _click_once(point: Vector2) -> void:
	# Exactly one motion/down/up. All following assertions/captures send NO input.
	var viewport: Viewport = get_viewport()
	if not mouse_inside:
		viewport.notify_mouse_entered()
		mouse_inside = true
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	pointer_events += 1
	last_pointer = point
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		event.position = point
		event.global_position = point
		viewport.push_input(event, true)
		pointer_events += 1


func _no_rebuild(label: String) -> void:
	_check(is_instance_valid(screen) and screen.get_instance_id() == screen_identity, label + ": same screen instance")
	if not is_instance_valid(screen): return
	_check(screen.renderer.get_instance_id() == renderer_identity, label + ": same renderer instance")
	_check(int(screen.get("_world_rebuild_total")) == rebuild_baseline, label + ": no full-world rebuild")
	_check(screen.qa_world_rebuilds_per_action() == 0, label + ": zero rebuilds/action metric")
	_geometry(label)


func _read_geometry(root: Node) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var paths: Array[String] = []
	for path in GEOMETRY_PATHS: paths.append(String(path))
	for plot_id in range(1, 13): paths.append("EDIT_ME/FieldArea/Plot%02d" % plot_id)
	for path in paths:
		var control: Control = root.get_node(path) as Control
		records.append({"path": path, "position": control.position, "size": control.size, "scale": control.scale, "rotation": control.rotation, "pivot": control.pivot_offset, "anchors": [control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom]})
	return records


func _geometry(label: String) -> void:
	for record in expected_geometry:
		var control: Control = screen.get_node(String(record["path"])) as Control
		var size_retained: bool = control.size.is_equal_approx(record["size"])
		if String(record["path"]) == "EDIT_ME/CropInfoPanel/DetailLabel" and not control.visible:
			# Godot can grow the hidden text-only diagnostic label's minimum size.
			# It owns no visible layout: exempt SIZE ONLY and report every unique size.
			var observation_key: String = UILocale.current_locale() + ":" + str(control.size)
			if not size_retained and not hidden_detail_sizes_seen.has(observation_key):
				hidden_detail_sizes_seen.append(observation_key)
				hidden_detail_observations.append({"locale": UILocale.current_locale(), "case": label, "path": String(record["path"]), "authored_size": [Vector2(record["size"]).x, Vector2(record["size"]).y], "observed_hidden_size": [control.size.x, control.size.y], "exception": "hidden text-only Label size; position/scale/anchors/rotation/pivot still strict; not visual geometry proof"})
			size_retained = true
		var same: bool = control.position.is_equal_approx(record["position"]) and size_retained and control.scale.is_equal_approx(record["scale"]) and is_equal_approx(control.rotation, float(record["rotation"])) and control.pivot_offset.is_equal_approx(record["pivot"]) and [control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom] == record["anchors"]
		_check(same, label + ": authored/manual geometry retained: " + String(record["path"]))


func _apply_layout_fixture() -> void:
	# Explicit nonpersistent manual-layout fixture; no scene file is changed.
	var area: Control = screen.get_node("EDIT_ME/FieldArea") as Control
	var preview: Control = screen.get_node("EDIT_ME/CropInfoPanel/CropPreview") as Control
	area.position += Vector2(20, 20)
	preview.position += Vector2(20, 20)
	preview.scale = Vector2(1.13, 0.89)
	for record in expected_geometry:
		var path: String = String(record["path"])
		if path == "EDIT_ME/FieldArea" or path == "EDIT_ME/CropInfoPanel/CropPreview":
			record["position"] = Vector2(record["position"]) + Vector2(20, 20)
		if path == "EDIT_ME/CropInfoPanel/CropPreview": record["scale"] = Vector2(1.13, 0.89)
	_geometry("FIXTURE +20 position and preview scale")


func _visible_feedback(expected: String, error: bool, label: String) -> void:
	var tip: Label = screen.get_node("EDIT_ME/CropInfoPanel/TipText") as Label
	var next_step: String = "" if error else _expected_next_step()
	var visible: String = expected + ("\n" + next_step if not next_step.is_empty() else "")
	_check(tip.is_visible_in_tree() and tip.get_global_rect().intersects(Rect2(Vector2.ZERO, Vector2(1280, 720))), label + ": feedback is on-screen")
	_check(tip.text == visible and not expected.is_empty(), label + ": exact result prefix then concise next step; guidance does not replace success")
	_check(String(screen.get("feedback")) == expected, label + ": stored feedback remains exact atomic result")
	_check(bool(screen.get("_feedback_is_error")) == error, label + ": correct success/error state")
	_check((screen.get_node("EDIT_ME/CropInfoPanel/DetailLabel") as Label).text.contains(expected), label + ": detail matches current feedback")
	_body_fits(tip, label)
	var guidance: String = _expected_full_guidance()
	if not guidance.is_empty():
		_check(tip.tooltip_text.contains(guidance) and tip.mouse_filter != Control.MOUSE_FILTER_IGNORE, label + ": full guidance available on hover")
	_no_rebuild(label)


func _expected_next_step() -> String:
	if int(GameState.data.get("orders_done", 0)) != 0: return ""
	var plot: Dictionary = GameState.get_plot()
	if int(GameState.data.inventory.get("crop_carrot", 0)) >= 1: return tr("Next: ORDERS.")
	if bool(plot.get("ready_to_harvest", false)): return tr("Next: HARVEST.")
	if not bool(plot.get("is_hoed", false)): return tr("Select a plot, then press TILL.")
	if String(plot.get("crop", "")).is_empty(): return tr("Next: PLANT.")
	if String(plot.get("crop", "")) == "carrot":
		return tr("Next: NEXT DAY.") if bool(plot.get("watered_today", false)) else tr("Next: WATER.")
	return ""


func _expected_full_guidance() -> String:
	if int(GameState.data.get("orders_done", 0)) != 0: return ""
	var plot: Dictionary = GameState.get_plot()
	if int(GameState.data.inventory.get("crop_carrot", 0)) >= 1: return tr("Carrot is in Storage. Open Orders to complete your first order.")
	if bool(plot.get("ready_to_harvest", false)): return tr("Carrot is ready. Press HARVEST.")
	if not bool(plot.get("is_hoed", false)): return tr("Select a plot, then press TILL.")
	if String(plot.get("crop", "")).is_empty(): return tr("Press PLANT, choose Carrot, then select a plot.")
	if String(plot.get("crop", "")) == "carrot":
		return tr("Press NEXT DAY. Water again tomorrow.") if bool(plot.get("watered_today", false)) else tr("Press WATER.")
	return ""


func _body_fits(tip: Label, label: String) -> void:
	_check(not tip.clip_text and tip.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING and tip.visible_characters == -1 and tip.lines_skipped == 0 and tip.max_lines_visible == -1, label + ": body has no clipping, ellipsis, skipped lines or character limit")
	var lines: int = tip.get_line_count()
	var height: float = 0.0
	for line in range(lines): height += float(tip.get_line_height(line))
	height += float(maxi(0, lines - 1) * tip.get_theme_constant("line_spacing"))
	_check(tip.get_visible_line_count() == lines and height <= tip.size.y + 1.0, label + ": all body lines fit authored rectangle without truncation")


func _idle_guidance(label: String) -> void:
	if not String(screen.get("feedback")).is_empty(): return
	var guidance: String = _expected_full_guidance()
	if guidance.is_empty(): return
	var tip: Label = screen.get_node("EDIT_ME/CropInfoPanel/TipText") as Label
	_check(tip.text == guidance, label + ": full first-session guidance visibly returns when no result is pending")
	_body_fits(tip, label)


func _rendered_plot(plot_id: int, label: String) -> void:
	var plot: Dictionary = GameState.get_plot(plot_id)
	_check(screen.renderer.plot_cache.get(plot_id, {}) == plot, label + ": renderer reads current committed plot")
	var bed: Node = screen.renderer.bed_world.get_node("Bed_%02d" % plot_id)
	var expected: String = "fertilized" if bool(plot.get("fertilizer_pending", false)) else ("tilled_wet" if bool(plot.get("watered_today", false)) else ("tilled_dry" if bool(plot.get("is_hoed", false)) else "untilled"))
	_check(String(bed.get("state")) == expected, label + ": bed state is current without another click")
	_check(bool(bed.get("fertilized")) == bool(plot.get("fertilizer_pending", false)), label + ": fertilizer flag is current")
	_check(bed.get("reconstruction_texture") != null, label + ": current bed texture exists")
	if not String(plot.get("crop", "")).is_empty():
		var values: Label = screen.get_node("EDIT_ME/CropInfoPanel/StatValues") as Label
		_check(values.text.contains(tr("Watered") if bool(plot.get("watered_today", false)) else tr("Dry")), label + ": current water detail visible")
		_check(screen.renderer.crop_world.get_node_or_null("Crop_%02d_%s" % [plot_id, plot.get("crop", "")]) != null, label + ": crop rendered")
	if bool(plot.get("fertilizer_pending", false)):
		_check((screen.get_node("EDIT_ME/CropInfoPanel/LifecycleLabel") as Label).text == tr("Fertilized"), label + ": fertilizer state visibly persistent")


func _selected_tool(action: String, label: String) -> void:
	var path: String = "EDIT_ME/BottomActionHUD/Action_harvest" if action == "harvest" else TOOLS + action
	var button: BaseButton = screen.get_node(path) as BaseButton
	_check(String(screen.get("_active_tool")) == action and bool(button.get_meta("field_selected", false)), label + ": active tool retained")
	var frame: Panel = button.get_node("ToolStateFrame") as Panel
	_check(frame.visible, label + ": selected tool frame visible")
	_check(frame.get_theme_stylebox("panel") == screen.tool_selected_style, label + ": selected frame survives press release")
	_check((screen.get_node("EDIT_ME/CropInfoPanel/TipHeading") as Label).text == tr("Selected: %s") % _tool_name(action), label + ": active tool heading retained")
	var heading: Label = screen.get_node("EDIT_ME/CropInfoPanel/TipHeading") as Label
	_check(heading.clip_text and heading.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS and heading.tooltip_text == heading.text, label + ": heading bounded with full hover caption")


func _tool_name(action: String) -> String:
	match action:
		"till": return tr("Till")
		"seed": return tr("Plant")
		"water": return tr("Water")
		"fertilize": return tr("Fertilize")
		"harvest": return tr("Harvest")
	return ""


func _press(path: String) -> void:
	var button: BaseButton = screen.get_node(path) as BaseButton
	_check(button.is_visible_in_tree() and not button.disabled, "Usable control: " + path)
	if not button.is_visible_in_tree() or button.disabled: return
	var fired: Array[bool] = [false]
	var witness := func() -> void: fired[0] = true
	button.pressed.connect(witness, CONNECT_ONE_SHOT)
	_click_once(button.get_global_rect().get_center())
	await _settle()
	if button.pressed.is_connected(witness): button.pressed.disconnect(witness)
	_check(fired[0], "Actual pointer activates: " + path)
	_idle_guidance("Control " + path)
	_no_rebuild("Control " + path)


func _tool(action: String) -> void:
	await _press("EDIT_ME/BottomActionHUD/Action_harvest" if action == "harvest" else TOOLS + action)
	await get_tree().create_timer(0.18).timeout
	_selected_tool(action, "Tool selection " + action)


func _plot_point(plot_id: int) -> Vector2:
	var polygon: PackedVector2Array = PixelMap.visual_interaction_polygon(plot_id)
	var center: Vector2 = Vector2.ZERO
	for vertex in polygon: center += vertex
	center /= polygon.size()
	return (screen.get_node("EDIT_ME/FieldArea") as Control).get_global_transform() * center


func _plot_action(plot_id: int, expected: String, action: String, error: bool = false) -> void:
	var label: String = "%s plot %d" % [action, plot_id]
	var action_before: Dictionary = GameState.data.duplicate(true)
	screen.qa_reset_last_clicked_plot()
	_click_once(_plot_point(plot_id))
	var stationary_events: int = pointer_events
	var stationary_point: Vector2 = last_pointer
	_check(screen.qa_last_clicked_plot_id() == plot_id, label + ": actual polygon pointer click")
	# Synchronous release assertion: no frame, mouse move, or second click required.
	_visible_feedback(expected, error, label + " immediate")
	_rendered_plot(plot_id, label + " immediate")
	if not error:
		var committed: Dictionary = GameState.get_plot(plot_id)
		match action:
			"till": _check(bool(committed.get("is_hoed", false)), label + ": synchronous till commit")
			"seed":
				_check(String(committed.get("crop", "")) == "carrot", label + ": synchronous seed commit")
				_check(int(GameState.data.inventory.seed_carrot) == int(action_before.inventory.seed_carrot) - 1, label + ": synchronous seed inventory delta")
			"water": _check(bool(committed.get("watered_today", false)), label + ": synchronous water commit")
			"fertilize": _check(bool(committed.get("fertilizer_pending", false)), label + ": synchronous fertilizer commit")
			"harvest":
				_check(String(committed.get("crop", "")).is_empty(), label + ": synchronous crop removal")
				_check(int(GameState.data.inventory.crop_carrot) == int(action_before.inventory.crop_carrot) + 1, label + ": synchronous Storage inventory delta")
				var reward: Node = screen.renderer.fx_world.get_node_or_null("HarvestReward_%02d" % plot_id)
				_check(reward != null, label + ": synchronous quantity popup exists")
				if reward != null:
					_check((reward.get_node("RewardQuantityLabel") as Label).text == "+1 " + tr("Carrot"), label + ": actual localized reward quantity")
	await _settle()
	await get_tree().create_timer(0.18).timeout
	_check(pointer_events == stationary_events and last_pointer == stationary_point, label + ": pointer stationary; no second input")
	_visible_feedback(expected, error, label + " stationary")
	_rendered_plot(plot_id, label + " stationary")
	_selected_tool(action, label + " stationary")
	completed.append(label + (" rejection" if error else " success"))


func _next_day() -> void:
	var next: BaseButton = screen.get_node("EDIT_ME/BottomActionHUD/Action_advance_day") as BaseButton
	var expected_day: int = int(GameState.data.get("day", 1)) + 1
	_click_once(next.get_global_rect().get_center())
	var stationary_events: int = pointer_events
	var expected: String = tr("Day %d. Energy restored.") % expected_day
	_visible_feedback(expected, false, "Next Day immediate")
	_check(int(GameState.data.get("day", 0)) == expected_day and int(GameState.data.get("energy", 0)) == 100, "Next Day commits day and energy")
	_rendered_plot(1, "Next Day immediate")
	await _settle()
	_check(pointer_events == stationary_events, "Next Day has no second input")
	_visible_feedback(expected, false, "Next Day stationary")
	completed.append("Next Day success")


func _on_fx_entered(node: Node) -> void:
	if String(node.name).begins_with("FX_") or String(node.name).begins_with("HarvestReward_"):
		success_fx_entered += 1


func _capture(name: String) -> void:
	var stationary_events: int = pointer_events
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var target: String = capture_root.path_join(name + ".png")
	_check(image != null and image.get_size() == Vector2i(1280, 720), "Native 1280x720 capture: " + name)
	_check(not FileAccess.file_exists(target), "Never overwrite capture: " + name)
	if image == null or FileAccess.file_exists(target): return
	_check(image.save_png(ProjectSettings.globalize_path(target)) == OK, "Capture saved: " + name)
	_check(pointer_events == stationary_events, "Capture has no input: " + name)
	captures.append(target)


func _without_status(state: Dictionary) -> Dictionary:
	var result: Dictionary = state.duplicate(true)
	result.erase("status_text")
	return result


func _run() -> void:
	run_root = REPORT_ROOT.path_join("RUN_%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_msec()])
	capture_root = run_root.path_join("CAPTURES")
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(run_root)):
		push_error("Manual Field QA refuses an existing evidence directory.")
		get_tree().quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_root)) != OK:
		push_error("Manual Field QA could not create a new evidence directory.")
		get_tree().quit(2)
		return
	get_window().size = Vector2i(1280, 720)
	var authored: Node = FIELD.instantiate()
	authored_geometry = _read_geometry(authored)
	authored.free()
	var main: Node = MAIN.instantiate()
	add_child(main)
	host = main.get_node("ScreenHost") as Control
	real_save_service = GameState.save_service
	await _settle()
	for locale in ["vi", "en"]:
		# Locale and reset are setup only; the entire crop loop below uses pointer UI.
		UILocale.set_locale(String(locale))
		GameState.new_state(1, false)
		ScreenRouter.go("field")
		await _settle()
		screen = host.get_child(host.get_child_count() - 1)
		screen_identity = screen.get_instance_id()
		renderer_identity = screen.renderer.get_instance_id()
		rebuild_baseline = int(screen.get("_world_rebuild_total"))
		expected_geometry = authored_geometry.duplicate(true)
		_geometry("Serialized manual baseline " + String(locale))
		capture_prefix = String(locale)
		if locale == "en":
			_apply_layout_fixture()
			capture_prefix += "_LAYOUT_FIXTURE"
		_check(screen.scene_file_path == "res://scenes/screens/05_field_gameplay.tscn", "Canonical Field route " + String(locale))
		_check(GameState.data.get("field_plots", []).size() == 12 and int(GameState.data.get("orders_done", -1)) == 0, "Twelve plots and first-session guidance fixture")
		screen.renderer.fx_world.child_entered_tree.connect(_on_fx_entered)
		if locale == "vi":
			_check(tr("Tilled plot %d.") != "Tilled plot %d.", "Vietnamese new action key is localized")
			_check(tr("Harvested +%d %s.\nStorage: %d.") != "Harvested +%d %s.\nStorage: %d.", "Vietnamese Storage reward key is localized")
			for key in ["Next: PLANT.", "Next: WATER.", "Next: NEXT DAY.", "Next: HARVEST.", "Next: ORDERS."]:
				_check(tr(String(key)) != String(key), "Vietnamese concise guidance localized: " + String(key))
		_idle_guidance("Initial untouched plot")
		await _tool("till")
		await _plot_action(1, tr("Tilled plot %d.") % 1, "till")
		_check(bool(GameState.get_plot(1).get("is_hoed", false)), "Till commits immediately")
		await _capture(capture_prefix + "_01_TILLED_STATIONARY")
		await _press(TOOLS + "seed")
		_check((screen.get_node(POPUP) as CanvasItem).visible, "Seed popup opened by pointer")
		await _press(POPUP + "/Seed_carrot")
		await _plot_action(1, tr("Planted %s on plot %d.") % [tr("Carrot"), 1], "seed")
		_check(GameState.get_plot(1).get("crop", "") == "carrot" and int(GameState.data.inventory.seed_carrot) == 5, "Plant commits crop and one seed")
		await _capture(capture_prefix + "_02_PLANTED_STATIONARY")
		await _tool("water")
		await _plot_action(1, tr("Watered plot %d.") % 1, "water")
		_check(bool(GameState.get_plot(1).get("watered_today", false)), "Water commits immediately")
		await _capture(capture_prefix + "_03_WATERED_STATIONARY")
		var before_water_retry: Dictionary = GameState.data.duplicate(true)
		var fx_before: int = success_fx_entered
		await _plot_action(1, tr("Already watered today."), "water", true)
		_check(_without_status(GameState.data) == _without_status(before_water_retry) and success_fx_entered == fx_before, "Water rejection changes no data or success FX")
		await _capture(capture_prefix + "_04_WATER_REJECTION")
		await _tool("fertilize")
		await _plot_action(1, tr("Fertilized plot %d.") % 1, "fertilize")
		_check(bool(GameState.get_plot(1).get("fertilizer_pending", false)), "Fertilizer commits immediately")
		await _capture(capture_prefix + "_05_FERTILIZED_STATIONARY")
		var before_fert_retry: Dictionary = GameState.data.duplicate(true)
		fx_before = success_fx_entered
		await _plot_action(1, tr("Already fertilized."), "fertilize", true)
		_check(_without_status(GameState.data) == _without_status(before_fert_retry) and success_fx_entered == fx_before, "Fertilizer rejection changes no data or success FX")
		await _capture(capture_prefix + "_06_FERTILIZER_REJECTION")
		await _next_day()
		_check(not bool(GameState.get_plot(1).get("fertilizer_pending", true)) and not bool(GameState.get_plot(1).get("watered_today", true)), "Next Day visibly consumes pending fertilizer and dries water")
		await _capture(capture_prefix + "_07_NEXT_DAY_STATIONARY")
		for _day in range(6):
			if bool(GameState.get_plot(1).get("ready_to_harvest", false)): break
			await _tool("water")
			await _plot_action(1, tr("Watered plot %d.") % 1, "water")
			await _next_day()
		_check(bool(GameState.get_plot(1).get("ready_to_harvest", false)), "Crop reaches ready through real UI actions")
		await _capture(capture_prefix + "_08_READY")
		await _tool("harvest")
		var before_harvest: int = int(GameState.data.inventory.crop_carrot)
		await _plot_action(1, tr("Harvested +%d %s.\nStorage: %d.") % [1, tr("Carrot"), before_harvest + 1], "harvest")
		_check(int(GameState.data.inventory.crop_carrot) == before_harvest + 1 and String(GameState.get_plot(1).get("crop", "")).is_empty(), "Harvest immediately grants quantity and clears crop")
		await _capture(capture_prefix + "_09_HARVEST_STORAGE_STATIONARY")
		# Persistent panel feedback must remain even after the transient reward expires.
		var stationary_events: int = pointer_events
		await get_tree().create_timer(0.9).timeout
		_check(pointer_events == stationary_events, "Harvest reward expires with no new pointer input")
		_visible_feedback(tr("Harvested +%d %s.\nStorage: %d.") % [1, tr("Carrot"), before_harvest + 1], false, "Harvest persistent Storage reward")
		await _capture(capture_prefix + "_10_HARVEST_PERSISTENT")
		fx_before = success_fx_entered
		await _plot_action(1, tr("Nothing is ready to harvest."), "harvest", true)
		_check(int(GameState.data.inventory.crop_carrot) == before_harvest + 1 and success_fx_entered == fx_before, "Harvest rejection neither duplicates crop nor success feedback")
		await _tool("till")
		await _plot_action(2, tr("Tilled plot %d.") % 2, "till")
		var before_reject: Dictionary = GameState.data.duplicate(true)
		var stored_path: String = OS.get_environment("MSF_TEST_SAVE_DIR").path_join("my_sisters_farm_slot_1.save")
		var stored_bytes: PackedByteArray = FileAccess.get_file_as_bytes(stored_path)
		var reject := RejectSave.new()
		GameState.save_service = reject
		fx_before = success_fx_entered
		# Expected failure source is fixed by GameState; never fake the UI result.
		var error_text: String = UILocale.translate_message("Could not save this action; your previous farm state was kept.")
		await _plot_action(3, error_text, "till", true)
		GameState.save_service = real_save_service
		_check(reject.calls == 1, "Persistence rejection attempted exactly one write")
		_check(_without_status(GameState.data) == _without_status(before_reject), "Persistence rejection rolls back gameplay")
		_check(FileAccess.get_file_as_bytes(stored_path) == stored_bytes, "Persistence rejection preserves stored bytes")
		_check(success_fx_entered == fx_before and String(screen.get("feedback")) == GameState.status, "Persistence rejection replaces success with actual error; no new success FX")
		await _capture(capture_prefix + "_11_SAVE_REJECTION_STATIONARY")
		completed.append(capture_prefix + " full pointer feedback loop")
	GameState.save_service = real_save_service
	var result: Dictionary = {"status": "PASS" if failures.is_empty() else "FAIL", "assertions": checks, "failures": failures, "completed_cases": completed, "captures": captures, "save_root": OS.get_environment("MSF_TEST_SAVE_DIR"), "input_path": "viewport motion/down/up only; no callback action fallback", "stationary_pointer_asserts": true, "manual_geometry_checks": "serialized visible baseline each locale; EN nonpersistent +20 FieldArea/preview position and preview scale (1.13,0.89) fixture retained through all actions", "hidden_detail_size_observations": hidden_detail_observations, "first_session_guidance": "atomic success prefix + concise state-derived next line, full hover guidance, and idle full guidance checked in VI/EN", "legacy_phase2_status": "NOT_REVALIDATED; old immediate full-tip assertions conflict with V4 success-prefix contract; no global phase2 PASS inferred", "pesticide_status": "NOT_IMPLEMENTED: no authoritative contract or approved spray asset", "human_visual_approval": false}
	var report: FileAccess = FileAccess.open(run_root.path_join("FIELD_FEEDBACK_RESULTS.json"), FileAccess.WRITE)
	if report == null:
		push_error("Manual Field QA could not save results.")
		get_tree().quit(1)
		return
	report.store_string(JSON.stringify(result, "\t"))
	report.close()
	print("MANUAL_FIELD_FEEDBACK_V4_PASS" if failures.is_empty() else "MANUAL_FIELD_FEEDBACK_V4_FAIL")
	print("Field assertions: %d; evidence: %s" % [checks, run_root])
	get_tree().quit(0 if failures.is_empty() else 1)
