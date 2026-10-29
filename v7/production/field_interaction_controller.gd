extends Node
class_name FieldInteractionController

signal plot_selected(plot_id: int)
const Geometry = preload("res://v7/runtime/field_projection_v7_2.gd")
var enabled := true

func _ready() -> void:
	set_process_unhandled_input(true)

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var plot_id := Geometry.hit_test_plot(event.position)
		if plot_id > 0:
			plot_selected.emit(plot_id)
			get_viewport().set_input_as_handled()
