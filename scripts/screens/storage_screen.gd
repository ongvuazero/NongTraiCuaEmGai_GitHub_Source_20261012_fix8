extends BaseScreen

const GameSkin = preload("res://scripts/ui/gameplay_button_skin.gd")

const CardState = preload("res://scripts/ui/item_card_state_presenter.gd")
const WorldRules = preload("res://scripts/world_systems.gd")
const ItemSource = preload("res://scripts/ui/item_source_presenter.gd")
const PAGE_SIZE := 10
const CATEGORY_IDS := ["All", "Seeds", "Crops", "Food", "Medicine", "Eggs", "Materials", "Other"]
const CATEGORY_LABELS := {
	"All": "Tất cả", "Seeds": "Hạt giống", "Crops": "Nông sản",
	"Food": "Food", "Medicine": "Thuốc", "Eggs": "Eggs", "Materials": "Vật liệu", "Other": "Hiếm / khác",
}
const DISPLAY_NAMES := {
	"seed_carrot": "Hạt Cà rốt", "seed_tomato": "Hạt Cà chua", "seed_pumpkin": "Hạt Bí ngô",
	"crop_carrot": "Cà rốt tươi", "crop_tomato": "Cà chua", "crop_pumpkin": "Bí ngô",
	"animal_feed": "Cloud Chicken Feed", "medicine": "Energy Tonic", "egg": "Trứng gà", "dragon_treat": "Bánh Rồng",
}
var category := "All"
var selected_item := "seed_carrot"
var feedback := "Chọn một nhóm vật phẩm để xem kho."
var page_index := 0
var _definitions: Dictionary = {}
var _discard_item := ""
var _discard_amount := 0


func build() -> void:
	bind_top_hud()
	set_meta("SHOP_STORAGE_CORE_LOCK", "FUNCTIONAL_TEST_REQUIRED")
	set_meta("TRUE_WYSIWYG_V2", "VISUAL_REVIEW_REQUIRED")
	# Storage uses the authored full board. The Close action returns to Home.
	bind_button("StorageBackToHub", ScreenRouter.back_home)
	bind_button("StorageSellSelected", _sell_selected)
	bind_button("StorageUseSelected", _use_selected)
	bind_button("StorageClose", ScreenRouter.back_home)
	bind_button("StoragePreviousPage", _change_page.bind(-1))
	bind_button("StorageNextPage", _change_page.bind(1))
	for id in CATEGORY_IDS:
		bind_button("StorageCategory_%s" % id, _set_category.bind(id))
	for index in range(PAGE_SIZE):
		var slot := get_node("MainContent/ItemGrid_5x3/ItemSlot%02d" % (index + 1))
		var buttons := slot.find_children("Select*", "Button", true, false)
		if not buttons.is_empty():
			var callback := _select_slot.bind(index)
			if not (buttons[0] as BaseButton).pressed.is_connected(callback):
				(buttons[0] as BaseButton).pressed.connect(callback)
	_refresh_in_place()


func _refresh() -> void:
	_refresh_in_place()


func _refresh_in_place() -> void:
	if not is_inside_tree(): return
	bind_top_hud()
	_refresh_category_tabs()
	_update_storage_slots()
	_update_storage_detail()
	_refresh_storage_actions()
	_update_page_controls()
	_update_feedback()
	var capacity_label := find_child("StorageCapacityValue", true, false) as Label
	if capacity_label != null:
		var stacks := WorldRules.inventory_stacks(GameState.data)
		var capacity := WorldRules.inventory_capacity(GameState.data)
		capacity_label.text = "%d / %d" % [stacks, capacity]
		capacity_label.tooltip_text = tr("Storage: %d / %d item types. All categories share this capacity.") % [stacks, capacity]


# This is a view of the existing inventory and registries, never another store.
# Registry order keeps the ten familiar farm items on the first All page.
func _config() -> Dictionary:
	if _definitions.is_empty(): _definitions = GameState.world_config()
	return _definitions


func _all_item_ids() -> Array:
	var ids: Array = []
	for entry in FarmData.INVENTORY_CATALOG:
		if not ids.has(String(entry["id"])): ids.append(String(entry["id"]))
	var config := _config()
	for table_name in ["items", "eggs"]:
		for item_id in config.get(table_name, {}):
			if not ids.has(String(item_id)): ids.append(String(item_id))
	# Preserve access to loaded inventory IDs even when no current registry owns them.
	for item_id in GameState.data.get("inventory", {}):
		if not ids.has(String(item_id)): ids.append(String(item_id))
	return ids


func _item_category(item_id: String) -> String:
	var config := _config()
	if config.get("eggs", {}).has(item_id) or item_id in ["egg", "duck_egg"]: return "Eggs"
	if item_id.begins_with("seed_"): return "Seeds"
	if item_id.begins_with("crop_"): return "Crops"
	if item_id == "animal_feed": return "Food"
	if item_id == "medicine": return "Medicine"
	var group := String(config.get("items", {}).get(item_id, {}).get("group", ""))
	match group:
		"Herb": return "Crops"
		"Food", "Treat": return "Food"
		"Medicine": return "Medicine"
		"Material", "Creature Material": return "Materials"
		"Animal Product": return "Crops"
	return "Other"


func _category_items() -> Array:
	var result: Array = []
	for item_id in _all_item_ids():
		if category == "All" or _item_category(String(item_id)) == category:
			result.append(item_id)
	return result


func _visible_items() -> Array:
	var ids := _category_items()
	page_index = clampi(page_index, 0, maxi(0, ceili(float(ids.size()) / PAGE_SIZE) - 1))
	return ids.slice(page_index * PAGE_SIZE, (page_index + 1) * PAGE_SIZE)


func _amount(item_id: String) -> int:
	return GameState.dragon_energy() if item_id == "dragon_energy" else int(GameState.data.get("inventory", {}).get(item_id, 0))


func _inventory_total() -> int:
	var total := 0
	for value in GameState.data.get("inventory", {}).values(): total += int(value)
	return total


func _set_category(value: String) -> void:
	if not CATEGORY_LABELS.has(value): return
	category = value
	page_index = 0
	var ids := _category_items()
	selected_item = String(ids[0]) if not ids.is_empty() else ""
	feedback = tr("Đang xem: %s") % tr(String(CATEGORY_LABELS[category]))
	_refresh_in_place()


func _change_page(direction: int) -> void:
	var last_page := maxi(0, ceili(float(_category_items().size()) / PAGE_SIZE) - 1)
	page_index = clampi(page_index + direction, 0, last_page)
	var ids := _visible_items()
	selected_item = String(ids[0]) if not ids.is_empty() else ""
	feedback = tr("Page %d / %d") % [page_index + 1, last_page + 1]
	_refresh_in_place()


func _select_slot(index: int) -> void:
	var ids := _visible_items()
	if index >= 0 and index < ids.size(): _select_item(String(ids[index]))


func _select_item(item_id: String) -> void:
	if not _all_item_ids().has(item_id): return
	var ids := _category_items()
	if not ids.has(item_id):
		category = "All"
		ids = _category_items()
	page_index = floori(float(ids.find(item_id)) / PAGE_SIZE)
	selected_item = item_id
	feedback = tr("Đã chọn %s · số lượng %d") % [_display_name(item_id), _amount(item_id)]
	if item_id == "crop_carrot" and int(GameState.data.get("orders_done", 0)) == 0 and _amount(item_id) >= 1:
		feedback += "\n" + tr("Cà rốt dùng cho Đơn đầu tiên. Hãy giữ lại ít nhất 1 củ.")
	_refresh_in_place()


func _sell_selected() -> void:
	_sell(selected_item)


func _sell_info(item_id: String) -> Dictionary:
	var crop_id := item_id.trim_prefix("crop_")
	if item_id.begins_with("crop_") and FarmData.CROP_DEFINITIONS.has(crop_id):
		var value := int(FarmData.CROP_DEFINITIONS[crop_id]["sell_value"])
		return {"ok": _amount(item_id) > 0, "reason": tr("Sell one: %d coins") % value if _amount(item_id) > 0 else tr("You do not own this item.")}
	return GameState.world_action_info("sell_item", item_id)


func _sell(item_id: String) -> void:
	selected_item = item_id
	var info := _sell_info(item_id)
	if not bool(info.get("ok", false)):
		feedback = String(info.get("reason", ""))
	else:
		var crop_id := item_id.trim_prefix("crop_")
		if item_id.begins_with("crop_") and FarmData.CROP_DEFINITIONS.has(crop_id):
			var value := int(FarmData.CROP_DEFINITIONS[crop_id]["sell_value"])
			feedback = tr("Đã bán 1 %s · nhận %d xu") % [_display_name(item_id), value] if GameState.sell(item_id) else UILocale.translate_message(GameState.status)
		else:
			GameState.world_action("sell_item", item_id)
			feedback = UILocale.translate_message(GameState.status)
	_refresh_in_place()


func _use_info(item_id: String) -> Dictionary:
	if item_id == "medicine":
		return {"ok": _amount(item_id) > 0 and int(GameState.data.get("energy", 0)) < 100, "action": "core_medicine", "reason": tr("Farm energy is already full.") if int(GameState.data.get("energy", 0)) >= 100 else tr("Dùng để hồi năng lượng") if _amount(item_id) > 0 else tr("You do not own this item.")}
	var action := ""
	if item_id == "ancient_fruit": action = "convert_fruit"
	elif item_id == "dragon_energy": action = "dragon_blessing"
	elif _config().get("eggs", {}).has(item_id): action = "incubate"
	if not action.is_empty():
		var info := GameState.world_action_info(action, item_id)
		info["action"] = action
		return info
	return {"ok": false, "action": "", "reason": _item_usage(item_id)}


func _use_selected() -> void:
	var info := _use_info(selected_item)
	if not bool(info.get("ok", false)):
		feedback = String(info.get("reason", ""))
	elif String(info.get("action", "")) == "core_medicine":
		feedback = tr("Đã dùng Thuốc bổ sung · năng lượng được hồi phục.") if GameState.use_item(selected_item) else UILocale.translate_message(GameState.status)
	else:
		GameState.world_action(String(info["action"]), selected_item)
		feedback = UILocale.translate_message(GameState.status)
	_refresh_in_place()


func _refresh_storage_actions() -> void:
	var sell := find_child("StorageSellSelected", true, false) as BaseButton
	var use := find_child("StorageUseSelected", true, false) as BaseButton
	var sell_info := _sell_info(selected_item)
	var use_info := _use_info(selected_item)
	if sell != null: CardState.apply_action(sell, bool(sell_info.get("ok", false)), String(sell_info.get("reason", "")))
	if use != null:
		use.visible = true
		CardState.apply_action(use, bool(use_info.get("ok", false)), String(use_info.get("reason", "")))
		var caption := use.get_node_or_null("Caption") as Label
		if caption != null:
			caption.text = tr("Ấp") if String(use_info.get("action", "")) == "incubate" else tr("Đổi") if String(use_info.get("action", "")) == "convert_fruit" else tr("Dùng")
	for target in [sell, use, find_child("StorageClose", true, false)]:
		GameSkin.apply(target as TextureButton, {"font_size": 16, "layout_content": true})


func _update_storage_slots() -> void:
	var ids := _visible_items()
	for index in range(PAGE_SIZE):
		var slot := get_node("MainContent/ItemGrid_5x3/ItemSlot%02d" % (index + 1))
		slot.visible = index < ids.size()
		var cards := slot.find_children("Storage*Card*", "Panel", false, false)
		if cards.is_empty(): continue
		var card := cards[0] as Panel
		card.visible = index < ids.size()
		if index >= ids.size(): continue
		var item_id := String(ids[index])
		var amount := _amount(item_id)
		card.set_meta("inventory_item_id", item_id)
		var textures := card.find_children("*", "TextureRect", true, false)
		var has_art := Assets.ITEM_ICONS.has(item_id)
		if not textures.is_empty():
			var artwork := textures[0] as TextureRect
			artwork.texture = Assets.get_item_texture(item_id) if has_art else null
			artwork.visible = has_art
		# Content labels are stable; selection badges are never item-name labels.
		var name_label := card.get_node_or_null(String(card.name) + "Label") as Label
		var quantity_label := card.find_child(String(card.name) + "SurfaceLabel", true, false) as Label
		if name_label != null:
			name_label.text = _display_name(item_id)
			name_label.tooltip_text = _display_name(item_id)
			name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_label.max_lines_visible = 2
			name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if quantity_label != null: quantity_label.text = "× %d" % amount
		CardState.apply_card(card, selected_item == item_id, false, amount <= 0, tr("Chọn %s · số lượng %d") % [_display_name(item_id), amount])
		var state_frame := card.get_node_or_null("UIStateFrame") as Control
		if state_frame != null:
			var selected_style := state_frame.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
			if selected_style != null:
				# A filled shadow at z30 tints the entire item and its captions.
				# Keep selection on the border, never over the content.
				selected_style.bg_color = Color(0, 0, 0, 0)
				selected_style.shadow_color = Color(0, 0, 0, 0)
				selected_style.shadow_size = 0
				state_frame.add_theme_stylebox_override("panel", selected_style)


func _update_storage_detail() -> void:
	var panel := find_child("ItemDetailPanel", true, false)
	if panel == null: return
	var artwork := panel.get_node_or_null("SelectedItemArtwork") as TextureRect
	var has_art := Assets.ITEM_ICONS.has(selected_item)
	if artwork != null:
		artwork.texture = Assets.get_item_texture(selected_item) if has_art else null
		artwork.visible = has_art
		artwork.position = Vector2(49, 49)
		artwork.size = Vector2(224, 138)
	var name_label := panel.get_node_or_null("SelectedItemName") as Label
	var description := panel.get_node_or_null("SelectedItemDescription") as Label
	if name_label != null:
		name_label.text = _display_name(selected_item)
		name_label.tooltip_text = name_label.text
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.position.y = 190
	if description != null:
		var item_group := tr(String(CATEGORY_LABELS.get(_item_category(selected_item), "Hiếm / khác")))
		var value := _sell_value(selected_item)
		var sell_copy := tr("Sell one: %d coins") % value if value > 0 else tr("Cannot be sold.")
		description.text = tr("Owned: %d\nCategory: %s\n%s\n%s") % [_amount(selected_item), item_group, sell_copy, ""]
		description.position.y = 245
		description.size.y = 73
		description.tooltip_text = description.text.strip_edges() + "\n" + _item_usage(selected_item)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var usage := panel.get_node_or_null("SelectedItemUsage") as Label
	if usage != null:
		usage.text = _item_usage(selected_item)
		usage.tooltip_text = usage.text
		usage.position.y = 320
		usage.size.y = 55
	var source := ItemSource.source(selected_item)
	var source_button := panel.get_node_or_null("StorageItemSource") as TextureButton
	if source_button == null:
		source_button = UI.title_button("", Rect2(19, 384, 284, 56))
		source_button.name = "StorageItemSource"
		source_button.get_child(0).name = "Caption"
		source_button.pressed.connect(_open_item_source)
		panel.add_child(source_button)
	source_button.visible = not source.is_empty()
	if not source.is_empty():
		GameSkin.apply(source_button, {"caption": String(source["caption"]), "font_size": 15, "layout_content": true})
		var caption := source_button.get_node_or_null("Caption") as Label
		if caption != null: caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		source_button.tooltip_text = String(source["hint"])
		if selected_item == "ancient_fruit" and usage != null:
			usage.text = String(source["hint"])
			usage.tooltip_text = _item_usage(selected_item) + "\n" + String(source["hint"])
			usage.max_lines_visible = 3
			usage.add_theme_font_size_override("font_size", 14)
	var discard := panel.get_node_or_null("StorageDiscardSelected") as TextureButton
	if discard == null:
		discard = UI.title_button("", Rect2(19, 384, 284, 56))
		discard.name = "StorageDiscardSelected"
		discard.get_child(0).name = "Caption"
		discard.pressed.connect(_request_discard)
		panel.add_child(discard)
	var discard_info := GameState.world_action_info("discard_item", selected_item)
	discard.visible = _amount(selected_item) > 0 and selected_item != "dragon_energy"
	CardState.apply_action(discard, bool(discard_info.get("ok", false)), UILocale.translate_message(String(discard_info.get("reason", ""))))
	discard.position = Vector2(167 if source_button.visible else 19, 384)
	discard.size = Vector2(136 if source_button.visible else 284, 56)
	source_button.size.x = 136 if discard.visible else 284
	GameSkin.apply(discard, {"caption": UILocale.pair("Bỏ cả chồng…", "Discard stack…"), "font_size": 14, "layout_content": true})
	if source_button.visible:
		GameSkin.apply(source_button, {"caption": String(source["caption"]), "font_size": 14 if discard.visible else 15, "layout_content": true})
		(source_button.get_node("Caption") as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(discard.get_node("Caption") as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _open_item_source() -> void:
	ItemSource.open(selected_item)


func _request_discard() -> void:
	if get_node_or_null("StorageDiscardDialog") != null: return
	var info := GameState.world_action_info("discard_item", selected_item)
	if not bool(info.get("ok", false)):
		feedback = UILocale.translate_message(String(info.get("reason", "")))
		_refresh_in_place()
		return
	_discard_item = selected_item
	_discard_amount = _amount(selected_item)
	var overlay := Control.new()
	overlay.name = "StorageDiscardDialog"
	overlay.z_index = 4092
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var shade := ColorRect.new()
	shade.name = "InputBlocker"
	shade.color = Color(0.12, 0.09, 0.06, 0.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(shade)
	var paper := UI.panel(Rect2(330, 205, 620, 310))
	overlay.add_child(paper)
	var heading := UI.label(UILocale.pair("Xác nhận bỏ vật phẩm", "Confirm item discard"), Rect2(20, 18, 580, 46), 25, Color("6c351e"), HORIZONTAL_ALIGNMENT_CENTER)
	heading.name = "DiscardHeading"
	paper.add_child(heading)
	var details := UI.label(UILocale.pair("Bỏ toàn bộ %s ×%d?\nCác vật phẩm này sẽ mất. Bạn không nhận được xu.", "Discard all %s ×%d?\nThese items will be lost. You receive no coins.") % [_display_name(_discard_item), _discard_amount], Rect2(24, 78, 572, 112), 19, Color("6c351e"), HORIZONTAL_ALIGNMENT_CENTER)
	details.name = "DiscardWarning"
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	paper.add_child(details)
	var cancel := UI.title_button("", Rect2(35, 222, 260, 58))
	cancel.name = "CancelDiscardStack"
	cancel.get_child(0).name = "Caption"
	cancel.pressed.connect(_cancel_discard)
	paper.add_child(cancel)
	GameSkin.apply(cancel, {"caption": UILocale.pair("Hủy", "Cancel"), "font_size": 18, "layout_content": true})
	var confirm := UI.title_button("", Rect2(325, 222, 260, 58))
	confirm.name = "ConfirmDiscardStack"
	confirm.get_child(0).name = "Caption"
	confirm.pressed.connect(_confirm_discard)
	paper.add_child(confirm)
	GameSkin.apply(confirm, {"caption": UILocale.pair("Bỏ cả chồng", "Discard stack"), "font_size": 18, "layout_content": true})
	LocaleFonts.apply_to_tree(overlay)
	cancel.grab_focus()
	var menu := get_node_or_null("GameplaySaveMenu")
	if menu != null: menu.set_process_input(false)


func _cancel_discard() -> void:
	var overlay := get_node_or_null("StorageDiscardDialog")
	if overlay != null:
		remove_child(overlay)
		overlay.queue_free()
	_discard_item = ""
	_discard_amount = 0
	var menu := get_node_or_null("GameplaySaveMenu")
	if menu != null: menu.set_process_input(true)


func _confirm_discard() -> void:
	if _discard_item.is_empty(): return
	var target := _discard_item
	var reviewed_amount := _discard_amount
	_cancel_discard()
	if _amount(target) != reviewed_amount:
		feedback = UILocale.pair("Số lượng đã thay đổi. Hãy kiểm tra lại chồng vật phẩm.", "The quantity changed. Review the stack again.")
	else:
		GameState.world_action("discard_item", target)
		feedback = UILocale.translate_message(GameState.status)
	_refresh_in_place()


func _input(event: InputEvent) -> void:
	if get_node_or_null("StorageDiscardDialog") != null and event.is_action_pressed("ui_cancel", true):
		get_viewport().set_input_as_handled()
		if not event.is_echo(): _cancel_discard()


func _sell_value(item_id: String) -> int:
	var crop_id := item_id.trim_prefix("crop_")
	if item_id.begins_with("crop_") and FarmData.CROP_DEFINITIONS.has(crop_id):
		return int(FarmData.CROP_DEFINITIONS[crop_id]["sell_value"])
	return int(_config().get("items", {}).get(item_id, {}).get("sell", 0))


func _item_usage(item_id: String) -> String:
	var config := _config()
	var item: Dictionary = config.get("items", {}).get(item_id, {})
	var known_core := false
	for entry in FarmData.INVENTORY_CATALOG:
		if String(entry["id"]) == item_id: known_core = true
	if not known_core and item.is_empty() and not config.get("eggs", {}).has(item_id):
		return tr("Unrecognized saved item. Kept safely; no current action is available.")
	if item_id == "medicine": return tr("Recover 25 farm energy. Creature diseases need matching remedies.")
	if item_id == "dragon_energy": return tr("Use an altar blessing to recover farm energy.")
	if item_id == "ancient_fruit": return tr("Convert one fruit to 5 Dragon Energy on Dragon Island.")
	if config.get("eggs", {}).has(item_id):
		var egg: Dictionary = config["eggs"][item_id]
		var species := String(egg.get("species", ""))
		return tr("Hatches %s in %d days. Collect the hatchling in Companions.") % [tr(String(config.get("creatures", {}).get(species, {}).get("name", species))), int(egg.get("days", 1))]
	if item_id == "dragon_treat": return tr("Offer this cake to an owned dragon in Companions.")
	if item_id == "animal_feed": return tr("Food for Cloud Chicken. Feed from the Animal screen.")
	if String(item.get("group", "")) == "Food":
		var species_names: Array[String] = []
		for species in config.get("creatures", {}):
			if String(config["creatures"][species].get("food", "")) == item_id:
				species_names.append(tr(String(config["creatures"][species].get("name", species))))
		return tr("Food for %s. Feed in Animal or Companions.") % ", ".join(species_names)
	if item.has("cures"): return tr("Cures %s. Choose the sick creature in Companions.") % tr(String(item["cures"]))
	if item_id.begins_with("seed_"):
		return tr("Plant in the Herb Garden.") if String(item.get("group", "")) == "Herb Seed" else tr("Choose a field bed to plant this seed.")
	if item_id.begins_with("crop_"): return tr("Sell a crop or keep it for farm orders.")
	if String(item.get("group", "")) in ["Herb", "Material", "Creature Material", "Animal Product"]:
		return tr("Keep for recipes and buildings, or sell when a price is shown.")
	return tr("Keep this item for farm activities.")


func _update_page_controls() -> void:
	var pages := maxi(1, ceili(float(_category_items().size()) / PAGE_SIZE))
	var label := find_child("StoragePageLabel", true, false) as Label
	if label != null: label.text = tr("Page %d / %d") % [page_index + 1, pages]
	var previous := find_child("StoragePreviousPage", true, false) as BaseButton
	var next := find_child("StorageNextPage", true, false) as BaseButton
	if previous != null: CardState.apply_action(previous, page_index > 0, tr("Previous page"))
	if next != null: CardState.apply_action(next, page_index + 1 < pages, tr("Next page"))


func _update_feedback() -> void:
	var panel := find_child("StorageFeedbackPanel", true, false)
	if panel == null: return
	for child in panel.get_children():
		if child is Label:
			(child as Label).text = UILocale.translate_message(feedback)
			(child as Label).tooltip_text = (child as Label).text


func _show_navigation_day_result(_succeeded: bool, message: String) -> void:
	feedback = message
	_refresh_in_place()


func _refresh_category_tabs() -> void:
	for id in CATEGORY_IDS:
		var button := find_child("StorageCategory_%s" % id, true, false) as TextureButton
		if button == null: continue
		var selected: bool = category == id
		var textures := ROOT + "/UI/SHARED_BUTTONS/primary_medium" if selected else ROOT + "/UI/TITLE_SAVE_HOME/title_button_frame"
		button.texture_normal = Assets.texture(textures + "/default.png") if selected else Assets.texture(textures + "_default.png")
		button.texture_pressed = Assets.texture(textures + "/pressed.png") if selected else Assets.texture(textures + "_pressed.png")
		button.texture_hover = Assets.texture(textures + "/hover.png") if selected else Assets.texture(textures + "_hover.png")
		button.texture_disabled = Assets.texture(textures + "/disabled.png") if selected else Assets.texture(textures + "_disabled.png")
		var caption := button.get_node_or_null("Caption") as Label
		if caption != null: caption.text = tr(String(CATEGORY_LABELS[id]))
		CardState.apply_tab(button, selected, true, tr("Xem %s") % tr(String(CATEGORY_LABELS[id])))
		GameSkin.apply(button, {"caption": tr(String(CATEGORY_LABELS[id])), "font_size": 13, "selected": selected})


func _display_name(item_id: String) -> String:
	if DISPLAY_NAMES.has(item_id): return tr(String(DISPLAY_NAMES[item_id]))
	var config := _config()
	for table_name in ["items", "eggs"]:
		if config.get(table_name, {}).has(item_id): return tr(String(config[table_name][item_id].get("name", item_id)))
	return item_id.replace("_", " ").capitalize()
