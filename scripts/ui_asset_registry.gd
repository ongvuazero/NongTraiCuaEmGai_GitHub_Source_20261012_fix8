extends RefCounted
class_name UIAssetRegistry


const ROOT := "res://assets/canonical_v2/03_ART_RUNTIME_READY"

const BACKGROUNDS := {
	"title": ROOT + "/ENVIRONMENT/BACKGROUND_PLATES/E01-01__Title_far_background_sky_sea_cliffs.png",
	"hub": ROOT + "/ENVIRONMENT/BACKGROUND_PLATES/E01-04__Home_Hub_far_coast_distant_Dragon_Island.png",
	"field_select": ROOT + "/ENVIRONMENT/BACKGROUND_PLATES/E01-08__Field_Select_scenic_background_farmhouse_edge.png",
	"field": ROOT + "/ENVIRONMENT/BACKGROUND_PLATES/E01-10__Field_4x3_plot_ground_master_without_crops.png",
	"shop": ROOT + "/ENVIRONMENT/BACKGROUND_PLATES/E02-01__Shop_wood_wall_shelf_background.png",
	"storage": ROOT + "/ENVIRONMENT/BACKGROUND_PLATES/E02-05__Storage_wood_shelf_wall_background.png",
	"settings": ROOT + "/REPAIRS_AND_SHARED/SETTINGS/settings_neutral_parchment_wood_backdrop.png",
	"animal": ROOT + "/ENVIRONMENT/BACKGROUND_PLATES/E03-01__Animal_far_farm_mountains_lake_background.png",
	"dragon_far": ROOT + "/ENVIRONMENT/BACKGROUND_PLATES/E03-06__Dragon_Island_far_floating_islands_sky.png",
	"dragon_near": ROOT + "/ENVIRONMENT/BACKGROUND_PLATES/E03-07__Dragon_Island_waterfalls_cliffs_ocean_midground.png",
}

const ENVIRONMENT_LAYERS := {
	"title": [ROOT + "/ENVIRONMENT/SCREEN_PLATES/farmhouse_parity_environment.png"],
	"hub": [ROOT + "/ENVIRONMENT/BACKGROUND_PLATES/E01-04__Home_Hub_far_coast_distant_Dragon_Island.png"],
	"shop": [ROOT + "/ENVIRONMENT/SCREEN_PLATES/shop_environment.png"],
	"storage": [ROOT + "/ENVIRONMENT/SCREEN_PLATES/storage_environment.png"],
	"animal": [ROOT + "/ENVIRONMENT/SCREEN_PLATES/animal_environment.png"],
	"dragon": [ROOT + "/ENVIRONMENT/SCREEN_PLATES/dragon_environment.png"],
}

const FIELD_PREVIEWS := {
	"lakeside": ROOT + "/UI/TITLE_SAVE_HOME/FIELD_PREVIEWS/lakeside_field.png",
	"forest": ROOT + "/UI/TITLE_SAVE_HOME/FIELD_PREVIEWS/forest_field.png",
	"highland": ROOT + "/UI/TITLE_SAVE_HOME/FIELD_PREVIEWS/highland_field.png",
}

const ANIMAL_COOP_YARD := ROOT + "/ENVIRONMENT/SCREEN_PLATES/animal_coop_yard.png"
const DRAGON_INHABITANTS_SHEET := ROOT + "/CHARACTERS/DRAGONS/dragon_inhabitants_sheet.png"

const ITEM_ICONS := {
	"seed_carrot": "res://assets/gdd_closure_v3/items/seed_carrot.png",
	"crop_carrot": "res://assets/gdd_closure_v3/items/crop_carrot.png",
	"seed_tomato": "res://assets/gdd_closure_v3/items/seed_tomato.png",
	"crop_tomato": "res://assets/gdd_closure_v3/items/crop_tomato.png",
	"seed_pumpkin": "res://assets/production_ui_v1/items/seed_pumpkin.png",
	"crop_pumpkin": "res://assets/production_ui_v1/items/crop_pumpkin.png",
	"dragon_treat": "res://assets/production_ui_v1/items/dragon_treat.png",
	"egg": ROOT + "/ITEMS/egg.png",
	"animal_feed": "res://assets/gdd_closure_v3/items/animal_feed.png",
	# These aliases represent the same authored items, never generic fallbacks.
	"grain_feed": "res://assets/gdd_closure_v3/items/animal_feed.png",
	"dragon_energy": "res://assets/visual_animation_closure_v1/long_khi_complete.tres",
	"duck_feed": "res://assets/gdd_closure_v3/items/duck_feed.png",
	"pig_feed": "res://assets/gdd_closure_v3/items/pig_feed.png",
	"cow_feed": "res://assets/gdd_closure_v3/items/cow_feed.png",
	"duck_egg": "res://assets/gdd_closure_v3/items/duck_egg.png",
	"truffle": "res://assets/gdd_closure_v3/items/truffle.png",
	"milk": "res://assets/gdd_closure_v3/items/milk.png",
	"medicine_cold": "res://assets/gdd_closure_v3/items/medicine_cold.png",
	"medicine_fever": "res://assets/gdd_closure_v3/items/medicine_fever.png",
	"medicine_poison": "res://assets/gdd_closure_v3/items/medicine_poison.png",
	"medicine_fatigue": "res://assets/gdd_closure_v3/items/medicine_fatigue.png",
	"seed_mint": "res://assets/gdd_closure_v3/items/seed_mint.png",
	"seed_lavender": "res://assets/gdd_closure_v3/items/seed_lavender.png",
	"seed_sun_herb": "res://assets/gdd_closure_v3/items/seed_sun_herb.png",
	"seed_frost_herb": "res://assets/gdd_closure_v3/items/seed_frost_herb.png",
	"seed_antidote_herb": "res://assets/gdd_closure_v3/items/seed_antidote_herb.png",
	"aquatic_feed": "res://assets/gdd_closure_v3/items/aquatic_feed.png",
	"ember_feed": "res://assets/gdd_closure_v3/items/ember_feed.png",
	"frost_feed": "res://assets/gdd_closure_v3/items/frost_feed.png",
	"forest_feed": "res://assets/gdd_closure_v3/items/forest_feed.png",
	"golden_feed": "res://assets/gdd_closure_v3/items/golden_feed.png",
	"shadow_feed": "res://assets/gdd_closure_v3/items/shadow_feed.png",
	"crystal_feed": "res://assets/gdd_closure_v3/items/crystal_feed.png",
	"rainbow_feed": "res://assets/gdd_closure_v3/items/rainbow_feed.png",
	"fish_flakes": "res://assets/gdd_closure_v3/items/fish_flakes.png",
	"koi_pellets": "res://assets/gdd_closure_v3/items/koi_pellets.png",
	"ice_fish_feed": "res://assets/gdd_closure_v3/items/ice_fish_feed.png",
	"gold_fish_feed": "res://assets/gdd_closure_v3/items/gold_fish_feed.png",
	"feeder_fish_feed": "res://assets/gdd_closure_v3/items/feeder_fish_feed.png",
	"slime_feed": "res://assets/gdd_closure_v3/items/slime_feed.png",
	"golem_feed": "res://assets/gdd_closure_v3/items/golem_feed.png",
	"snake_feed": "res://assets/gdd_closure_v3/items/snake_feed.png",
	"barn": "res://assets/gdd_closure_v3/items/barn.png",
	"alchemy": "res://assets/gdd_closure_v3/items/alchemy.png",
	"special_shop": "res://assets/gdd_closure_v3/items/special_shop.png",
	"dragon_altar": "res://assets/gdd_closure_v3/items/dragon_altar.png",
	"garden": "res://assets/gdd_closure_v3/items/garden.png",
	"pond": "res://assets/gdd_closure_v3/items/pond.png",
	"monster_pen": "res://assets/gdd_closure_v3/items/monster_pen.png",
	"icehouse": "res://assets/gdd_closure_v3/items/icehouse.png",
	"forge": "res://assets/gdd_closure_v3/items/forge.png",
	"serpent_den": "res://assets/gdd_closure_v3/items/serpent_den.png",
	"warehouse": "res://assets/gdd_closure_v3/items/warehouse.png",
	"water_egg": "res://assets/gdd_closure_v3/items/water_egg.png",
	"fire_egg": "res://assets/gdd_closure_v3/items/fire_egg.png",
	"forest_egg": "res://assets/gdd_closure_v3/items/forest_egg.png",
	"ice_egg": "res://assets/gdd_closure_v3/items/ice_egg.png",
	"gold_egg": "res://assets/gdd_closure_v3/items/gold_egg.png",
	"shadow_egg": "res://assets/gdd_closure_v3/items/shadow_egg.png",
	"crystal_egg": "res://assets/gdd_closure_v3/items/crystal_egg.png",
	"rainbow_egg": "res://assets/gdd_closure_v3/items/rainbow_egg.png",
	"ancient_fruit": "res://assets/gdd_closure_v3/items/ancient_fruit.png",
	"dragon_crystal": "res://assets/gdd_closure_v3/items/dragon_crystal.png",
	"stone": "res://assets/gdd_closure_v3/items/stone.png",
	"ice_shard": "res://assets/gdd_closure_v3/items/ice_shard.png",
	"ember": "res://assets/gdd_closure_v3/items/ember.png",
	"snake_scale": "res://assets/gdd_closure_v3/items/snake_scale.png",
	"monster_gel": "res://assets/gdd_closure_v3/items/monster_gel.png",
	"mint": "res://assets/gdd_closure_v3/items/mint.png",
	"lavender": "res://assets/gdd_closure_v3/items/lavender.png",
	"sun_herb": "res://assets/gdd_closure_v3/items/sun_herb.png",
	"frost_herb": "res://assets/gdd_closure_v3/items/frost_herb.png",
	"antidote_herb": "res://assets/gdd_closure_v3/items/antidote_herb.png",
	"fish_scale": "res://assets/gdd_closure_v3/items/fish_scale.png",
	"koi_pearl": "res://assets/gdd_closure_v3/items/koi_pearl.png",
	"ice_pearl": "res://assets/gdd_closure_v3/items/ice_pearl.png",
	"gold_scale": "res://assets/gdd_closure_v3/items/gold_scale.png",
	"feeder_flakes": "res://assets/gdd_closure_v3/items/feeder_flakes.png",
	"medicine": "res://assets/gdd_closure_v3/items/medicine.png",
}

const PLOTS := {
	"unhoed": ROOT + "/FIELD/PLOTS/plot_unhoed_raw.png",
	"dry": ROOT + "/FIELD/PLOTS/plot_tilled_dry.png",
	"watered": ROOT + "/FIELD/PLOTS/plot_tilled_watered.png",
	"fertilized_dry": ROOT + "/FIELD/PLOTS/overlay_fertilized_dry.png",
	"fertilized_watered": ROOT + "/FIELD/PLOTS/overlay_fertilized_watered.png",
	"selected": ROOT + "/FIELD/PLOTS/overlay_selected.png",
	"hover": ROOT + "/FIELD/PLOTS/overlay_hover.png",
	"valid": ROOT + "/FIELD/PLOTS/overlay_valid_action.png",
	"invalid": ROOT + "/FIELD/PLOTS/overlay_invalid_action.png",
	"disabled": ROOT + "/FIELD/PLOTS/overlay_disabled.png",
}

const CROP_OVERLAYS := {
	"watered": ROOT + "/FIELD/CROP_OVERLAYS/watered_droplet_overlay.png",
	"fertilized": ROOT + "/FIELD/CROP_OVERLAYS/fertilized_nutrient_overlay.png",
	"stage_up": ROOT + "/FIELD/CROP_OVERLAYS/growth_stage_up_pulse_overlay.png",
	"ready": ROOT + "/FIELD/CROP_OVERLAYS/harvest_ready_sparkle_overlay.png",
	"harvest": ROOT + "/FIELD/CROP_OVERLAYS/harvest_complete_pickup_overlay.png",
}

const CROP_FRAMES := {
	"carrot": [
		ROOT + "/FIELD/CROPS/COMMON/seed_mound_stage0.png",
		ROOT + "/FIELD/CROPS/CARROT/carrot_stage1_young.png",
		ROOT + "/FIELD/CROPS/CARROT/carrot_stage2_growing.png",
		ROOT + "/FIELD/CROPS/CARROT/carrot_stage3_mature.png",
		ROOT + "/FIELD/CROPS/CARROT/carrot_stage4_ready.png",
	],
	"tomato": [
		ROOT + "/FIELD/CROPS/COMMON/seed_mound_stage0.png",
		ROOT + "/FIELD/CROPS/TOMATO/tomato_stage1_young.png",
		ROOT + "/FIELD/CROPS/TOMATO/tomato_stage2_growing.png",
		ROOT + "/FIELD/CROPS/TOMATO/tomato_stage3_mature.png",
		ROOT + "/FIELD/CROPS/TOMATO/tomato_stage4_ready.png",
	],
	"pumpkin": [
		ROOT + "/FIELD/CROPS/COMMON/seed_mound_stage0.png",
		ROOT + "/FIELD/CROPS/PUMPKIN/pumpkin_stage1_young.png",
		ROOT + "/FIELD/CROPS/PUMPKIN/pumpkin_stage2_growing.png",
		ROOT + "/FIELD/CROPS/PUMPKIN/pumpkin_stage3_fruiting_immature_green.png",
		ROOT + "/FIELD/CROPS/PUMPKIN/pumpkin_stage4_mature_orange_turning.png",
		ROOT + "/FIELD/CROPS/PUMPKIN/pumpkin_stage5_ready.png",
	],
}

const SEED_CARDS := {
	"carrot": {"default": ROOT + "/UI/SEED_PICKER/carrot_default.png", "selected": ROOT + "/UI/SEED_PICKER/carrot_selected.png"},
	"tomato": {"default": ROOT + "/UI/SEED_PICKER/tomato_default.png", "selected": ROOT + "/UI/SEED_PICKER/tomato_selected.png"},
	"pumpkin": {"default": ROOT + "/UI/SEED_PICKER/pumpkin_default.png", "selected": ROOT + "/UI/SEED_PICKER/pumpkin_selected.png"},
}

const ACTION_BUTTONS := ["hoe", "plant", "water", "fertilize", "harvest", "care"]
const FARMER_ACTIONS := ["idle", "walk", "hoe", "plant", "water", "fertilize", "harvest", "feed", "pet_care", "clean"]


static func texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	return load(path) as Texture2D


static func background(screen: String) -> Texture2D:
	return texture(BACKGROUNDS.get(screen, BACKGROUNDS["hub"]))


static func environment_layers(screen: String) -> Array:
	var result: Array = []
	for runtime_path in ENVIRONMENT_LAYERS.get(screen, []):
		result.append(texture(runtime_path))
	return result


static func plot_texture(kind: String) -> Texture2D:
	return texture(PLOTS.get(kind, PLOTS["unhoed"]))


static func crop_overlay(kind: String) -> Texture2D:
	return texture(CROP_OVERLAYS.get(kind, ""))


static func feedback_badge(kind: String) -> Texture2D:
	return texture(ROOT + "/UI/FIELD/FEEDBACK_BADGES/%s.png" % kind)


static func world_crop(crop_id: String, stage: int) -> Texture2D:
	if not CROP_FRAMES.has(crop_id):
		return null
	var frames: Array = CROP_FRAMES[crop_id]
	return texture(frames[clampi(stage, 0, frames.size() - 1)])


static func seed_card(crop_id: String, selected: bool = false) -> Texture2D:
	if not SEED_CARDS.has(crop_id):
		return null
	return texture(SEED_CARDS[crop_id]["selected" if selected else "default"])


static func get_item_texture(item_id: String) -> Texture2D:
	if ITEM_ICONS.has(item_id):
		return texture(ITEM_ICONS[item_id])
	# Unknown items must remain unillustrated rather than becoming fake medicine.
	return null


static func get_order_texture(item_id: String) -> Texture2D:
	return get_item_texture(item_id)


static func get_animal_texture(_animal_id: String) -> Texture2D:
	return animal_overlay("happy_cared_heart")


static func get_pet_texture(_pet_name: String) -> Texture2D:
	return texture(ROOT + "/REPAIRS_AND_SHARED/DRAGON/blue_sleeping_dragon.png")


static func action_button(action: String, state: String) -> Texture2D:
	if action not in ACTION_BUTTONS:
		return null
	return texture(ROOT + "/UI/FIELD/ACTION_BUTTONS/%s/%s.png" % [action, state])


static func home_nav(item: String) -> Texture2D:
	return texture(ROOT + "/REPAIRS_AND_SHARED/HOME_HUB_NAV/%s.png" % item)


static func animal_overlay(kind: String) -> Texture2D:
	return texture(ROOT + "/ANIMAL/STATUS_OVERLAYS/%s.png" % kind)


static func animal_base() -> Texture2D:
	return texture(ROOT + "/ANIMAL/BASE/chicken_idle.png")


static func animal_bar(kind: String) -> Texture2D:
	return texture(ROOT + "/REPAIRS_AND_SHARED/ANIMAL_STATUS_BARS/%s.png" % kind)


static func farmer_frames(action: String) -> SpriteFrames:
	var safe_action := action if action in FARMER_ACTIONS else "idle"
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation(safe_action)
	frames.set_animation_speed(safe_action, 10.0 if safe_action == "walk" else (6.0 if safe_action == "idle" else 8.0))
	frames.set_animation_loop(safe_action, safe_action in ["idle", "walk"])
	for i in range(1, 11):
		frames.add_frame(safe_action, texture(ROOT + "/ANIMATION/FARMER/%s/frame_%02d.png" % [safe_action, i]))
	return frames
