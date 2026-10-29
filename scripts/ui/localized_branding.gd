extends Control
class_name LocalizedBranding

# One painted identity, exact native Unicode wordmarks. No input/save ownership.
const Registry = preload("res://scripts/localization/locale_registry.gd")
const Fonts = preload("res://scripts/localization/locale_fonts.gd")
const PLAQUE_PATH := "res://assets/branding_v1/logo_plaque_blank.png"
const MASK_PATH := "res://scripts/ui/background_native_ui_mask.gdshader"
var screen: Control
var route := ""
var plaque: TextureRect
var lines: Array[Label] = []
var clock := 0.0
var last_locale := ""
var last_rect := Rect2()

static func install(target: Control, screen_route: String) -> void:
	if target.get_node_or_null("LocalizedBranding")!=null: return
	var presenter := LocalizedBranding.new()
	presenter.name="LocalizedBranding"
	presenter.screen=target
	presenter.route=screen_route
	target.add_child(presenter)

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	focus_mode=Control.FOCUS_NONE
	z_index=1400
	set_meta("presentation_only",true)
	plaque=TextureRect.new()
	plaque.name="LocalizedLogoPlaque"
	plaque.texture=load(PLAQUE_PATH) as Texture2D
	plaque.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	plaque.stretch_mode=TextureRect.STRETCH_SCALE
	plaque.mouse_filter=Control.MOUSE_FILTER_IGNORE
	plaque.auto_translate_mode=Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(plaque)
	for index in range(2):
		var caption:=Label.new()
		caption.name="LocalizedLogoLine%d"%index
		caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
		caption.auto_translate_mode=Node.AUTO_TRANSLATE_MODE_DISABLED
		caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		caption.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		caption.add_theme_color_override("font_color",Color("fff3db") if index==0 else Color("d0efa2"))
		caption.add_theme_color_override("font_outline_color",Color("4b2513"))
		caption.add_theme_color_override("font_shadow_color",Color("582713"))
		add_child(caption)
		lines.append(caption)
	_refresh()

func _notification(what: int) -> void:
	if what==NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		last_locale=""
		call_deferred("_refresh")

func _process(delta: float) -> void:
	clock+=delta
	if clock<0.20: return
	clock=0.0
	_refresh()

func _logo_rect() -> Rect2:
	if route=="title": return Rect2(407,40,449,237)
	if route=="hub": return Rect2(26,3,238,118)
	if route=="save": return Rect2(27,8,244,114)
	var result:=Rect2()
	for candidate in screen.find_children("*","TextureRect",true,false):
		var texture:=candidate as TextureRect
		if is_ancestor_of(texture): continue
		var source:=texture.texture
		var known := String(texture.name)=="Logo" or texture.has_meta("logo_source_diagnostics")
		if source!=null:
			known = known or source.resource_path.ends_with("/canonical_logo.png") or source.resource_path.ends_with("/farm_logo_shared.tres") or source.resource_path.ends_with("/runtime/ui/logo.png")
		if not known: continue
		if not texture.is_visible_in_tree() and not texture.has_meta("localized_brand_hidden"): continue
		if result.size==Vector2.ZERO:
			result=Rect2(screen.get_global_transform().affine_inverse()*texture.global_position,texture.get_global_rect().size/screen.get_global_transform().get_scale().abs())
		texture.set_meta("localized_brand_hidden",true)
		texture.hide()
	return result

func _mask_baked_logo(rect: Rect2) -> void:
	if route not in ["title","hub","save"]: return
	for candidate in screen.find_children("*","CanvasItem",true,false):
		var item:=candidate as CanvasItem
		var material:=item.material as ShaderMaterial
		if material==null or material.shader==null or material.shader.resource_path!=MASK_PATH: continue
		# Current mask plate is authored at1280x720 and its transform is retained.
		material.set_shader_parameter("localized_brand_exclusion",Vector4(rect.position.x,rect.position.y,rect.size.x,rect.size.y))

func _refresh() -> void:
	if not is_instance_valid(screen) or not is_instance_valid(plaque): return
	var rect:=_logo_rect()
	if rect.size==Vector2.ZERO:
		hide()
		return
	show()
	_mask_baked_logo(rect)
	var locale:=UILocale.current_locale()
	if rect==last_rect and locale==last_locale: return
	last_rect=rect
	last_locale=locale
	position=rect.position
	size=rect.size
	plaque.position=Vector2.ZERO
	plaque.size=size
	var names:=Registry.title_lines(locale)
	var font:=Fonts.bold()
	for index in range(2):
		var caption:=lines[index]
		caption.text=names[index]
		caption.add_theme_font_override("font",font)
		caption.position=Vector2(size.x*0.14,size.y*(0.20 if index==0 else 0.47))
		caption.size=Vector2(size.x*0.72,size.y*0.31)
		var font_size:=int(size.y*(0.255 if index==0 else 0.285))
		var minimum:=12
		while font_size>minimum and (font.get_string_size(caption.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>caption.size.x-4 or font.get_height(font_size)>caption.size.y-2):
			font_size-=1
		caption.add_theme_font_size_override("font_size",font_size)
		caption.add_theme_constant_override("outline_size",maxi(1,int(size.y/70)))
		caption.add_theme_constant_override("shadow_offset_y",maxi(1,int(size.y/55)))
		set_meta("line%d_font_size"%index,font_size)
	set_meta("localized_title",Registry.game_title(locale))
	set_meta("localized_locale",locale)
	set_meta("localized_rect",rect)

func qa_summary() -> Dictionary:
	return {"locale":last_locale,"title":Registry.game_title(last_locale),"visible":is_visible_in_tree(),"rect":last_rect,"line0_font":get_meta("line0_font_size",0),"line1_font":get_meta("line1_font_size",0),"input_ignored":mouse_filter==Control.MOUSE_FILTER_IGNORE}
