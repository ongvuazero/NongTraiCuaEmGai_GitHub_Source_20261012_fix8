extends Node2D

# Additive native flow over existing painted feedback. No input, game state,
# resource costs or global geometry changes. One draw node + one bounded CPU
# emitter + at most one painted token; the owner may cancel at any time.
const MAX_PARTICLES := 24
var action := ""
var lifetime := 0.7
var elapsed := 0.0
var contact := Vector2.ZERO
var destination := Vector2.ZERO
var particles: Array[Dictionary] = []
var emitter: CPUParticles2D
var token: Sprite2D
var _emit_at := 0.2
var _emitted := false
var _has_receipt := false
var _mouth_target: WeakRef
var _modal: Control
var _modal_searched := false

func follow_mouth(body: Control) -> void:
	_mouth_target = weakref(body)
	# Nested care flows must sample AFTER the source-pose controller (priority0),
	# otherwise frame changes leave a one-frame gap between grains and mouth.
	process_priority = 1


func configure(kind: String, duration: float, landing := Vector2.ZERO, art: Texture2D = null, receipt := Vector2.ZERO) -> void:
	action = kind
	lifetime = clampf(duration, 0.35, 1.2)
	contact = landing
	destination = receipt
	set_meta("semantic_action", action)
	set_meta("target_contact", contact)
	set_meta("max_particles", MAX_PARTICLES)
	set_meta("presentation_only", true)
	match action:
		"water", "clean":
			for index in range(10):
				var delay := float(index) * lifetime * 0.026
				_particle(contact + Vector2(-36 + (index % 3) * 3, -52), contact, contact + Vector2(-7, -40), delay, lifetime * 0.42, "drop", Color("76d4fa"), 2.2)
		"till":
			for index in range(8):
				var side := -1.0 if index % 2 == 0 else 1.0
				var end := contact + Vector2(side * (8 + index * 2), 1)
				_particle(contact, end, contact + Vector2(side * (5 + index), -12 - index), index * 0.008, lifetime * 0.7, "clod", Color("957046"), 2.8)
		"seed":
			for index in range(3):
				_particle(contact + Vector2(-34 + index * 5, -35), contact, contact + Vector2(-12, -52), index * 0.04, lifetime * 0.55, "grain", Color("986334"), 2.6)
		"fertilize":
			for index in range(10):
				var x := float((index * 7) % 31) - 15
				_particle(contact + Vector2(x, -33 - index % 3 * 6), contact + Vector2(x * 0.75, 0), contact + Vector2(x + 4, -13), index * 0.012, lifetime * 0.65, "spark", Color("d9bf64"), 2)
		"feed", "heal":
			for index in range(7):
				_particle(contact + Vector2(-31 - index % 2 * 4, -18 + index % 3 * 3), contact, contact + Vector2(-13, -28), index * 0.017, lifetime * 0.52, "grain" if action == "feed" else "spark", Color("cb9f57") if action == "feed" else Color("86d7ad"), 2.4)
		"pet":
			for index in range(6):
				var x := float(index - 3) * 5
				_particle(contact + Vector2(x, 4), contact + Vector2(x + 9, -41), contact + Vector2(x - 9, -21), index * 0.018, lifetime * 0.72, "spark", Color("eca0a1"), 2.6)
		"harvest", "collect":
			for index in range(6):
				_particle(contact, contact + Vector2((index - 3) * 7, -25), contact + Vector2((index - 3) * 3, -18), index * 0.012, lifetime * 0.6, "spark", Color("f0c970"), 2.3)
	_setup_emitter()
	if art != null: _make_token(art)
	_has_receipt = action == "collect"
	set_meta("analytic_particle_count", particles.size())
	set_meta("cpu_particle_count", emitter.amount)
	set_meta("particle_budget", particles.size() + emitter.amount)
	_update_token()
	set_process(true)
	queue_redraw()


func _particle(start: Vector2, end: Vector2, bend: Vector2, delay: float, duration: float, shape: String, tint: Color, radius: float) -> void:
	if particles.size() >= 14: return
	particles.append({"start": start, "end": end, "bend": bend, "delay": delay, "duration": duration, "shape": shape, "tint": tint, "radius": radius})


func _setup_emitter() -> void:
	emitter = CPUParticles2D.new()
	emitter.name = "NativeContactParticles"
	emitter.emitting = false
	emitter.amount = 8
	emitter.lifetime = minf(0.3, lifetime * 0.4)
	emitter.one_shot = true
	emitter.explosiveness = 1.0
	emitter.local_coords = true
	emitter.position = contact
	emitter.direction = Vector2.UP
	emitter.spread = 85
	emitter.initial_velocity_min = 12
	emitter.initial_velocity_max = 24
	emitter.gravity = Vector2(0, 85)
	emitter.scale_amount_min = 1.4
	emitter.scale_amount_max = 2.6
	emitter.color = Color("75ccee") if action in ["water", "clean"] else Color("92724d") if action == "till" else Color("edc967") if action in ["fertilize", "harvest", "collect"] else Color("ebaba1") if action == "pet" else Color("b2cf8a")
	if action == "till":
		emitter.initial_velocity_max = 14
		emitter.gravity = Vector2(0, 120)
	_emit_at = lifetime * (0.53 if action in ["water", "clean", "seed", "feed", "heal"] else 0.24)
	add_child(emitter)


func _make_token(art: Texture2D) -> void:
	if token == null:
		token = Sprite2D.new()
		token.name = "PaintedActionToken"
		add_child(token)
	token.texture = art
	token.scale = Vector2.ONE * (25.0 / maxf(art.get_width(), art.get_height()))


func attach_receipt(point: Vector2, art: Texture2D) -> void:
	# Field harvest gets this only from its real post-commit reward node. Never
	# create an inventory gain or reward label in this presentation helper.
	destination = point
	_has_receipt = true
	if art != null and token == null: _make_token(art)
	set_meta("receipt_destination", destination)
	_update_token()


func _process(delta: float) -> void:
	if not _modal_searched:
		_modal_searched = true
		var ancestor := get_parent()
		while ancestor != null:
			_modal = ancestor.find_child("SaveMenuDialog",true,false) as Control
			if _modal != null: break
			ancestor = ancestor.get_parent()
	var frozen := is_instance_valid(_modal) and _modal.is_visible_in_tree()
	if emitter != null: emitter.speed_scale = 0.0 if frozen else 1.0
	if frozen: return
	if _mouth_target != null:
		var body := _mouth_target.get_ref() as Control
		if is_instance_valid(body) and body.has_meta("motion_mouth"):
			global_position = body.get_global_transform()*Vector2(body.get_meta("motion_mouth"))
	elapsed += delta
	if not _emitted and elapsed >= _emit_at:
		_emitted = true
		emitter.emitting = true
	_update_token()
	queue_redraw()
	if elapsed >= lifetime: queue_free()


func _bezier(start: Vector2, bend: Vector2, end: Vector2, progress: float) -> Vector2:
	return start.lerp(bend, progress).lerp(bend.lerp(end, progress), progress)


func _update_token() -> void:
	if token == null: return
	var progress := clampf(elapsed / lifetime, 0, 1)
	if action in ["harvest", "collect"]:
		token.visible = _has_receipt
		token.position = _bezier(contact + Vector2(0, -8), contact.lerp(destination, 0.45) + Vector2(18, -65), destination, smoothstep(0.04, 0.94, progress))
	elif action in ["feed", "heal"]:
		token.position = _bezier(contact + Vector2(-35, -18), contact + Vector2(-18, -36), contact, smoothstep(0.0, 0.7, progress))
	else:
		token.position = contact + Vector2(sin(progress * PI) * 8, -progress * 37)
	token.modulate.a = 1.0 - smoothstep(0.7, 1.0, progress)
	token.rotation = sin(progress * TAU) * 0.15


func _draw() -> void:
	if action in ["water", "clean"] and elapsed < lifetime * 0.7:
		var alpha := smoothstep(0, lifetime * 0.12, elapsed) * (1.0 - smoothstep(lifetime * 0.48, lifetime * 0.7, elapsed))
		var points := PackedVector2Array()
		for index in range(9): points.append(_bezier(contact + Vector2(-36, -52), contact + Vector2(-7, -40), contact, float(index) / 8.0))
		draw_polyline(points, Color(0.35, 0.75, 0.94, alpha * 0.65), 2.4, true)
	for particle in particles:
		var progress := (elapsed - float(particle["delay"])) / float(particle["duration"])
		if progress < 0 or progress > 1: continue
		var point := _bezier(particle["start"], particle["bend"], particle["end"], progress)
		var tint: Color = particle["tint"]
		tint.a *= 1.0 - smoothstep(0.75, 1, progress)
		var radius := float(particle["radius"])
		match String(particle["shape"]):
			"drop":
				var prior := _bezier(particle["start"], particle["bend"], particle["end"], maxf(0, progress - 0.07))
				draw_line(prior, point, tint, radius, true)
				draw_circle(point, radius * 0.6, tint)
			"clod":
				draw_colored_polygon(PackedVector2Array([point + Vector2(-radius, 0), point + Vector2(0, -radius * 0.7), point + Vector2(radius, 0), point + Vector2(0, radius * 0.65)]), tint)
			"spark":
				draw_line(point + Vector2(-radius, 0), point + Vector2(radius, 0), tint, 1.3, true)
				draw_line(point + Vector2(0, -radius), point + Vector2(0, radius), tint, 1.3, true)
			_: draw_circle(point, radius, tint)
	if action == "seed" and elapsed > lifetime * 0.5:
		var growth := smoothstep(lifetime * 0.5, lifetime * 0.84, elapsed)
		var green := Color("8bab58")
		green.a = (1 - smoothstep(lifetime * 0.87, lifetime, elapsed)) * growth
		draw_line(contact, contact + Vector2(0, -10 * growth), green, 2, true)
		draw_colored_polygon(PackedVector2Array([contact + Vector2(0, -5), contact + Vector2(-6, -9) * growth, contact + Vector2(-2, -11) * growth]), green)
		draw_colored_polygon(PackedVector2Array([contact + Vector2(0, -5), contact + Vector2(6, -11) * growth, contact + Vector2(2, -12) * growth]), green)

