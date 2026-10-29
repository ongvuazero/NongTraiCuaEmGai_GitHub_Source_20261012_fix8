extends BaseButton

const Badge = preload("res://scripts/ui/world_caption_badge.gd")

# Runtime world object: its state layers stay anchored as transactions refresh.
var record: Dictionary = {}
var artwork: Texture2D
var herb: Texture2D
var state := "empty"
var level := 0
var selected := false
var polygon := PackedVector2Array()
var caption: Label
var status_label: Label
var caption_badge: Control
const BED_ART := {
	# Herb gardens have no till command in existing gameplay; an empty garden
	# is already prepared soil, not an untilled main-Field grass bed.
	"empty": preload("res://assets/field_approved_v1/runtime/plots/plot_tilled.png"),
	"dry": preload("res://assets/field_approved_v1/runtime/plots/plot_tilled.png"),
	"wet": preload("res://assets/field_approved_v1/runtime/plots/plot_wet.png"),
}

func setup(spec: Dictionary, texture: Texture2D, herb_texture: Texture2D, text: String) -> void:
	record = spec
	artwork = texture
	herb = herb_texture
	var dimensions: Array = spec.size
	size = Vector2(dimensions[0], dimensions[1])
	var feet: Array = spec.feet
	var pivot: Array = spec.pivot
	position = Vector2(feet[0], feet[1]) - size * Vector2(pivot[0], pivot[1])
	z_index = int(feet[1])
	for p in spec.hit_shape: polygon.append(Vector2(p[0], p[1]) * size)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	var kind := String(spec.get("kind", "resource"))
	var width := 236.0 if kind == "building" else 190.0 if kind == "workbench" else clampf(size.x, 146, 196)
	var caption_override: Array = spec.get("caption_rect", [])
	if caption_override.size() == 4: width = float(caption_override[2])
	caption_badge = Badge.new()
	caption_badge.name = "CaptionPlaque"
	caption_badge.setup(text, width)
	# Captions on tall landmarks sit over their own base; gardens/resources
	# retain a ground footer. Keep footer paper outside the context's x943 edge.
	var x := clampf(position.x + (size.x - width) * 0.5, 252, 934 - width) - position.x
	caption_badge.position = Vector2(x, size.y - 32 if kind in ["building", "workbench"] else size.y + 6)
	if caption_override.size() == 4:
		# Explicit global paper placement leaves the object's feet, size, pivot,
		# depth and polygon untouched. Text retains its natural measured height.
		caption_badge.position = Vector2(caption_override[0], caption_override[1]) - position
		caption_badge.set_meta("caption_reserved_rect", Rect2(caption_override[0], caption_override[1], caption_override[2], caption_override[3]))
	add_child(caption_badge)
	caption = caption_badge.caption
	status_label = caption_badge.status_label
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func _has_point(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point, polygon)

func set_world_state(value: String, text: String, building_level := 0) -> void:
	state = value
	level = building_level
	set_meta("world_state", state)
	caption_badge.set_status(text)
	queue_redraw()

func _draw() -> void:
	var kind := String(record.get("kind", "resource"))
	draw_set_transform(Vector2(size.x * 0.5, size.y * 0.88), 0.0, Vector2(1, 0.25))
	draw_circle(Vector2.ZERO, size.x * 0.43, Color(0.13, 0.10, 0.08, 0.30))
	draw_set_transform(Vector2.ZERO)
	if kind == "garden":
		# Reuse the painterly soil language, not a flat UI diamond. This is an
		# island herb bed; the 12 canonical Field beds and their geometry are untouched.
		var bed: Texture2D = BED_ART["empty" if state == "empty" else "wet" if state == "wet" else "dry"]
		draw_texture_rect(bed, Rect2(Vector2.ZERO,size),false)
		if state != "empty" and herb != null:
			var plant_size := Vector2(56,58) if state in ["growing", "wet"] else Vector2(72,74)
			for spot in [Vector2(0.34,0.48),Vector2(0.60,0.59)]:
				draw_texture_rect(herb, Rect2(size * spot - plant_size * Vector2(0.5,0.85),plant_size), false)
		if state == "ready":
			draw_arc(size * Vector2(0.5,0.56),size.x * 0.40,0,TAU,40,Color("ffe985"),3.0,true)
	elif artwork != null:
		var tint := Color.WHITE
		if state in ["unbuilt", "blocked"]: tint = Color(0.65,0.65,0.65,0.60)
		if state == "depleted": tint = Color(0.65,0.65,0.65,0.6)
		draw_texture_rect(artwork, Rect2(Vector2.ZERO,size),false,tint)
		if state == "unbuilt":
			draw_line(size * Vector2(0.12,0.88),size * Vector2(0.88,0.88),Color("ebc77a"),4.0,true)
		if state == "ready": draw_circle(size * Vector2(0.8,0.2),6.0,Color("ffe985"))
	if selected or is_hovered() or has_focus():
		var outline := polygon.duplicate()
		if not outline.is_empty():
			outline.append(outline[0])
			draw_polyline(outline, Color("ffe9a7"), 2.0, true)
