extends TextureRect

# The same rendered source-pose bitmap is published by LiveCreatureMotion.
# This native Control hit override keeps transparent corners non-interactive,
# including after a mirrored pose. It never reads gameplay state.
var _fallback_key := ""
var _fallback_image: Image

func _has_point(point: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, size).has_point(point): return false
	var pose_mask := get_meta("motion_alpha_hit_mask", null) as BitMap
	if pose_mask != null:
		var pixel := Vector2i(point.floor())
		return Rect2i(Vector2i.ZERO, pose_mask.get_size()).has_point(pixel) and pose_mask.get_bitv(pixel)
	if texture == null: return false
	# Until the controller supplies its first pose, match this TextureRect's
	# authored KEEP_ASPECT_CENTERED source rather than its outer rectangle.
	var key := str(texture.get_instance_id())
	if key != _fallback_key:
		_fallback_key = key
		_fallback_image = texture.get_image()
	if _fallback_image == null or _fallback_image.is_empty(): return false
	var texture_size := Vector2(_fallback_image.get_size())
	var draw_size := size
	var origin := Vector2.ZERO
	if stretch_mode in [STRETCH_KEEP_ASPECT, STRETCH_KEEP_ASPECT_CENTERED]:
		draw_size = texture_size * minf(size.x / texture_size.x, size.y / texture_size.y)
		if stretch_mode == STRETCH_KEEP_ASPECT_CENTERED: origin = (size - draw_size) * 0.5
	if not Rect2(origin, draw_size).has_point(point): return false
	var uv := (point - origin) / draw_size
	if flip_h: uv.x = 1.0 - uv.x
	if flip_v: uv.y = 1.0 - uv.y
	var pixel := Vector2i((uv * texture_size).floor()).clamp(Vector2i.ZERO, _fallback_image.get_size() - Vector2i.ONE)
	return _fallback_image.get_pixelv(pixel).a > 0.18
