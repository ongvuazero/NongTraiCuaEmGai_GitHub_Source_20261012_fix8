extends CanvasLayer

# Installation preference only. Choosing a language never creates/loads a farm.
signal modal_completed

const Registry = preload("res://scripts/localization/locale_registry.gd")
const Fonts = preload("res://scripts/localization/locale_fonts.gd")
const UI = preload("res://scripts/ui_factory.gd")
var _selected := ""
var _buttons: Dictionary = {}
var _preview: Label
var _error: Label
var _confirm: Button
var _open := true
var _saving := false
var _host: Control
var _old_host_mode := Node.PROCESS_MODE_INHERIT
var _old_focus: Control

func setup(host: Control) -> void:
	_host = host

func is_open() -> bool:
	return _open

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_selected = UILocale.current_locale()
	if is_instance_valid(_host):
		_old_host_mode = _host.process_mode
		_old_focus = get_viewport().gui_get_focus_owner()
		_host.process_mode = Node.PROCESS_MODE_DISABLED
	var root := Control.new()
	root.name = "LanguageChoiceRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var veil := ColorRect.new()
	veil.color = Color(0.06, 0.10, 0.08, 0.78)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(veil)
	var card := UI.panel(Rect2(236, 36, 808, 648), Color("fff1d5"), Color("80532f"), 20)
	card.name = "LanguageChoiceCard"
	root.add_child(card)
	card.add_child(UI.raw_label("Chọn ngôn ngữ / Choose your language", Rect2(22, 14, 764, 46), 27, Color("3e2b1d"), HORIZONTAL_ALIGNMENT_CENTER))
	_preview = UI.raw_label("", Rect2(28, 62, 752, 42), 22, Color("386239"), HORIZONTAL_ALIGNMENT_CENTER)
	card.add_child(_preview)
	for index in range(Registry.SUPPORTED.size()):
		var language: String = Registry.SUPPORTED[index]
		var button := _button(Registry.native_name(language), Rect2(28 + (index % 2) * 384, 114 + (index / 2) * 56, 368, 48))
		button.name = "Language_" + language
		button.pressed.connect(_select.bind(language))
		card.add_child(button)
		_buttons[language] = button
	_error = UI.raw_label("", Rect2(28, 509, 752, 46), 17, Color("a02f22"), HORIZONTAL_ALIGNMENT_CENTER)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(_error)
	_confirm = _button("Tiếp tục / Continue", Rect2(210, 564, 388, 56))
	_confirm.name = "ConfirmLanguage"
	_confirm.pressed.connect(_submit)
	card.add_child(_confirm)
	_select(_selected)
	_buttons[_selected].call_deferred("grab_focus")

func _button(caption: String, rect: Rect2) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.text = caption
	button.add_theme_font_override("font", Fonts.for_text(caption, Fonts.semibold()))
	button.add_theme_font_size_override("font_size", 21)
	button.add_theme_color_override("font_color", Color("3e2b1d"))
	button.add_theme_color_override("font_hover_color", Color("3e2b1d"))
	button.add_theme_color_override("font_pressed_color", Color("3e2b1d"))
	button.add_theme_color_override("font_focus_color", Color("3e2b1d"))
	button.add_theme_stylebox_override("normal", _style("fff8e8", "b38a51", 2))
	button.add_theme_stylebox_override("hover", _style("e8efcf", "719248", 2))
	button.add_theme_stylebox_override("pressed", _style("d4e5b2", "507338", 3))
	button.add_theme_stylebox_override("focus", _style("00000000", "466b39", 3))
	return button

func _style(fill: String, edge: String, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(fill)
	style.border_color = Color(edge)
	style.set_border_width_all(width)
	style.set_corner_radius_all(12)
	return style

func _select(language: String) -> void:
	if _saving: return
	_selected = language
	for code in _buttons:
		_buttons[code].add_theme_stylebox_override("normal", _style("dcebc2" if code == language else "fff8e8", "507338" if code == language else "b38a51", 3 if code == language else 2))
	_preview.text = Registry.game_title(language)
	_preview.add_theme_font_override("font", Fonts.for_text(_preview.text, Fonts.semibold()))
	_error.text = ""

func _submit() -> void:
	if _saving or not _open: return
	_saving = true
	_confirm.disabled = true
	if not UILocale.confirm_language_choice(_selected):
		_error.text = "Không lưu được lựa chọn. Hãy thử lại. / Cannot save your choice. Please retry."
		_saving = false
		_confirm.disabled = false
		return
	_open = false
	_release_host()
	modal_completed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()

func _release_host() -> void:
	if is_instance_valid(_host): _host.process_mode = _old_host_mode
	if is_instance_valid(_old_focus): _old_focus.call_deferred("grab_focus")

func _exit_tree() -> void:
	_release_host()
