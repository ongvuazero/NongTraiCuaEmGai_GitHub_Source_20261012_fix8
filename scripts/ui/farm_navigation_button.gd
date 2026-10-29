@tool
extends TextureButton

const FarmNav = preload("res://scripts/ui/farm_navigation_presenter.gd")

@export var icon_id := "field":
	set(value):
		icon_id = value
		if is_inside_tree(): _present()
@export var caption_source := "":
	set(value):
		caption_source = value
		if is_inside_tree(): _present()
@export var caption_font_size := 18:
	set(value):
		caption_font_size = value
		if is_inside_tree(): _present()


func _ready() -> void:
	_present()


func _present() -> void:
	var caption := get_node_or_null("Caption") as Label
	var text := caption_source if not caption_source.is_empty() else (caption.text if caption != null else "")
	FarmNav.style_button(self, icon_id, text, caption_font_size)
