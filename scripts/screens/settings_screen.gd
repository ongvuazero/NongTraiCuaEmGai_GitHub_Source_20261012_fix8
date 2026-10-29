extends BaseScreen

const CardState = preload("res://scripts/ui/item_card_state_presenter.gd")
const ButtonSkin = preload("res://scripts/ui/gameplay_button_skin.gd")
const MobileRuntime = preload("res://scripts/ui/mobile_runtime.gd")
var _settings_save_failed := false


func build() -> void:
	set_meta("TRUE_WYSIWYG_V2", "VISUAL_REVIEW_REQUIRED")
	set_meta("UI_IN_PLACE_REFRESH", true)
	GameState.begin_settings()
	bind_standard_left_navigation()
	if GameState.settings_use_global_preferences():
		for child in get_node("TopHUD").get_children():
			if child.name != "Logo": (child as CanvasItem).hide()
		for route in ["field_select", "shop", "storage", "animal", "dragon", "quest", "settings", "RestNextDay"]:
			var navigation := find_child("LeftNav_" + route, true, false) as Control
			if navigation != null: navigation.hide()
	bind_button("SettingsBack", _back)
	bind_button("SettingsClose", _back)
	bind_button("SettingsFullscreenToggle", _toggle_fullscreen)
	bind_button("SettingsResetDefaults", _reset_defaults)
	bind_button("SettingsApply", _apply)
	_bind_language_control()
	for key in ["master", "music", "sfx"]:
		bind_button("Settings_%s_Down" % key, _step_volume.bind(key, -5))
		bind_button("Settings_%s_Up" % key, _step_volume.bind(key, 5))
	var selected_nav := find_child("LeftNav_settings", true, false) as TextureButton
	if selected_nav != null:
		preload("res://scripts/ui/farm_navigation_presenter.gd").set_selected(selected_nav, true)
	_refresh()
	preload("res://scripts/ui/credits_dialog.gd").install(self)


func _refresh() -> void:
	bind_top_hud()
	_refresh_settings_visuals()
	var dirty := _is_draft_dirty()
	var apply := find_child("SettingsApply", true, false) as BaseButton
	var reason := GameState.status if _settings_save_failed and dirty else tr("Lưu thay đổi cài đặt.") if dirty else tr("Cài đặt đã được lưu; chưa có thay đổi mới.")
	CardState.apply_action(apply, dirty, reason)
	(apply.get_node("Caption") as Label).text = tr("Retry save") if _settings_save_failed and dirty else tr("Áp dụng")
	for name in ["SettingsApply", "SettingsResetDefaults", "SettingsFullscreenToggle", "SettingsBack", "SettingsClose"]:
		var button := find_child(name, true, false) as TextureButton
		if button != null: ButtonSkin.apply(button, {"font_size": 20 if name == "SettingsApply" else 17})
	set_meta("settings_draft_dirty", dirty)
	LocaleFonts.apply_to_tree(self)
	_fit_audio_row_labels()


func _fit_audio_row_labels() -> void:
	for pair in [["MasterVolumeLabel", "master"], ["MusicVolumeLabel", "music"], ["SfxVolumeLabel", "sfx"]]:
		var label := find_child(pair[0], true, false) as Label
		var decrease := find_child("Settings_%s_Down" % pair[1], true, false) as BaseButton
		if label == null or decrease == null: continue
		# Enable wrapping/clipping BEFORE resizing so the translated one-line
		# minimum width cannot silently push the label back over the minus button.
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.clip_text = true
		# Reserve the MOBILE extension as well as the visible minus button.
		var extension := maxf(0.0, 48.0 - decrease.size.x) * 0.5 if MobileRuntime.is_mobile() else 0.0
		label.size.x = maxf(60.0, decrease.get_global_rect().position.x - label.get_global_rect().position.x - extension - 12.0)
		# Rows are55px apart; 50px fits two localized16pt lines without clipping.
		label.size.y = 50.0
		var font := label.get_theme_font("font")
		var shown_text := label.tr(label.text)
		var point_size := 17
		while point_size > 16 and font.get_string_size(shown_text, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size).x > label.size.x:
			point_size -= 1
		label.add_theme_font_size_override("font_size", point_size)


func _refresh_settings_visuals() -> void:
	var definitions := {
		"master": ["SettingsMasterValue", "SettingsMasterTrack"],
		"music": ["SettingsMusicValue", "SettingsMusicTrack"],
		"sfx": ["SettingsSfxValue", "SettingsSfxTrack"],
	}
	for key in definitions:
		var value := clampf(float(GameState.settings_draft.get(key, 0.0)), 0.0, 100.0)
		var value_label := find_child(definitions[key][0], true, false) as Label
		var track := find_child(definitions[key][1], true, false) as Control
		if value_label != null: value_label.text = "%d%%" % int(value)
		if track != null:
			var fill := track.find_child("ProgressFill", true, false) as Control
			if fill != null: fill.size.x = maxf(track.size.x - 8, 0) * value / 100.0
			var handle_name: String = {"master": "MasterSliderHandle", "music": "MusicSliderHandle", "sfx": "SfxSliderHandle"}[key]
			var handle := track.get_parent().get_node_or_null(handle_name) as Control
			if handle != null: handle.position.x = track.position.x + 4 + (track.size.x - 8) * value / 100.0 - handle.size.x * 0.5
		CardState.apply_action(find_child("Settings_%s_Down" % key, true, false) as BaseButton, value > 0, tr("Giảm âm lượng.") if value > 0 else tr("Âm lượng đã ở mức thấp nhất."))
		CardState.apply_action(find_child("Settings_%s_Up" % key, true, false) as BaseButton, value < 100, tr("Tăng âm lượng.") if value < 100 else tr("Âm lượng đã ở mức cao nhất."))
	var caption := get_node_or_null("MainContent/DisplaySection/SettingsFullscreenToggle/Caption") as Label
	var mobile := MobileRuntime.is_mobile()
	if caption != null: caption.text = tr("BẬT") if mobile or bool(GameState.settings_draft.get("fullscreen", false)) else tr("TẮT")
	var display_toggle := find_child("SettingsFullscreenToggle", true, false) as BaseButton
	if display_toggle != null:
		display_toggle.disabled = mobile
		display_toggle.tooltip_text = tr("Toàn màn hình") if mobile else ""
	var mode_label := get_node_or_null("MainContent/DisplaySection/WindowModeValue/ValueLabel") as Label
	if mode_label != null: mode_label.text = tr("Toàn màn hình") if mobile or bool(GameState.settings_draft.get("fullscreen", false)) else tr("Cửa sổ")
	var mode_title := get_node_or_null("MainContent/DisplaySection/WindowModeLabel") as Label
	if mode_title != null: mode_title.text = tr("HIỂN THỊ") if mobile else tr("Chế độ cửa sổ")
	var language := get_node_or_null("MainContent/LanguageSection/LanguageValue/ValueLabel") as Label
	if language != null: language.text = LocaleRegistry.native_name(UILocale.current_locale())
	var language_button := find_child("SettingsLanguageToggle", true, false) as BaseButton
	if language_button is OptionButton:
		var picker := language_button as OptionButton
		picker.select(LocaleRegistry.SUPPORTED.find(UILocale.current_locale()))
		var info := UILocale.coverage()
		picker.tooltip_text = tr("Đổi ngôn ngữ · lưu ngay") + "\n" + (tr("Translation coverage: %d / %d") % [info.translated, info.total])
		if not info.native_approved: picker.tooltip_text += "\n" + tr("Draft translation — not yet reviewed by a native speaker.")
	# These passive values replace the previous unbound gameplay toggles.
	var progress := get_node("MainContent/GameplaySection/RestConfirmValue/ValueLabel") as Label
	progress.text = "%d / 3" % mini(int(GameState.data.get("orders_done", 0)), 3)
	var guide := get_node("MainContent/GameplaySection/GuideVisibilityValue/ValueLabel") as Label
	guide.text = tr("Đang hiện") if int(GameState.data.get("orders_done", 0)) == 0 else tr("Đã xong")


func _bind_language_control() -> void:
	var panel := get_node_or_null("MainContent/LanguageSection/LanguageValue") as Control
	if panel == null or panel.get_node_or_null("SettingsLanguageToggle") != null: return
	# Native names are longer than VI/EN; keep the selected text inside the
	# existing paper instead of allowing OptionButton's minimum size to spill.
	panel.position.x = 892
	panel.size.x = 215
	var language_label := get_node_or_null("MainContent/LanguageSection/LanguageLabel") as Control
	if language_label != null: language_label.size.x = 137
	var text_label := get_node_or_null("MainContent/LanguageSection/TextSizeLabel") as Control
	if text_label != null: text_label.size.x = 137
	var text_value := get_node_or_null("MainContent/LanguageSection/TextSizeValue") as Control
	if text_value != null:
		text_value.position.x = 892
		text_value.size.x = 215
	var button := OptionButton.new()
	button.name = "SettingsLanguageToggle"
	# These are registry-owned native names, not game translation keys. Without
	# this, aliases can translate English to Tiếng Anh or Malay to "Language".
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.fit_to_longest_item = false
	button.add_theme_font_override("font", LocaleFonts.semibold())
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color("4a2b19"))
	for language in LocaleRegistry.SUPPORTED: button.add_item(LocaleRegistry.native_name(language))
	button.item_selected.connect(_choose_language)
	var popup := button.get_popup()
	popup.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	popup.add_theme_font_override("font", LocaleFonts.multilingual())
	popup.add_theme_font_size_override("font_size", 19)
	popup.add_theme_color_override("font_color", Color("4a2b19"))
	popup.add_theme_color_override("font_hover_color", Color("fff2d9"))
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("fff1d8")
	paper.border_color = Color("855329")
	paper.set_border_width_all(3)
	paper.set_corner_radius_all(8)
	popup.add_theme_stylebox_override("panel", paper)
	var selected := paper.duplicate() as StyleBoxFlat
	selected.bg_color = Color("28733b")
	popup.add_theme_stylebox_override("hover", selected)
	button.select(LocaleRegistry.SUPPORTED.find(UILocale.current_locale()))
	panel.add_child(button)
	var value := panel.get_node_or_null("ValueLabel") as Label
	if value != null:
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		value.hide()


func _choose_language(index: int) -> void:
	if index < 0 or index >= LocaleRegistry.SUPPORTED.size(): return
	UILocale.set_locale(LocaleRegistry.SUPPORTED[index])
	_refresh()


func _is_draft_dirty() -> bool:
	var baseline := GameState.settings_baseline()
	for key in ["master", "music", "sfx"]:
		if not is_equal_approx(float(GameState.settings_draft.get(key, 0.0)), float(baseline.get(key, 0.0))):
			return true
	return not MobileRuntime.is_mobile() and bool(GameState.settings_draft.get("fullscreen", false)) != bool(baseline.get("fullscreen", false))


func _step_volume(key: String, delta: int) -> void:
	GameState.update_setting(key, clampi(int(GameState.settings_draft.get(key, 0)) + delta, 0, 100))
	_refresh()


func _toggle_fullscreen() -> void:
	if MobileRuntime.is_mobile(): return
	GameState.update_setting("fullscreen", not bool(GameState.settings_draft.get("fullscreen", false)))
	_refresh()


func _reset_defaults() -> void:
	GameState.reset_settings()
	_refresh()


func _apply() -> void:
	if _is_draft_dirty():
		_settings_save_failed = not GameState.apply_settings()
	_refresh()


func _back() -> void:
	ScreenRouter.go(GameState.settings_return)
