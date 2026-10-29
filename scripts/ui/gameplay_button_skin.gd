extends RefCounted
class_name GameplayButtonSkin

# Presentation only. No action, route, currency, save or disabled-state authority.
const FRAME_PATH := "res://assets/player_feedback_v2/ui/action_frame_green.png"
const FALLBACK_ROOT := "res://assets/canonical_v2/03_ART_RUNTIME_READY/UI/TITLE_SAVE_HOME/title_button_frame_"
const CAPTION_FONT = preload("res://assets/fonts/BeVietnamPro-SemiBold.ttf")
static var _frame_cache: Texture2D
static var _state_shader: Shader


static func apply(button: TextureButton, options: Dictionary = {}) -> void:
	if button == null: return
	var settings: Dictionary = button.get_meta("gameplay_button_skin_options", {}).duplicate()
	settings.merge(options, true)
	button.set_meta("gameplay_button_skin_options", settings)
	button.set_meta("gameplay_button_skin", true)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	var texture := _frame_texture()
	button.texture_normal = texture
	button.texture_hover = texture
	button.texture_pressed = texture
	button.texture_focused = texture
	button.texture_disabled = texture
	if not button.material is ShaderMaterial or not bool(button.get_meta("gameplay_button_material", false)):
		var material := ShaderMaterial.new()
		material.shader = _shader()
		button.material = material
		button.set_meta("gameplay_button_material", true)
	if settings.has("selected"): button.set_meta("gameplay_button_selected", bool(settings["selected"]))
	var caption := _caption(button, settings)
	if caption != null:
		if settings.has("caption"): caption.text = String(settings["caption"])
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.add_theme_font_override("font", LocaleFonts.for_text(caption.text, CAPTION_FONT))
		caption.add_theme_font_size_override("font_size", int(settings.get("font_size", 18)))
		caption.add_theme_color_override("font_outline_color", Color("342919"))
		caption.add_theme_constant_override("outline_size", 1)
		caption.add_theme_color_override("font_shadow_color", Color("281f1870"))
		caption.add_theme_constant_override("shadow_offset_y", 1)
	var icon := _icon(button, settings)
	if icon != null and settings.has("icon_texture"): icon.texture = settings["icon_texture"] as Texture2D
	if icon != null: icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_state_border(button)
	_ensure_selection_check(button)
	if not bool(button.get_meta("gameplay_button_skin_connected", false)):
		button.mouse_entered.connect(_hover.bind(button, true))
		button.mouse_exited.connect(_hover.bind(button, false))
		button.button_down.connect(_pressed.bind(button, true))
		button.button_up.connect(_pressed.bind(button, false))
		button.focus_entered.connect(refresh.bind(button))
		button.focus_exited.connect(refresh.bind(button))
		button.resized.connect(_layout.bind(button))
		button.set_meta("gameplay_button_skin_connected", true)
	_layout(button)
	refresh(button)


static func set_selected(button: TextureButton, selected: bool) -> void:
	if button == null: return
	button.set_meta("gameplay_button_selected", selected)
	refresh(button)


static func refresh(button: TextureButton) -> void:
	if button == null: return
	var settings: Dictionary = button.get_meta("gameplay_button_skin_options", {})
	var selected := bool(button.get_meta("gameplay_button_selected", false))
	var hovered := bool(button.get_meta("gameplay_button_hover", false)) and not button.disabled
	var pressed := bool(button.get_meta("gameplay_button_pressed", false)) and not button.disabled
	button.self_modulate = Color(0.78, 0.78, 0.78, 0.95) if button.disabled else Color(0.68, 0.82, 0.58) if pressed else Color(1.1, 1.12, 1.02) if hovered else Color.WHITE
	(button.material as ShaderMaterial).set_shader_parameter("saturation", 0.0 if button.disabled else 1.0)
	var caption := _caption(button, settings)
	if caption != null:
		caption.add_theme_color_override("font_color", Color("d2cdc1") if button.disabled else Color("fff8df"))
		caption.add_theme_constant_override("outline_size", 1)
	var icon := _icon(button, settings)
	if icon != null: icon.modulate = Color(0.68, 0.68, 0.68, 0.78) if button.disabled else Color.WHITE
	var border := button.get_node("GameplayStateBorder") as Panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color("dbaf54") if pressed else Color("ffe08e") if selected else Color("fff3b7")
	style.set_border_width_all(4 if selected or pressed else 2)
	style.set_corner_radius_all(11)
	style.shadow_size = 0
	style.shadow_color = Color(0, 0, 0, 0)
	border.add_theme_stylebox_override("panel", style)
	border.visible = not button.disabled and (selected or hovered or pressed or button.has_focus())
	(button.get_node("GameplaySelectedCheck") as Label).visible = selected
	button.set_meta("gameplay_button_visual_state", "disabled" if button.disabled else "pressed" if pressed else "selected_hover" if selected and hovered else "selected" if selected else "hover" if hovered else "normal")


static func _frame_texture() -> Texture2D:
	if _frame_cache != null: return _frame_cache
	var source := load(FRAME_PATH) as Texture2D if ResourceLoader.exists(FRAME_PATH) else load(FALLBACK_ROOT + "default.png") as Texture2D
	if source == null: return null
	if ResourceLoader.exists(FRAME_PATH):
		# Alpha>32 bounds measured from the original 1860x846 source. Scaling
		# uses the actual imported texture, not source-sized Atlas coordinates.
		var atlas := AtlasTexture.new()
		atlas.atlas = source
		var imported_scale := source.get_size() / Vector2(1860, 846)
		atlas.region = Rect2(Vector2(198, 125) * imported_scale, Vector2(1461, 567) * imported_scale).intersection(Rect2(Vector2.ZERO, source.get_size()))
		_frame_cache = atlas
		return _frame_cache
	var pixels := source.get_image()
	if pixels != null:
		if pixels.is_compressed(): pixels.decompress()
		var used := pixels.get_used_rect()
		if used.has_area():
			var atlas := AtlasTexture.new()
			atlas.atlas = source
			atlas.region = Rect2(used)
			_frame_cache = atlas
			return _frame_cache
	_frame_cache = source
	return source


static func _shader() -> Shader:
	if _state_shader == null:
		_state_shader = Shader.new()
		_state_shader.code = "shader_type canvas_item; uniform float saturation = 1.0; void fragment() { vec4 tex = texture(TEXTURE, UV); float grey = dot(tex.rgb, vec3(0.299, 0.587, 0.114)); tex.rgb = mix(vec3(grey), tex.rgb, saturation); COLOR = tex * COLOR; }"
	return _state_shader


static func _caption(button: TextureButton, settings: Dictionary) -> Label:
	var supplied = settings.get("caption_node", "Caption")
	if supplied is Label: return supplied as Label
	return button.get_node_or_null(NodePath(String(supplied))) as Label


static func _icon(button: TextureButton, settings: Dictionary) -> TextureRect:
	var supplied = settings.get("icon_node", "GameplayIcon")
	if supplied is TextureRect: return supplied as TextureRect
	var icon := button.get_node_or_null(NodePath(String(supplied))) as TextureRect
	if icon == null and settings.get("icon_texture") is Texture2D:
		icon = TextureRect.new()
		icon.name = String(supplied)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		button.add_child(icon)
	return icon


static func _layout(button: TextureButton) -> void:
	if button == null: return
	var settings: Dictionary = button.get_meta("gameplay_button_skin_options", {})
	var caption := _caption(button, settings)
	var icon := _icon(button, settings)
	# Authored Animal/scene label/icon rectangles remain untouched by default.
	if bool(settings.get("layout_content", false)):
		var icon_width := minf(50.0, button.size.y - 18.0) if icon != null else 0.0
		if icon != null:
			icon.position = Vector2(12, 9)
			icon.size = Vector2(icon_width, maxf(1, button.size.y - 18))
		if caption != null:
			caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			caption.position = Vector2(16 + icon_width, 6)
			caption.size = Vector2(maxf(1, button.size.x - 32 - icon_width), maxf(1, button.size.y - 12))
	var check := button.get_node_or_null("GameplaySelectedCheck") as Label
	if check != null:
		check.position = Vector2(maxf(4, button.size.x - 23), 2)
		check.size = Vector2(20, 22)


static func _ensure_state_border(button: TextureButton) -> void:
	if button.get_node_or_null("GameplayStateBorder") != null: return
	var border := Panel.new()
	border.name = "GameplayStateBorder"
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border.offset_left = 3
	border.offset_top = 3
	border.offset_right = -3
	border.offset_bottom = -3
	border.z_index = 20
	button.add_child(border)


static func _ensure_selection_check(button: TextureButton) -> void:
	if button.get_node_or_null("GameplaySelectedCheck") != null: return
	var check := Label.new()
	check.name = "GameplaySelectedCheck"
	check.text = "✓"
	check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	check.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	check.add_theme_font_override("font", LocaleFonts.for_text(check.text, CAPTION_FONT))
	check.add_theme_font_size_override("font_size", 18)
	check.add_theme_color_override("font_color", Color("fff1bd"))
	check.add_theme_color_override("font_outline_color", Color("644011"))
	check.add_theme_constant_override("outline_size", 2)
	check.z_index = 21
	button.add_child(check)


static func _hover(button: TextureButton, value: bool) -> void:
	button.set_meta("gameplay_button_hover", value)
	if not value: button.set_meta("gameplay_button_pressed", false)
	refresh(button)


static func _pressed(button: TextureButton, value: bool) -> void:
	button.set_meta("gameplay_button_pressed", value)
	refresh(button)
