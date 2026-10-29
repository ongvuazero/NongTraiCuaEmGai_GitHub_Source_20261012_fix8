extends Control

# Home uses an empty scenery plate. All occupants below are presentation-only
# bodies; navigation/care remains with the existing router and animal screen.
const ROOT := "res://assets/canonical_v2/03_ART_RUNTIME_READY/"
const Silhouette = preload("res://scripts/ui/source_silhouette_texture.gd")
const PaintedPortal = preload("res://scripts/ui/painted_portal.gd")
const ACTORS := [
	{"name":"FarmerVisual","species":"farmer_front","source":"ANIMATION/FARMER/idle/frame_01.png","feet":Vector2(786,618),"height":198.0,"route":"field_select","lane":Rect2(0,0,0,0)},
	{"name":"CatVisual","species":"cat","source":"CHARACTERS/CAT/calico_cat_sitting.png","feet":Vector2(855,627),"height":77.0,"route":"","lane":Rect2(-6,-1,12,3)},
	{"name":"CowVisual","species":"cow","source":"CHARACTERS/ANIMALS/cow_idle.png","feet":Vector2(1122,495),"height":97.0,"route":"animal","lane":Rect2(-10,-3,20,5)},
	{"name":"SheepVisual","species":"sheep","source":"CHARACTERS/ANIMALS/sheep_idle.png","feet":Vector2(1064,501),"height":65.0,"route":"animal","lane":Rect2(-7,-2,14,4)},
	{"name":"ChickenVisual01","species":"cloud_chicken","source":"CHARACTERS/ANIMALS/chicken_idle.png","feet":Vector2(1198,519),"height":48.0,"route":"animal","lane":Rect2(-10,-2,20,4)},
	{"name":"ChickenVisual02","species":"cloud_chicken","source":"CHARACTERS/ANIMALS/chicken_idle.png","feet":Vector2(1158,519),"height":23.0,"route":"animal","lane":Rect2(-8,-2,16,4)},
]
var _actors: Array[Control] = []
var _portal: BaseButton
var _bunting: BuntingCanvas
var _modal: Control
var menu_presentation := false
var _actor_parent: Control
static var _retained_presentation_phase := 0.0
var local_clock := 0.0
var externally_paused := false
var _last_route := ""

class BuntingCanvas extends Control:
	var local_clock := 0.0
	func _draw() -> void:
		var rope := PackedVector2Array()
		for index in range(25):
			var p := float(index)/24.0
			rope.append(Vector2(p*91,2.0+sin(p*PI)*6.0-p*4.0))
		draw_polyline(rope,Color("715537"),1.4,true)
		var colors := [Color("d99675"),Color("ebc16f"),Color("86af91"),Color("d6a4ac"),Color("ebc16f")]
		for index in range(5):
			var p := (float(index)+0.75)/6.0
			var top := Vector2(p*91,2.0+sin(p*PI)*6.0-p*4.0)
			var flutter := sin(local_clock*1.1+float(index)*0.6)*2.3
			draw_colored_polygon(PackedVector2Array([top+Vector2(-5,0),top+Vector2(5,0),top+Vector2(flutter,15+sin(local_clock*0.8+float(index)))]),colors[index])

static func install(screen: Control) -> Control:
	var existing := screen.get_node_or_null("HomeLivingPresenter") as Control
	if existing != null: return existing
	var presenter = load("res://scripts/ui/home_living_presenter.gd").new()
	presenter.name = "HomeLivingPresenter"
	screen.add_child(presenter)
	# Behind the existing HUD, nav and order panel. The live controller scans
	# recursively and owns each body's motion without moving the UI hit targets.
	screen.move_child(presenter,mini(2,screen.get_child_count()-1))
	return presenter

static func install_title(screen: Control) -> Control:
	var existing := screen.get_node_or_null("TitleLivingPresenter") as Control
	if existing != null: return existing
	var presenter = load("res://scripts/ui/home_living_presenter.gd").new()
	presenter.name = "TitleLivingPresenter"
	presenter.menu_presentation = true
	presenter.z_index = -10
	screen.add_child(presenter)
	screen.move_child(presenter,mini(1,screen.get_child_count()-1))
	return presenter

func _ready() -> void:
	local_clock = _retained_presentation_phase
	position = Vector2.ZERO
	size = Vector2(1280,720)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_meta("presentation_only",true)
	set_meta("clean_plate_required",true)
	_actor_parent = self
	if menu_presentation:
		# The menu's fixed controls occupy x=486..784. This scenic clip makes
		# their entire column inaccessible to occupants, including future poses.
		_actor_parent = Control.new()
		_actor_parent.name = "TitleScenicOccupantsClip"
		_actor_parent.position = Vector2(786,260)
		_actor_parent.size = Vector2(494,428)
		_actor_parent.clip_contents = true
		_actor_parent.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_actor_parent)
	for spec in ACTORS:
		var actor_spec: Dictionary = spec.duplicate()
		if menu_presentation:
			if String(actor_spec.name)=="FarmerVisual": actor_spec.feet = Vector2(883,625)
			elif String(actor_spec.name)=="CatVisual": actor_spec.feet = Vector2(943,625)
		_add_actor(actor_spec)
	_portal = PaintedPortal.new()
	_portal.presentation_only = menu_presentation
	_portal.name = "TitlePortalVortex" if menu_presentation else "HomePortalVortex"
	_portal.position = Vector2(1114,133)
	_portal.size = Vector2(63,100)
	_portal.set("local_clock",local_clock)
	_portal.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_portal.tooltip_text = tr("Đảo Rồng")
	if not menu_presentation: _portal.pressed.connect(_navigate.bind("dragon",""))
	add_child(_portal)
	_bunting = BuntingCanvas.new()
	_bunting.name = "HomeWindBunting"
	_bunting.position = Vector2(943,369)
	_bunting.size = Vector2(92,26)
	_bunting.local_clock = local_clock
	_bunting.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bunting)
	if not menu_presentation:
		_add_route_zone("HomeFieldEntry",Rect2(256,433,367,117),"field_select",tr("Ruộng"))
		_add_route_zone("HomeFarmhouseEntry",Rect2(488,278,61,85),"storage",tr("Kho"))
		_add_route_zone("HomeBarnEntry",Rect2(1042,353,224,140),"animal",tr("Vật nuôi"))
	# Actor click targets are above the broad world zones.
	if not menu_presentation:
		for body in _actors: move_child(body,get_child_count()-1)
	set_process(true)

func _add_actor(spec: Dictionary) -> void:
	var source := load(ROOT+String(spec.source)) as Texture2D
	if source == null: return
	var isolated := Silhouette.texture(ROOT+String(spec.source))
	var image := isolated.get_image()
	var visible := Rect2(image.get_used_rect()) if image != null else Rect2(Vector2.ZERO,source.get_size())
	if visible.size.x<=0.0 or visible.size.y<=0.0: return
	var trimmed := AtlasTexture.new()
	trimmed.atlas = isolated
	trimmed.region = visible
	trimmed.filter_clip = true
	var body: Control
	if menu_presentation:
		var decorative := TextureRect.new()
		decorative.texture = trimmed
		decorative.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		decorative.stretch_mode = TextureRect.STRETCH_SCALE
		decorative.mouse_filter = Control.MOUSE_FILTER_IGNORE
		decorative.focus_mode = Control.FOCUS_NONE
		body = decorative
	else:
		var interactive := TextureButton.new()
		interactive.texture_normal = trimmed
		interactive.ignore_texture_size = true
		interactive.stretch_mode = TextureButton.STRETCH_SCALE
		body = interactive
	body.name = String(spec.name)
	body.size = visible.size*(float(spec.height)/visible.size.y)
	body.position = Vector2(spec.feet)-body.size*Vector2(0.5,1.0)-(_actor_parent.position if menu_presentation else Vector2.ZERO)
	body.pivot_offset = body.size*Vector2(0.5,0.94)
	body.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	body.tooltip_text = tr("Ruộng") if String(spec.species).begins_with("farmer") else tr("Vuốt ve") if spec.species=="cat" else tr("Vật nuôi")
	if image != null and body is TextureButton:
		var click_mask := BitMap.new()
		click_mask.create_from_image_alpha(image.get_region(Rect2i(visible)),0.12)
		(body as TextureButton).texture_click_mask = click_mask
	body.set_meta("species_id",String(spec.species))
	body.set_meta("live_motion_scene","hub")
	body.set_meta("live_motion_lane",spec.lane)
	body.set_meta("home_ground_feet",spec.feet)
	body.set_meta("presentation_only",true)
	body.set_meta("original_source",ROOT+String(spec.source))
	body.set_meta("source_isolation","center connected alpha silhouette; cached in memory; original PNG unchanged")
	body.set_meta("care_action","")
	if body is TextureButton: (body as TextureButton).pressed.connect(_actor_pressed.bind(body,String(spec.route),String(spec.species)))
	_actor_parent.add_child(body)
	_actors.append(body)

func _add_route_zone(id: String,rect: Rect2,route: String,caption: String) -> void:
	var button := Button.new()
	button.name = id
	button.position = rect.position
	button.size = rect.size
	button.flat = true
	button.modulate.a = 0.0
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = caption
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(_navigate.bind(route,""))
	add_child(button)

func _actor_pressed(body: Control,route: String,species: String) -> void:
	if species=="cat":
		body.set_meta("care_action","pet")
		body.set_meta("care_action_at_msec",Time.get_ticks_msec())
		return
	_navigate(route,species)

func _navigate(route: String,species: String) -> void:
	_last_route = route
	if ScreenRouter.host == null: return
	ScreenRouter.go(route)
	if route=="animal" and species in ["cow","cloud_chicken"] and ScreenRouter.host.get_child_count()>0:
		var screen := ScreenRouter.host.get_child(ScreenRouter.host.get_child_count()-1)
		if screen.has_method("_select_species"): screen.call_deferred("_select_species",species)

func set_paused(value: bool) -> void:
	externally_paused = value

func _draw() -> void:
	for body in _actors:
		if not is_instance_valid(body): continue
		var feet := body.position+body.size*Vector2(0.5,1.0)+(_actor_parent.position if menu_presentation else Vector2.ZERO)
		if menu_presentation and feet.x<786.0: continue
		var width := body.size.x*0.30
		var depth := clampf(body.size.y*0.025,2.0,5.0)
		draw_set_transform(feet-Vector2(0,1),0.0,Vector2(width,depth))
		draw_circle(Vector2.ZERO,1.0,Color(0.15,0.13,0.08,0.18))
		draw_set_transform(Vector2.ZERO)

func _process(delta: float) -> void:
	if externally_paused or not is_visible_in_tree(): return
	if _modal==null or not is_instance_valid(_modal): _modal=get_parent().find_child("SaveMenuDialog",true,false) as Control
	if _modal!=null and _modal.is_visible_in_tree(): return
	local_clock += minf(delta,0.05)
	_retained_presentation_phase = local_clock
	_portal.set("local_clock",local_clock)
	_bunting.local_clock = local_clock
	_bunting.queue_redraw()
	queue_redraw()

func qa_summary() -> Dictionary:
	return {"actors":_actors.size(),"clock":local_clock,"last_route":_last_route,"mouse_filter":mouse_filter,"portal_clock":_portal.get("local_clock"),"menu_presentation":menu_presentation,"save_writes":0}
