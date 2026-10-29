extends Node

const FIELD_SCENE = preload("res://scenes/screens/05_field_gameplay.tscn")
const PixelMap = preload("res://v7/production/field_pixel_map_v2.gd")
const REPORT_DIR := "res://REPORTS"

var failures: Array[String] = []
var screen: Node
var latency_samples: Array[float] = []
var max_rebuilds := 0


func _ready() -> void:
	call_deferred("_run")


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("FIELD RESPONSE V11 ASSERTION FAILED: " + message)


func _settle(frames := 3) -> void:
	for _frame in range(frames):
		await get_tree().process_frame


func _capture() -> Image:
	await _settle(2)
	return get_viewport().get_texture().get_image()


func _save(image: Image, file_name: String) -> void:
	var result := image.save_png(ProjectSettings.globalize_path(REPORT_DIR.path_join(file_name)))
	_assert_true(result == OK, "Could not save " + file_name)


func _sheet(images: Array[Image], columns: int, cell_size: Vector2i, file_name: String) -> void:
	var rows := ceili(float(images.size()) / float(columns))
	var output := Image.create(cell_size.x * columns, cell_size.y * rows, false, Image.FORMAT_RGBA8)
	output.fill(Color("f4ead6"))
	for index in range(images.size()):
		var frame := images[index].duplicate()
		frame.resize(cell_size.x, cell_size.y, Image.INTERPOLATE_LANCZOS)
		frame.convert(Image.FORMAT_RGBA8)
		output.blit_rect(frame, Rect2i(Vector2i.ZERO, cell_size), Vector2i((index % columns) * cell_size.x, (index / columns) * cell_size.y))
	_save(output, file_name)


func _centroid(polygon: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in polygon:
		center += point
	return center / float(polygon.size())


func _send_mouse(local_point: Vector2) -> void:
	var field_area := screen.get_node("EDIT_ME/FieldArea") as Control
	var global_point := field_area.get_global_transform_with_canvas() * local_point
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = global_point
	press.global_position = global_point
	Input.parse_input_event(press)
	await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = global_point
	release.global_position = global_point
	Input.parse_input_event(release)
	await get_tree().process_frame


func _click_plot(plot_id: int) -> void:
	await _send_mouse(_centroid(PixelMap.visual_plot_polygon(plot_id)))
	await _settle(2)
	var rebuilds := int(screen.call("qa_world_rebuilds_per_action"))
	var latency := float(screen.call("qa_action_latency_ms"))
	max_rebuilds = maxi(max_rebuilds, rebuilds)
	latency_samples.append(latency)
	_assert_true(rebuilds == 0, "Plot%02d caused %d full world rebuilds" % [plot_id, rebuilds])
	_assert_true(int(screen.call("qa_last_clicked_plot_id")) == plot_id, "Plot%02d real input routed incorrectly" % plot_id)


func _closeup(frame: Image, plot_id: int) -> Image:
	var region := PixelMap.visual_plot_rect(plot_id).grow(82.0)
	region = region.intersection(Rect2(Vector2.ZERO, Vector2(frame.get_size())))
	return frame.get_region(Rect2i(region))


func _capture_vfx(action: String, plot_id: int, file_name: String) -> void:
	var renderer: Node = screen.get("renderer")
	var effect := renderer.fx_world.get_node_or_null("FX_%s_%02d" % [action, plot_id]) as Node2D
	_assert_true(effect != null, "%s VFX was not created" % action)
	if effect == null:
		return
	var frame_count := int(effect.get_meta("frame_count", 0))
	var duration := float(effect.get_meta("duration", 0.0))
	var anchor: Vector2 = effect.get_meta("target_anchor", Vector2(-9999, -9999))
	_assert_true(frame_count >= 5 and frame_count <= 8, "%s VFX frame count is %d" % [action, frame_count])
	_assert_true(anchor.distance_to(PixelMap.visual_crop_anchor(plot_id)) < 0.1, "%s VFX target anchor is wrong" % action)
	var frames: Array[Image] = []
	for index in range(frame_count):
		frames.append(_closeup(await _capture(), plot_id))
		if index < frame_count - 1:
			await get_tree().create_timer(duration / float(frame_count + 1)).timeout
	_sheet(frames, 4, Vector2i(320, 220), file_name)


func _animation_contact(action: String, file_name: String) -> void:
	var frames: Array[Image] = []
	var stem: String = action.to_lower()
	for index in range(1, 9):
		var texture := load("res://assets/field_approved_v1/runtime/farmer_aligned/%s/%s_%02d.png" % [action, stem, index]) as Texture2D
		_assert_true(texture != null, "Missing %s frame %02d" % [action, index])
		if texture != null:
			frames.append(texture.get_image())
	_sheet(frames, 4, Vector2i(209, 189), file_name)


func _set_ready(plot_id: int) -> void:
	var plots: Array = GameState.data.get("field_plots", [])
	var plot: Dictionary = plots[plot_id - 1]
	plot["is_hoed"] = true
	plot["crop"] = "carrot"
	plot["growth_stage"] = 4
	plot["ready_to_harvest"] = true
	plot["watered_today"] = false
	plots[plot_id - 1] = plot
	GameState.data["field_plots"] = plots
	var renderer: Node = screen.get("renderer")
	renderer.update_plot(GameState.get_plot(plot_id), plot_id)


func _count_hoed() -> int:
	var count := 0
	for plot in GameState.data.get("field_plots", []):
		if bool(plot.get("is_hoed", false)):
			count += 1
	return count


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_DIR))
	get_window().size = Vector2i(1280, 720)
	GameState.new_state(1, false)
	GameState.data["energy"] = 999
	GameState.data["inventory"]["seed_carrot"] = 40
	screen = FIELD_SCENE.instantiate()
	add_child(screen)
	await _settle(12)
	var initial_rebuild_total := int(screen.get("_world_rebuild_total"))
	var farmer: Node2D = screen.get("farmer")
	var farmer_instance := farmer.get_instance_id()

	# Polygon debug is drawn from the exact same PixelMap polygons as bed art/input.
	screen.call("qa_set_debug_mode", "hit_polygons")
	await _settle(2)
	_save(await _capture(), "V11_01_HIT_POLYGON_DEBUG.png")

	# Real gutter presses must not resolve to any polygon or mutate a plot.
	screen.call("_on_action_pressed", "till")
	var hoed_before_gutters := _count_hoed()
	for row in range(3):
		for column in range(3):
			var left_id := row * 4 + column + 1
			var left_rect := PixelMap.visual_plot_rect(left_id)
			var right_rect := PixelMap.visual_plot_rect(left_id + 1)
			var gutter := Vector2((left_rect.end.x + right_rect.position.x) * 0.5, (left_rect.get_center().y + right_rect.get_center().y) * 0.5)
			_assert_true(screen.call("_plot_at_point", gutter) == 0, "Gutter resolves to a plot")
			screen.call("qa_reset_last_clicked_plot")
			await _send_mouse(gutter)
			_assert_true(int(screen.call("qa_last_clicked_plot_id")) == 0, "Gutter triggered plot input")
	_assert_true(_count_hoed() == hoed_before_gutters, "Gutter click changed gameplay state")
	_save(await _capture(), "V11_02_GUTTER_CLICK_TEST.png")
	screen.call("qa_set_debug_mode", "")

	# Real center input across all twelve plots; action is immediate and rebuild-free.
	var till_vfx_captured := false
	for plot_id in range(1, 13):
		await _click_plot(plot_id)
		_assert_true(bool(GameState.get_plot(plot_id).get("is_hoed", false)), "Plot%02d did not till" % plot_id)
		if not till_vfx_captured:
			await _capture_vfx("till", plot_id, "V11_08_TILL_VFX.png")
			till_vfx_captured = true
	_save(await _capture(), "V11_03_RAPID_12_PLOT_INPUT.png")

	# Plant Plot01 first and let its evidence capture finish so the farmer has
	# reached the left side. The following Plot12 click then measures a meaningful
	# cross-field retarget rather than whatever position the rapid till pass left.
	screen.call("_select_seed_from_popup", "carrot")
	await _settle(2)
	await _click_plot(1)
	_assert_true(String(GameState.get_plot(1).get("crop", "")) == "carrot", "Plot01 did not plant")
	await _capture_vfx("seed", 1, "V11_09_PLANT_VFX.png")

	# Persistent farmer retargets smoothly after immediate gameplay commits.
	_assert_true(farmer.get_instance_id() == farmer_instance, "Farmer was recreated during actions")
	var movement_frames: Array[Image] = []
	var farmer_start := farmer.position
	await _click_plot(12)
	_assert_true(String(GameState.get_plot(12).get("crop", "")) == "carrot", "Gameplay waited for farmer movement")
	var destination: Vector2 = screen.call("_stable_farmer_path_anchor", 12)
	_assert_true(farmer.position.distance_to(destination) > 1.0, "Farmer teleported to Plot12")
	movement_frames.append(await _capture())
	await get_tree().create_timer(0.07).timeout
	movement_frames.append(await _capture())
	await get_tree().create_timer(0.07).timeout
	movement_frames.append(await _capture())
	await get_tree().create_timer(0.14).timeout
	movement_frames.append(await _capture())
	_assert_true(farmer.position.distance_to(destination) < 1.0, "Farmer did not reach the retargeted path anchor")
	_assert_true(farmer_start.distance_to(destination) > 20.0, "Farmer movement QA did not cover a meaningful distance")
	_assert_true(farmer.get_instance_id() == farmer_instance, "Farmer instance changed during movement")
	_sheet(movement_frames, 2, Vector2i(640, 360), "V11_04_FARMER_MOVE_SEQUENCE.png")

	# Water VFX on Plot01.
	screen.call("_on_action_pressed", "water")
	await _click_plot(1)
	await _capture_vfx("water", 1, "V11_10_WATER_VFX.png")

	# Fertilizer VFX on Plot01.
	screen.call("_on_action_pressed", "fertilize")
	await _click_plot(1)
	await _capture_vfx("fertilize", 1, "V11_11_FERTILIZE_VFX.png")

	# Harvest VFX on Plot01.
	_set_ready(1)
	screen.call("_on_action_pressed", "harvest")
	await _click_plot(1)
	await _capture_vfx("harvest", 1, "V11_12_HARVEST_VFX.png")

	_animation_contact("TILL", "V11_05_TILL_ANIMATION_CONTACT.png")
	_animation_contact("PLANT", "V11_05B_PLANT_ANIMATION_CONTACT.png")
	_animation_contact("WATER", "V11_06_WATER_ANIMATION_CONTACT.png")
	_animation_contact("HARVEST", "V11_07_HARVEST_ANIMATION_CONTACT.png")

	_assert_true(int(screen.get("_world_rebuild_total")) == initial_rebuild_total, "Normal actions triggered a full world rebuild")
	var average_latency := 0.0
	if not latency_samples.is_empty():
		var total := 0.0
		for value in latency_samples:
			total += value
		average_latency = total / float(latency_samples.size())
	_assert_true(max_rebuilds == 0, "Full world rebuild count per action is not zero")
	_assert_true(average_latency < 12.0, "Average action processing %.2f ms exceeds 12 ms" % average_latency)
	print("FIELD_V11_FULL_REBUILDS_PER_ACTION=%d" % max_rebuilds)
	print("FIELD_V11_AVERAGE_ACTION_MS=%.2f" % average_latency)
	if failures.is_empty():
		print("FIELD_RESPONSE_V11_TEST_PASS")
		get_tree().quit(0)
	else:
		print("FIELD_RESPONSE_V11_TEST_FAIL: %s" % "; ".join(failures))
		get_tree().quit(1)
