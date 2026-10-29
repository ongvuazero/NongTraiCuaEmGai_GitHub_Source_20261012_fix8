extends BaseScreen

const SharedContent = preload("res://scripts/ui/shared_shop_content.gd")
const ButtonSkin = preload("res://scripts/ui/gameplay_button_skin.gd")
const PAGE_SIZE := 5
var shop_content

# State lives in one controller. Main Shop authored controls keep their parents
# and geometry, while former screen callers can still inspect/select its offers.
var selected_product: String:
	get: return shop_content.selected_product if shop_content != null else "seed_carrot"
var active_category: String:
	get: return shop_content.active_category if shop_content != null else "seeds"
var page_index: int:
	get: return shop_content.page_index if shop_content != null else 0
var feedback: String:
	get: return shop_content.feedback if shop_content != null else ""
	set(value):
		if shop_content != null: shop_content.feedback = value


func build() -> void:
	bind_top_hud()
	set_meta("SHOP_STORAGE_CORE_LOCK", "FUNCTIONAL_TEST_REQUIRED")
	set_meta("TRUE_WYSIWYG_V2", "VISUAL_REVIEW_REQUIRED")
	var back := bind_button("ShopBackToHub", ScreenRouter.back_home)
	if back != null:
		back.tooltip_text = tr("Về trang trại")
		var caption := back.get_node_or_null("Caption") as Label
		if caption != null: caption.text = tr("Quay lại")
		if back is TextureButton: ButtonSkin.apply(back as TextureButton, {"font_size": 18, "layout_content": true})
	shop_content = SharedContent.new()
	shop_content.name = "SharedShopContent"
	add_child(shop_content)
	shop_content.presentation_changed.connect(bind_top_hud)
	shop_content.attach_surface(self, "main")


func _refresh() -> void:
	_refresh_in_place()


func _refresh_in_place() -> void:
	if shop_content != null: shop_content._refresh_in_place()


func _show_navigation_day_result(_succeeded: bool, message: String) -> void:
	feedback = message
	_refresh_in_place()


func _category_shop_items() -> Array:
	return shop_content._category_shop_items() if shop_content != null else []


func _visible_shop_items() -> Array:
	return shop_content._visible_shop_items() if shop_content != null else []


func _shop_item(id: String) -> Dictionary:
	return shop_content._shop_item(id) if shop_content != null else {}


func _purchase_info(item: Dictionary) -> Dictionary:
	return shop_content._purchase_info(item) if shop_content != null else {"ok": false}


func _price_text(item: Dictionary) -> String:
	return shop_content._price_text(item) if shop_content != null else ""


func _world_action(item: Dictionary) -> String:
	return shop_content._world_action(item) if shop_content != null else ""


func _building_maxed(item: Dictionary) -> bool:
	return shop_content._building_maxed(item) if shop_content != null else false


func _product_description(item: Dictionary) -> String:
	return shop_content._product_description(item) if shop_content != null else ""


func _set_category(category: String) -> void:
	if shop_content != null: shop_content._set_category(category)


func _select_product(id: String) -> void:
	if shop_content != null: shop_content._select_product(id)


func _buy(id: String) -> void:
	if shop_content != null: shop_content._buy(id)


func _change_page(delta: int) -> void:
	if shop_content != null: shop_content._change_page(delta)
