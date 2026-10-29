extends Control
class_name BaseScreen

const UI = preload("res://scripts/ui_factory.gd")
const Assets = preload("res://scripts/ui_asset_registry.gd")
const FarmData = preload("res://scripts/farm_data.gd")
const ROOT := "res://assets/canonical_v2/03_ART_RUNTIME_READY"
const GameplayMenu = preload("res://scripts/ui/gameplay_save_menu.gd")

@export var show_visual_guide_at_runtime := false
var _serialized_root_children: Array[StringName] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for child in get_children():
		_serialized_root_children.append(child.name)
	var visual_guide := get_node_or_null("VISUAL_GUIDE_OVERLAY") as CanvasItem
	if visual_guide != null:
		visual_guide.visible = show_visual_guide_at_runtime
	if not GameState.changed.is_connected(_refresh): GameState.changed.connect(_refresh)
	if not UILocale.events().locale_changed.is_connected(_on_locale_changed): UILocale.events().locale_changed.connect(_on_locale_changed)
	build()
	if ScreenRouter.current_screen not in ["title", "save"] and GameState.has_active_farm() and not (ScreenRouter.current_screen == "settings" and GameState.settings_use_global_preferences()):
		var menu := GameplayMenu.new()
		menu.name = "GameplaySaveMenu"
		add_child(menu)
		_serialized_root_children.append(menu.name)
	# Authored labels may use Godot's default Latin-only face. Apply bundled
	# glyph fallbacks after the first build as well as after locale changes.
	call_deferred("_apply_locale_font_faces")


func _exit_tree() -> void:
	if GameState.changed.is_connected(_refresh): GameState.changed.disconnect(_refresh)
	if UILocale.events().locale_changed.is_connected(_on_locale_changed): UILocale.events().locale_changed.disconnect(_on_locale_changed)


func _on_locale_changed(_language: String) -> void:
	# Existing per-screen refresh retains tab/selection and runtime life nodes.
	# No farm mutation, route change, modal close, or BGM restart.
	_refresh()
	call_deferred("_apply_locale_font_faces")

func _apply_locale_font_faces() -> void:
	LocaleFonts.apply_to_tree(self)


func _refresh() -> void:
	for child in get_children():
		if child.name not in _serialized_root_children:
			child.queue_free()
	call_deferred("build")


func author_rect(node_path: NodePath, fallback: Rect2) -> Rect2:
	var node := get_node_or_null(node_path) as Control
	if node == null:
		return fallback
	return node.get_global_rect()


func author_position(node_path: NodePath, fallback: Vector2) -> Vector2:
	var node := get_node_or_null(node_path) as Node2D
	if node != null:
		return node.global_position
	var control := get_node_or_null(node_path) as Control
	return control.global_position if control != null else fallback


func bind_button(node_name: String, callback: Callable) -> BaseButton:
	var button := find_child(node_name, true, false) as BaseButton
	if button != null and not button.pressed.is_connected(callback):
		button.pressed.connect(callback)
	return button


func first_label_under(node_name: String) -> Label:
	var parent := find_child(node_name, true, false)
	return parent.find_child("*", true, false) as Label if parent != null else null


func bind_standard_left_navigation() -> void:
	for route_id in ["field_select", "shop", "storage", "animal", "dragon", "quest", "settings"]:
		bind_button("LeftNav_%s" % route_id, ScreenRouter.go.bind(route_id))
	bind_button("LeftNav_RestNextDay", _on_navigation_next_day)


func _on_navigation_next_day() -> void:
	var succeeded := GameState.advance_day()
	var message := tr("New day. Changes autosaved.") if succeeded else UILocale.translate_message(GameState.status)
	var button := find_child("LeftNav_RestNextDay", true, false) as BaseButton
	if button != null:
		button.tooltip_text = message
		var caption := button.find_child("Caption", true, false) as Label
		if caption != null: caption.text = tr("Nghỉ / Ngày mới") if succeeded else tr("Retry save")
	_show_navigation_day_result(succeeded, message)


func _show_navigation_day_result(_succeeded: bool, _message: String) -> void:
	pass


func bind_top_hud() -> void:
	var day_label := find_child("HUD_DaySeasonLabel", true, false) as Label
	var coin_label := find_child("HUD_CoinValue", true, false) as Label
	var energy_label := find_child("HUD_EnergyValue", true, false) as Label
	var dragon_label := find_child("HUD_DragonEnergyValue", true, false) as Label
	# Keep dynamic HUD copy inside the authored chip at 1280x720.
	if day_label != null:
		day_label.text = tr("Ngày %d\n%s") % [int(GameState.data.get("day", 1)), tr(GameState.current_season())]
		day_label.add_theme_font_size_override("font_size", 15)
		day_label.add_theme_constant_override("line_spacing", -4)
		day_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if coin_label != null: coin_label.text = str(int(GameState.data.get("coins", 0)))
	if energy_label != null:
		energy_label.text = str(int(GameState.data.get("energy", 0)))
		energy_label.tooltip_text = tr("Năng lượng: %s / 100") % energy_label.text
	if dragon_label != null: dragon_label.text = str(GameState.dragon_energy())


func build() -> void:
	pass
