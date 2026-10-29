extends Node

const FIELD_SCENE = preload("res://scenes/screens/05_field_gameplay.tscn")
const PixelMap = preload("res://v7/production/field_pixel_map_v2.gd")
const REPORT_DIR := "res://REPORTS"

var failures: Array[String] = []
var screen: Node


func _ready() -> void:
	call_deferred("_run")


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("FIELD RESPONSE V12 ASSERTION FAILED: " + message)


func _settle(frames := 3) -> void:
	for _frame in range(frames):
		await get_tree().process_frame


func _capture() -> Image:
	await _settle(2)
	return get_viewport().get_texture().get_image()


func _save(image: Image, file_name: String) -> void:
	var result := image.save_png(ProjectSettings.globalize_path(REPORT_DIR.path_join(file_name)))
	_assert_true(result == OK, "Could not save " + file_name)


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


func _gutter_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	for row in range(3):
		for column in range(3):
			var left := PixelMap.visual_plot_rect(row * 4 + column + 1)
			var right := PixelMap.visual_plot_rect(row * 4 + column + 2)
			points.append(Vector2((left.end.x + right.position.x) * 0.5, (left.get_center().y + right.get_center().y) * 0.5))
	for row in range(2):
		for column in range(4):
			var above := PixelMap.visual_plot_rect(row * 4 + column + 1)
			var below := PixelMap.visual_plot_rect((row + 1) * 4 + column + 1)
			points.append(Vector2((above.get_center().x + below.get_center().x) * 0.5, (above.end.y + below.position.y) * 0.5))
	return points


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_DIR))
	get_window().size = Vector2i(1280, 720)
	GameState.new_state(1, false)
	GameState.data["energy"] = 999
	screen = FIELD_SCENE.instantiate()
	add_child(screen)
	await _settle(12)
	var rebuild_baseline := int(screen.get("_world_rebuild_total"))

	# Close-up proof: opaque-enough cyan shows the exact usable-soil footprint.
	screen.call("qa_set_debug_mode", "hit_polygons")
	await _settle(2)
	var full_debug := await _capture()
	var closeup_rect := Rect2i(225, 250, 775, 345)
	_save(full_debug.get_region(closeup_rect), "V12_01_HIT_POLYGON_CLOSEUP.png")

	# Gutter points are marked red and must resolve to zero through real input.
	var gutters := _gutter_points()
	var overlay: Node = screen.get("debug_overlay")
	overlay.call("set_gutter_points", gutters)
	screen.call("_on_action_pressed", "till")
	var hoed_before := 0
	for plot in GameState.data.get("field_plots", []):
		if bool(plot.get("is_hoed", false)):
			hoed_before += 1
	for point in gutters:
		_assert_true(int(screen.call("_plot_at_point", point)) == 0, "Gutter point resolved to a plot")
		screen.call("qa_reset_last_clicked_plot")
		await _send_mouse(point)
		_assert_true(int(screen.call("qa_last_clicked_plot_id")) == 0, "Gutter triggered a plot")
	var hoed_after := 0
	for plot in GameState.data.get("field_plots", []):
		if bool(plot.get("is_hoed", false)):
			hoed_after += 1
	_assert_true(hoed_after == hoed_before, "Gutter input changed gameplay state")
	_save(await _capture(), "V12_02_GUTTER_TEST.png")

	# Every center and near-edge interior point maps to its own plot; real clicks
	# till all plots immediately without a world rebuild.
	overlay.call("set_gutter_points", PackedVector2Array())
	screen.call("qa_set_debug_mode", "")
	for plot_id in range(1, 13):
		var polygon := PixelMap.visual_interaction_polygon(plot_id)
		var center := _centroid(polygon)
		_assert_true(int(screen.call("_plot_at_point", center)) == plot_id, "Plot%02d center offset" % plot_id)
		for vertex in polygon:
			var inside_edge := vertex.lerp(center, 0.12)
			_assert_true(int(screen.call("_plot_at_point", inside_edge)) == plot_id, "Plot%02d edge offset" % plot_id)
		await _send_mouse(center)
		_assert_true(bool(GameState.get_plot(plot_id).get("is_hoed", false)), "Plot%02d did not commit immediately" % plot_id)
		_assert_true(int(screen.call("qa_world_rebuilds_per_action")) == 0, "Plot%02d rebuilt the world" % plot_id)

	_assert_true(int(screen.get("_world_rebuild_total")) == rebuild_baseline, "Normal V12 actions caused a full rebuild")
	_save(await _capture(), "V12_12_FULL_RUNTIME.png")
	print("FIELD_V12_FULL_REBUILDS_PER_ACTION=0")
	if failures.is_empty():
		print("FIELD_RESPONSE_V12_GEOMETRY_TEST_PASS")
		get_tree().quit(0)
	else:
		print("FIELD_RESPONSE_V12_GEOMETRY_TEST_FAIL: %s" % "; ".join(failures))
		get_tree().quit(1)
