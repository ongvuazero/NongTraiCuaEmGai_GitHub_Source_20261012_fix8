extends RefCounted
class_name LocaleFonts

const BASE_PATHS := ["res://assets/fonts/BeVietnamPro-Regular.ttf", "res://assets/fonts/BeVietnamPro-SemiBold.ttf", "res://assets/fonts/BeVietnamPro-Bold.ttf"]
const FALLBACK_PATHS := ["res://assets/fonts/noto/NotoSans.ttf", "res://assets/fonts/noto/NotoSansThai.ttf", "res://assets/fonts/noto/NotoSansSC.ttf", "res://assets/fonts/noto/NotoSansJP.ttf", "res://assets/fonts/noto/NotoSansKR.ttf", "res://assets/fonts/noto/NotoSansSymbols2.ttf", "res://assets/fonts/noto/NotoEmoji.ttf", "res://assets/fonts/noto/NotoSansSymbols.ttf"]
static var _initialized := false
static var _fonts: Array[Font] = []
static var _fallbacks: Array[Font] = []
static var _active_locale := ""
static var _multilingual_fonts: Dictionary = {}
static var _text_fallback_fonts: Dictionary = {}
static var _locale_faces: Dictionary = {}
const WEIGHT_TAG := 2003265652 # OpenType big-endian tag wght; native4.6 coordinates require int.


static func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	for path in FALLBACK_PATHS:
		if ResourceLoader.exists(path):
			var font := load(path) as FontFile
			font.allow_system_fallback = false
			_fallbacks.append(font)
		else:
			push_error("Required bundled locale font missing: " + path)
	for path in BASE_PATHS:
		var font := load(path) as FontFile
		# Configure the shared resources, including existing scene/font preloads.
		# Rendering must not depend on fonts installed on the player's machine.
		var weight: float = [400.0, 600.0, 700.0][_fonts.size()]
		var weighted_fallbacks: Array[Font] = []
		for fallback in [_fallbacks[0]]:
			var variation := FontVariation.new()
			variation.base_font = fallback
			variation.variation_opentype = {WEIGHT_TAG: weight}
			weighted_fallbacks.append(variation)
		font.fallbacks = weighted_fallbacks
		font.allow_system_fallback = false
		_fonts.append(font)
	set_locale(TranslationServer.get_locale())


static func set_locale(language: String) -> void:
	initialize()
	if _active_locale == language: return
	_active_locale = language
	# Faces already used by shaped labels stay immutable. Switching a locale
	# selects a cached independent face instead of replacing its fallback RIDs.

static func _locale_face(source: Font, weight: int) -> Font:
	if not source is FontFile: return source
	var key := "%d:%s:%d" % [source.get_instance_id(), _active_locale, weight]
	if not _locale_faces.has(key):
		var face := _fresh_face(source as FontFile)
		var preferred := 3 if _active_locale.begins_with("ja") else 4 if _active_locale.begins_with("ko") else 2 if _active_locale.begins_with("zh") else 1 if _active_locale.begins_with("th") else 0
		var order: Array = [0] if preferred == 0 else [preferred,0]
		var fallbacks: Array[Font] = []
		for index in order:
			var variation := FontVariation.new()
			variation.base_font = _fallbacks[index]
			variation.variation_opentype = {WEIGHT_TAG:float(weight)}
			fallbacks.append(variation)
		face.fallbacks = fallbacks
		face.set_meta("locale_fallback_source",source)
		_locale_faces[key] = face
	return _locale_faces[key]


static func multilingual(weight := 400) -> Font:
	initialize()
	if not _multilingual_fonts.has(weight):
		var index := 2 if weight >= 700 else 1 if weight >= 600 else 0
		var font := _fresh_face(_fonts[index] as FontFile)
		var weighted: Array[Font] = []
		for base in _fallbacks:
			var variation := FontVariation.new()
			variation.base_font = base
			variation.variation_opentype = {WEIGHT_TAG: float(weight)}
			weighted.append(variation)
		font.fallbacks = weighted
		font.allow_system_fallback = false
		_multilingual_fonts[weight] = font
	return _multilingual_fonts[weight]


static func for_text(text: String, preferred: Font = null) -> Font:
	initialize()
	var font := preferred if preferred != null else regular()
	# Keep only the missing glyph faces, not every CJK/Thai/symbol line metric.
	# Remember the original face so a later locale update can choose its own CJK
	# forms rather than inheriting a derived font from a previous locale.
	font = font.get_meta("locale_fallback_source", font) as Font
	var weight := 700 if font == _fonts[2] else 600 if font == _fonts[1] else 400
	var source := font
	font = _locale_face(source,weight)
	var preferred_index := 3 if _active_locale.begins_with("ja") else 4 if _active_locale.begins_with("ko") else 2 if _active_locale.begins_with("zh") else 1 if _active_locale.begins_with("th") else 0
	var order: Array[int] = [preferred_index]
	for index in _fallbacks.size():
		if index not in order: order.append(index)
	var needed: Array[int] = []
	for character in text:
		var code := character.unicode_at(0)
		if code >= 32 and not font.has_char(code):
			for index in order:
				if _fallbacks[index].has_char(code):
					if index not in needed: needed.append(index)
					break
	if needed.is_empty(): return font
	if not font is FontFile: return multilingual(weight)
	var key := "%d:%s:%d:%s" % [font.get_instance_id(), _active_locale, weight, str(needed)]
	if not _text_fallback_fonts.has(key):
		var derived := _fresh_face(font as FontFile)
		var faces: Array[Font] = (font as FontFile).fallbacks.duplicate()
		for index in needed:
			var variation := FontVariation.new()
			variation.base_font = _fallbacks[index]
			variation.variation_opentype = {WEIGHT_TAG: float(weight)}
			faces.append(variation)
		derived.fallbacks = faces
		derived.allow_system_fallback = false
		derived.set_meta("locale_fallback_source", source)
		_text_fallback_fonts[key] = derived
	return _text_fallback_fonts[key]

static func _fresh_face(source: FontFile) -> FontFile:
	# Resource.duplicate also copies populated glyph/texture caches. Reusing
	# those caches with a different fallback RID list corrupted glyphs after
	# locale cycling and inflated unrelated Latin line boxes. Copy font bytes,
	# never the rendered cache, so this face has independent TextServer RIDs.
	var face := FontFile.new()
	face.data = source.data
	face.antialiasing = source.antialiasing
	face.hinting = source.hinting
	face.subpixel_positioning = source.subpixel_positioning
	face.allow_system_fallback = false
	return face


static func regular() -> Font:
	initialize()
	return _locale_face(_fonts[0],400)


static func semibold() -> Font:
	initialize()
	return _locale_face(_fonts[1],600)


static func bold() -> Font:
	initialize()
	return _locale_face(_fonts[2],700)


static func apply_to_tree(root: Node) -> void:
	initialize()
	if root is Control:
		var control := root as Control
		if control is Label or control is BaseButton:
			var existing := control.get_theme_font("font")
			if existing == null:
				control.add_theme_font_override("font", regular())
			elif control is Label:
				control.add_theme_font_override("font", for_text((control as Label).text, existing))
		if control is RichTextLabel:
			control.add_theme_font_override("normal_font", regular())
			control.add_theme_font_override("bold_font", bold())
	for child in root.get_children():
		apply_to_tree(child)
