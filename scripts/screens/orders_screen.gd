extends BaseScreen

const CardState = preload("res://scripts/ui/item_card_state_presenter.gd")
const ButtonSkin = preload("res://scripts/ui/gameplay_button_skin.gd")
const DISPLAY_NAMES := {
	"crop_carrot": "Cà rốt tươi",
	"crop_tomato": "Cà chua",
	"crop_pumpkin": "Bí ngô",
	"seed_carrot": "Hạt Cà rốt",
	"seed_tomato": "Hạt Cà chua",
	"seed_pumpkin": "Hạt Bí ngô",
}

var feedback := "Hoàn thành đơn hiện tại để mở đơn kế tiếp."


func build() -> void:
	set_meta("ORDERS_CORE_LOCK", "PASS")
	set_meta("orders_core_status", "ORDERS_CORE_LOCK_PASS")
	set_meta("UI_IN_PLACE_REFRESH", true)
	if find_child("ActiveOrderPanel", true, false) == null:
		_build_orders_once()
	_refresh()


func _build_orders_once() -> void:
	_add_named(UI.background("hub"), "OrdersBackground", self)
	var hud_start := get_child_count()
	UI.add_hud(self, tr("ĐƠN HÀNG"))
	var hud_names := ["OrdersLogo", "HUD_DaySeasonChip", "HUD_DaySeasonLabel", "HUD_CoinChip", "HUD_CoinValue", "HUD_EnergyChip", "HUD_EnergyValue", "HUD_DragonEnergyChip", "HUD_DragonEnergyValue"]
	for index in range(hud_names.size()): get_child(hud_start + index).name = hud_names[index]
	_add_named(UI.nine_patch(ROOT + "/UI/PANELS/large_parchment_9slice.png", Rect2(104, 101, 1072, 536)), "OrdersBoard", self)
	_add_named(UI.label(tr("BẢNG GIAO HÀNG MỖI NGÀY"), Rect2(250, 158, 780, 44), 28, Color("fff3d9"), HORIZONTAL_ALIGNMENT_CENTER), "OrdersTitle", self)
	_add_named(UI.panel(Rect2(465, 207, 350, 35), Color("fff2d7"), Color("b18044"), 9), "OrdersCountPlaque", self)
	_add_named(UI.label("", Rect2(465, 207, 350, 35), 18, Color("6b482a"), HORIZONTAL_ALIGNMENT_CENTER), "OrdersCompletedCount", self)
	_add_order_cards()
	_add_active_order_panel()
	var home := UI.title_button(tr("Về trang trại"), Rect2(25, 650, 190, 52))
	home.name = "OrdersBackToHub"
	home.get_child(0).name = "BackCaption"
	(home.get_child(0) as Label).add_theme_font_size_override("font_size", 18)
	ButtonSkin.apply(home, {"caption_node": "BackCaption", "font_size": 18, "layout_content": true})
	home.pressed.connect(ScreenRouter.back_home)
	add_child(home)
	# One clear return action; the order board keeps the focus on progression.


func _refresh() -> void:
	if find_child("ActiveOrderPanel", true, false) == null: return
	bind_top_hud()
	var count := find_child("OrdersCompletedCount", true, false) as Label
	if count != null: count.text = tr("Đã hoàn thành: %d") % int(GameState.data.get("orders_done", 0))
	_refresh_order_cards()
	_refresh_active_order()


func _add_order_cards() -> void:
	for index in range(FarmData.ORDER_DEFINITIONS.size()):
		var order: Dictionary = FarmData.ORDER_DEFINITIONS[index]
		var x := 157.0 + index * 333.0
		var card := UI.panel(Rect2(x, 248, 300, 229), Color("fff0d8"), Color("8a603a"), 18)
		_add_named(card, "OrderCard_%s" % String(order["id"]), self)
		_add_named(UI.texture_rect("res://assets/ui_mockup_application_v1/item_card_blank_v1.png", Rect2(0, 0, 300, 229), TextureRect.STRETCH_SCALE), "OrderCardArtwork", card)
		_add_named(UI.label("", Rect2(18, 6, 264, 24), 14, Color("fff2d2"), HORIZONTAL_ALIGNMENT_CENTER), "OrderStatus", card)
		var title := UI.label(tr(String(order["title"])), Rect2(15, 37, 270, 34), 22, Color("4b2c18"), HORIZONTAL_ALIGNMENT_CENTER)
		title.add_theme_font_override("font", preload("res://assets/fonts/BeVietnamPro-Bold.ttf"))
		_add_named(title, "OrderTitle", card)
		_add_named(UI.texture_rect(Assets.get_order_texture(String(order["need_item"])), Rect2(23, 76, 100, 94)), "RequiredItemArtwork", card)
		var required := UI.label("%s x%d" % [_display_name(String(order["need_item"])), int(order["need_amount"])], Rect2(127, 72, 155, 69), 19, Color("5c351d"), HORIZONTAL_ALIGNMENT_CENTER)
		required.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_add_named(required, "RequiredItemAmount", card)
		var reward := UI.label(_reward_text(order), Rect2(22, 145, 258, 65), 18, Color("49652a"), HORIZONTAL_ALIGNMENT_CENTER)
		reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_add_named(reward, "OrderReward", card)


func _refresh_order_cards() -> void:
	var active_index := posmod(int(GameState.data.get("active_order_index", 0)), FarmData.ORDER_DEFINITIONS.size())
	var completed := int(GameState.data.get("orders_done", 0))
	for index in range(FarmData.ORDER_DEFINITIONS.size()):
		var order: Dictionary = FarmData.ORDER_DEFINITIONS[index]
		var card := find_child("OrderCard_%s" % String(order["id"]), true, false) as Panel
		if card == null: continue
		var selected := index == active_index
		var style := UI.panel(Rect2(), Color("00000000"), Color("e6b043") if selected else Color("8a603a"), 18)
		card.add_theme_stylebox_override("panel", style.get_theme_stylebox("panel").duplicate())
		style.free()
		var state := card.get_node_or_null("OrderStatus") as Label
		if state != null: state.text = tr("ĐANG GIAO") if selected else (tr("ĐÃ HOÀN THÀNH") if completed > index else tr("ĐƠN KẾ TIẾP"))
		(card.get_node("OrderTitle") as Label).text = tr(String(order["title"]))
		(card.get_node("RequiredItemAmount") as Label).text = "%s x%d" % [_display_name(String(order["need_item"])), int(order["need_amount"])]
		(card.get_node("OrderReward") as Label).text = _reward_text(order)
		card.set_meta("ui_selected", selected)
		(card.get_node("OrderCardArtwork") as CanvasItem).modulate = Color.WHITE if selected or completed > index else Color(0.85, 0.80, 0.71)


func _add_active_order_panel() -> void:
	var panel := UI.panel(Rect2(149, 490, 980, 117), Color("fff6ddeb"), Color("9a6835"), 16)
	_add_named(panel, "ActiveOrderPanel", self)
	_add_named(UI.label("", Rect2(20, 8, 660, 30), 18, Color("5c351d")), "ActiveOrderDescription", panel)
	_add_named(UI.label("", Rect2(20, 41, 660, 29), 20, Color("a34b35")), "ActiveOrderInventory", panel)
	var submit := UI.art_button(tr("Giao đơn"), Rect2(704, 20, 246, 64))
	submit.name = "SubmitActiveOrder"
	submit.get_child(0).name = "SubmitCaption"
	submit.pressed.connect(_submit)
	panel.add_child(submit)
	var message := UI.label("", Rect2(20, 76, 940, 31), 16, Color("6b482a"))
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_add_named(message, "OrdersFeedback", panel)


func _refresh_active_order() -> void:
	var order := GameState.get_active_order()
	if order.is_empty(): return
	var item_id := String(order["need_item"])
	var owned := int(GameState.data.get("inventory", {}).get(item_id, 0))
	var needed := int(order["need_amount"])
	var eligibility := GameState.submit_active_order_info()
	var ready := bool(eligibility.ok)
	(find_child("ActiveOrderDescription", true, false) as Label).text = tr(String(order["desc"]))
	var inventory_label := find_child("ActiveOrderInventory", true, false) as Label
	inventory_label.text = tr("Trong kho: %d / %d %s") % [owned, needed, _display_name(item_id)]
	inventory_label.add_theme_color_override("font_color", Color("42713a") if ready else Color("a34b35"))
	var reason := tr("Giao đơn và nhận phần thưởng.") if ready else String(eligibility.reason)
	CardState.apply_action(find_child("SubmitActiveOrder", true, false) as BaseButton, ready, reason)
	ButtonSkin.apply(find_child("SubmitActiveOrder", true, false) as TextureButton, {"caption_node": "SubmitCaption", "font_size": 21, "layout_content": true, "icon_texture": Assets.get_order_texture(item_id)})
	var message := find_child("OrdersFeedback", true, false) as Label
	message.text = tr("Đã hoàn thành mục tiêu nông trại đầu tiên!") if int(GameState.data.get("orders_done", 0)) >= 3 else UILocale.translate_message(feedback)


func _submit() -> void:
	GameState.submit_active_order()
	feedback = GameState.status
	_refresh()


func _add_named(node: Node, node_name: String, parent: Node) -> void:
	node.name = node_name
	parent.add_child(node)


func _display_name(item_id: String) -> String:
	return tr(String(DISPLAY_NAMES.get(item_id, FarmData.get_inventory_name(item_id))))


func _reward_text(order: Dictionary) -> String:
	return tr("+%d xu\n%s ×%d") % [int(order["reward_coins"]), _display_name(String(order["reward_item"])), int(order["reward_amount"])]
