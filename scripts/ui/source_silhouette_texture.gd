extends RefCounted

# Read original sheet slices, keep only the central connected alpha occupant,
# and cache a cropped in-memory texture. No PNG is written or altered.
static var _cache: Dictionary = {}

static func texture(path: String) -> Texture2D:
	return record(path).get("texture") as Texture2D

static func full_texture(path: String) -> Texture2D:
	var data := record(path)
	return data.get("full_texture",data.get("texture")) as Texture2D

static func record(path: String) -> Dictionary:
	if _cache.has(path): return _cache[path]
	var source := load(path) as Texture2D
	if source==null: return {}
	var pixels := source.get_image()
	if pixels==null: return {"texture":source,"region":Rect2(Vector2.ZERO,source.get_size()),"source_size":source.get_size()}
	var width := pixels.get_width()
	var height := pixels.get_height()
	var seed := Vector2i(width/2,height/2)
	if pixels.get_pixelv(seed).a<0.03: return {"texture":source,"region":Rect2(Vector2.ZERO,source.get_size()),"source_size":source.get_size()}
	var retained := PackedByteArray()
	retained.resize(width*height)
	var pending := PackedInt32Array([seed.y*width+seed.x])
	retained[pending[0]]=1
	while not pending.is_empty():
		var index := pending[pending.size()-1]
		pending.resize(pending.size()-1)
		var point := Vector2i(index%width,index/width)
		for direction in [Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,1)]:
			var neighbor: Vector2i = point+direction
			if neighbor.x<0 or neighbor.y<0 or neighbor.x>=width or neighbor.y>=height: continue
			var next: int = neighbor.y*width+neighbor.x
			if retained[next]==1 or pixels.get_pixelv(neighbor).a<0.03: continue
			retained[next]=1
			pending.append(next)
	for y in range(height):
		for x in range(width):
			if retained[y*width+x]==0: pixels.set_pixel(x,y,Color.TRANSPARENT)
	var bounds := pixels.get_used_rect()
	var full := ImageTexture.create_from_image(pixels)
	var result := ImageTexture.create_from_image(pixels.get_region(bounds))
	var data := {"texture":result,"full_texture":full,"region":Rect2(bounds),"source_size":Vector2(width,height),"source":path,"method":"center connected alpha > 0.03; immutable in-memory cache"}
	_cache[path]=data
	return data
