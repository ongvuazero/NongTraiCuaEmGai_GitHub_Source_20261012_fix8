@tool
extends TextureRect

const FarmNav = preload("res://scripts/ui/farm_navigation_presenter.gd")


func _ready() -> void:
	FarmNav.style_logo(self)
