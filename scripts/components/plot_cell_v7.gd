extends Control
class_name FieldPlotCellV7

signal plot_selected(plot_id: int)

const Assets = preload("res://scripts/ui_asset_registry.gd")
const Grid = preload("res://v6/runtime/field_grid_registry_v7.gd")

@onready var base_soil: TextureRect = $BaseSoil
@onready var watered_overlay: TextureRect = $WateredOverlay
@onready var fertilizer_overlay: TextureRect = $FertilizerOverlay
@onready var crop_sprite: TextureRect = $CropSprite
@onready var ready_overlay: TextureRect = $ReadyOverlay
@onready var selection_overlay: TextureRect = $SelectionOverlay
@onready var hover_overlay: TextureRect = $HoverOverlay
@onready var disabled_overlay: TextureRect = $DisabledOverlay
@onready var click_area: Button = $ClickArea

var plot_id := 0
var _selected := false


func _ready() -> void:
	for layer in [base_soil, watered_overlay, fertilizer_overlay, crop_sprite, ready_overlay, selection_overlay, hover_overlay, disabled_overlay]:
		layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	click_area.flat = true
	click_area.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	click_area.pressed.connect(_emit_selection)
	click_area.mouse_entered.connect(_show_hover.bind(true))
	click_area.mouse_exited.connect(_show_hover.bind(false))


func bind(record: Dictionary, plot: Dictionary, is_selected: bool) -> void:
	plot_id = int(record.get("plot_id", 0))
	_selected = is_selected
	name = "PlotCell_%02d" % plot_id
	var visible_rect := Grid.shape_rect(record, "visible_shape")
	position = visible_rect.position
	size = visible_rect.size
	z_index = int(record.get("depth_group", 0))
	_set_rect(base_soil, visible_rect, visible_rect)
	_set_rect(watered_overlay, visible_rect, visible_rect)
	_set_rect(fertilizer_overlay, Grid.rect_from(record.get("status_visual_rect", [])), visible_rect)
	_set_rect(crop_sprite, Grid.rect_from(record.get("crop_visual_rect", [])), visible_rect)
	_set_rect(ready_overlay, Grid.rect_from(record.get("status_visual_rect", [])), visible_rect)
	_set_rect(selection_overlay, Grid.shape_rect(record, "selection_shape"), visible_rect)
	_set_rect(hover_overlay, Grid.shape_rect(record, "selection_shape"), visible_rect)
	_set_rect(disabled_overlay, Grid.shape_rect(record, "selection_shape"), visible_rect)
	_set_rect(click_area, Grid.shape_rect(record, "interaction_shape"), visible_rect)
	bind_state(plot, is_selected)


func bind_state(plot: Dictionary, is_selected: bool) -> void:
	_selected = is_selected
	var is_hoed := bool(plot.get("is_hoed", false))
	var watered := bool(plot.get("watered_today", false))
	var fertilized := bool(plot.get("fertilizer_pending", false))
	var ready := bool(plot.get("ready_to_harvest", false))
	var locked := bool(plot.get("locked", false))
	var crop_id := String(plot.get("crop", ""))
	var growth_stage := int(plot.get("growth_stage", 0))
	base_soil.texture = Assets.plot_texture("dry" if is_hoed else "unhoed")
	watered_overlay.texture = Assets.plot_texture("watered") if is_hoed and watered else null
	fertilizer_overlay.texture = Assets.crop_overlay("fertilized") if fertilized else null
	crop_sprite.texture = Assets.world_crop(crop_id, growth_stage) if not crop_id.is_empty() else null
	ready_overlay.texture = Assets.crop_overlay("ready") if ready else null
	selection_overlay.texture = Assets.plot_texture("selected") if is_selected else null
	hover_overlay.texture = null
	disabled_overlay.texture = Assets.plot_texture("disabled") if locked else null
	click_area.disabled = locked
	set_meta("plot_id", plot_id)
	set_meta("lifecycle", lifecycle(plot))
	set_meta("crop_id", crop_id)
	set_meta("growth_stage", growth_stage)
	set_meta("watered", watered)
	set_meta("fertilized", fertilized)
	set_meta("ready", ready)
	set_meta("selected", is_selected)


func lifecycle(plot: Dictionary) -> String:
	if bool(plot.get("ready_to_harvest", false)):
		return "READY_TO_HARVEST"
	var crop_id := String(plot.get("crop", ""))
	if not crop_id.is_empty():
		return "PLANTED" if int(plot.get("growth_stage", 0)) == 0 else "GROWING"
	if bool(plot.get("is_hoed", false)):
		return "TILLED"
	return "UNTILLED"


func _set_rect(node: Control, absolute_rect: Rect2, visible_rect: Rect2) -> void:
	node.position = absolute_rect.position - visible_rect.position
	node.size = absolute_rect.size


func _emit_selection() -> void:
	plot_selected.emit(plot_id)


func _show_hover(visible: bool) -> void:
	hover_overlay.texture = Assets.plot_texture("hover") if visible and not _selected and not click_area.disabled else null
