@tool
extends RefCounted
class_name FarmNavigationPresenter

# Shared game-art presentation. Geometry and callbacks remain owned by each
# screen. These are authored transparent UI assets, never viewport captures.
const ART_PATH := "res://v6/art/plates/home_hub/home_hub_ui_overlay_v6_5.png"
const ART = preload("res://v6/art/plates/home_hub/home_hub_ui_overlay_v6_5.png")
const FONT = preload("res://assets/fonts/BeVietnamPro-Regular.ttf")
const ROOT := "res://assets/canonical_v2/03_ART_RUNTIME_READY"
const DRAGON_ART := ROOT + "/UI/SETTINGS_ANIMAL_DRAGON/dragon_nav.png"
const CELL := Rect2i(23, 129, 208, 62)
const LOGO := Rect2i(29, 9, 235, 111)
const STYLE_ID := "FARM_CREAM_WOOD_ICON_MENU_V1"
const LOGO_RESOURCE_PATH := "res://resources/ui/farm_logo_shared.tres"
const ICONS := {
	"field": [ART_PATH, Rect2i(43, 141, 55, 46)],
	"shop": [ART_PATH, Rect2i(43, 202, 55, 48)],
	"storage": [ART_PATH, Rect2i(43, 268, 55, 48)],
	"animal": [ART_PATH, Rect2i(42, 330, 57, 48)],
	"dragon": [ART_PATH, Rect2i(42, 398, 57, 48)],
	"quest": [ART_PATH, Rect2i(42, 461, 58, 48)],
	"settings": [ART_PATH, Rect2i(42, 528, 56, 49)],
	"egg": [DRAGON_ART, Rect2i(76, 307, 112, 120)],
	"nursery": [DRAGON_ART, Rect2i(62, 454, 144, 108)],
	"play": [DRAGON_ART, Rect2i(70, 601, 127, 103)],
	"book": [DRAGON_ART, Rect2i(64, 879, 140, 108)],
	"home": [ROOT + "/REPAIRS_AND_SHARED/HOME_HUB_NAV/farm_home.png", Rect2i(85, 124, 233, 183)],
	"islands": ["res://v6/art/plates/save/icons/save_detail_icon_location.png", Rect2i()],
	"craft": ["res://assets/gdd_closure_v3/items/alchemy.png", Rect2i()],
	"creatures": [ART_PATH, Rect2i(42, 398, 57, 48)],
	"events": [ART_PATH, Rect2i(42, 461, 58, 48)],
}

static var _shells: Dictionary = {}
static var _icons: Dictionary = {}
static var _logo_texture: Texture2D
static var _logo_source_info: Dictionary = {}

class NavigationLocaleBinding:
	extends Node
	var target: TextureButton
	var refresh: Callable
	func _ready() -> void:
		UILocale.events().locale_changed.connect(_changed)
	func _changed(language: String) -> void:
		refresh.call(language,target)
	func _exit_tree() -> void:
		if UILocale.events().locale_changed.is_connected(_changed): UILocale.events().locale_changed.disconnect(_changed)


static func style_button(button: TextureButton, icon_id: String, caption_text: String, font_size: int = 18) -> void:
	if button == null: return
	button.set_meta("navigation_source_caption",caption_text)
	button.set_meta("farm_navigation_style", STYLE_ID)
	button.set_meta("farm_navigation_icon", icon_id)
	button.set_meta("farm_navigation_art", ART_PATH)
	button.set_meta("navigation_caption_size", font_size)
	button.set_meta("navigation_caption_min_size", mini(font_size, 16))
	button.texture_normal = _shell("normal")
	button.texture_hover = _shell("hover")
	button.texture_pressed = _shell("pressed")
	button.texture_disabled = _shell("disabled")
	button.texture_focused = _shell("hover")
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.focus_mode = Control.FOCUS_ALL
	button.modulate = Color.WHITE
	button.self_modulate = Color.WHITE
	var icon := button.get_node_or_null("NavigationIcon") as TextureRect
	if icon == null:
		icon = TextureRect.new()
		icon.name = "NavigationIcon"
		button.add_child(icon)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _icon(icon_id)
	var caption := button.get_node_or_null("Caption") as Label
	if caption == null:
		# UIFactory's earlier buttons did not assign a caption name.
		for child in button.get_children():
			if child is Label:
				caption = child as Label
				caption.name = "Caption"
				break
	if caption == null:
		caption = Label.new()
		caption.name = "Caption"
		button.add_child(caption)
	caption.text = String(TranslationServer.translate(caption_text)) if Engine.is_editor_hint() else UILocale.translate_message(caption_text)
	caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_override("font", LocaleFonts.for_text(caption.text, FONT))
	caption.add_theme_font_size_override("font_size", font_size)
	caption.add_theme_color_override("font_color", Color("3c2818"))
	caption.add_theme_color_override("font_outline_color", Color("fff4dc"))
	caption.add_theme_constant_override("outline_size", 1)
	caption.add_theme_constant_override("shadow_offset_x", 1)
	caption.add_theme_constant_override("shadow_offset_y", 1)
	caption.add_theme_color_override("font_shadow_color", Color("0000002e"))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.clip_text = true
	caption.max_lines_visible = 1
	_place_content(button)
	var resize := _place_content.bind(button)
	if not button.resized.is_connected(resize): button.resized.connect(resize)
	_bind_locale_refresh(button)


static func _place_content(button: TextureButton) -> void:
	var icon := button.get_node_or_null("NavigationIcon") as TextureRect
	var caption := button.get_node_or_null("Caption") as Label
	var factor := minf(button.size.y / 62.0, 1.0)
	var icon_width := 50.0 * factor
	if icon != null:
		icon.position = Vector2(20.0 * factor, (button.size.y - 46.0 * factor) * 0.5)
		icon.size = Vector2(icon_width, 46.0 * factor)
	if caption != null:
		var font := LocaleFonts.for_text(caption.text, FONT)
		caption.add_theme_font_override("font", font)
		# Reserve the entire icon, a five-pixel gap and the inner wood edge.
		# Label minimum-size behavior must not define the safe text footprint.
		caption.position = Vector2(75.0 * factor, 4.0 * factor)
		var safe_width := maxf(button.size.x - caption.position.x - 14.0 * factor, 1.0)
		button.set_meta("navigation_caption_safe_width", safe_width)
		var font_size := int(button.get_meta("navigation_caption_size", 18))
		var minimum := int(button.get_meta("navigation_caption_min_size", 16))
		while font_size > minimum and font.get_string_size(caption.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 2.0 > safe_width:
			font_size -= 1
		caption.add_theme_font_size_override("font_size", font_size)
		var needs_wrap := font.get_string_size(caption.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 2.0 > safe_width
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if needs_wrap else TextServer.AUTOWRAP_OFF
		caption.max_lines_visible = 2 if needs_wrap else 1
		caption.add_theme_constant_override("line_spacing", -2 if needs_wrap else 1)
		caption.custom_minimum_size = Vector2.ZERO
		caption.size = Vector2(safe_width, maxf(button.size.y - 8.0 * factor, 1.0))


static func set_caption(button: TextureButton, caption_text: String) -> void:
	if button == null: return
	button.set_meta("navigation_source_caption",caption_text)
	var caption := button.get_node_or_null("Caption") as Label
	if caption == null: return
	caption.text = String(TranslationServer.translate(caption_text)) if Engine.is_editor_hint() else UILocale.translate_message(caption_text)
	_place_content(button)


static func _bind_locale_refresh(button: TextureButton) -> void:
	if Engine.is_editor_hint() or button.get_node_or_null("NavigationLocaleBinding")!=null: return
	# A real per-button receiver gives each connection an independent identity;
	# static script callables with binds can collapse to one signal target.
	var binding := NavigationLocaleBinding.new()
	binding.name="NavigationLocaleBinding"
	binding.target=button
	binding.refresh=_on_navigation_locale_changed
	button.add_child(binding)


static func _on_navigation_locale_changed(_locale: String,button: TextureButton) -> void:
	if not is_instance_valid(button) or button.is_queued_for_deletion(): return
	set_caption(button,String(button.get_meta("navigation_source_caption","")))


static func set_selected(button: TextureButton, selected: bool) -> void:
	if button == null: return
	button.texture_normal = _shell("pressed") if selected else _shell("normal")
	button.set_meta("selected", selected)


static func style_logo(logo: TextureRect) -> void:
	if logo == null: return
	# This overlay exports the already-baked Home logo with zero alpha while
	# preserving its RGB artwork. Restore only its silhouette for other screens.
	if _logo_texture == null:
		if ResourceLoader.exists(LOGO_RESOURCE_PATH):
			_logo_texture = load(LOGO_RESOURCE_PATH) as Texture2D
			_logo_source_info = _logo_texture.get_meta("logo_source_diagnostics", {})
		else:
			_logo_texture = build_logo_texture(_source_image(ART))
	logo.texture = _logo_texture
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_SCALE
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.set_meta("farm_navigation_style", STYLE_ID)
	logo.set_meta("farm_navigation_art", ART_PATH)
	logo.set_meta("logo_source_diagnostics", _logo_source_info)


static func build_logo_texture(source: Image) -> ImageTexture:
	# The source-build script reads the original approved UI PNG before any
	# ETC2/ASTC importer can discard RGB hidden under its zero-alpha logo.
	_logo_source_info = {"source_art": ART_PATH, "source_region": [LOGO.position.x, LOGO.position.y, LOGO.size.x, LOGO.size.y], "source_image_size": [source.get_width(), source.get_height()], "source_image_format": source.get_format(), "source_image_compressed": source.is_compressed()}
	if source.is_compressed(): source.decompress()
	if source.get_format() != Image.FORMAT_RGBA8: source.convert(Image.FORMAT_RGBA8)
	var image := source.get_region(LOGO)
	var alpha_max := 0.0
	var colored := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			alpha_max = maxf(alpha_max, color.a)
			if maxf(color.r, maxf(color.g, color.b)) > 0.12: colored += 1
	_logo_source_info["logo_alpha_max_before_restore"] = alpha_max
	_logo_source_info["logo_colored_rgb_pixels"] = colored
	_logo_source_info["mask_recovery"] = "restore approved RGB silhouette; remove connected black background and extraction matte"
	_restore_logo_alpha(image)
	var texture := ImageTexture.create_from_image(image)
	texture.set_meta("logo_source_diagnostics", _logo_source_info)
	return texture


static func _source_image(texture: Texture2D) -> Image:
	var image := texture.get_image()
	# Mobile imports can store ETC2/ASTC; CPU region and flood operations require
	# a decompressed image with explicit RGBA channels.
	if image.is_compressed():
		var error := image.decompress()
		if error != OK: push_error("Farm navigation source image cannot decompress: %d" % error)
	if image.get_format() != Image.FORMAT_RGBA8: image.convert(Image.FORMAT_RGBA8)
	return image


static func _restore_logo_alpha(image: Image) -> void:
	var width := image.get_width()
	var height := image.get_height()
	for y in range(height):
		for x in range(width):
			var color := image.get_pixel(x, y)
			color.a = 1.0
			image.set_pixel(x, y, color)
	var seen := PackedByteArray()
	seen.resize(width * height)
	var points: Array[Vector2i] = []
	for x in range(width):
		points.append(Vector2i(x, 0))
		points.append(Vector2i(x, height - 1))
	for y in range(height):
		points.append(Vector2i(0, y))
		points.append(Vector2i(width - 1, y))
	while not points.is_empty():
		var point: Vector2i = points.pop_back()
		if point.x < 0 or point.y < 0 or point.x >= width or point.y >= height: continue
		var index := point.y * width + point.x
		if seen[index] != 0: continue
		seen[index] = 1
		var color := image.get_pixelv(point)
		var black_background := color.r + color.g + color.b < 0.12
		var extraction_matte := color.r > 0.45 and color.g < 0.15 and color.b < 0.15
		if not black_background and not extraction_matte: continue
		image.set_pixelv(point, Color.TRANSPARENT)
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]: points.append(point + offset)


static func component_signature(button: TextureButton) -> Dictionary:
	var caption := button.get_node_or_null("Caption") as Label
	return {
		"style": button.get_meta("farm_navigation_style", ""),
		"art": button.get_meta("farm_navigation_art", ""),
		"cell": [CELL.position.x, CELL.position.y, CELL.size.x, CELL.size.y],
		"font": caption.get_theme_font("font").resource_path if caption != null else "",
		"font_size": int(button.get_meta("navigation_caption_size", 18)),
		"minimum_font_size": int(button.get_meta("navigation_caption_min_size", 16)),
		"caption_policy": "measured safe width after icon; fit font then two-line wrap",
		"font_color": caption.get_theme_color("font_color").to_html() if caption != null else "",
		"outline": caption.get_theme_constant("outline_size") if caption != null else 0,
		"states": ["normal", "hover", "pressed", "disabled", "focus"],
		"size": [button.size.x, button.size.y],
	}


static func _shell(state: String) -> Texture2D:
	if _shells.has(state): return _shells[state] as Texture2D
	var image := _source_image(ART).get_region(CELL)
	# The source cell's left interior contains its sprout. Retain the authored
	# wood border and copy the adjacent clean cream interior for semantic icons.
	# This composition stays in memory; original art files are never modified.
	for y in range(9, 57):
		for x in range(18, 78):
			image.set_pixel(x, y, image.get_pixel(112 + (x % 12), y))
	if state != "normal":
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var color := image.get_pixel(x, y)
				if state == "hover":
					color.r = minf(color.r * 1.045, 1.0)
					color.g = minf(color.g * 1.025, 1.0)
				elif state == "pressed":
					color.r *= 0.97
					color.g *= 0.94
					color.b *= 0.88
				elif state == "disabled":
					var gray := color.get_luminance()
					color = color.lerp(Color(gray, gray, gray, color.a), 0.45)
				image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	_shells[state] = texture
	return texture


static func _icon(icon_id: String) -> Texture2D:
	if _icons.has(icon_id): return _icons[icon_id] as Texture2D
	var definition: Array = ICONS.get(icon_id, ICONS["field"])
	var source := load(String(definition[0])) as Texture2D
	var rect: Rect2i = definition[1]
	var image := _source_image(source)
	if rect.has_area(): image = image.get_region(rect)
	if rect.has_area() or String(definition[0]).begins_with("res://v6/art/plates/save/icons/"):
		_clear_connected_cream(image)
	var used := image.get_used_rect()
	if used.has_area(): image = image.get_region(used)
	var texture := ImageTexture.create_from_image(image)
	_icons[icon_id] = texture
	return texture


static func _clear_connected_cream(image: Image) -> void:
	# Icon atlases are outlined sprites on cream. Flood only the connected
	# outer cream, retaining pale egg/book highlights enclosed by their ink.
	var width := image.get_width()
	var height := image.get_height()
	var seen := PackedByteArray()
	seen.resize(width * height)
	var points: Array[Vector2i] = []
	for x in range(width):
		points.append(Vector2i(x, 0))
		points.append(Vector2i(x, height - 1))
	for y in range(height):
		points.append(Vector2i(0, y))
		points.append(Vector2i(width - 1, y))
	while not points.is_empty():
		var point: Vector2i = points.pop_back()
		if point.x < 0 or point.y < 0 or point.x >= width or point.y >= height: continue
		var index := point.y * width + point.x
		if seen[index] != 0: continue
		seen[index] = 1
		var color := image.get_pixelv(point)
		if color.a > 0.05 and not (color.r > 0.45 and color.g > 0.28 and color.b > 0.14): continue
		image.set_pixelv(point, Color.TRANSPARENT)
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			points.append(point + offset)
