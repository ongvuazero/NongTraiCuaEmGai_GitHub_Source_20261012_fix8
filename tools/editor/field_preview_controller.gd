@tool
extends Node

const RendererClass = preload("res://v7/production/field_renderer.gd")

enum PreviewState { EMPTY, HOED, WATERED, FERTILIZED, GROWING, HARVEST_READY }

@export_category("Editor Preview Only")
@export var editor_preview_state: PreviewState = PreviewState.GROWING:
	set(value):
		editor_preview_state = value
		if Engine.is_editor_hint(): call_deferred("_apply_preview")


func _ready() -> void:
	if Engine.is_editor_hint(): call_deferred("_apply_preview")


func _apply_preview() -> void:
	if not Engine.is_editor_hint(): return
	var scene_root := get_parent().get_parent()
	var field_area := scene_root.get_node_or_null("EDIT_ME/FieldArea")
	if field_area == null: return
	var world_root := field_area.get_node_or_null("WorldRenderer")
	if world_root == null: return
	world_root.apply_tuning()
	for plot_id in range(1, 13):
		var plot := field_area.get_node_or_null("Plot%02d" % plot_id)
		if plot != null: plot.visible = false
	for child in world_root.get_children():
		if child.name == "EditorV73WorldPreview": child.free()
	var renderer := RendererClass.new()
	renderer.name = "EditorV73WorldPreview"
	world_root.add_child(renderer, false, Node.INTERNAL_MODE_FRONT)
	if renderer.bed_world == null:
		renderer._ready()
	renderer.render(_preview_plots(), 1)


func _preview_plots() -> Array:
	var plots: Array = []
	for plot_id in range(1, 13):
		var record := {
			"id": plot_id,
			"is_hoed": editor_preview_state != PreviewState.EMPTY,
			"watered_today": editor_preview_state in [PreviewState.WATERED, PreviewState.FERTILIZED],
			"fertilizer_pending": editor_preview_state == PreviewState.FERTILIZED,
			"crop": "",
			"growth_stage": 0,
			"ready_to_harvest": false,
		}
		if editor_preview_state in [PreviewState.GROWING, PreviewState.HARVEST_READY]:
			record["crop"] = ["carrot", "tomato", "pumpkin"][posmod(plot_id - 1, 3)]
			record["growth_stage"] = 4 if record["crop"] != "pumpkin" else 5
			record["ready_to_harvest"] = editor_preview_state == PreviewState.HARVEST_READY
		plots.append(record)
	return plots
