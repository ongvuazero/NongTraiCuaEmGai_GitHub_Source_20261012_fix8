extends BaseButton

# The painted liquid comes from the existing canonical portal. The stone frame
# stays in the Home plate, and this component only fills its original opening.
const PAINT := "res://assets/canonical_v2/03_ART_RUNTIME_READY/PROPS/PORTAL/dragon_portal_complete.png"
const FLOW = preload("res://scripts/ui/painted_portal.gdshader")
const OPENING := [Vector2(16,8),Vector2(30,3),Vector2(44,8),Vector2(55,24),Vector2(61,43),Vector2(58,94),Vector2(4,94),Vector2(7,37)]
var opening := PackedVector2Array(OPENING)
var local_clock := 0.0:
	set(value):
		local_clock = value
		if material is ShaderMaterial: (material as ShaderMaterial).set_shader_parameter("local_clock",value)
var presentation_only := false

func _ready() -> void:
	var flow := ShaderMaterial.new()
	flow.shader = FLOW
	flow.set_shader_parameter("paint_source",load(PAINT))
	flow.set_shader_parameter("local_clock",local_clock)
	material = flow
	set_meta("paint_source",PAINT)
	set_meta("presentation_only",true)
	set_meta("opening_clip","original eight-point Home polygon; inward painted texture flow")
	if presentation_only:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
		disabled = true
	else:
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
	queue_redraw()

func _has_point(point: Vector2) -> bool:
	return false if presentation_only else Geometry2D.is_point_in_polygon(point,opening)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color.WHITE)
	# Keyboard/pointer feedback uses the painted light, with no geometric ring.
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("focused",not presentation_only and (is_hovered() or has_focus()))

func qa_summary() -> Dictionary:
	return {"clock":local_clock,"paint_source":PAINT,"polygon":opening,"presentation_only":presentation_only,"inward_flow":true}
