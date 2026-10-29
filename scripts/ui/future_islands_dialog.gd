extends CanvasLayer

# Presentation of the author's future intent only: no download counter, island
# unlock, transaction, player-state mutation, network request or save operation.
const UI = preload("res://scripts/ui_factory.gd")
const Fonts = preload("res://scripts/localization/locale_fonts.gd")
const TITLE = "Islands to come"
const BODY = "When My Little Sister’s Farm reaches 1 million downloads, I plan to add Undersea Island, Prehistoric Island, Space Island… and many more new ideas!"
const FREE_PROJECT = "This is a free project. The complete source code will be shared on GitHub Jxnhalam."
const DISCLAIMER = "Future update plans — these islands are not available yet."
var _screen: Control
var _old_mode := Node.PROCESS_MODE_INHERIT
var _open := true
var _restored := false
var _title: Label
var _body: Label
var _disclaimer: Label
var _close: BaseButton

static func title_text() -> String:
	return UILocale.translate_message(TITLE)

static func open_for(screen: Control) -> void:
	var previous := screen.get_node_or_null("FutureIslandsDialog")
	if previous != null and not previous.is_queued_for_deletion(): return
	if previous != null: screen.remove_child(previous)
	var save_menu := screen.get_node_or_null("GameplaySaveMenu")
	if save_menu != null and save_menu.has_method("close_menu"): save_menu.call("close_menu")
	var dialog := new()
	dialog.name = "FutureIslandsDialog"
	dialog._screen = screen
	screen.add_child(dialog)
	# Locale refresh may rebuild Home's ordinary art, not this active modal.
	var retained = screen.get("_serialized_root_children")
	if retained is Array and "FutureIslandsDialog" not in retained: retained.append("FutureIslandsDialog")

func is_open() -> bool:
	return _open

func _ready() -> void:
	layer = 115
	process_mode = Node.PROCESS_MODE_ALWAYS
	_old_mode = _screen.process_mode
	_screen.process_mode = Node.PROCESS_MODE_DISABLED
	var root := Control.new()
	root.name = "FutureIslandsModalRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var veil := ColorRect.new()
	veil.color = Color(0.05,0.09,0.06,0.70)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(veil)
	root.add_child(UI.panel(Rect2(250,92,780,536), Color("fff1d8"), Color("83532d"), 18))
	_title = UI.label("", Rect2(284,111,712,58), 29, Color("49301c"), HORIZONTAL_ALIGNMENT_CENTER)
	_title.name = "FutureIslandsTitle"; root.add_child(_title)
	_body = UI.label("", Rect2(292,189,696,282), 22, Color("473421"), HORIZONTAL_ALIGNMENT_CENTER)
	_body.name = "FutureIslandsBody"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_constant_override("line_spacing", 5)
	root.add_child(_body)
	_disclaimer = UI.label("", Rect2(292,480,696,48), 16, Color("4a6443"), HORIZONTAL_ALIGNMENT_CENTER)
	_disclaimer.name = "FutureIslandsPlanOnly"
	_disclaimer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_disclaimer)
	_close = UI.title_button("", Rect2(504,549,272,56))
	_close.name = "CloseFutureIslands"
	_close.focus_mode = Control.FOCUS_ALL
	_close.focus_neighbor_left = NodePath(".")
	_close.focus_neighbor_right = NodePath(".")
	_close.focus_neighbor_top = NodePath(".")
	_close.focus_neighbor_bottom = NodePath(".")
	_close.focus_next = NodePath(".")
	_close.focus_previous = NodePath(".")
	_close.pressed.connect(close)
	root.add_child(_close)
	UILocale.events().locale_changed.connect(_localize)
	_localize(UILocale.current_locale())
	_close.call_deferred("grab_focus")
	set_meta("future_intent_only", true)
	set_meta("has_download_counter", false)
	set_meta("github_statement_only", true)

func _localize(_locale: String) -> void:
	_title.text = title_text()
	# A separate paragraph: source sharing is an author's future statement, not
	# already-published repository/licensing, nor contingent on the download goal.
	_body.text = UILocale.translate_message(BODY) + "\n\n" + UILocale.translate_message(FREE_PROJECT)
	_disclaimer.text = UILocale.translate_message(DISCLAIMER)
	_close.tooltip_text = UILocale.translate_message("Close")
	var caption := _close.get_child(0) as Label
	caption.text = _close.tooltip_text
	Fonts.apply_to_tree(self)
	_fit(_title,29,20)
	_fit(_body,22,18)
	_fit(_disclaimer,16,14)
	caption.add_theme_font_size_override("font_size", 20)

func _fit(label: Label, maximum: int, minimum: int) -> void:
	var available := label.size
	label.clip_text = true
	for points in range(maximum, minimum-1, -1):
		label.add_theme_font_size_override("font_size", points)
		var rows := maxi(label.get_line_count(), 1)
		var height := rows * label.get_line_height() + maxi(0,rows-1) * label.get_theme_constant("line_spacing")
		var width := label.get_theme_font("font").get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,points).x
		if height <= available.y and (label.autowrap_mode != TextServer.AUTOWRAP_OFF or width <= available.x): break
	label.size = available
	label.tooltip_text = label.text

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
	if _restored or not is_instance_valid(_screen): return
	_restored = true
	_screen.process_mode = _old_mode
	if _screen.has_method("_focus_future_sign_if_ready"): _screen.call_deferred("_focus_future_sign_if_ready")

func _exit_tree() -> void:
	if UILocale.events().locale_changed.is_connected(_localize): UILocale.events().locale_changed.disconnect(_localize)
	_restore_screen()
