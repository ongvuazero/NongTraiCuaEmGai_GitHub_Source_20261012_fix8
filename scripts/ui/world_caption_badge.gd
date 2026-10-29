extends Control

# Readable, pointer-transparent presentation. This node never owns a world hit
# shape, feet anchor, or action; its labels fit inside a cream paper surface.
const UI = preload("res://scripts/ui_factory.gd")
const NAME_FONT = preload("res://assets/fonts/BeVietnamPro-SemiBold.ttf")
const STATUS_FONT = preload("res://assets/fonts/BeVietnamPro-Regular.ttf")
var caption: Label
var status_label: Label
var paper: Panel
var _width := 170.0
var _name_size := 15
var _status_size := 14
var _view_safe_rect := Rect2(252,168,682,536)

func setup(text: String, width: float, status := "", name_size := 15, view_safe_rect := Rect2(252,168,682,536)) -> void:
	_view_safe_rect = view_safe_rect
	_width = minf(width, _view_safe_rect.size.x)
	_name_size = maxi(14, name_size)
	mouse_filter = MOUSE_FILTER_IGNORE
	# World cutouts retain their feet depth. Their readable paper captions sit
	# above those cutouts, so a later resource cannot paint over an earlier label.
	z_as_relative = false
	z_index = 900
	paper = UI.panel(Rect2(Vector2.ZERO, Vector2(_width, 44)), Color("fff1d9f2"), Color("b28b55"), 7)
	paper.name = "Paper"
	paper.mouse_filter = MOUSE_FILTER_IGNORE
	var style := paper.get_theme_stylebox("panel") as StyleBoxFlat
	style.set_border_width_all(1)
	add_child(paper)
	caption = _label("WorldCaptionName", NAME_FONT, _name_size)
	status_label = _label("WorldCaptionStatus", STATUS_FONT, _status_size)
	set_copy(text, status)

func _label(id: String, font: Font, font_size: int) -> Label:
	var label := UI.label("", Rect2(8, 3, _width - 16, 20), font_size, Color("49301c"), HORIZONTAL_ALIGNMENT_CENTER)
	label.name = id
	label.add_theme_font_override("font", font)
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = true
	label.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func set_copy(text: String, status := "") -> void:
	caption.text = text
	status_label.text = status
	_reflow()

func set_status(text: String) -> void:
	status_label.text = text
	_reflow()

func _reflow() -> void:
	var safe_width := _width - 16.0
	caption.add_theme_font_override("font", LocaleFonts.for_text(caption.text, NAME_FONT))
	status_label.add_theme_font_override("font", LocaleFonts.for_text(status_label.text, STATUS_FONT))
	# Label's shaped line metrics include fallback-font ascent/descent. A direct
	# Font multiline estimate can be smaller (19px vs27px with bundled Noto),
	# which clips every letter when clip_text is enabled. Measure the renderer.
	caption.size.x = safe_width
	status_label.size.x = safe_width
	var name_height := _label_height(caption, NAME_FONT, safe_width, _name_size)
	var status_height := _label_height(status_label, STATUS_FONT, safe_width, _status_size)
	caption.position = Vector2(8, 3)
	caption.custom_minimum_size = Vector2.ZERO
	caption.size = Vector2(safe_width, name_height)
	caption.visible = name_height > 0
	status_label.position = Vector2(8, 3 + name_height)
	status_label.custom_minimum_size = Vector2.ZERO
	status_label.size = Vector2(safe_width, status_height)
	status_label.visible = status_height > 0
	size = Vector2(_width, maxf(26, name_height + status_height + 6))
	paper.size = size
	tooltip_text = caption.text + ("\n" + status_label.text if not status_label.text.is_empty() else "")
	set_meta("readable_world_caption", true)
	set_meta("text_safe_width", safe_width)
	if is_inside_tree(): _keep_in_view()
	else: call_deferred("_keep_in_view")

func _keep_in_view() -> void:
	if not is_inside_tree(): return
	# Only the paper moves: never change the world's feet or clickable body.
	# Text height varies with locale and status, including after in-place refresh.
	var safe := _view_safe_rect
	var actual := get_global_rect()
	var fitted := Vector2(clampf(actual.position.x,safe.position.x,maxf(safe.position.x,safe.end.x-size.x)),clampf(actual.position.y,safe.position.y,maxf(safe.position.y,safe.end.y-size.y)))
	global_position += fitted-actual.position
	set_meta("caption_view_safe_rect",safe)

func _label_height(label: Label, font: Font, width: float, font_size: int) -> float:
	if label.text.is_empty(): return 0.0
	var estimated := font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size).y
	var lines := maxi(label.get_line_count(), 1)
	var shaped := float(label.get_line_height()) * lines + float(label.get_theme_constant("line_spacing")) * maxi(lines - 1, 0)
	return maxf(estimated, shaped) + 2.0
