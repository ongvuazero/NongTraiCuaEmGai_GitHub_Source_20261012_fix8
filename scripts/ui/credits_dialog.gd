extends CanvasLayer

const UI = preload("res://scripts/ui_factory.gd")
const Fonts = preload("res://scripts/localization/locale_fonts.gd")
const FONT_NOTICES := [
	"res://assets/fonts/OFL.txt", "res://assets/fonts/noto/NotoSans.OFL.txt",
	"res://assets/fonts/noto/NotoSansThai.OFL.txt", "res://assets/fonts/noto/NotoSansSC.OFL.txt",
	"res://assets/fonts/noto/NotoSansJP.OFL.txt", "res://assets/fonts/noto/NotoSansKR.OFL.txt",
	"res://assets/fonts/noto/LICENSE-NotoSansSymbols2.txt",
	"res://assets/fonts/noto/LICENSE-NotoSansSymbols.txt",
	"res://assets/fonts/noto/LICENSE-NotoEmoji.txt",
]
var _screen: Control
var _old_mode := Node.PROCESS_MODE_INHERIT
var _open := true

static func install(screen: Control) -> void:
	if screen.get_node_or_null("OpenCredits") != null: return
	var access := UI.title_button(UILocale.pair("Thông tin", "Credits"), Rect2(934, 80, 178, 48))
	access.name = "OpenCredits"
	var caption := access.get_child(0) as Label
	if caption != null:
		caption.name = "Caption"
		caption.add_theme_font_override("font", Fonts.for_text(caption.text, Fonts.semibold()))
		caption.add_theme_font_size_override("font_size", 19)
	access.pressed.connect(func():
		if screen.get_node_or_null("CreditsDialog") != null: return
		var dialog := new()
		dialog.name = "CreditsDialog"
		dialog._screen = screen
		screen.add_child(dialog)
	)
	screen.add_child(access)

func is_open() -> bool:
	return _open

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_old_mode = _screen.process_mode
	_screen.process_mode = Node.PROCESS_MODE_DISABLED
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var veil := ColorRect.new()
	veil.color = Color(0.06, 0.10, 0.08, 0.78)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(veil)
	root.add_child(UI.panel(Rect2(154, 42, 972, 636), Color("fff1d5"), Color("80532f"), 20))
	root.add_child(UI.label(UILocale.pair("Thông tin & giấy phép", "Credits & licenses"), Rect2(182, 55, 916, 52), 28, Color("3e2b1d"), HORIZONTAL_ALIGNMENT_CENTER))
	var scroll := ScrollContainer.new()
	scroll.name = "LicenseScroll"
	scroll.position = Vector2(182, 119)
	scroll.size = Vector2(916, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var body := RichTextLabel.new()
	body.name = "OriginalLicenseTexts"
	body.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	body.custom_minimum_size = Vector2(888, 0)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.fit_content = true
	body.scroll_active = false
	body.selection_enabled = true
	body.bbcode_enabled = false # Original notice text is data, never markup/code.
	body.text = _original_notices()
	body.add_theme_font_override("normal_font", Fonts.for_text(body.text, Fonts.regular()))
	body.add_theme_font_size_override("normal_font_size", 18)
	body.add_theme_color_override("default_color", Color("3e2b1d"))
	scroll.add_child(body)
	var dismiss := UI.title_button(UILocale.translate_message("Close"), Rect2(500, 609, 280, 52))
	dismiss.name = "CloseCredits"
	dismiss.pressed.connect(close)
	root.add_child(dismiss)
	Fonts.apply_to_tree(root)
	dismiss.call_deferred("grab_focus")

func _original_notices() -> String:
	var sections: PackedStringArray = []
	var inventory := "res://assets/THIRD_PARTY_NOTICES.txt"
	if FileAccess.file_exists(inventory): sections.append(FileAccess.get_file_as_string(inventory))
	sections.append("Godot Engine — original MIT license\n\n" + Engine.get_license_text())
	# Godot provides all bundled engine dependency notices at runtime.
	for dependency in Engine.get_copyright_info():
		sections.append(String(dependency.get("name", "")))
		for part in dependency.get("parts", []):
			sections.append("\n".join(PackedStringArray(part.get("copyright", []))) + "\nLicense: " + String(part.get("license", "")))
	var engine_licenses: Dictionary = Engine.get_license_info()
	for id in engine_licenses: sections.append(String(id) + "\n\n" + String(engine_licenses[id]))
	for path in FONT_NOTICES:
		if FileAccess.file_exists(path): sections.append(path.get_file() + "\n\n" + FileAccess.get_file_as_string(path))
		else: push_warning("Bundled font notice missing: " + path)
	return "\n\n────────────────────────\n\n".join(sections)

func _input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	if not _open: return
	_open = false
	_restore_screen()
	queue_free()

func _restore_screen() -> void:
	if not is_instance_valid(_screen): return
	_screen.process_mode = _old_mode
	var access := _screen.get_node_or_null("OpenCredits") as Control
	if access != null: access.call_deferred("grab_focus")

func _exit_tree() -> void:
	_restore_screen()
