extends Control

# Presentation only. The existing GameState/SaveService own the current slot.
const UI = preload("res://scripts/ui_factory.gd")
const Nav = preload("res://scripts/ui/farm_navigation_presenter.gd")
const ACCESS_RECT := Rect2(282, 18, 48, 48)
const GEAR_RECT := Rect2(8, 8, 32, 32)
var dialog: Control
var slot_label: Label
var result_label: Label
var save_button: TextureButton
var _screen_input_was_enabled := false
var _screen_process_mode := Node.PROCESS_MODE_INHERIT
var _screen_frozen := false
var _return_focus: Control

func _ready() -> void:
	UILocale.events().locale_changed.connect(_on_locale_changed)
	# This modal remains interactive while the scene's visual/tween clocks stop.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = MOUSE_FILTER_IGNORE
	# Destination world objects use feet-depth up to 1100. The modal must
	# shade the HUD and sit above every transient world/context surface too.
	z_index = 4090
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var access := _build_access()
	access.pressed.connect(open_menu)
	dialog = Control.new()
	dialog.name = "SaveMenuDialog"
	dialog.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dialog.mouse_filter = MOUSE_FILTER_STOP
	dialog.visible = false
	add_child(dialog)
	var veil := ColorRect.new()
	veil.color = Color(0.08, 0.05, 0.02, 0.35)
	veil.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	veil.mouse_filter = MOUSE_FILTER_STOP
	dialog.add_child(veil)
	var paper := UI.panel(Rect2(414, 190, 452, 340))
	dialog.add_child(paper)
	slot_label = UI.label("", Rect2(440, 211, 400, 47), 24, Color("4a2b19"), HORIZONTAL_ALIGNMENT_CENTER)
	dialog.add_child(slot_label)
	result_label = UI.label("", Rect2(446, 275, 388, 77), 17, Color("4a2b19"), HORIZONTAL_ALIGNMENT_CENTER)
	result_label.name = "SaveResult"
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.add_child(result_label)
	save_button = _button("SaveCurrentGame", _t("Lưu game", "Save game"), Rect2(467, 364, 346, 58), "storage", dialog)
	save_button.pressed.connect(save_current_game)
	var close := _button("ResumeGame", _t("Chơi tiếp", "Resume"), Rect2(467, 439, 346, 58), "home", dialog)
	close.pressed.connect(close_menu)

func _build_access() -> TextureButton:
	var access := TextureButton.new()
	access.name = "OpenGameplayMenu"
	# Animal's authored date chip fills x56..432 at y14..79. Its original
	# access band below that HUD stays clear without moving unrelated art.
	access.position = {
		"animal": Vector2(28, 103),
		"settings": Vector2(282, 80),
	}.get(ScreenRouter.current_screen, ACCESS_RECT.position)
	access.size = ACCESS_RECT.size
	access.ignore_texture_size = true
	access.stretch_mode = TextureButton.STRETCH_SCALE
	access.texture_normal = _gear_shell("normal")
	access.texture_hover = _gear_shell("hover")
	access.texture_pressed = _gear_shell("pressed")
	access.texture_disabled = _gear_shell("disabled")
	access.texture_focused = access.texture_hover
	access.mouse_filter = MOUSE_FILTER_STOP
	access.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	access.focus_mode = FOCUS_ALL
	access.tooltip_text = _t("Menu / Lưu (Esc)", "Menu / Save (Esc)")
	access.set_meta("farm_navigation_style", Nav.STYLE_ID)
	access.set_meta("farm_navigation_icon", "settings")
	access.set_meta("presentation_role", "icon_only_gameplay_menu")
	add_child(access)
	var icon := UI.texture_rect(Nav._icon("settings"), GEAR_RECT)
	icon.name = "NavigationIcon"
	icon.mouse_filter = MOUSE_FILTER_IGNORE
	access.add_child(icon)
	return access

func _gear_shell(state: String) -> Texture2D:
	# Preserve the shared skin's authored corner widths instead of squeezing a
	# whole 208px navigation bar into the square icon button. No source art edits.
	var source := Nav._shell(state).get_image()
	var square := Image.create(62, 62, false, Image.FORMAT_RGBA8)
	square.blit_rect(source, Rect2i(0, 0, 31, 62), Vector2i.ZERO)
	square.blit_rect(source, Rect2i(source.get_width() - 31, 0, 31, 62), Vector2i(31, 0))
	return ImageTexture.create_from_image(square)

func _t(vi: String, en: String) -> String:
	return UILocale.pair(vi, en)

func _on_locale_changed(_language: String) -> void:
	# Reword the existing modal without closing it or changing its pause state.
	var access := get_node_or_null("OpenGameplayMenu") as BaseButton
	if access != null: access.tooltip_text = _t("Menu / Lưu (Esc)", "Menu / Save (Esc)")
	var resume := dialog.find_child("ResumeGame", true, false) as TextureButton
	if resume != null: Nav.set_caption(resume, _t("Chơi tiếp", "Resume"))
	if dialog.visible:
		slot_label.text = _t("GAME ĐANG CHƠI · Ô LƯU %d", "CURRENT GAME · SLOT %d") % int(GameState.data.get("selected_slot", GameState.selected_slot))
		_fit_slot_heading()
		result_label.text = UILocale.translate_message(result_label.text)
		var caption := save_button.find_child("Caption", true, false) as Label
		if caption != null: Nav.set_caption(save_button, UILocale.translate_message(caption.text))
	else: Nav.set_caption(save_button, _t("Lưu game", "Save game"))

func _button(id: String, caption: String, rect: Rect2, icon: String, parent: Control = self) -> TextureButton:
	var button := UI.title_button(caption, rect)
	button.name = id
	parent.add_child(button)
	Nav.style_button(button, icon, caption, 18)
	return button

func _fit_slot_heading() -> void:
	var font := LocaleFonts.for_text(slot_label.text, LocaleFonts.regular())
	slot_label.add_theme_font_override("font", font)
	var points := 24
	while points > 18 and (font.get_string_size(slot_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, points).x > 384 or font.get_height(points) > 47):
		points -= 1
	slot_label.add_theme_font_size_override("font_size", points)
	slot_label.clip_text = true
	slot_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	slot_label.tooltip_text = slot_label.text
	slot_label.size = Vector2(400,47)

func open_menu() -> void:
	if dialog.visible: return
	_close_screen_presentation()
	_return_focus = get_viewport().gui_get_focus_owner()
	# Field/animal use _input for pointer gestures, before Godot's GUI modal
	# filtering. Suspend that root handler while the full-screen veil owns input.
	var screen := get_parent()
	_screen_input_was_enabled = screen.is_processing_input()
	screen.set_process_input(false)
	_screen_process_mode = int(screen.get_meta("route_transition_restore_mode", screen.process_mode))
	_screen_frozen = true
	screen.process_mode = Node.PROCESS_MODE_DISABLED
	slot_label.text = _t("GAME ĐANG CHƠI · Ô LƯU %d", "CURRENT GAME · SLOT %d") % int(GameState.data.get("selected_slot", GameState.selected_slot))
	_fit_slot_heading()
	result_label.text = _t("Thao tác thành công đã tự lưu.\nBạn cũng có thể lưu tại đây.", "Successful actions autosave.\nYou can also save here.")
	Nav.set_caption(save_button, _t("Lưu game", "Save game"))
	dialog.show()
	save_button.grab_focus()

func close_menu() -> void:
	if not dialog.visible: return
	dialog.hide()
	# Closing before the fade ends must not enable Field's raw _input early.
	# After it ends, the saved mode is the true pre-guard mode, never DISABLED
	# merely because Back opened us during a transition.
	get_parent().process_mode = Node.PROCESS_MODE_DISABLED if get_parent().has_meta("route_transition_restore_mode") else _screen_process_mode
	_screen_frozen = false
	get_parent().set_process_input(_screen_input_was_enabled)
	if is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree():
		_return_focus.grab_focus()
	else:
		save_button.release_focus()

func _exit_tree() -> void:
	if UILocale.events().locale_changed.is_connected(_on_locale_changed): UILocale.events().locale_changed.disconnect(_on_locale_changed)
	var screen := get_parent()
	if _screen_frozen and is_instance_valid(screen) and not screen.is_queued_for_deletion():
		screen.process_mode = _screen_process_mode
		screen.set_process_input(_screen_input_was_enabled)

func _close_screen_presentation() -> bool:
	var screen := get_parent()
	return bool(screen.call("close_top_presentation")) if screen.has_method("close_top_presentation") else false

func save_current_game() -> bool:
	var location := ScreenRouter.current_screen
	if location == "destination" or location.begins_with("visit_"): location = "islands"
	var succeeded := GameState.save(location)
	result_label.text = (_t("Đã lưu vào ô %d.", "Saved to slot %d.") % int(GameState.data.get("selected_slot", GameState.selected_slot))) if succeeded else _t("Không lưu được. Dữ liệu chưa được xác nhận lưu.\nHãy thử lại.", "Save failed. Your progress is not confirmed saved.\nPlease retry.")
	result_label.add_theme_color_override("font_color", Color("2b6b37") if succeeded else Color("a13c2a"))
	result_label.set_meta("save_succeeded", succeeded)
	Nav.set_caption(save_button, _t("Lưu lại", "Save again") if succeeded else _t("Thử lưu lại", "Retry save"))
	return succeeded

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel", true): return
	get_viewport().set_input_as_handled()
	if event.is_echo(): return
	if dialog.visible:
		close_menu()
	elif not _close_screen_presentation():
		open_menu()
