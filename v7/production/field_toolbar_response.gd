extends Control

# Presentation only. This echoes the approved toolbar art; plot-action sheets
# remain exclusively owned by FieldActionVFX after a real gameplay commit.
const RESPONSE_DURATION := 0.56

var _approved_texture: Texture2D
var _selected := false
var _disabled := false
var _pressed := false
var _selected_caption := ""
var _unavailable_caption := ""
var _command_result := ""
var _show_selection_badge := true
var _elapsed := RESPONSE_DURATION
var _failure := false
var _response_count := 0
var _badge: Label
var _badge_style := StyleBoxFlat.new()


func configure(button: TextureButton) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 6
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_approved_texture = button.texture_normal
	_show_selection_badge = String(button.name).begins_with("Action_")
	_badge_style.set_corner_radius_all(7)
	_badge_style.set_border_width_all(2)
	_badge = Label.new()
	_badge.name = "PersistentSelectionBadge"
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.add_theme_font_size_override("font_size", 13)
	_badge.add_theme_color_override("font_color", Color(0.25, 0.13, 0.045, 1.0))
	_badge.add_theme_color_override("font_outline_color", Color(1.0, 0.97, 0.80, 0.45))
	_badge.add_theme_constant_override("outline_size", 1)
	add_child(_badge)
	set_process(false)
	_sync_badge()


func sync_state(selected: bool, disabled: bool, pressed: bool, selected_caption: String, unavailable_caption: String) -> void:
	_selected = selected
	_disabled = disabled
	_pressed = pressed
	_selected_caption = selected_caption
	_unavailable_caption = unavailable_caption
	_sync_badge()
	queue_redraw()


func play_acknowledgement(failure := false) -> void:
	_failure = failure
	_elapsed = 0.0
	_response_count += 1
	set_process(true)
	_sync_badge()
	queue_redraw()


func set_command_result(caption: String) -> void:
	_command_result = caption
	_sync_badge()
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed = minf(RESPONSE_DURATION, _elapsed + delta)
	_sync_badge()
	queue_redraw()
	if _elapsed >= RESPONSE_DURATION:
		set_process(false)


func _sync_badge() -> void:
	if _badge == null:
		return
	var failing := _failure and response_active()
	_badge.visible = _show_selection_badge and (_selected or not _command_result.is_empty() or failing)
	_badge.text = _unavailable_caption if failing or (_selected and _disabled) else (_command_result if not _command_result.is_empty() else _selected_caption)
	var badge_width := clampf(float(_badge.text.length()) * 8.0 + 18.0, 76.0, maxf(76.0, size.x - 8.0))
	_badge.position = Vector2((size.x - badge_width) * 0.5, -9.0)
	_badge.size = Vector2(badge_width, 23.0)
	_badge_style.bg_color = Color(1.0, 0.88, 0.48, 1.0) if not failing and not _disabled else Color(0.92, 0.77, 0.67, 1.0)
	_badge_style.border_color = Color(0.57, 0.35, 0.10, 1.0) if not failing and not _disabled else Color(0.65, 0.25, 0.15, 1.0)
	_badge.add_theme_stylebox_override("normal", _badge_style)


func _draw() -> void:
	if not response_active():
		return
	var progress := _elapsed / RESPONSE_DURATION
	var strength := pow(1.0 - progress, 1.2)
	var margin := 3.0 + 12.0 * sin(progress * PI * 0.5)
	# Only the response overlay grows; the authored button never moves or scales.
	# Both responses use the button's painterly source art; no procedural
	# particles, cursor rings, or debug lines are added to the Field.
	if _approved_texture != null:
		var tint := Color(1.35, 1.24, 0.94, strength * 0.64) if not _failure else Color(1.20, 0.56, 0.42, strength * 0.70)
		draw_texture_rect(_approved_texture, Rect2(Vector2.ONE * -margin, size + Vector2.ONE * margin * 2.0), false, tint)


func response_active() -> bool:
	return _elapsed < RESPONSE_DURATION


func qa_snapshot() -> Dictionary:
	return {
		"active": response_active(),
		"selected": _selected,
		"disabled": _disabled,
		"pressed": _pressed,
		"failure": _failure and response_active(),
		"response_count": _response_count,
		"elapsed": _elapsed,
		"duration": RESPONSE_DURATION,
		"badge_visible": _badge.visible if _badge != null else false,
		"badge_text": _badge.text if _badge != null else "",
		"approved_texture": _approved_texture.resource_path if _approved_texture != null else "",
		"overlay_scale": scale,
	}
