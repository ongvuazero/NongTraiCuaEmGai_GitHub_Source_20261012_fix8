extends RefCounted

# Ink on cream action cards; moon/night remains cream text on blue.
# Only local text style changes. Authored bounds, input and actions stay intact.
const FONT = preload("res://assets/fonts/BeVietnamPro-SemiBold.ttf")
const ACTIONS := ["till","seed","water","fertilize","harvest","advance_day"]

static func apply(screen: Control) -> void:
	for action in ACTIONS:
		var button := screen.find_child("Action_"+action,true,false)
		if button == null: continue
		var label := button.get_node_or_null("Caption") as Label
		if label == null: continue
		# ToolbarResponse draws its selected-card tint at z=6. Keep the ink
		# above that card so the selected tool is just as readable as idle.
		label.z_index = 7
		label.add_theme_font_override("font",FONT)
		label.add_theme_font_size_override("font_size",17)
		label.add_theme_color_override("font_color",Color("fff2d9") if action=="advance_day" else Color("4b2e19"))
		label.add_theme_color_override("font_outline_color",Color("4b2e19") if action=="advance_day" else Color("fff2d9"))
		label.add_theme_constant_override("outline_size",2 if action=="advance_day" else 0)
		label.set_meta("readable_field_action_caption",true)
