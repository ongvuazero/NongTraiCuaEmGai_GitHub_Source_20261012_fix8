extends RefCounted
class_name ItemCardStatePresenter

const SELECTED_COLOR := Color("f4c85d")
const LOCKED_COLOR := Color("8b6748")
const EMPTY_COLOR := Color("8b8174")
const CLEAR_COLOR := Color(0, 0, 0, 0)


static func apply_card(card: Control, selected: bool, locked: bool = false, unavailable: bool = false, tooltip: String = "") -> void:
	if card == null:
		return
	card.set_meta("ui_selected", selected)
	card.set_meta("ui_locked", locked)
	card.set_meta("ui_unavailable", unavailable)
	card.tooltip_text = tooltip
	card.self_modulate = Color(0.78, 0.72, 0.64, 1.0) if locked else (Color(0.82, 0.82, 0.82, 0.82) if unavailable else Color.WHITE)

	var frame := _ensure_frame(card)
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = CLEAR_COLOR
	frame_style.border_width_left = 4 if selected else 0
	frame_style.border_width_top = 4 if selected else 0
	frame_style.border_width_right = 4 if selected else 0
	frame_style.border_width_bottom = 4 if selected else 0
	frame_style.border_color = SELECTED_COLOR
	frame_style.corner_radius_top_left = 12
	frame_style.corner_radius_top_right = 12
	frame_style.corner_radius_bottom_left = 12
	frame_style.corner_radius_bottom_right = 12
	frame.add_theme_stylebox_override("panel", frame_style)
	frame.visible = selected

	var badge := _ensure_badge(card)
	badge.visible = locked
	badge.text = TranslationServer.translate("KHÓA")
	badge.tooltip_text = tooltip
	var selected_badge := _ensure_selection_badge(card)
	selected_badge.visible = selected

	for child in card.find_children("Select*", "BaseButton", true, false):
		(child as BaseButton).tooltip_text = tooltip


static func apply_tab(button: BaseButton, selected: bool, enabled: bool = true, tooltip: String = "") -> void:
	if button == null:
		return
	button.disabled = not enabled
	button.tooltip_text = tooltip
	button.set_meta("ui_selected", selected)
	button.self_modulate = SELECTED_COLOR.lightened(0.22) if selected else (Color.WHITE if enabled else Color(0.65, 0.65, 0.65, 0.72))
	var selected_badge := _ensure_selection_badge(button)
	selected_badge.visible = selected


static func apply_action(button: BaseButton, enabled: bool, tooltip: String) -> void:
	if button == null:
		return
	button.disabled = not enabled
	button.tooltip_text = tooltip
	button.self_modulate = Color.WHITE if enabled else Color(0.72, 0.72, 0.72, 0.76)


static func _ensure_frame(card: Control) -> Panel:
	var frame := card.get_node_or_null("UIStateFrame") as Panel
	if frame == null:
		frame = Panel.new()
		frame.name = "UIStateFrame"
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.z_index = 30
		card.add_child(frame)
	return frame


static func _ensure_badge(card: Control) -> Label:
	var badge := card.get_node_or_null("UIStateLockBadge") as Label
	if badge == null:
		badge = Label.new()
		badge.name = "UIStateLockBadge"
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.position = Vector2(maxf(card.size.x - 72.0, 4.0), 5.0)
		badge.size = Vector2(66, 26)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 14)
		badge.add_theme_color_override("font_color", Color("fff4d2"))
		var badge_style := StyleBoxFlat.new()
		badge_style.bg_color = LOCKED_COLOR
		badge_style.corner_radius_top_left = 7
		badge_style.corner_radius_top_right = 7
		badge_style.corner_radius_bottom_left = 7
		badge_style.corner_radius_bottom_right = 7
		badge.add_theme_stylebox_override("normal", badge_style)
		badge.z_index = 31
		card.add_child(badge)
	return badge


static func _ensure_selection_badge(card: Control) -> Label:
	var badge := card.get_node_or_null("UISelectedCheck") as Label
	if badge == null:
		badge = Label.new()
		badge.name = "UISelectedCheck"
		badge.text = "✓"
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.position = Vector2(5, 3)
		badge.size = Vector2(23, 24)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_theme_color_override("font_color", Color("28602d"))
		badge.add_theme_font_size_override("font_size", 20)
		badge.z_index = 32
		card.add_child(badge)
	return badge
