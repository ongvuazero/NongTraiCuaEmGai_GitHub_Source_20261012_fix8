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
		push_error("FIELD GAMEPLAY RESTORE V7 ASSERTION FAILED: " + message)


func _settle(frames := 10) -> void:
	for _frame in range(frames):
		await get_tree().process_frame


func _plot(plot_id: int) -> Dictionary:
	return GameState.get_plot(plot_id)


func _click_plot(plot_id: int) -> void:
	var coord := Geometry.grid_coord(plot_id)
	var polygon: PackedVector2Array = Geometry.cell_polygon(coord.x, coord.y)
	var local_point := Vector2.ZERO
	for point in polygon:
		local_point += point
	local_point /= float(polygon.size())
	_assert_true(Geometry.hit_test_plot(local_point) == plot_id, "Plot %02d center does not hit its runtime click target" % plot_id)
	var field_area := screen.get_node("EDIT_ME/FieldArea") as Control
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = field_area.get_global_transform_with_canvas() * local_point
	screen.call("_unhandled_input", event)
	await _settle()


func _assert_no_range_gate() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/screens/field_screen.gd")
	for forbidden in ["_in_action_range", "interaction_range", "farmer_distance", "distance_to"]:
		_assert_true(source.find(forbidden) == -1, "Field runtime still contains range gate token: " + forbidden)


func _make_ready(plot_id: int) -> void:
	var plots: Array = GameState.data.get("field_plots", [])
	var plot: Dictionary = plots[plot_id - 1]
	plot["is_hoed"] = true
	plot["crop"] = "carrot"
	plot["growth_stage"] = 4
	plot["ready_to_harvest"] = true
	plot["watered_today"] = false
	plots[plot_id - 1] = plot
	GameState.data["field_plots"] = plots


func _run() -> void:
	_assert_no_range_gate()
	GameState.new_state(1, false)
	GameState.data["energy"] = 999
	GameState.data["inventory"]["seed_carrot"] = 30
	screen = FIELD_SCENE.instantiate()
	add_child(screen)
	await _settle(15)

	# Global toolbar proof: WATER remains selectable even though Plot01 is invalid.
	var water_button := screen.get_node("EDIT_ME/BottomActionHUD/ToolGroup/Action_water") as BaseButton
	_assert_true(not water_button.disabled, "WATER was disabled by the currently selected invalid plot")
	var energy_before_invalid := int(GameState.data.get("energy", 0))
	screen.call("_on_action_pressed", "water")
	await _settle()
	await _click_plot(1)
	_assert_true(not bool(_plot(1).get("watered_today", false)), "Invalid WATER changed Plot01")
	_assert_true(int(GameState.data.get("energy", 0)) == energy_before_invalid, "Invalid WATER consumed energy")
	_assert_true(String(screen.get("_active_tool")) == "water", "Invalid target cleared the selected tool")

	# An untilled plot rejects PLANT without consuming seed or energy.
	screen.call("_select_seed_from_popup", "carrot")
	await _settle()
	var seed_before_untilled := int(GameState.data["inventory"].get("seed_carrot", 0))
	var energy_before_untilled := int(GameState.data.get("energy", 0))
	await _click_plot(12)
	_assert_true(String(_plot(12).get("crop", "")) == "", "Invalid PLANT changed untilled Plot12")
	_assert_true(int(GameState.data["inventory"].get("seed_carrot", 0)) == seed_before_untilled, "Invalid PLANT on untilled Plot12 consumed seed")
	_assert_true(int(GameState.data.get("energy", 0)) == energy_before_untilled, "Invalid PLANT on untilled Plot12 consumed energy")

	# Toolbar-first direct click must till every runtime plot, including Plot01/Plot12.
	screen.call("_on_action_pressed", "till")
	await _settle()
	for plot_id in range(1, 13):
		await _click_plot(plot_id)
		_assert_true(bool(_plot(plot_id).get("is_hoed", false)), "TILL direct-click failed on Plot%02d" % plot_id)
	_assert_true(String(screen.get("_active_tool")) == "till", "TILL tool did not remain selected")
	var energy_before_empty_water := int(GameState.data.get("energy", 0))
	screen.call("_on_action_pressed", "water")
	await _settle()
	await _click_plot(1)
	_assert_true(not bool(_plot(1).get("watered_today", false)), "WATER changed a tilled empty plot")
	_assert_true(int(GameState.data.get("energy", 0)) == energy_before_empty_water, "WATER on a tilled empty plot consumed energy")

	# PLANT uses the existing seed chooser, then direct-clicks all twelve plots.
	screen.call("_select_seed_from_popup", "carrot")
	await _settle()
	_assert_true(String(screen.get("_active_tool")) == "seed", "Carrot selection did not activate PLANT")
	var seeds_before := int(GameState.data["inventory"].get("seed_carrot", 0))
	for plot_id in range(1, 13):
		await _click_plot(plot_id)
		_assert_true(String(_plot(plot_id).get("crop", "")) == "carrot", "PLANT direct-click failed on Plot%02d" % plot_id)
	_assert_true(int(GameState.data["inventory"].get("seed_carrot", 0)) == seeds_before - 12, "Planting 12 plots did not consume exactly 12 seeds")

	# Invalid PLANT cannot consume a second seed or replace the existing crop.
	var seeds_before_invalid := int(GameState.data["inventory"].get("seed_carrot", 0))
	var energy_before_invalid_seed := int(GameState.data.get("energy", 0))
	await _click_plot(12)
	_assert_true(int(GameState.data["inventory"].get("seed_carrot", 0)) == seeds_before_invalid, "Invalid PLANT consumed seed inventory")
	_assert_true(int(GameState.data.get("energy", 0)) == energy_before_invalid_seed, "Invalid PLANT consumed energy")
	_assert_true(String(_plot(12).get("crop", "")) == "carrot", "Invalid PLANT replaced Plot12 crop")

	# WATER works across far/middle/near rows without farmer distance dependency.
	screen.call("_on_action_pressed", "water")
	await _settle()
	for plot_id in [1, 6, 12]:
		await _click_plot(plot_id)
		_assert_true(bool(_plot(plot_id).get("watered_today", false)), "WATER direct-click failed on Plot%02d" % plot_id)

	# HARVEST works on distant rows and preserves the existing post-harvest state.
	for plot_id in [1, 6, 12]:
		_make_ready(plot_id)
	GameState.changed.emit()
	await _settle()
	var crops_before := int(GameState.data["inventory"].get("crop_carrot", 0))
	screen.call("_on_action_pressed", "harvest")
	await _settle()
	for plot_id in [1, 6, 12]:
		await _click_plot(plot_id)
		_assert_true(String(_plot(plot_id).get("crop", "")) == "", "HARVEST direct-click failed on Plot%02d" % plot_id)
	_assert_true(int(GameState.data["inventory"].get("crop_carrot", 0)) == crops_before + 3, "Harvest did not award exactly three crops")

	if failures.is_empty():
		print("FIELD_GAMEPLAY_RESTORE_V7_TEST_PASS")
		get_tree().quit(0)
	else:
		print("FIELD_GAMEPLAY_RESTORE_V7_TEST_FAIL: %s" % "; ".join(failures))
		get_tree().quit(1)
