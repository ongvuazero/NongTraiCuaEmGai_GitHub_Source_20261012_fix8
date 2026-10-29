extends RefCounted

# Reuse the existing timber/flower panel in memory. The original 9-slice
# compressed its clean name board to ~130px; dedicated endcaps leave a measured
# 202px timber center while retaining the same native paper and ornament art.
const SOURCE = preload("res://assets/canonical_v2/03_ART_RUNTIME_READY/UI/PANELS/right_detail_panel_9slice.png")
const FONT = preload("res://assets/fonts/BeVietnamPro-SemiBold.ttf")
const SAFE_RECT := Rect2(64, 38, 194, 75)
static var _texture: ImageTexture

static func panel_texture() -> Texture2D:
	if _texture != null: return _texture
	var source := SOURCE.get_image()
	if source.is_compressed(): source.decompress()
	source.convert(Image.FORMAT_RGBA8)
	var composed := Image.create(322, 438, false, Image.FORMAT_RGBA8)
	for region in [[Rect2i(0, 0, 165, 118), Vector2i(0, 0), Vector2i(60, 125)], [Rect2i(165, 0, 295, 118), Vector2i(60, 0), Vector2i(202, 125)], [Rect2i(460, 0, 161, 118), Vector2i(262, 0), Vector2i(60, 125)], [Rect2i(0, 118, 621, 320), Vector2i(0, 125), Vector2i(322, 313)]]:
		var piece := source.get_region(region[0])
		var dimensions: Vector2i = region[2]
		piece.resize(dimensions.x, dimensions.y, Image.INTERPOLATE_LANCZOS)
		composed.blit_rect(piece, Rect2i(Vector2i.ZERO, dimensions), region[1])
	_texture = ImageTexture.create_from_image(composed)
	return _texture

static func fit(label: Label, text: String) -> void:
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	# Refreshes happen after the tree-wide locale pass. Do not replace its Thai/
	# CJK face with the bare Vietnamese-only preload and render names as tofu.
	var font := LocaleFonts.for_text(text, FONT)
	label.add_theme_font_override("font", font)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	# Match Label's WORD_SMART mode, including long German compound words.
	var break_flags := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	label.position = SAFE_RECT.position
	label.custom_minimum_size = Vector2.ZERO
	label.size = SAFE_RECT.size
	var measured := Vector2.ZERO
	for points in range(20, 15, -1):
		label.add_theme_font_size_override("font_size", points)
		measured = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, SAFE_RECT.size.x - 4, points, -1, break_flags)
		# Fallback ascent/descent can exceed Font's estimate. Size against the
		# actual Label shape as well, keeping a readable minimum of 16pt.
		var lines := maxi(label.get_line_count(), 1)
		var shaped_height := float(label.get_line_height()) * lines + float(label.get_theme_constant("line_spacing")) * maxi(lines - 1, 0)
		measured.y = maxf(measured.y, shaped_height)
		if measured.x <= SAFE_RECT.size.x and measured.y <= SAFE_RECT.size.y: break
	label.tooltip_text = text
	label.set_meta("timber_safe_rect", SAFE_RECT)
	label.set_meta("measured_title_size", measured)
	label.set_meta("title_fits_timber", measured.x <= SAFE_RECT.size.x and measured.y <= SAFE_RECT.size.y)
