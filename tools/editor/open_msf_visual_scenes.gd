@tool
extends EditorScript

const VISUAL_SCENES := [
	"res://scenes/screens/04_field_select.tscn",
	"res://scenes/screens/05_field_gameplay.tscn",
	"res://scenes/screens/06_shop.tscn",
	"res://scenes/screens/07_storage.tscn",
	"res://scenes/screens/08_settings.tscn",
	"res://scenes/screens/09_animal.tscn",
	"res://scenes/screens/10_dragon.tscn",
]


func _run() -> void:
	var editor := get_editor_interface()
	for scene_path in VISUAL_SCENES:
		editor.open_scene_from_path(scene_path)
	print("Opened all seven My Sister's Farm visual scenes.")
