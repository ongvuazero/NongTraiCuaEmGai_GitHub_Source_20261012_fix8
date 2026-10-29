extends Control

# Painted source feedback at a world target, not an authority for the transaction.
# Existing static cutouts animate position/scale/alpha; no new creature frames.
const Assets = preload("res://scripts/ui_asset_registry.gd")
const UI = preload("res://scripts/ui_factory.gd")
const Flow = preload("res://scripts/ui/action_feedback_flow.gd")
var action := ""
var succeeded := false
var progress := 0.0
var sprites: Array[TextureRect] = []
var receipt: Label

func start(point: Vector2, action_id: String, success: bool, icon: Texture2D = null, amount := "") -> void:
	position = point - Vector2(55,55)
	size = Vector2(110,110)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 1100
	action = action_id
	succeeded = success
	set_meta("action",action)
	set_meta("action_succeeded",success)
	set_meta("source_animation","painted static cutout feedback; not source-frame animation")
	if success:
		var semantic := {"plant_garden":"seed","water_garden":"water","harvest_garden":"collect","feed":"feed","pet":"pet","clean":"clean","heal":"heal","collect":"collect","gather":"collect"}
		if semantic.has(action):
			var flow := Flow.new()
			flow.name = "SemanticWorldFlow"
			add_child(flow)
			flow.position = Vector2(55,55)
			var receipt_point := Vector2(0,-40)
			if action in ["collect","gather","harvest_garden"]: receipt_point = Vector2(1165,43)-point
			flow.configure(String(semantic[action]),0.95,Vector2.ZERO,icon,receipt_point)
		var source := icon
		if action == "pet": source = Assets.animal_overlay("interaction_success_heart_burst")
		elif action == "clean": source = Assets.animal_overlay("clean_fresh_sparkle")
		elif action == "water_garden": source = Assets.crop_overlay("watered")
		elif source == null: source = Assets.crop_overlay("stage_up")
		var count := 0 if semantic.has(action) else 1
		for index in range(count):
			var sprite := UI.texture_rect(source,Rect2(26 + (index - (count-1)*0.5)*21,26,58,58))
			add_child(sprite)
			sprites.append(sprite)
		if not amount.is_empty():
			receipt = UI.label(amount,Rect2(2,2,106,30),20,Color("fff4c4"),HORIZONTAL_ALIGNMENT_CENTER)
			receipt.add_theme_color_override("font_outline_color",Color("4a2b19"))
			receipt.add_theme_constant_override("outline_size",3)
			add_child(receipt)
	var tween := create_tween()
	tween.tween_method(_step,0.0,1.0,0.95)
	tween.tween_callback(queue_free)

func _step(value: float) -> void:
	progress = value
	modulate.a = 1.0 - smoothstep(0.55,1.0,value)
	for index in range(sprites.size()):
		var sprite := sprites[index]
		var centered := float(index) - (sprites.size()-1)*0.5
		match action:
			"water_garden": sprite.position = Vector2(26 + centered*22,2 + value*45)
			"clean": sprite.position = Vector2(26 + centered*(20+value*10),26-value*18)
			"pet": sprite.position = Vector2(26 + centered*22,26-value*36)
			"feed", "plant_garden": sprite.position = Vector2(26,8+value*20)
			_: sprite.position = Vector2(26,26-value*29)
		sprite.pivot_offset = sprite.size * 0.5
		sprite.scale = Vector2.ONE * (0.82+sin(value*PI)*0.18)
	if receipt != null: receipt.position.y = 2-value*25
	queue_redraw()

func _draw() -> void:
	if succeeded: return
	# Failure never borrows a success heart/product graphic.
	var center := Vector2(55,55)
	var color := Color("dc7666")
	draw_arc(center,18+progress*10,0,TAU,32,color,3.0,true)
	draw_line(center+Vector2(-7,-7),center+Vector2(7,7),color,3.0,true)
	draw_line(center+Vector2(7,-7),center+Vector2(-7,7),color,3.0,true)
