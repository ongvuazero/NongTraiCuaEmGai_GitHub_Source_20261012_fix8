extends Node

const FIELD_SCENE = preload("res://scenes/screens/05_field_gameplay.tscn")
const PixelMap = preload("res://v7/production/field_pixel_map_v2.gd")
const REPORT_DIR := "res://REPORTS"

var failures: Array[String] = []
var screen: Node
var serialized_rects: Dictionary = {}
var max_rebuilds := 0
var latency_samples: Array[int] = []
var vfx_frames: Array[Image] = []


func _ready() -> void:
	call_deferred("_run")


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("FIELD FEEL V10 ASSERTION FAILED: " + message)


func _settle(frames := 5) -> void:
	for _frame in range(frames):
		await get_tree().process_frame


func _capture() -> Image:
	await _settle(2)
	return get_viewport().get_texture().get_image()


func _save_image(image: Image, file_name: String) -> void:
	var error := image.save_png(ProjectSettings.globalize_path(REPORT_DIR.path_join(file_name)))
	_assert_true(error == OK, "Could not save " + file_name)


func _save_sheet(images: Array[Image], columns: int, file_name: String) -> void:
	if images.is_empty():
		_assert_true(false, "No images available for " + file_name)
		return
	var cell_size := Vector2i(640, 360) if columns <= 2 else Vector2i(426, 360)
	var rows := ceili(float(images.size()) / float(columns))
	var sheet := Image.create(cell_size.x * columns, cell_size.y * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("f5ead4"))
	for index in range(images.size()):
		var frame := images[index].duplicate()
		frame.resize(cell_size.x, cell_size.y, Image.INTERPOLATE_LANCZOS)
		frame.convert(Image.FORMAT_RGBA8)
		var target := Vector2i((index % columns) * cell_size.x, (index / columns) * cell_size.y)
		sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, cell_size), target)
	_save_image(sheet, file_name)


func _target(plot_id: int) -> BaseButton:
	return screen.get_node("EDIT_ME/FieldArea/Plot%02d/TECHNICAL/ClickTarget" % plot_id) as BaseButton


func _press_plot(plot_id: int, capture_vfx := false) -> Image:
	var target := _target(plot_id)
	_assert_true(target.visible and not target.disabled, "Plot%02d ClickTarget is not interactive" % plot_id)
	var click_position := target.get_global_rect().get_center()
	await _send_mouse_click(click_position)
	await _settle(3)
	_check_action_metrics(plot_id)
	var frame := await _capture()
	if capture_vfx:
		vfx_frames.append(_vfx_closeup(frame, plot_id))
	return frame


func _send_mouse_click(click_position: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = click_position
	press.global_position = click_position
	Input.parse_input_event(press)
	await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = click_position
	release.global_position = click_position
	Input.parse_input_event(release)
	await get_tree().process_frame


func _vfx_closeup(frame: Image, plot_id: int) -> Image:
	var target := PixelMap.visual_plot_rect(plot_id).grow(72.0)
	var bounds := Rect2(Vector2.ZERO, Vector2(frame.get_size()))
	target = target.intersection(bounds)
	return frame.get_region(Rect2i(target))


func _check_action_metrics(plot_id: int) -> void:
	var rebuilds := int(screen.call("qa_world_rebuilds_per_action"))
	var latency := int(screen.call("qa_action_latency_ms"))
	max_rebuilds = maxi(max_rebuilds, rebuilds)
	latency_samples.append(latency)
	_assert_true(rebuilds <= 1, "Plot%02d action rebuilt Field %d times" % [plot_id, rebuilds])


func _assert_runtime_rects_unchanged() -> void:
	for plot_id in range(1, 13):
		var plot := screen.get_node("EDIT_ME/FieldArea/Plot%02d" % plot_id) as Control
		var runtime_rect := Rect2(plot.position, plot.size)
		_assert_true(runtime_rect == Rect2(serialized_rects[plot_id]), "Plot%02d authored rect changed" % plot_id)


func _test_edges_and_gutters() -> void:
	var rects: Dictionary = {}
	for plot_id in range(1, 13):
		var plot := screen.get_node("EDIT_ME/FieldArea/Plot%02d" % plot_id) as Control
		var rect := Rect2(plot.position, plot.size)
		rects[plot_id] = rect
		var edge_points := [
			Vector2(rect.position.x + 1, rect.get_center().y),
			Vector2(rect.end.x - 1, rect.get_center().y),
			Vector2(rect.get_center().x, rect.position.y + 1),
			Vector2(rect.get_center().x, rect.end.y - 1),
		]
		for point in edge_points:
			var owners := 0
			for candidate in range(1, 13):
				if Rect2(serialized_rects[candidate]).has_point(point):
					owners += 1
			_assert_true(owners == 1, "Plot%02d inside edge point has %d click owners" % [plot_id, owners])
			screen.call("qa_reset_last_clicked_plot")
			var field_area := screen.get_node("EDIT_ME/FieldArea") as Control
			await _send_mouse_click(field_area.get_global_transform_with_canvas() * point)
			await _settle(2)
			_assert_true(int(screen.call("qa_last_clicked_plot_id")) == plot_id, "Plot%02d inside edge click routed incorrectly" % plot_id)
	for row in range(3):
		for column in range(3):
			var left_id := row * 4 + column + 1
			var left_rect := Rect2(rects[left_id])
			var right_rect := Rect2(rects[left_id + 1])
			var gutter := Vector2((left_rect.end.x + right_rect.position.x) * 0.5, left_rect.get_center().y)
			var owners := 0
			for candidate in range(1, 13):
				if Rect2(rects[candidate]).has_point(gutter):
					owners += 1
			_assert_true(owners == 0, "Gutter between Plot%02d and Plot%02d belongs to a click target" % [left_id, left_id + 1])
			screen.call("qa_reset_last_clicked_plot")
			var field_area := screen.get_node("EDIT_ME/FieldArea") as Control
			await _send_mouse_click(field_area.get_global_transform_with_canvas() * gutter)
			await _settle(2)
			_assert_true(int(screen.call("qa_last_clicked_plot_id")) == 0, "Gutter between Plot%02d and Plot%02d caused a plot click" % [left_id, left_id + 1])


func _assert_vfx_anchor(plot_id: int, action: String) -> void:
	var renderer: Node = screen.get("renderer")
	var fx := renderer.fx_world.get_node_or_null("FX_%s_%02d" % [action, plot_id]) as Node2D
	_assert_true(fx != null, "%s VFX missing on Plot%02d" % [action, plot_id])
	if fx != null:
		var target_anchor: Vector2 = fx.get_meta("target_anchor", Vector2(-9999, -9999))
		_assert_true(target_anchor.distance_to(PixelMap.visual_crop_anchor(plot_id)) < 0.1, "%s VFX is offset from Plot%02d crop anchor" % [action, plot_id])


func _assert_farmer_alignment() -> void:
	var root := "res://assets/field_approved_v1/runtime/farmer_aligned"
	for action in ["IDLE", "TILL", "PLANT", "WATER", "HARVEST"]:
		var centers: Array[float] = []
		var bottoms: Array[int] = []
		for index in range(1, 9):
			var stem: String = String(action).to_lower()
			var texture := load("%s/%s/%s_%02d.png" % [root, action, stem, index]) as Texture2D
			_assert_true(texture != null, "Missing aligned %s frame %02d" % [action, index])
			if texture == null:
				continue
			var used := texture.get_image().get_used_rect()
			centers.append(float(used.position.x) + float(used.size.x) * 0.5)
			bottoms.append(used.end.y)
		if not centers.is_empty():
			var center_spread: float = centers.max() - centers.min()
			var bottom_spread: int = bottoms.max() - bottoms.min()
			_assert_true(center_spread <= 1.0, "%s horizontal frame jitter is %.2f px" % [action, center_spread])
			_assert_true(bottom_spread == 0, "%s foot contact jitter is %d px" % [action, bottom_spread])


func _make_ready(plot_ids: Array[int]) -> void:
	var plots: Array = GameState.data.get("field_plots", [])
	for plot_id in plot_ids:
		var plot: Dictionary = plots[plot_id - 1]
		plot["is_hoed"] = true
		plot["crop"] = "carrot"
		plot["growth_stage"] = 4
		plot["ready_to_harvest"] = true
		plot["watered_today"] = false
		plots[plot_id - 1] = plot
	GameState.data["field_plots"] = plots
	GameState.changed.emit()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_DIR))
	get_window().size = Vector2i(1280, 720)
	var reference := FIELD_SCENE.instantiate()
	for plot_id in range(1, 13):
		var plot := reference.get_node("EDIT_ME/FieldArea/Plot%02d" % plot_id) as Control
		serialized_rects[plot_id] = Rect2(plot.position, plot.size)
	reference.free()
	GameState.new_state(1, false)
	GameState.data["energy"] = 999
	GameState.data["inventory"]["seed_carrot"] = 40
	screen = FIELD_SCENE.instantiate()
	add_child(screen)
	await _settle(15)
	_assert_runtime_rects_unchanged()
	await _test_edges_and_gutters()
	_assert_farmer_alignment()

	# Debug overlay directly visualizes the twelve authored input rectangles.
	screen.call("qa_set_debug_mode", "hitboxes")
	await _settle(3)
	_save_image(await _capture(), "FIELD_HITBOX_DEBUG.png")
	screen.call("qa_set_debug_mode", "")

	# Center-click every authored target. First four frames form the TILL sequence.
	screen.call("_on_action_pressed", "till")
	var till_frames: Array[Image] = []
	for plot_id in range(1, 13):
		var frame := await _press_plot(plot_id, plot_id == 1)
		_assert_true(bool(GameState.get_plot(plot_id).get("is_hoed", false)), "Center click did not till Plot%02d" % plot_id)
		_assert_true(int(screen.call("qa_last_clicked_plot_id")) == plot_id, "Plot%02d click routed to wrong plot" % plot_id)
		if plot_id <= 4:
			till_frames.append(frame)
	_save_sheet(till_frames, 2, "V10_TILL_SEQUENCE.png")

	# Plant four crops and capture plant VFX on the crop anchor.
	screen.call("_select_seed_from_popup", "carrot")
	await _settle(4)
	for plot_id in range(1, 5):
		await _press_plot(plot_id, plot_id == 1)
		_assert_true(String(GameState.get_plot(plot_id).get("crop", "")) == "carrot", "Plant failed on Plot%02d" % plot_id)
		if plot_id == 1:
			_assert_vfx_anchor(plot_id, "seed")

	# Rapid WATER on four plots.
	screen.call("_on_action_pressed", "water")
	var water_frames: Array[Image] = []
	for plot_id in range(1, 5):
		var frame := await _press_plot(plot_id, plot_id == 1)
		water_frames.append(frame)
		_assert_true(bool(GameState.get_plot(plot_id).get("watered_today", false)), "Water failed on Plot%02d" % plot_id)
		if plot_id == 1:
			_assert_vfx_anchor(plot_id, "water")
	_save_sheet(water_frames, 2, "V10_WATER_SEQUENCE.png")

	# Fertilize supplies the fourth VFX close-up.
	screen.call("_on_action_pressed", "fertilize")
	await _press_plot(1, true)
	_assert_vfx_anchor(1, "fertilize")

	# Ready four crops and rapidly harvest them.
	_make_ready([1, 2, 3, 4])
	await _settle(6)
	screen.call("_on_action_pressed", "harvest")
	var harvest_frames: Array[Image] = []
	for plot_id in range(1, 5):
		var frame := await _press_plot(plot_id, plot_id == 1)
		harvest_frames.append(frame)
		_assert_true(String(GameState.get_plot(plot_id).get("crop", "")) == "", "Harvest failed on Plot%02d" % plot_id)
		if plot_id == 1:
			_assert_vfx_anchor(plot_id, "harvest")
	_save_sheet(harvest_frames, 2, "V10_HARVEST_SEQUENCE.png")
	_save_sheet(vfx_frames, 3, "V10_VFX_CLOSEUPS.png")

	# Effects must be transient and cleanly disappear.
	await get_tree().create_timer(0.75).timeout
	var renderer: Node = screen.get("renderer")
	var lingering := 0
	for child in renderer.fx_world.get_children():
		if String(child.name).begins_with("FX_"):
			lingering += 1
	_assert_true(lingering == 0, "Action VFX did not finish within the allowed timing")

	var average_latency := 0.0
	if not latency_samples.is_empty():
		var total := 0
		for value in latency_samples:
			total += value
		average_latency = float(total) / float(latency_samples.size())
	print("FIELD_V10_MAX_REBUILDS=%d" % max_rebuilds)
	print("FIELD_V10_AVERAGE_LATENCY_MS=%.2f" % average_latency)
	if failures.is_empty():
		print("FIELD_FEEL_V10_TEST_PASS")
		get_tree().quit(0)
	else:
		print("FIELD_FEEL_V10_TEST_FAIL: %s" % "; ".join(failures))
		get_tree().quit(1)
