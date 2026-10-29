extends RefCounted
class_name FarmData

const WorldData = preload("res://scripts/world_data.gd")
const Fields = preload("res://scripts/field_zones.gd")


const TITLE_MENU := [
	{"label": "Bat dau", "action": "open_save"},
	{"label": "Tiep tuc", "action": "continue_game"},
	{"label": "Cai dat", "action": "open_settings"},
	{"label": "Thoat", "action": "quit_game"},
]

const SAVE_SLOTS := [
	{
		"id": 1,
		"name": "Dao Rong 01",
		"unlocked": true,
		"has_data": true,
		"day": 1,
		"coins": 400,
		"energy": 100,
		"master_volume": 80.0,
		"music_volume": 70.0,
		"sfx_volume": 85.0,
		"fullscreen": false,
		"pet": "Rong May",
		"note": "Save goc de vao hub va thao tac nong trai.",
	},
	{
		"id": 2,
		"name": "Slot 02",
		"unlocked": false,
		"has_data": false,
		"day": 0,
		"coins": 0,
		"energy": 0,
		"pet": "Khoa",
		"note": "Se mo sau khi hoan thanh phien ban dau.",
	},
	{
		"id": 3,
		"name": "Slot 03",
		"unlocked": false,
		"has_data": false,
		"day": 0,
		"coins": 0,
		"energy": 0,
		"pet": "Khoa",
		"note": "Du phong cho ban save thu nghiem sau nay.",
	},
]

const HUB_HOTSPOTS := [
	{
		"id": "shop",
		"label": "Shop",
		"hint": "Mo cua hang mua hat giong va vat pham.",
		"rect": Rect2(34, 204, 176, 190),
		"action": "open_shop",
	},
	{
		"id": "house",
		"label": "Nha",
		"hint": "Mo thong tin nha, save slot va tien do.",
		"rect": Rect2(220, 115, 170, 170),
		"action": "open_house",
	},
	{
		"id": "barn",
		"label": "Chuong",
		"hint": "Di vao khu chuong de cham soc vat nuoi.",
		"rect": Rect2(405, 96, 188, 126),
		"action": "go_animal_entry",
	},
	{
		"id": "field",
		"label": "Ruong",
		"hint": "Di sang man thao tac o dat va gieo trong.",
		"rect": Rect2(716, 160, 286, 250),
		"action": "go_field",
	},
	{
		"id": "craft",
		"label": "Craft",
		"hint": "Mo khu cong thuc va doi vat pham.",
		"rect": Rect2(1074, 305, 136, 186),
		"action": "open_craft",
	},
	{
		"id": "inventory",
		"label": "Kho",
		"hint": "Xem vat pham da thu duoc trong kho.",
		"rect": Rect2(916, 472, 252, 150),
		"action": "open_inventory",
	},
	{
		"id": "pet",
		"label": "Pet",
		"hint": "Xem doi dong hanh, rong va thu ho tro.",
		"rect": Rect2(915, 60, 190, 120),
		"action": "open_pet",
	},
]

const HUB_ACTIONS := [
	{"label": "Ruong", "action": "go_field"},
	{"label": "Kho", "action": "open_inventory"},
	{"label": "Shop", "action": "open_shop"},
	{"label": "Pet", "action": "open_pet"},
	{"label": "Ban do", "action": "open_island"},
	{"label": "Su kien", "action": "open_event"},
	{"label": "Ngay moi", "action": "advance_day"},
]

const FIELD_ACTIONS := [
	{"label": "Cay", "action": "field_till"},
	{"label": "Gieo", "action": "field_seed"},
	{"label": "Tuoi", "action": "field_water"},
	{"label": "Bon", "action": "field_fertilize"},
	{"label": "Thu", "action": "field_harvest"},
	{"label": "Ngay moi", "action": "advance_day"},
	{"label": "Ve hub", "action": "go_hub"},
]

const ACTION_ENERGY_COSTS := {
	"till": 4,
	"seed": 3,
	"water": 2,
	"fertilize": 2,
	"harvest": 3,
	"feed_animals": 2,
	"clean_animals": 2,
	"pet_animals": 1,
}

const ANIMAL_ENTRY_ACTIONS := [
	{"label": "Vao chuong", "action": "go_animal_inside"},
	{"label": "Pet", "action": "open_pet"},
	{"label": "Kho", "action": "open_inventory"},
	{"label": "Ve hub", "action": "go_hub"},
]

const ANIMAL_INSIDE_ACTIONS := [
	{"label": "Cho an", "action": "feed_animals"},
	{"label": "Don dep", "action": "clean_animals"},
	{"label": "Vuot ve", "action": "pet_animals"},
	{"label": "Thu trung", "action": "collect_eggs"},
	{"label": "Kho", "action": "open_inventory"},
	{"label": "Ve hub", "action": "go_hub"},
]

const FIELD_GRID := [
	{"id": 1, "position": Vector2(405, 230)}, {"id": 2, "position": Vector2(535, 230)},
	{"id": 3, "position": Vector2(665, 230)}, {"id": 4, "position": Vector2(795, 230)},
	{"id": 5, "position": Vector2(405, 345)}, {"id": 6, "position": Vector2(535, 345)},
	{"id": 7, "position": Vector2(665, 345)}, {"id": 8, "position": Vector2(795, 345)},
	{"id": 9, "position": Vector2(405, 460)}, {"id": 10, "position": Vector2(535, 460)},
	{"id": 11, "position": Vector2(665, 460)}, {"id": 12, "position": Vector2(795, 460)},
]

const CROP_DEFINITIONS := {
	"carrot": {
		"label": "Ca rot",
		"seed_item": "seed_carrot",
		"crop_item": "crop_carrot",
		"max_stage": 4,
		"sell_value": 40,
	},
	"tomato": {
		"label": "Ca chua",
		"seed_item": "seed_tomato",
		"crop_item": "crop_tomato",
		"max_stage": 4,
		"sell_value": 52,
	},
	"pumpkin": {
		"label": "Bi ngo",
		"seed_item": "seed_pumpkin",
		"crop_item": "crop_pumpkin",
		"max_stage": 5,
		"sell_value": 76,
	},
}

const INVENTORY_CATALOG := [
	{"id": "seed_carrot", "label": "Hat Ca rot", "group": "Hat giong"},
	{"id": "seed_tomato", "label": "Hat Ca chua", "group": "Hat giong"},
	{"id": "seed_pumpkin", "label": "Hat Bi ngo", "group": "Hat giong"},
	{"id": "crop_carrot", "label": "Ca rot tuoi", "group": "Nong san"},
	{"id": "crop_tomato", "label": "Ca chua", "group": "Nong san"},
	{"id": "crop_pumpkin", "label": "Bi ngo", "group": "Nong san"},
	{"id": "animal_feed", "label": "Thuc an vat nuoi", "group": "Cham soc"},
	{"id": "medicine", "label": "Thuoc bo sung", "group": "Cham soc"},
	{"id": "egg", "label": "Trung ga", "group": "Thu hoach"},
	{"id": "dragon_treat", "label": "Banh Rong", "group": "Craft"},
]

const SHOP_ITEMS := [
	{"id": "seed_carrot", "label": "Hat Ca rot", "price": 12, "amount": 3, "group": "Hat giong"},
	{"id": "seed_tomato", "label": "Hat Ca chua", "price": 16, "amount": 3, "group": "Hat giong"},
	{"id": "seed_pumpkin", "label": "Hat Bi ngo", "price": 22, "amount": 2, "group": "Hat giong"},
	{"id": "animal_feed", "label": "Thuc an vat nuoi", "price": 22, "amount": 2, "group": "Cham soc"},
	{"id": "medicine", "label": "Thuoc bo sung", "price": 28, "amount": 1, "group": "Cham soc"},
]

const ORDER_DEFINITIONS := [
	{
		"id": "order_carrot",
		"title": "Đơn đầu tiên",
		"need_item": "crop_carrot",
		"need_amount": 1,
		"reward_coins": 70,
		"reward_item": "seed_tomato",
		"reward_amount": 3,
		"desc": "Giao 1 Cà rốt tươi để mở khóa Cà chua.",
	},
	{
		"id": "order_tomato",
		"title": "Vụ mùa mới",
		"need_item": "crop_tomato",
		"need_amount": 2,
		"reward_coins": 120,
		"reward_item": "seed_pumpkin",
		"reward_amount": 2,
		"desc": "Giao 2 Cà chua để mở khóa Bí ngô.",
	},
	{
		"id": "order_pumpkin",
		"title": "Thu hoạch lớn",
		"need_item": "crop_pumpkin",
		"need_amount": 1,
		"reward_coins": 200,
		"reward_item": "seed_carrot",
		"reward_amount": 3,
		"desc": "Giao 1 Bí ngô để hoàn thành mục tiêu nông trại đầu tiên.",
	},
]

const PETS := [
	{"name": "Rong May", "level": 3, "mood": "Vui ve", "role": "Tang may man khi di giao don hang."},
	{"name": "Rong Lua", "level": 5, "mood": "Am ap", "role": "Tang toc do cham soc vuon."},
	{"name": "Rong Reu", "level": 2, "mood": "On dinh", "role": "Nhat them vat pham nho khi thu hoach."},
]

const ISLANDS := [
	{"name": "Dao Chinh", "state": "Dang mo", "desc": "Noi bat dau hub chinh va khu ruong."},
	{"name": "Dao Rong", "state": "Dang mo", "desc": "Khu rong va pet ho tro nong trai."},
	{"name": "Dao Bang", "state": "Sap mo", "desc": "Man map tiep theo cho event va ho ca."},
	{"name": "Dao Huyen Moc", "state": "Khoa", "desc": "Teaser cho chapter sau."},
]

const CRAFT_RECIPES := [
	{
		"name": "Banh Rong nong",
		"need": "2 Ca rot tuoi + 1 Trung ga",
		"reward": "1 Banh Rong",
		"note": "Dung de tang tam trang cho rong.",
	},
	{
		"name": "Qua thuong nong trai",
		"need": "3 Lua vang + 1 Thuoc bo sung",
		"reward": "60 Tien",
		"note": "Cong thuc doi nhanh tien trong ban demo.",
	},
]

const EVENT_TASKS := [
	{"id": "till", "label": "Cay 2 o dat", "target": 2},
	{"id": "seed", "label": "Gieo 2 o dat", "target": 2},
	{"id": "harvest", "label": "Thu hoach 1 lan", "target": 1},
	{"id": "collect", "label": "Thu 1 trung ga", "target": 1},
]

const SETTINGS_ITEMS := [
	{"label": "Am thanh", "value": "80%"},
	{"label": "Hieu ung", "value": "Bat"},
	{"label": "Do phan giai", "value": "1280 x 720"},
	{"label": "Flow hien tai", "value": "Title -> Save -> Hub -> Sub-scene"},
]

const QUICK_NOTES := [
	"Flow dung theo SWF: Hub -> Field / Animal scene.",
	"Khong nhoi crop, chuong va panel lon len cung mot map.",
	"Crop thao tac truc tiep trong man ruong bang action bar.",
	"Dung 4 anh reference goc lam nen de giu huong nhin SWF.",
	"Them don hang ngay de khuyen khich chay loop ruong -> chuong -> hub.",
]


static func create_initial_state() -> Dictionary:
	var plot_states: Array = []
	for plot in FIELD_GRID:
		plot_states.append(
			{
				"id": plot["id"],
				"position": plot["position"],
				"locked": false,
				"is_hoed": false,
				"crop": "",
				"growth_stage": 0,
				"planted_day": -1,
				"last_watered_day": -1,
				"watered_today": false,
				"fertilizer_pending": false,
				"ready_to_harvest": false,
			}
		)

	return {
		"save_version": 4,
		"selected_slot": 1,
		"day": 1,
		"coins": 400,
		"energy": 100,
		"world": WorldData.initial_state(),
		"selected_plot": 1,
		"selected_seed": "carrot",
		"active_order_index": 0,
		"orders_done": 0,
		"field_plots": plot_states,
		"active_field_zone": "home",
		"field_zone_plots": Fields.initial_extra_fields(plot_states),
		"inventory": {
			"seed_carrot": 6,
			"seed_tomato": 0,
			"seed_pumpkin": 0,
			"animal_feed": 3,
			"medicine": 1,
			"crop_carrot": 0,
			"crop_tomato": 0,
			"crop_pumpkin": 0,
			"egg": 0,
			"dragon_treat": 0,
		},
		"animal": {
			"fullness": 60,
			"cleanliness": 75,
			"happiness": 68,
			"eggs_ready": 1,
		},
		"event_progress": {
			"till": 0,
			"seed": 0,
			"harvest": 0,
			"collect": 0,
		},
		"last_rewards": [
			{"label": "Tien", "value": "+40"},
			{"label": "Hat Ca rot", "value": "+3"},
		],
		"status_text": "Click ruong de trong trot, click chuong de cham soc vat nuoi.",
	}


static func get_inventory_name(item_id: String) -> String:
	for item in INVENTORY_CATALOG:
		if item["id"] == item_id:
			return item["label"]
	return String(WorldData.config()["items"].get(item_id, {}).get("name", WorldData.config()["eggs"].get(item_id, {}).get("name", item_id)))


static func get_crop_label(crop_id: String) -> String:
	if CROP_DEFINITIONS.has(crop_id):
		return CROP_DEFINITIONS[crop_id]["label"]
	return crop_id
