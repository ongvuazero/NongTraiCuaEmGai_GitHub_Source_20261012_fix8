extends RefCounted
class_name RuntimeCropRegistryV73

const ROOT := "res://v7/art/runtime_crops_plant_only"

const FRAMES := {
	"carrot": [
		ROOT + "/seed_stage0_plant_only.png",
		ROOT + "/carrot_stage1_plant_only.png",
		ROOT + "/carrot_stage2_plant_only.png",
		ROOT + "/carrot_stage3_plant_only.png",
		ROOT + "/carrot_stage4_plant_only.png",
	],
	"tomato": [
		ROOT + "/seed_stage0_plant_only.png",
		ROOT + "/tomato_stage1_plant_only.png",
		ROOT + "/tomato_stage2_plant_only.png",
		ROOT + "/tomato_stage3_plant_only.png",
		ROOT + "/tomato_stage4_plant_only.png",
	],
	"pumpkin": [
		ROOT + "/seed_stage0_plant_only.png",
		ROOT + "/pumpkin_stage1_plant_only.png",
		ROOT + "/pumpkin_stage2_plant_only.png",
		ROOT + "/pumpkin_stage3_plant_only.png",
		ROOT + "/pumpkin_stage4_plant_only.png",
		ROOT + "/pumpkin_stage5_plant_only.png",
	],
}

const COMMON := {
	"seed": ROOT + "/seed_stage0_plant_only.png",
	"sprout": ROOT + "/sprout_stage1_plant_only.png",
}


static func world_crop(crop_id: String, stage: int) -> Texture2D:
	if not FRAMES.has(crop_id):
		return null
	var frames: Array = FRAMES[crop_id]
	return load(String(frames[clampi(stage, 0, frames.size() - 1)])) as Texture2D


static func all_runtime_paths() -> PackedStringArray:
	var result := PackedStringArray([COMMON["seed"], COMMON["sprout"]])
	for crop_id in ["carrot", "tomato", "pumpkin"]:
		for path in FRAMES[crop_id]:
			if not result.has(String(path)):
				result.append(String(path))
	return result
