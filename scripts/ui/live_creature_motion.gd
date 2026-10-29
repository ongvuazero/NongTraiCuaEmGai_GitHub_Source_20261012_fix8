extends Node
# Presentation only: bounded state machine and measured, complete source poses. The
# existing Control is the actor, so its hit target and attached state move with it.
# Neither this controller nor its manifest reads or writes farm/economy state.
const SOURCE_PATH := "res://data/presentation/creature_motion_sources_v1.json"
const BEHAVIOR_PATH := "res://data/presentation/creature_behavior_layout_v1.json"
const MOTION_SHADER = preload("res://scripts/ui/live_creature_motion.gdshader")
const ActorSource = preload("res://scripts/ui/source_silhouette_texture.gd")
const ANIMAL_IDS := {"ChickenVisual01":"cloud_chicken","ChickenVisual02":"cloud_chicken","CowVisual":"cow","SheepVisual":"sheep","DuckVisual":"duck","PigVisual":"pig","CatVisual":"cat","FarmerVisual":"farmer","DestinationFarmer":"farmer"}
const ACTION_IDS := {"feed":1,"pet":2,"clean":3,"collect":4,"heal":4}
const CYCLE := ["walk","forage","idle","walk","look","idle"]
const CARE_DURATION := 0.95
# Memory lasts only for this running game. It is deliberately outside GameState
# and the save service, so returning to a route resumes its presentation.
static var _session_states: Dictionary = {}
var local_clock := 0.0
var externally_paused := false
var paused := true
var records: Dictionary = {}
var _source_data: Dictionary = {}
var _behavior_data: Dictionary = {}
var _frame_sets: Dictionary = {}
var _frame_load_count := 0
var _peak_sheet_rgba_bytes := 0
var _scan_wait := 0.0
var _modal: Control
var max_step_usec := 0
var motion_frames := 0
var _activity_token_seed := 0

func _ready() -> void:
	name = "LiveCreatureMotion"
	var source = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
	var behavior = JSON.parse_string(FileAccess.get_file_as_string(BEHAVIOR_PATH))
	_source_data = source if source is Dictionary else {}
	_behavior_data = behavior if behavior is Dictionary else {}
	_prepare_frames()
	set_process(true)
	set_meta("presentation_only",true)
	set_meta("behavior_manifest",BEHAVIOR_PATH)

func _prepare_frames() -> void:
	# Metadata only. A controller is installed on Title too; loading every
	# creature here used to retain 21 sheets even before one actor was visible.
	for species in _source_data:
		var spec = _source_data[species]
		if not spec is Dictionary or not spec.has("frames") or not spec.has("source"): continue
		# JSON numbers arrive as floats. Array membership is type-sensitive in
		# Godot, so normalize approvals before comparing an integer frame index.
		# Otherwise explicitly approved companions silently hold approved[0].
		var approved: Array[int] = []
		for index in spec.get("approved_frames",range((spec.frames as Array).size())):
			if int(index)>=0 and int(index)<(spec.frames as Array).size(): approved.append(int(index))
		if approved.is_empty(): continue
		spec.approved_frames = approved

func _ensure_frames(species: String) -> bool:
	if _frame_sets.has(species): return not (_frame_sets[species] as Array).is_empty()
	var spec: Dictionary = _source_data.get(species,{})
	if not spec.has("frames") or not spec.has("source"): return false
	var approved: Array = spec.get("approved_frames",[])
	if approved.is_empty(): return false
	var sheets: Dictionary = {}
	var frames: Array[Texture2D] = []
	frames.resize((spec.frames as Array).size()) # Keep original frame indices.
	for index in approved:
		var frame: Dictionary = spec.frames[int(index)]
		var path := String(frame.get("source",spec.source))
		if not sheets.has(path):
			# An absent reviewed source cannot safely use a differently cut sheet.
			# Leave the original static actor visible rather than rendering a bad crop.
			if not ResourceLoader.exists(path): return false
			var sheet := load(path) as Texture2D
			if sheet == null: return false
			sheets[path] = sheet
			_frame_load_count += 1
		var rect: Array = frame.rect
		var atlas := AtlasTexture.new()
		atlas.atlas = sheets[path]
		atlas.region = Rect2(rect[0],rect[1],rect[2],rect[3])
		atlas.filter_clip = true
		frames[int(index)] = atlas
	_frame_sets[species] = frames
	_peak_sheet_rgba_bytes = maxi(_peak_sheet_rgba_bytes,int(_resident_frames().rgba8_bytes_estimate))
	return true

func _prune_frames() -> void:
	var visible_species: Dictionary = {}
	for record in records.values():
		if is_instance_valid(record.body) and (record.body as Control).is_visible_in_tree():
			visible_species[_body_id(record.body)] = true
		else:
			# Hidden actors must not pin atlases or their native alpha mask cache.
			if is_instance_valid(record.sprite): (record.sprite as Sprite2D).texture = null
			(record.frame_masks as Dictionary).clear()
	for species in _frame_sets.keys():
		if not visible_species.has(species): _frame_sets.erase(species)

func _resident_frames() -> Dictionary:
	var sheets: Dictionary = {}
	for frames in _frame_sets.values():
		for frame in frames:
			if frame == null: continue
			var sheet := (frame as AtlasTexture).atlas
			if sheet != null: sheets[sheet.resource_path] = sheet.get_size()
	var estimate := 0
	for size in sheets.values(): estimate += int(size.x)*int(size.y)*4
	var paths: Array = sheets.keys()
	paths.sort()
	return {"species":_frame_sets.keys(),"sheet_count":sheets.size(),"sheet_paths":paths,"rgba8_bytes_estimate":estimate,"scope":"motion atlas references only, not measured GPU/RSS memory"}

func _texture(body: Control) -> Texture2D:
	if body is TextureButton: return (body as TextureButton).texture_normal
	if body is TextureRect: return (body as TextureRect).texture
	return null

func _body_id(body: Control) -> String:
	if body.has_meta("species_id"): return String(body.get_meta("species_id",""))
	if String(body.name) == "DestinationFarmer" or (String(body.name) == "FarmerVisual" and String(body.get_meta("live_motion_scene","")) != "hub"): return "farmer_front"
	if String(body.name).begins_with("DestinationBody_"): return String(body.get_meta("config_id",""))
	return String(ANIMAL_IDS.get(String(body.name),""))

func _vec(value: Array) -> Vector2:
	return Vector2(float(value[0]),float(value[1]))

func _spec(body: Control) -> Dictionary:
	return (_behavior_data.get("bodies",{}) as Dictionary).get(String(body.name),{})

func _lane(body: Control,spec: Dictionary) -> Rect2:
	if body.has_meta("live_motion_lane"):
		var custom = body.get_meta("live_motion_lane")
		if custom is Rect2: return custom
		if custom is Array and custom.size() == 4: return Rect2(custom[0],custom[1],custom[2],custom[3])
	if String(body.get_meta("live_motion_scene","")) == "hub": return Rect2(-4,0,8,3)
	var lane: Array = spec.get("lane",[0,0,0,0])
	return Rect2(lane[0],lane[1],lane[2],lane[3])

func _continuity_key(body: Control,species: String) -> String:
	return String(get_parent().name)+"/"+String(body.get_meta("live_motion_scene",""))+"/"+String(body.name)+"/"+species

func _remember(record: Dictionary) -> void:
	var state: Dictionary = {}
	for key in ["offset","target","behavior","behavior_time","duration","cycle","walk_clock","pose_clock","facing_left","pending_facing","distance","transitions","visited"]:
		state[key] = record[key]
	state.random_state = (record.random as RandomNumberGenerator).state
	_session_states[String(record.continuity_key)] = state.duplicate(true)

func _restore(record: Dictionary) -> bool:
	var state: Dictionary = _session_states.get(String(record.continuity_key),{})
	if state.is_empty(): return false
	for key in state:
		if key != "random_state": record[key] = state[key].duplicate(true) if state[key] is Array or state[key] is Dictionary else state[key]
	(record.random as RandomNumberGenerator).state = int(state.random_state)
	var lane: Rect2 = record.lane
	record.offset = (record.offset as Vector2).clamp(lane.position,lane.end)
	record.target = (record.target as Vector2).clamp(lane.position,lane.end)
	record.restored = true
	return true

func _exit_tree() -> void:
	for record in records.values():
		if is_instance_valid(record.body): _remember(record)
	_frame_sets.clear() # No static texture cache survives a route/controller.

func _discover() -> void:
	var screen := get_parent()
	if screen == null: return
	for node in screen.find_children("*","Control",true,false):
		var body := node as Control
		if _body_id(body).is_empty() or _texture(body) == null: continue
		if not body.is_visible_in_tree(): continue
		if records.has(body.get_instance_id()): continue
		_ensure_frames(_body_id(body))
		var material := ShaderMaterial.new()
		material.shader = MOTION_SHADER
		body.material = material
		var spec := _spec(body)
		var random := RandomNumberGenerator.new()
		random.seed = (String(body.name)+_body_id(body)).hash()
		var phase := random.randf_range(0.0,TAU)
		var sprite := Sprite2D.new()
		sprite.name = "CreatureSourceFrames"
		sprite.centered = false
		sprite.visible = false
		body.add_child(sprite)
		var record := {"body":body,"material":material,"sprite":sprite,"texture":null,"phase":phase,"frame":-1,"source_frames":false,"species":_body_id(body),"action_stamp":-10000,"action_elapsed":10.0,"base":body.position,"offset":Vector2.ZERO,"target":Vector2.ZERO,"lane":_lane(body,spec),"random":random,"behavior":"idle","behavior_time":0.0,"duration":1.0,"cycle":0,"walk_clock":0.0,"pose_clock":phase,"speed":float(spec.get("speed",10.0)),"stride_pixels":float(spec.get("stride_pixels",0.0)),"focused":false,"distance":0.0,"transitions":0,"visited":[],"frame_masks":{},"facing_left":bool(body.get("flip_h")),"pending_facing":bool(body.get("flip_h")),"continuity_key":_continuity_key(body,_body_id(body)),"restored":false,"original_stretch":(body as TextureButton).stretch_mode if body is TextureButton else -1,"original_mask":(body as TextureButton).texture_click_mask if body is TextureButton else null}
		records[body.get_instance_id()] = record
		record["activity"] = {}
		if String(body.get_meta("live_motion_scene","")) == "hub":
			var actor_ratio := clampf(body.size.y/250.0,0.15,1.0)
			record.speed = float(record.speed)*actor_ratio
			# Both travel and stride shrink with the small source silhouette.
			# Scaling speed alone leaves most of the hub lane on one foot pose.
			record.stride_pixels = float(record.stride_pixels)*actor_ratio
		if not _restore(record): _begin_behavior(record,String(spec.get("start","walk")))
		body.set_meta("live_motion_controller",true)
		body.set_meta("live_motion_base",body.position)
		body.set_meta("live_motion_offset",record.offset)

func _begin_behavior(record: Dictionary,behavior: String) -> void:
	var random := record.random as RandomNumberGenerator
	var lane: Rect2 = record.lane
	var pose_spec: Dictionary = _source_data.get(String(record.species),{})
	if behavior == "walk" and (lane.size.length() < 1.0 or not bool(pose_spec.get("locomotion_frames",false))): behavior = "look"
	record.behavior = behavior
	record.behavior_time = 0.0
	record.transitions = int(record.transitions)+1
	if not (record.visited as Array).has(behavior): (record.visited as Array).append(behavior)
	match behavior:
		"walk":
			# Choose the far half of the actor's own lane, so a walk is visible
			# instead of repeatedly picking a nearby subpixel destination.
			var offset: Vector2 = record.offset
			var target_x := lane.end.x if offset.x <= lane.get_center().x else lane.position.x
			record.target = Vector2(target_x,random.randf_range(lane.position.y,lane.end.y))
			record.pending_facing = target_x < offset.x
			record.duration = offset.distance_to(record.target)/maxf(1.0,float(record.speed))+0.15
			if bool(record.pending_facing) != bool(record.facing_left):
				# A sparse side-view sheet cannot author an in-between rotation.
				# Stop, show an accepted attention pose, flip while stationary and
				# recover in that pose before the next source stride can begin.
				record.behavior = "turn"
				record.duration = float(pose_spec.get("turn_duration",0.48))
				record.walk_clock = 0.0
				if not (record.visited as Array).has("turn"): (record.visited as Array).append("turn")
		"forage": record.duration = random.randf_range(1.2,2.0)
		"look": record.duration = random.randf_range(0.8,1.6)
		_: record.duration = random.randf_range(1.0,2.3)

func _focused(body: Control) -> bool:
	if bool(body.get_meta("live_motion_focused",false)): return true
	var screen := get_parent()
	var body_name := String(body.name)
	if body_name.begins_with("DragonBody_"):
		var presenter := body.get_parent()
		var care := presenter.get("care") as Control
		return care != null and care.is_visible_in_tree() and String(presenter.get("selected_id")) == _body_id(body)
	if body_name.begins_with("DestinationBody_"):
		var context := screen.get("context") as Control
		return context != null and context.is_visible_in_tree() and String(screen.get("current_id")) == _body_id(body)
	if String(body.get_meta("live_motion_scene","")) == "hub": return false
	if body_name in ANIMAL_IDS:
		var context := screen.find_child("AnimalCareContext",true,false) as Control
		return context != null and context.is_visible_in_tree() and String(screen.get("_selected_visual_name")) == body_name
	return false

func _paused_now() -> bool:
	var parent := get_parent() as CanvasItem
	if externally_paused or parent == null or not parent.is_visible_in_tree(): return true
	if _modal == null or not is_instance_valid(_modal): _modal = get_parent().find_child("SaveMenuDialog",true,false) as Control
	return _modal != null and _modal.is_visible_in_tree()


func begin_activity(body: Control, offset_points: Array[Vector2], contact_index: int, on_contact: Callable, on_complete := Callable(), speed := 48.0) -> bool:
	if body == null or not records.has(body.get_instance_id()) or offset_points.is_empty() or offset_points.size() > 8: return false
	var record: Dictionary = records[body.get_instance_id()]
	if not (record.get("activity", {}) as Dictionary).is_empty(): return false
	var lane: Rect2 = record.lane
	for point in offset_points:
		if not point.is_equal_approx(point.clamp(lane.position, lane.end)): return false
	if contact_index < 0 or contact_index >= offset_points.size() or not on_contact.is_valid(): return false
	_activity_token_seed += 1
	record["activity"] = {"points": offset_points.duplicate(), "index": 0, "contact_index": contact_index, "on_contact": on_contact, "on_complete": on_complete, "speed": clampf(speed, 12.0, 80.0), "phase": "prepare", "hold": 0.0, "contact_sent": false, "contact_pending": false, "contact_dispatched": false, "token": _activity_token_seed}
	body.set_meta("motion_activity_active", true)
	return true


func cancel_activity(body: Control) -> void:
	if body == null or not records.has(body.get_instance_id()): return
	var record: Dictionary = records[body.get_instance_id()]
	record["activity"] = {}
	body.set_meta("motion_activity_active", false)
	_begin_behavior(record, "idle")


func activity_summary(body: Control) -> Dictionary:
	if body == null or not records.has(body.get_instance_id()): return {"active": false}
	var record: Dictionary = records[body.get_instance_id()]
	var activity: Dictionary = record.get("activity", {})
	return {"active": not activity.is_empty(), "phase": String(activity.get("phase", "")), "index": int(activity.get("index", -1)), "offset": record.offset, "base": record.base, "lane": record.lane}


func _step_activity(record: Dictionary, step: float) -> String:
	var activity: Dictionary = record.activity
	if bool(activity.contact_pending) and not bool(activity.contact_dispatched):
		_dispatch_activity_contact.call_deferred((record.body as Control).get_instance_id(), int(activity.token))
	var points: Array = activity.points
	var target: Vector2 = points[int(activity.index)]
	var offset: Vector2 = record.offset
	if String(activity.phase) == "prepare":
		var direction := target.x - offset.x
		record.pending_facing = direction < 0.0 if absf(direction) > 0.01 else record.facing_left
		if bool(record.pending_facing) != bool(record.facing_left):
			activity.phase = "turn"
			record.behavior_time = 0.0
			record.duration = float((_source_data.get(String(record.species), {}) as Dictionary).get("turn_duration", 0.48))
		else: activity.phase = "walk"
	if String(activity.phase) == "turn":
		record.behavior_time = float(record.behavior_time) + step
		if float(record.behavior_time) >= float(record.duration):
			record.facing_left = record.pending_facing
			activity.phase = "walk"
			return "look"
		return "turn"
	if String(activity.phase) == "hold":
		activity.hold = float(activity.hold) - step
		if float(activity.hold) <= 0.0:
			activity.index = int(activity.index) + 1
			if int(activity.index) >= points.size():
				var complete: Callable = activity.on_complete
				var body := record.body as Control
				cancel_activity(body)
				if complete.is_valid(): complete.call_deferred()
				return "look"
			activity.phase = "prepare"
		return "look"
	var previous: Vector2 = record.offset
	record.offset = previous.move_toward(target, float(activity.speed) * step)
	var moved := previous.distance_to(record.offset)
	record.distance = float(record.distance) + moved
	var walk: Array = (_source_data.get(String(record.species), {}) as Dictionary).get("walk", [])
	var cycle_seconds := _sequence_duration(walk)
	var stride := maxf(float(record.stride_pixels), 1.0)
	record.walk_clock = float(record.walk_clock) + moved / stride * cycle_seconds
	if (record.offset as Vector2).distance_to(target) <= 0.01:
		activity.phase = "hold"
		activity.hold = CARE_DURATION if int(activity.index) == int(activity.contact_index) else 0.12
		if int(activity.index) == int(activity.contact_index) and not bool(activity.contact_sent):
			activity.contact_sent = true
			activity.contact_pending = true
			_dispatch_activity_contact.call_deferred((record.body as Control).get_instance_id(), int(activity.token))
		return "look"
	return "walk"


func _dispatch_activity_contact(body_id: int, token: int) -> void:
	if not records.has(body_id) or _paused_now(): return
	var record: Dictionary = records[body_id]
	var activity: Dictionary = record.get("activity", {})
	if activity.is_empty() or int(activity.get("token", -1)) != token or bool(activity.get("contact_dispatched", false)): return
	var body := record.body as Control
	if not is_instance_valid(body) or not body.is_visible_in_tree(): return
	activity.contact_dispatched = true
	activity.contact_pending = false
	var callback: Callable = activity.on_contact
	if callback.is_valid(): callback.call()

func _process(delta: float) -> void:
	paused = _paused_now()
	if paused:
		_prune_frames() # A hidden route must not retain its motion-only sheets.
		return
	var started := Time.get_ticks_usec()
	var step := minf(delta,0.05)
	local_clock += step
	motion_frames += 1
	_scan_wait -= delta
	if _scan_wait <= 0.0:
		_scan_wait = 0.35
		_discover()
		_prune_frames()
	for key in records.keys():
		var record: Dictionary = records[key]
		if not is_instance_valid(record.body):
			records.erase(key)
			continue
		var body := record.body as Control
		if not body.is_visible_in_tree(): continue
		var texture := _texture(body)
		if texture == null: continue
		if _body_id(body) == "cow" and texture.resource_path.ends_with("cow_idle.png"):
			# Reuse Home's cached connected silhouette in the original full-size
			# texture canvas. Original draw scale, ground feet and Control anchors
			# remain exact; only disconnected neighbor fragments become transparent.
			texture = ActorSource.full_texture(texture.resource_path)
			if body is TextureRect: (body as TextureRect).texture = texture
			elif body is TextureButton:
				(body as TextureButton).texture_normal = texture
				(body as TextureButton).texture_hover = texture
			var clean_mask := BitMap.new()
			if body is TextureButton:
				clean_mask.create_from_image_alpha(texture.get_image(),0.18)
				(body as TextureButton).texture_click_mask = clean_mask
				record.original_mask = clean_mask
		if record.texture != texture: record.texture = texture
		var species := _body_id(body)
		_ensure_frames(species)
		if String(record.species) != species:
			_remember(record)
			record.species = species
			record.continuity_key = _continuity_key(body,species)
			record.offset = Vector2.ZERO
			record.target = Vector2.ZERO
			record.walk_clock = 0.0
			record.pose_clock = float(record.phase)
			record.cycle = 0
			record.distance = 0.0
			record.transitions = 0
			record.visited = []
			record.restored = false
			record.frame_masks = {}
			body.set_meta("care_action","")
			body.set_meta("care_action_at_msec",-10000)
			if not _restore(record): _begin_behavior(record,"look")
		var action := String(body.get_meta("care_action",""))
		var stamp := int(body.get_meta("care_action_at_msec",-10000))
		if int(record.action_stamp) != stamp:
			record.action_stamp = stamp
			record.action_elapsed = 0.0 if stamp>=0 else 10.0
		else: record.action_elapsed = float(record.action_elapsed)+step
		var elapsed := float(record.action_elapsed)
		var reacting := not action.is_empty() and elapsed < CARE_DURATION and elapsed >= 0.0
		var activity_active := not (record.get("activity", {}) as Dictionary).is_empty()
		var focused := (_focused(body) and not activity_active) or reacting
		var activity_state := ""
		record.pose_clock = float(record.pose_clock)+step
		if activity_active and not reacting:
			activity_state = _step_activity(record, step)
		elif not focused:
			record.behavior_time = float(record.behavior_time)+step
			if String(record.behavior) == "walk":
				var previous: Vector2 = record.offset
				record.offset = previous.move_toward(record.target,float(record.speed)*step)
				var moved := previous.distance_to(record.offset)
				record.distance = float(record.distance)+moved
				var walk: Array = (_source_data.get(species,{}) as Dictionary).get("walk",[])
				var cycle_seconds := _sequence_duration(walk)
				var stride := float(record.stride_pixels)
				if stride <= 0.0: stride = maxf(1.0,float(record.speed)*cycle_seconds)
				# Advance only for actual Control travel. A stopped/focused actor
				# never cycles its feet underneath itself; speed and source stride
				# use one distance clock rather than an ignored cadence setting.
				record.walk_clock = float(record.walk_clock)+moved/stride*cycle_seconds
			elif String(record.behavior) == "turn":
				if float(record.behavior_time) >= float(record.duration)*0.5:
					record.facing_left = record.pending_facing
			if float(record.behavior_time) >= float(record.duration):
				if String(record.behavior) == "turn": _begin_behavior(record,"walk")
				else:
					record.cycle = (int(record.cycle)+1)%CYCLE.size()
					_begin_behavior(record,CYCLE[int(record.cycle)])
		var state := "react" if reacting else activity_state if not activity_state.is_empty() else "look" if focused else String(record.behavior)
		var offset: Vector2 = record.offset
		body.position = (record.base as Vector2)+offset
		body.set_meta("live_motion_offset",offset)
		body.set_meta("motion_behavior",state)
		body.set_meta("motion_distance",float(record.distance))
		record.focused = focused
		var material := record.material as ShaderMaterial
		var source_frames := _frame_sets.has(species) and not (_frame_sets[species] as Array).is_empty()
		material.set_shader_parameter("hide_original",source_frames)
		(record.sprite as Sprite2D).visible = source_frames
		record.source_frames = source_frames
		body.set_meta("motion_source","measured source poses + bounded behavior" if source_frames else "unchanged static art; no valid locomotion sequence")
		body.set_meta("source_animation","source_frames_"+species if source_frames else "static fallback; no authored frame sequence")
		if source_frames: _update_source_frame(record,body,action,elapsed,state)
		else:
			if body is TextureButton: (body as TextureButton).stretch_mode = int(record.original_stretch)
			if body is TextureButton and (body as TextureButton).texture_click_mask != record.original_mask:
				(body as TextureButton).texture_click_mask = record.original_mask
			for source_key in ["motion_mouth","source_frame","source_frame_anchor","source_frame_scale"]:
				if body.has_meta(source_key): body.remove_meta(source_key)
			if body.has_meta("motion_alpha_hit_mask"): body.remove_meta("motion_alpha_hit_mask")
	max_step_usec = maxi(max_step_usec,Time.get_ticks_usec()-started)

func _sequence_duration(sequence: Array,default_duration := 0.13) -> float:
	var total := 0.0
	for step in sequence: total += float(step.get("duration",default_duration)) if step is Dictionary else default_duration
	return maxf(total,0.01)

func _sequence_frame(sequence: Array,clock: float,loop := true,default_duration := 0.13) -> int:
	if sequence.is_empty(): return 0
	var total := _sequence_duration(sequence,default_duration)
	var time := fposmod(clock,total) if loop else clampf(clock,0.0,total)
	for step in sequence:
		time -= float(step.get("duration",default_duration)) if step is Dictionary else default_duration
		if time < 0.0: return int(step.get("frame",0)) if step is Dictionary else int(step)
	var last = sequence.back()
	return int(last.get("frame",0)) if last is Dictionary else int(last)

func _sequence_phase(sequence: Array,clock: float) -> String:
	var time := maxf(clock,0.0)
	for step in sequence:
		time -= float(step.get("duration",0.13)) if step is Dictionary else 0.13
		if time < 0.0 and step is Dictionary:
			return String(step.get("phase","prepare" if clock < 0.24 else "bite" if clock < 0.68 else "recover"))
	return "recover"


func _sequence_mirror(sequence: Array, clock: float, loop: bool, fallback: bool) -> bool:
	var total := _sequence_duration(sequence)
	var time := fposmod(clock, total) if loop else clampf(clock, 0.0, total)
	for step in sequence:
		time -= float(step.get("duration", 0.13)) if step is Dictionary else 0.13
		if time < 0.0 and step is Dictionary: return bool(step.get("mirror", fallback))
	return bool((sequence.back() as Dictionary).get("mirror", fallback)) if not sequence.is_empty() and sequence.back() is Dictionary else fallback

func _update_source_frame(record: Dictionary,body: Control,action: String,elapsed: float,state: String) -> void:
	var species := _body_id(body)
	if not _ensure_frames(species): return
	var spec: Dictionary = _source_data[species]
	var sequence: Array = spec.get(state,spec.get("feed",spec.get("idle",[])) if state == "forage" else spec.get("idle",[]))
	var clock := float(record.pose_clock)
	var loop := true
	if state == "walk": clock = float(record.walk_clock)
	if state == "turn":
		var authored_direction := "turn_to_left" if bool(record.pending_facing) else "turn_to_right"
		sequence = spec.get(authored_direction, spec.get("turn",spec.get("look",spec.get("idle",[]))))
		clock = float(record.behavior_time)
		loop = false
	if state == "react":
		sequence = spec.get(action,spec.get("feed",[])) if action == "feed" else spec.get(action,spec.get("look",spec.get("idle",[])))
		clock = elapsed
		loop = false
	var index := clampi(_sequence_frame(sequence,clock,loop),0,(spec.frames as Array).size()-1)
	var approved: Array = spec.get("approved_frames",range((spec.frames as Array).size()))
	if index not in approved: index = int(approved[0])
	# A single uniform scale fits EVERY source pose inside the same input Control.
	# Never resize each pose independently: that makes heads/bodies pulse.
	var pivot := Vector2(0.5,1.0) if String(body.get_meta("live_motion_scene","")) == "hub" else _vec(spec.get("target_pivot",[0.5,0.96]))
	var hub := String(body.get_meta("live_motion_scene","")) == "hub"
	var height_ratio := 1.0 if hub else float(spec.get("fit_height_ratio",1.0))
	var frame_scale := _fit_pose_scale(record,spec,body.size,pivot,height_ratio)
	var frame: Dictionary = spec.frames[index]
	frame_scale *= float(frame.get("source_scale", 1.0))
	var rect: Array = frame.rect
	var feet: Array = frame.feet
	var mirrored := bool(record.facing_left) if bool(spec.get("locomotion_frames",false)) else bool(body.get("flip_h"))
	if state == "turn": mirrored = _sequence_mirror(sequence, clock, loop, mirrored)
	var sprite := record.sprite as Sprite2D
	sprite.texture = (_frame_sets[species] as Array)[index]
	sprite.scale = Vector2(-frame_scale if mirrored else frame_scale,frame_scale)
	sprite.position = body.size*Vector2(1.0-pivot.x if mirrored else pivot.x,pivot.y)
	sprite.offset = Vector2(rect[0]-feet[0],rect[1]-feet[1])
	sprite.self_modulate = body.self_modulate
	sprite.material = null
	record.frame = index
	body.set_meta("source_frame",index)
	body.set_meta("source_frame_anchor",sprite.position)
	body.set_meta("source_frame_scale",frame_scale)
	body.set_meta("motion_sequence_clock",clock)
	body.set_meta("motion_sequence_loop",loop)
	if state == "react":
		body.set_meta("motion_care_phase",_sequence_phase(sequence,elapsed))
	elif body.has_meta("motion_care_phase"): body.remove_meta("motion_care_phase")
	if frame.has("mouth"):
		var mouth_delta := (_vec(frame.mouth)-_vec(feet))*sprite.scale
		body.set_meta("motion_mouth",sprite.position+mouth_delta)
	if body is TextureButton or body is TextureRect: _source_hit_mask(record,index,sprite)

func _fit_pose_scale(record: Dictionary,spec: Dictionary,body_size: Vector2,pivot: Vector2,height_ratio: float) -> float:
	var fit_key := str(record.species)+"/"+str(body_size)+"/"+str(pivot)+"/"+str(height_ratio)
	if String(record.get("fit_key","")) == fit_key: return float(record.fit_scale)
	var extents := Vector4.ZERO # left, right, above ground, below ground
	var approved: Array = spec.get("approved_frames",range((spec.frames as Array).size()))
	for index in approved:
		var frame: Dictionary = spec.frames[int(index)]
		var rect: Array = frame.rect
		var anchor := _vec(frame.feet) # stable torso axis on the virtual ground, NOT the current planted paw
		# Separate reviewed source sheets can have different pixel densities.
		# One explicit normalization per source preserves physical body size;
		# this is never a per-animation-frame pulsing fit.
		var density := float(frame.get("source_scale", 1.0))
		extents.x = maxf(extents.x,(anchor.x-float(rect[0]))*density)
		extents.y = maxf(extents.y,(float(rect[0])+float(rect[2])-anchor.x)*density)
		extents.z = maxf(extents.z,(anchor.y-float(rect[1]))*density)
		extents.w = maxf(extents.w,(float(rect[1])+float(rect[3])-anchor.y)*density)
	var result := minf(body_size.x*pivot.x/maxf(extents.x,1.0),body_size.x*(1.0-pivot.x)/maxf(extents.y,1.0))
	result = minf(result,body_size.y*pivot.y*height_ratio/maxf(extents.z,1.0))
	if extents.w>0.01: result = minf(result,maxf(1.0,body_size.y*(1.0-pivot.y))/extents.w)
	record.fit_key = fit_key
	record.fit_scale = result
	return result

func _source_hit_mask(record: Dictionary,index: int,sprite: Sprite2D) -> void:
	# Cache native alpha masks per measured pose. Source-frame geometry is no
	# longer a static old atlas mask; the clicked silhouette follows the pose.
	var body := record.body as Control
	# The hidden old image no longer defines an aspect-letterboxed hit region.
	# Visible pose alpha spans this exact Control; use that same native space.
	if body is TextureButton: (body as TextureButton).stretch_mode = TextureButton.STRETCH_SCALE
	var mirrored := sprite.scale.x < 0.0
	var normal_texture := _texture(body)
	var normal_size := normal_texture.get_size() if normal_texture != null else body.size
	var key := str(index)+"/"+str(body.size)+"/"+str(mirrored)+"/"+str(normal_size)
	var masks: Dictionary = record.frame_masks
	if not masks.has(key):
		var image := sprite.texture.get_image()
		if image == null or image.is_empty(): return
		image.resize(maxi(1,int(round(image.get_width()*absf(sprite.scale.x)))),maxi(1,int(round(image.get_height()*sprite.scale.y))),Image.INTERPOLATE_BILINEAR)
		var canvas := Image.create(maxi(1,int(body.size.x)),maxi(1,int(body.size.y)),false,Image.FORMAT_RGBA8)
		canvas.fill(Color.TRANSPARENT)
		var corner := sprite.position+sprite.offset*sprite.scale
		if mirrored:
			image.flip_x()
			corner.x -= image.get_width()
		canvas.blit_rect(image,Rect2i(Vector2i.ZERO,image.get_size()),Vector2i(corner.round()))
		# Native BitMap maps render-size alpha over this exact input rectangle.
		var mask := BitMap.new()
		mask.create_from_image_alpha(canvas,0.18)
		masks[key] = mask
	if body is TextureButton: (body as TextureButton).texture_click_mask = masks[key]
	else: body.set_meta("motion_alpha_hit_mask", masks[key])

func set_paused(value: bool) -> void:
	externally_paused = value

func qa_summary() -> Dictionary:
	var source_count := 0
	var ids: Array[String] = []
	var actors: Array[Dictionary] = []
	for record in records.values():
		if not is_instance_valid(record.body): continue
		var body := record.body as Control
		ids.append(_body_id(body))
		if bool(record.source_frames): source_count += 1
		actors.append({"node":String(body.name),"species":_body_id(body),"behavior":String(body.get_meta("motion_behavior","idle")),"offset":[record.offset.x,record.offset.y],"lane":[record.lane.position.x,record.lane.position.y,record.lane.size.x,record.lane.size.y],"distance":record.distance,"transitions":record.transitions,"visited":record.visited,"source_frames":record.source_frames,"focused":record.focused,"frame":record.frame,"visible":body.is_visible_in_tree(),"walk_clock":record.walk_clock,"pose_clock":record.pose_clock,"session_continuity_restored":record.restored})
	# A native SaveMenu can disable the whole screen before our next process
	# tick. Report its current pause truth even in that inherited disabled mode.
	return {"clock":local_clock,"paused":_paused_now(),"targets":records.size(),"source_frame_targets":source_count,"species":ids,"motion_frames":motion_frames,"max_process_usec":max_step_usec,"actors":actors,"resident_frames":_resident_frames(),"frame_sheet_loads":_frame_load_count,"peak_motion_rgba8_bytes_estimate":_peak_sheet_rgba_bytes}
