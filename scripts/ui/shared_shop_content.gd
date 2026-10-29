extends Control

# One content controller binds authored controls. It owns no HUD, save menu,
# GameState signal or screen route lifecycle.
signal presentation_changed
const UI = preload("res://scripts/ui_factory.gd")
const Assets = preload("res://scripts/ui_asset_registry.gd")
const FarmData = preload("res://scripts/farm_data.gd")
const WorldRules = preload("res://scripts/world_systems.gd")
const Catalog = preload("res://scripts/ui/shop_catalog_adapter.gd")
var surface_root: Node
var catalog
var context := "main"

const CardState = preload("res://scripts/ui/item_card_state_presenter.gd")
const ButtonSkin = preload("res://scripts/ui/gameplay_button_skin.gd")
const PAGE_SIZE := 5
const CATEGORY_NAMES := {"seeds": "Hạt giống", "food": "Thực phẩm", "medicine": "Thuốc", "expansion": "Mở rộng", "rare": "Hiếm"}
const CATEGORY_TABS := [["Tab_Seeds", "seeds"], ["Tab_Food", "food"], ["Tab_Medicine", "medicine"], ["Tab_Expansion", "expansion"], ["Tab_Rare", "rare"]]

const VISIBLE_SHOP_IDS := ["seed_carrot", "seed_tomato", "seed_pumpkin", "animal_feed", "medicine"]
const DISPLAY_NAMES := {
	"seed_carrot": "Hạt Cà rốt", "seed_tomato": "Hạt Cà chua", "seed_pumpkin": "Hạt Bí ngô",
	"animal_feed": "Cloud Chicken Feed", "medicine": "Energy Tonic",
}
const DESCRIPTIONS := {
	"seed_carrot": "Hạt giống khỏe cho vụ mùa cà rốt mới.",
	"seed_tomato": "Hạt giống cà chua, phù hợp vụ mùa đều đặn.",
	"seed_pumpkin": "Hạt bí ngô cho vụ mùa dài và giá trị cao.",
	"animal_feed": "Compatible food for Cloud Chicken only. Other species need their own food.",
	"medicine": "Restores 25 farm energy when used from Storage. Does not cure creature disease.",
}
var selected_product := "seed_carrot"
var active_category := "seeds"
var feedback := "Chọn hạt giống để bắt đầu vụ mùa mới."
var page_index := 0


func attach_surface(root: Node, scope := "main") -> void:
	surface_root = root
	context = scope
	catalog = Catalog.new(scope)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if context == "dragon":
		active_category = "food"
		var products: Array = _category_shop_items()
		selected_product = String(products[0]["id"]) if not products.is_empty() else ""
		feedback = "Thức ăn và thuốc khác nhau theo loài."
	for definition in CATEGORY_TABS:
		var tab := _find(String(definition[0])) as BaseButton
		if tab != null:
			tab.disabled = false
			var callback := _set_category.bind(definition[1])
			if not tab.pressed.is_connected(callback): tab.pressed.connect(callback)
	var buy := _find("BuySelectedProduct") as BaseButton
	if buy != null and not buy.pressed.is_connected(_buy_selected): buy.pressed.connect(_buy_selected)
	_bind_page_controls()
	_refresh_in_place()


func _find(node_name: String) -> Node:
	return surface_root.find_child(node_name, true, false) if is_instance_valid(surface_root) else null

func _refresh() -> void:
	_refresh_in_place()


func _refresh_in_place() -> void:
	if not is_inside_tree():
		return
	_refresh_product_visibility()
	_refresh_tab_states()
	_refresh_product_cards()
	_update_shop_detail()
	_update_page_controls()
	_update_feedback()
	for node in surface_root.find_children("*", "Label", true, false):
		var label := node as Label
		if label.name == "ShopCoinSummary" or label.text.begins_with("Xu:") or label.text.begins_with("Coins:"):
			label.name = "ShopCoinSummary"
			label.text = tr("Xu: %d") % int(GameState.data.get("coins", 0))
	var title := _find("ShopTitle") as Label
	if title != null: title.text = tr("Shop Rồng").to_upper() if context == "dragon" else tr("CỬA HÀNG")
	var heading := _find("DetailHeading") as Label
	if heading != null: heading.text = tr("CHI TIẾT SẢN PHẨM")
	LocaleFonts.apply_to_tree(surface_root)
	layout_presentation_copy()
	presentation_changed.emit()


func _set_category(value: String) -> void:
	if not CATEGORY_NAMES.has(value) or (context == "dragon" and value not in ["food", "medicine"]): return
	active_category = value
	page_index = 0
	var products := _category_shop_items()
	if not products.is_empty(): selected_product = String(products[0]["id"])
	feedback = tr("Đã chọn nhóm sản phẩm: %s.") % tr(String(CATEGORY_NAMES[value]))
	_refresh_in_place()


func _refresh_product_visibility() -> void:
	var items := _visible_shop_items()
	for index in range(PAGE_SIZE):
		var slot := _find("ProductSlot%02d" % (index + 1)) as Control
		if slot == null: continue
		slot.visible = index < items.size()
	for index in range(6, 9):
		var unused := _find("ProductSlot%02d" % index) as Control
		if unused != null: unused.visible = false


func _select_product(item_id: String) -> void:
	if _shop_item(item_id).is_empty(): return
	var products := _category_shop_items()
	var index := -1
	for current in range(products.size()):
		if String(products[current]["id"]) == item_id: index = current
	if index < 0: return
	page_index = int(index / PAGE_SIZE)
	selected_product = item_id
	feedback = _locked_seed_message(item_id) if _is_seed_locked(item_id) else tr("Đang xem %s.") % _display_name(item_id)
	_refresh_in_place()


func _buy_selected() -> void:
	_buy(selected_product)


func _update_shop_detail() -> void:
	var item := _shop_item(selected_product)
	if item.is_empty(): return
	var panel := _find("ProductDetailPanel")
	if panel == null: return
	var artwork := panel.find_child("ProductArtwork", true, false) as TextureRect
	var name_label := panel.find_child("ProductNameLabel", true, false) as Label
	var quantity := panel.find_child("QuantityValue", true, false) as Label
	var price := panel.find_child("PriceValue", true, false) as Label
	var description := panel.find_child("ProductDescriptionLabel", true, false) as Label
	var buy := panel.find_child("BuySelectedProduct", true, false) as BaseButton
	var info := _purchase_info(item)
	_set_product_art(panel, artwork, selected_product, true)
	if name_label != null:
		name_label.text = _display_name(selected_product)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.tooltip_text = _display_name(selected_product)
	var kind := String(item.get("kind", "core"))
	var quantity_caption := panel.find_child("QuantityCaption", true, false) as Label
	var price_caption := panel.find_child("PriceCaption", true, false) as Label
	if quantity_caption != null: quantity_caption.text = tr("Level") if kind == "building" else tr("Số lượng")
	if quantity != null:
		quantity.text = "%d/%d" % [_building_level(selected_product), int(item.get("max_level", 1))] if kind == "building" else "x%d · %s" % [int(item.get("amount", 1)), tr("Owned: %d") % _owned(selected_product)]
		quantity.tooltip_text = quantity.text
	var dragon_cost := int(item.get("energy_cost", 0))
	if price_caption != null: price_caption.text = tr("Coins + DE") if dragon_cost > 0 else tr("Giá mua")
	if price != null:
		price.text = tr("Max") if _building_maxed(item) else tr("Not for sale") if int(item.get("price", 0)) <= 0 and kind == "world_item" else "%d + %d" % [int(item.get("price", 0)), dragon_cost] if dragon_cost > 0 else tr("%d xu") % int(item.get("price", 0))
		price.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		price.tooltip_text = _price_text(item)
	if description != null:
		description.text = String(info["reason"]) if not bool(info["ok"]) else _product_description(item)
		description.tooltip_text = _product_description(item) + "\n" + String(info["reason"])
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.max_lines_visible = 2
	if buy != null:
		CardState.apply_action(buy, bool(info["ok"]), String(info["reason"]))
		var caption := buy.get_node_or_null("Caption") as Label
		if caption != null: caption.text = tr("Build / upgrade") if kind == "building" else tr("MUA NGAY")
		if buy is TextureButton:
			ButtonSkin.apply(buy as TextureButton, {"font_size": 20, "layout_content": true, "icon_texture": Assets.get_item_texture(selected_product) if Assets.ITEM_ICONS.has(selected_product) else null})


func _update_feedback() -> void:
	var label := _find("FeedbackLabel") as Label
	if label != null:
		label.text = UILocale.pair("Thức ăn và thuốc khác nhau theo loài.","Food and remedies differ by species.") if context=="dragon" and feedback=="Thức ăn và thuốc khác nhau theo loài." else UILocale.translate_message(feedback)
		label.tooltip_text = label.text
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _show_navigation_day_result(_succeeded: bool, message: String) -> void:
	feedback = message
	_refresh_in_place()


func _visible_shop_items() -> Array:
	var items := _category_shop_items()
	page_index = clampi(page_index, 0, maxi(0, int(ceil(float(items.size()) / PAGE_SIZE)) - 1))
	return items.slice(page_index * PAGE_SIZE, (page_index + 1) * PAGE_SIZE)


func _category_shop_items() -> Array:
	return catalog.items(active_category) if catalog != null else []

func _buy(item_id: String) -> void:
	var item := _shop_item(item_id)
	if item.is_empty(): return
	var info := _purchase_info(item)
	if not bool(info["ok"]):
		feedback = String(info["reason"])
		_refresh_in_place()
		return
	var kind := String(item.get("kind", "core"))
	var succeeded := GameState.buy(item_id) if kind == "core" else GameState.world_action(_world_action(item), item_id)
	if succeeded and kind == "core":
		feedback = tr("Đã mua %s x%d · còn %d xu") % [_display_name(item_id), int(item["amount"]), int(GameState.data.get("coins", 0))]
	else:
		feedback = UILocale.translate_message(GameState.status)
	_refresh_in_place()


func _refresh_tab_states() -> void:
	for definition in CATEGORY_TABS:
		var tab := _find(definition[0]) as BaseButton
		var selected: bool = active_category == definition[1]
		CardState.apply_tab(tab, selected, true, tr("Lọc theo %s") % tr(String(CATEGORY_NAMES[definition[1]])))
		if tab is TextureButton:
			var texture_tab := tab as TextureButton
			var icon_id: String = {"seeds": "seed_carrot", "food": "animal_feed", "medicine": "medicine", "expansion": "barn", "rare": "water_egg"}[definition[1]]
			ButtonSkin.apply(texture_tab, {"selected": selected, "caption": tr(String(CATEGORY_NAMES[definition[1]])), "font_size": 16, "layout_content": true, "icon_texture": Assets.get_item_texture(icon_id)})
			var old_check := texture_tab.get_node_or_null("UISelectedCheck") as Label
			if old_check != null: old_check.visible = false


func _refresh_product_cards() -> void:
	var items := _visible_shop_items()
	for index in range(PAGE_SIZE):
		var slot := _find("ProductSlot%02d" % (index + 1)) as Control
		if slot == null: continue
		var selectors := slot.find_children("SelectProduct_*", "BaseButton", true, false)
		if selectors.is_empty(): selectors = slot.find_children("UnusedProductSelector_*", "BaseButton", true, false)
		if index >= items.size():
			if not selectors.is_empty(): selectors[0].name = "UnusedProductSelector_%02d" % (index + 1)
			continue
		var item: Dictionary = items[index]
		var item_id := String(item.get("id", ""))
		if not selectors.is_empty():
			var selector := selectors[0] as BaseButton
			var previous_callback: Callable = selector.get_meta("shop_selection_callback", Callable())
			if previous_callback.is_valid() and selector.pressed.is_connected(previous_callback):
				selector.pressed.disconnect(previous_callback)
			selector.name = "SelectProduct_%s" % item_id
			var callback := _select_product.bind(item_id)
			selector.pressed.connect(callback)
			selector.set_meta("shop_selection_callback", callback)
			selector.disabled = false
		slot.set_meta("shop_product_id", item_id)
		var artwork := slot.get_node_or_null("ProductArtwork") as TextureRect
		var name_label := slot.get_node_or_null("ProductNameLabel") as Label
		var offer_label := slot.get_node_or_null("OfferLabel") as Label
		var info := _purchase_info(item)
		var locked := _progression_locked(item)
		_set_product_art(slot, artwork, item_id)
		if name_label != null:
			name_label.text = _card_name(item_id)
			name_label.tooltip_text = _display_name(item_id)
			name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			name_label.max_lines_visible = 2
			name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if offer_label != null:
			# The clean card art carries no baked numbers or coin artwork.
			offer_label.text = tr("Max") if _building_maxed(item) else tr("Not for sale") if int(item.get("price", 0)) <= 0 and String(item.get("kind", "")) == "world_item" else "%s · ×%d" % [tr("%d xu") % int(item.get("price", 0)), int(item.get("amount", 1))]
			offer_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			offer_label.tooltip_text = _price_text(item)
			if context == "dragon":
				# A native currency icon leaves room for every digit and bundle
				# amount; translated currency words remain in the full tooltip.
				offer_label.text = "%d · ×%d" % [int(item.get("price", 0)), int(item.get("amount", 1))]
				var currency := slot.get_node_or_null("OfferCurrencyIcon") as TextureRect
				if currency == null:
					currency = UI.texture_rect(Assets.ROOT + "/ITEMS/coin.png", Rect2(8, 149, 24, 24))
					currency.name = "OfferCurrencyIcon"
					slot.add_child(currency)
		var tooltip := tr("Chọn %s") % _display_name(item_id)
		if not bool(info["ok"]): tooltip += "\n" + String(info["reason"])
		CardState.apply_card(slot, selected_product == item_id, locked, not bool(info["ok"]) and not locked, tooltip)
		_style_selected_card(slot)
		var lock_badge := slot.get_node_or_null("UIStateLockBadge") as Label
		if lock_badge != null and locked:
			# Short progression requirements remain visible on the card itself.
			var required := int(item.get("orders", 0))
			if item_id == "seed_tomato": required = 1
			elif item_id == "seed_pumpkin": required = 2
			lock_badge.text = tr("Max") if _building_maxed(item) else "%s %d" % [tr("ĐƠN HÀNG"), required] if required > int(GameState.data.get("orders_done", 0)) else tr("KHÓA")
			lock_badge.position = Vector2(slot.size.x - 98.0, 5.0)
			lock_badge.size = Vector2(92.0, 28.0)
			lock_badge.add_theme_font_size_override("font_size", 13)


func _fit_copy(label: Label, bounds: Rect2, point_size: int, minimum: int, wrap := true) -> void:
	if label == null: return
	label.add_theme_font_override("font", LocaleFonts.for_text(label.text, label.get_theme_font("font")))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	label.max_lines_visible = -1
	label.clip_text = true
	label.add_theme_font_size_override("font_size", point_size)
	label.position = bounds.position
	label.size = bounds.size
	while point_size > minimum:
		var too_wide := not wrap and label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size).x > bounds.size.x
		if not too_wide and label.get_minimum_size().y <= bounds.size.y: break
		point_size -= 1
		label.add_theme_font_size_override("font_size", point_size)
		label.size = bounds.size
	label.set_meta("shop_copy_safe_rect", bounds)
	label.set_meta("shop_copy_complete", label.get_minimum_size().y <= bounds.size.y)


func layout_presentation_copy() -> void:
	# Dragon Shop uses the same painted board scaled to .78. Keep its native
	# type >=18 (14 screen px), and reflow content rather than truncate values.
	if context != "dragon": return
	for index in range(PAGE_SIZE):
		var slot := _find("ProductSlot%02d" % (index + 1)) as Control
		if slot == null or not slot.visible: continue
		var name := slot.get_node_or_null("ProductNameLabel") as Label
		_fit_copy(name, Rect2(8, 98, 152, 48), 18, 18)
		var lines := maxi(name.get_line_count(),1)
		var shaped := float(name.get_line_height())*lines+float(name.get_theme_constant("line_spacing"))*maxi(lines-1,0)
		var height := maxf(48, maxf(name.get_minimum_size().y,shaped+4.0))
		_fit_copy(name, Rect2(8, 146 - height, 152, height), 18, 18)
		var art := slot.get_node_or_null("ProductArtwork") as TextureRect
		if art != null:
			art.position = Vector2(24, 9)
			art.size = Vector2(120, maxf(32, name.position.y - 13))
		var offer := slot.get_node_or_null("OfferLabel") as Label
		_fit_copy(offer, Rect2(33, 146, 125, 30), 18, 18, false)
	var panel := _find("ProductDetailPanel") as Control
	if panel == null: return
	_fit_copy(panel.find_child("DetailHeading", true, false) as Label, Rect2(12, 8, 317, 31), 18, 18)
	_fit_copy(panel.find_child("ProductNameLabel", true, false) as Label, Rect2(15, 40, 311, 60), 22, 18)
	var art := panel.find_child("ProductArtwork", true, false) as TextureRect
	if art != null:
		art.position = Vector2(60, 104)
		art.size = Vector2(221, 98)
	var facts := panel.find_child("ProductFacts", true, false) as Control
	facts.position = Vector2(18, 206)
	facts.size = Vector2(305, 150)
	_fit_copy(panel.find_child("QuantityCaption", true, false) as Label, Rect2(12, 2, 281, 28), 18, 18, false)
	_fit_copy(panel.find_child("QuantityValue", true, false) as Label, Rect2(12, 32, 281, 29), 18, 18, false)
	_fit_copy(panel.find_child("PriceCaption", true, false) as Label, Rect2(12, 63, 115, 30), 18, 18)
	_fit_copy(panel.find_child("PriceValue", true, false) as Label, Rect2(132, 63, 161, 30), 18, 18, false)
	var description := panel.find_child("ProductDescriptionLabel", true, false) as Label
	var scroll := facts.get_node_or_null("ProductDescriptionScroll") as ScrollContainer
	if scroll == null:
		scroll = ScrollContainer.new()
		scroll.name = "ProductDescriptionScroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		facts.add_child(scroll)
		description.reparent(scroll)
		var bar := scroll.get_v_scroll_bar()
		bar.custom_minimum_size.x = 9
		var track := StyleBoxFlat.new()
		track.bg_color = Color("b0874b44")
		track.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("scroll", track)
		var grip := track.duplicate() as StyleBoxFlat
		grip.bg_color = Color("a36d35")
		bar.add_theme_stylebox_override("grabber", grip)
		bar.add_theme_stylebox_override("grabber_highlight", grip)
		bar.add_theme_stylebox_override("grabber_pressed", grip)
	scroll.position = Vector2(12, 95)
	scroll.size = Vector2(281, 51)
	description.add_theme_font_override("font", LocaleFonts.for_text(description.text, LocaleFonts.regular()))
	description.add_theme_font_size_override("font_size", 18)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.max_lines_visible = -1
	description.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	description.clip_text = false
	description.custom_minimum_size = Vector2(265, 0)
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.size_flags_vertical = Control.SIZE_FILL
	_fit_copy(_find("ShopTitle") as Label, Rect2(146, 139, 251, 40), 24, 18, false)
	_fit_copy(_find("FeedbackLabel") as Label, Rect2(10, 3, 730, 39), 18, 18)


func _shop_item(item_id: String) -> Dictionary:
	return catalog.item(item_id) if catalog != null else {}

func _style_selected_card(card: Control) -> void:
	var frame := card.get_node_or_null("UIStateFrame") as Panel
	if frame == null: return
	var style := frame.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if style == null: return
	# StyleBoxFlat shadows fill behind the entire rectangle even when its
	# background is transparent. Selection must outline, never wash over text.
	style.bg_color = Color(0, 0, 0, 0)
	style.shadow_color = Color(0, 0, 0, 0)
	style.shadow_size = 0
	frame.add_theme_stylebox_override("panel", style)


func _is_seed_locked(item_id: String) -> bool:
	return item_id in ["seed_carrot", "seed_tomato", "seed_pumpkin"] and not GameState.is_crop_unlocked(item_id.trim_prefix("seed_"))


func _progression_locked(item: Dictionary) -> bool:
	# Lock badges describe unmet progression gates, not money, energy or space.
	if item.get("kind", "core") == "core": return _is_seed_locked(String(item.get("id", "")))
	if int(GameState.data.get("orders_done", 0)) < int(item.get("orders", 0)): return true
	var world := GameState.world_state()
	if not bool(world.get("unlocked_islands", {}).get(String(item.get("island", "main")), false)): return true
	var building := String(item.get("building", ""))
	if not building.is_empty() and int(world.get("buildings", {}).get(building, 0)) <= 0: return true
	return _building_maxed(item)


func _locked_seed_message(item_id: String) -> String:
	match item_id:
		"seed_tomato": return tr("Hoàn thành Đơn đầu tiên để mở khóa.")
		"seed_pumpkin": return tr("Hoàn thành Vụ mùa mới để mở khóa.")
	return ""


func _display_name(item_id: String) -> String:
	var item := _shop_item(item_id)
	return tr(String(DISPLAY_NAMES.get(item_id, item.get("name", item_id))))


func _card_name(item_id: String) -> String:
	return _display_name(item_id)


func _building_level(id: String) -> int:
	return int(GameState.world_state().get("buildings", {}).get(id, 0))


func _building_maxed(item: Dictionary) -> bool:
	return item.get("kind", "") == "building" and _building_level(String(item["id"])) >= int(item.get("max_level", 1))


func _world_action(item: Dictionary) -> String:
	return "build" if item.get("kind", "") == "building" else "buy_egg" if item.get("kind", "") == "egg" else "buy_item"


func _purchase_info(item: Dictionary) -> Dictionary:
	var id := String(item.get("id", ""))
	if item.get("kind", "core") != "core":
		var info := GameState.world_action_info(_world_action(item), id)
		info["reason"] = UILocale.translate_message(String(info.get("reason", "")))
		return info
	if _is_seed_locked(id): return {"ok": false, "reason": _locked_seed_message(id)}
	if int(GameState.data.get("coins", 0)) < int(item.get("price", 0)): return {"ok": false, "reason": tr("Không đủ xu")}
	var stacks := WorldRules.inventory_stacks(GameState.data)
	var capacity := WorldRules.inventory_capacity(GameState.data)
	var new_stack := int(GameState.data.get("inventory", {}).get(id, 0)) <= 0 and int(item.get("amount", 1)) > 0
	# Existing over-capacity saves may keep buying an existing type; only adding
	# a genuinely new positive stack is denied, matching _save_core_action.
	if new_stack and stacks + 1 > maxi(capacity, stacks):
		return {"ok": false, "reason": UILocale.translate_message("Storage is full (%d item stacks). Build a Warehouse upgrade or use/sell an item first." % capacity)}
	return {"ok": true, "reason": tr("Mua %s") % _display_name(id)}


func _owned(id: String) -> int:
	return GameState.dragon_energy() if id == "dragon_energy" else int(GameState.data.get("inventory", {}).get(id, 0))


func _price_text(item: Dictionary) -> String:
	if _building_maxed(item): return tr("Fully upgraded")
	if int(item.get("price", 0)) <= 0 and item.get("kind", "") == "world_item": return tr("Not for sale. Earn this through gameplay.")
	return tr("%d coins + %d Dragon Energy · Owned: %d") % [int(item.get("price", 0)), int(item.get("energy_cost", 0)), _owned(String(item["id"]))]


func _product_description(item: Dictionary) -> String:
	var id := String(item["id"])
	if DESCRIPTIONS.has(id): return tr(String(DESCRIPTIONS[id]))
	if item.get("kind", "") == "building": return tr(String(item.get("effect", "")))
	if item.get("kind", "") == "egg":
		var species: Dictionary = GameState.world_config().get("creatures", {}).get(String(item.get("species", "")), {})
		return tr("Hatches %s in %d days. Incubate after purchase on Dragon Island.") % [tr(String(species.get("name", ""))), int(item.get("days", 1))]
	if item.has("cures"): return tr("Cures %s. Not an energy refill.") % tr(String(item["cures"]).capitalize())
	var eaters: PackedStringArray = []
	for creature in GameState.world_config().get("creatures", {}).values():
		if String(creature.get("food", "")) == id: eaters.append(tr(String(creature.get("name", ""))))
	if not eaters.is_empty(): return tr("Species food: %s only.") % ", ".join(eaters)
	var description := String(item.get("description", ""))
	if not description.is_empty(): return tr(description)
	if String(item.get("group", "")) == "Herb Seed":
		return UILocale.pair("Trồng tại Vườn dược liệu, không phải 12 ô Ruộng.", "Plant in the Medicinal Garden, separate from the 12 farm plots.")
	if int(item.get("price", 0)) > 0:
		return UILocale.pair("Mua cho nông trại; xem cách dùng trong Kho.", "Buy for your farm; check Storage for its available uses.")
	return tr("Not for sale. Earn this through gameplay.")


func _set_product_art(parent: Node, artwork: TextureRect, id: String, detail := false) -> void:
	if artwork == null: return
	# Never call the registry's unknown-ID medicine fallback.
	var has_icon := Assets.ITEM_ICONS.has(id)
	artwork.texture = Assets.get_item_texture(id) if has_icon else null
	artwork.visible = has_icon
	var missing := parent.get_node_or_null("ArtworkUnavailable") as Label
	if missing == null:
		missing = UI.label("", Rect2(artwork.position, artwork.size), 15 if detail else 14, Color("604b36"), HORIZONTAL_ALIGNMENT_CENTER)
		missing.name = "ArtworkUnavailable"
		missing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		missing.max_lines_visible = 6 if detail else 3
		parent.add_child(missing)
	missing.visible = not has_icon
	missing.text = tr("Text only\nNo approved icon")
	if detail and not has_icon:
		var item := _shop_item(id)
		var info := _purchase_info(item)
		if item.get("kind", "") == "building":
			var materials: PackedStringArray = []
			for material in item.get("items", {}):
				materials.append(tr("%s %d/%d") % [_display_name(String(material)), _owned(String(material)), int(item["items"][material])])
			missing.text += "\n" + tr("Orders required: %d") % int(item.get("orders", 0))
			missing.text += "\n" + tr("Materials: %s") % (", ".join(materials) if not materials.is_empty() else tr("None"))
		else:
			missing.text += "\n" + tr("Owned: %d") % _owned(id)
			if item.get("kind", "") == "egg": missing.text += "\n" + tr("Hatch time: %d days") % int(item.get("days", 1))
		missing.tooltip_text = missing.text + "\n" + String(info["reason"])


func _bind_page_controls() -> void:
	# Pagination belongs to 06_shop.tscn. Bind behavior without re-authoring
	# positions so editor changes remain the runtime baseline after refresh.
	var pager := _find("ShopPagination") as Control
	if pager == null: return
	for definition in [["ShopPreviousPage", -1], ["ShopNextPage", 1]]:
		var button := pager.get_node_or_null(String(definition[0])) as BaseButton
		if button == null: continue
		var callback := _change_page.bind(int(definition[1]))
		if not button.pressed.is_connected(callback): button.pressed.connect(callback)


func _change_page(delta: int) -> void:
	var items := _category_shop_items()
	var pages := maxi(1, int(ceil(float(items.size()) / PAGE_SIZE)))
	page_index = clampi(page_index + delta, 0, pages - 1)
	if not items.is_empty(): selected_product = String(items[page_index * PAGE_SIZE]["id"])
	feedback = tr("Page %d / %d") % [page_index + 1, pages]
	_refresh_in_place()


func _update_page_controls() -> void:
	var pager := _find("ShopPagination") as Control
	if pager == null: return
	var pages := maxi(1, int(ceil(float(_category_shop_items().size()) / PAGE_SIZE)))
	pager.visible = pages > 1
	(pager.get_node("ShopPageLabel") as Label).text = tr("Page %d / %d") % [page_index + 1, pages]
	var previous := pager.get_node("ShopPreviousPage") as BaseButton
	var next := pager.get_node("ShopNextPage") as BaseButton
	CardState.apply_action(previous, page_index > 0, tr("Previous page"))
	CardState.apply_action(next, page_index + 1 < pages, tr("Next page"))
	(previous.get_child(0) as Label).text = tr("Previous")
	(next.get_child(0) as Label).text = tr("Next")
	ButtonSkin.apply(previous as TextureButton, {"font_size": 18, "layout_content": true})
	ButtonSkin.apply(next as TextureButton, {"font_size": 18, "layout_content": true})
