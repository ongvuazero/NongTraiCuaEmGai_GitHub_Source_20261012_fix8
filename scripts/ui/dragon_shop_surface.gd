extends Control

# Native content-only view; never instantiates the Main Shop BaseScreen.
signal closed
signal hatchery_requested
const VIEW = preload("res://scenes/ui/shared_shop_view.tscn")
const UI = preload("res://scripts/ui_factory.gd")
const Content = preload("res://scripts/ui/shared_shop_content.gd")
const ButtonSkin = preload("res://scripts/ui/gameplay_button_skin.gd")
var view: Control
var shop_content


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 30
	view = VIEW.instantiate() as Control
	view.name = "DragonShopBoard"
	view.position = Vector2(262, 98)
	view.scale = Vector2(0.78, 0.78)
	add_child(view)
	for name in ["Tab_Seeds", "Tab_Expansion"]:
		(view.find_child(name, true, false) as Control).hide()
	(view.find_child("Tab_Food", true, false) as Control).position = Vector2(90, 205)
	(view.find_child("Tab_Food", true, false) as Control).size = Vector2(210, 50)
	(view.find_child("Tab_Medicine", true, false) as Control).position = Vector2(316, 205)
	(view.find_child("Tab_Medicine", true, false) as Control).size = Vector2(210, 50)
	var hatchery := view.find_child("Tab_Rare", true, false) as TextureButton
	hatchery.name = "DragonShopHatchery"
	hatchery.position = Vector2(542, 205)
	hatchery.size = Vector2(300, 50)
	hatchery.pressed.connect(func() -> void: hatchery_requested.emit())
	ButtonSkin.apply(hatchery, {"caption": tr("Lò ấp trứng"), "font_size": 18, "layout_content": true})
	var dismiss := view.find_child("ShopBackToHub", true, false) as TextureButton
	dismiss.name = "DragonShopDismiss"
	dismiss.pressed.connect(func() -> void: closed.emit())
	ButtonSkin.apply(dismiss, {"caption": tr("Đóng"), "font_size": 18, "layout_content": true})
	var close := UI.title_button("×",Rect2(1164,140,42,42))
	close.name = "DragonShopClose"
	close.tooltip_text = tr("Đóng")
	(close.get_child(0) as Label).add_theme_font_size_override("font_size",28)
	close.pressed.connect(func() -> void: closed.emit())
	view.add_child(close)
	shop_content = Content.new()
	shop_content.name = "SharedShopContent"
	view.add_child(shop_content)
	shop_content.presentation_changed.connect(_sync_presentation_fonts)
	shop_content.attach_surface(view, "dragon")
	set_meta("visual_review", "REQUIRED")
	visibility_changed.connect(_request_mobile_layout)


func refresh_surface() -> void:
	if shop_content == null: return
	shop_content._refresh_in_place()
	var hatchery := view.find_child("DragonShopHatchery", true, false) as TextureButton
	ButtonSkin.apply(hatchery, {"caption": tr("Lò ấp trứng"), "font_size": 18, "layout_content": true})
	var dismiss := view.find_child("DragonShopDismiss", true, false) as TextureButton
	ButtonSkin.apply(dismiss, {"caption": tr("Đóng"), "font_size": 18, "layout_content": true})
	var close := view.find_child("DragonShopClose", true, false) as BaseButton
	close.tooltip_text = tr("Đóng")
	_sync_presentation_fonts()


func _sync_presentation_fonts() -> void:
	# The old blanket floor enlarged narrow value columns without reflowing
	# them. The shared controller now measures each safe content rectangle.
	LocaleFonts.apply_to_tree(view)
	if shop_content != null: shop_content.layout_presentation_copy()
	_request_mobile_layout()

func _request_mobile_layout() -> void:
	if is_instance_valid(view) and is_visible_in_tree(): preload("res://scripts/ui/mobile_runtime.gd").request_control_layout(view)
