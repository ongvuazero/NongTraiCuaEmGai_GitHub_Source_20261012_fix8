extends Node

const FIELD_SCENE = preload("res://scenes/screens/05_field_gameplay.tscn")
const Geometry = preload("res://v7/runtime/field_projection_v7_2.gd")

var failures: Array[String] = []
var screen: Node


func _ready() -> void:
	call_deferred("_run")


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("FIELD GUI CLICK V8 ASSERTION FAILED: " + message)


func _settle(frames := 8) -> void:
	for _frame in range(frames):
		await get_tree().process_frame


func _emit_field_gui_click(plot_id: int) -> void:
	var field_area := screen.get_node("EDIT_ME/FieldArea") as Control
	var coord := Geometry.grid_coord(plot_id)
	var polygon: PackedVector2Array = Geometry.cell_polygon(coord.x, coord.y)
	var local_point := Vector2.ZERO
	for point in polygon:
		local_point += point
	local_point /= float(polygon.size())
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = local_point
	# Exercise the real GUI signal route, not _unhandled_input directly.
	field_area.gui_input.emit(event)
	await _settle()


func _run() -> void:
	GameState.new_state(1, false)
	GameState.data["energy"] = 999
	GameState.data["inventory"]["seed_carrot"] = 30
	screen = FIELD_SCENE.instantiate()
	add_child(screen)
	await _settle(15)
	var field_area := screen.get_node("EDIT_ME/FieldArea") as Control
	var callback := Callable(screen, "_on_field_area_gui_input")
	_assert_true(field_area.gui_input.is_connected(callback), "FieldArea.gui_input handler not connected")
	_assert_true(field_area.mouse_filter == Control.MOUSE_FILTER_STOP, "FieldArea does not receive GUI mouse input")
	screen.call("_on_action_pressed", "till")
	await _settle()
	await _emit_field_gui_click(1)
	_assert_true(bool(GameState.get_plot(1).get("is_hoed", false)), "Plot01 did not till through GUI click route")
	await _emit_field_gui_click(12)
	_assert_true(bool(GameState.get_plot(12).get("is_hoed", false)), "Plot12 did not till through GUI click route")
	screen.call("_select_seed_from_popup", "carrot")
	await _settle()
	await _emit_field_gui_click(12)
	_assert_true(String(GameState.get_plot(12).get("crop", "")) == "carrot", "Plot12 did not plant through GUI click route")
	if failures.is_empty():
		print("FIELD_GAMEPLAY_GUI_CLICK_V8_TEST_PASS")
		get_tree().quit(0)
	else:
		print("FIELD_GAMEPLAY_GUI_CLICK_V8_TEST_FAIL: %s" % "; ".join(failures))
		get_tree().quit(1)
