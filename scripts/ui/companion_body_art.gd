extends RefCounted

# Measured alpha>80 connected silhouettes in the ORIGINAL 1774x887 atlas.
# AI spacing is not a regular grid: uniform quarter-cells clip feet/bleed neighbors.
const SOURCE := "res://assets/approved_world_v1/companions.png"
const DRAGON_REGIONS := {
	"water_dragon": [Vector2(1448, 1086), Rect2(67, 132, 1239, 879)],
	"fire_dragon": [Vector2(1422, 1106), Rect2(88, 71, 1274, 983)],
	"forest_dragon": [Vector2(1254, 1254), Rect2(21, 140, 1214, 978)],
	"ice_dragon": [Vector2(1254, 1254), Rect2(41, 119, 1155, 1029)],
	"gold_dragon": [Vector2(1254, 1254), Rect2(15, 115, 1216, 1025)],
	"shadow_dragon": [Vector2(1254, 1254), Rect2(25, 142, 1189, 1006)],
	"crystal_dragon": [Vector2(1254, 1254), Rect2(49, 131, 1180, 1031)],
	"rainbow_dragon": [Vector2(1254, 1254), Rect2(15, 122, 1217, 1022)]
}
const REGIONS := {
	"slime": Rect2(82, 136, 319, 297),
	"golem": Rect2(451, 58, 452, 406),
	"snake": Rect2(936, 66, 387, 405),
	"silver_fish": Rect2(1388, 157, 322, 271),
	"koi": Rect2(39, 514, 404, 267),
	"ice_fish": Rect2(494, 522, 369, 266),
	"gold_fish": Rect2(917, 525, 391, 266),
	"feeder_fish": Rect2(1368, 559, 365, 203),
}
static var _cache: Dictionary = {}

static func texture(id: String) -> Texture2D:
	if _cache.has(id): return _cache[id] as Texture2D
	var dragon := "res://assets/approved_world_v1/dragons/" + id + ".png"
	var result: Texture2D
	if ResourceLoader.exists(dragon):
		var source := load(dragon) as Texture2D
		var atlas := AtlasTexture.new()
		atlas.atlas = source
		var record: Array = DRAGON_REGIONS[id]
		var region: Rect2 = record[1]
		var imported_scale := source.get_size() / Vector2(record[0])
		atlas.region = Rect2(region.position * imported_scale, region.size * imported_scale)
		result = atlas
	elif REGIONS.has(id) and ResourceLoader.exists(SOURCE):
		var source := load(SOURCE) as Texture2D
		var atlas := AtlasTexture.new()
		atlas.atlas = source
		var region: Rect2 = REGIONS[id]
		var imported_scale := source.get_size() / Vector2(1774, 887)
		atlas.region = Rect2(region.position * imported_scale, region.size * imported_scale)
		result = atlas
	_cache[id] = result
	return result
