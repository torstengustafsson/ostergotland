class_name TreeGenMaterialLibrary
## Caches and builds the two StandardMaterial3Ds used by TreeGenMesh:
## - bark: albedo is the tree's bark texture (or a plain color as fallback)
## - leaves: alpha-cutout, double-sided, vertex-colored, with either the leaf
##   set's own texture or a procedural leaf shape.

const DEFAULT_LEAF_TEXTURE_SIZE := 64
const LEAF_ALPHA_CUTOFF := 0.4

static var bark_material_cache: Dictionary = {}
static var leaf_material_cache: Dictionary = {}
static var procedural_leaf_texture_cache: Dictionary = {}

static func bark_material(texture: Texture2D, fallback_color: Color) -> StandardMaterial3D:
	var cache_key := _texture_key(texture, fallback_color)
	if bark_material_cache.has(cache_key):
		return bark_material_cache[cache_key]

	var material := StandardMaterial3D.new()
	material.roughness = 0.9
	if texture != null:
		material.albedo_texture = texture
		material.albedo_color = Color.WHITE
	else:
		material.albedo_color = fallback_color
	bark_material_cache[cache_key] = material
	return material


static func leaf_material(texture: Texture2D) -> StandardMaterial3D:
	var cache_key := _texture_key(texture, Color.WHITE)
	if leaf_material_cache.has(cache_key):
		return leaf_material_cache[cache_key]

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = LEAF_ALPHA_CUTOFF
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.albedo_texture = texture if texture != null else procedural_leaf_texture(2)
	leaf_material_cache[cache_key] = material
	return material


## Procedural elliptical-leaf stencil, tinted by per-vertex colors at runtime.
static func procedural_leaf_texture(shape: int) -> Texture2D:
	shape = clampi(shape, 0, 2)
	if procedural_leaf_texture_cache.has(shape):
		return procedural_leaf_texture_cache[shape]

	var image := Image.create(DEFAULT_LEAF_TEXTURE_SIZE, DEFAULT_LEAF_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	var center := Vector2(DEFAULT_LEAF_TEXTURE_SIZE * 0.5, DEFAULT_LEAF_TEXTURE_SIZE * 0.5)

	match shape:
		0: # elongated (needle-like)
			_draw_ellipse(image, center, DEFAULT_LEAF_TEXTURE_SIZE * 0.1, DEFAULT_LEAF_TEXTURE_SIZE * 0.48)
		1: # heart
			_draw_heart(image, center)
		_: # ellipse (default broad leaf)
			_draw_ellipse(image, center, DEFAULT_LEAF_TEXTURE_SIZE * 0.34, DEFAULT_LEAF_TEXTURE_SIZE * 0.44)

	var texture := ImageTexture.create_from_image(image)
	procedural_leaf_texture_cache[shape] = texture
	return texture


static func _draw_ellipse(image: Image, center: Vector2, radius_x: float, radius_y: float) -> void:
	for y in range(DEFAULT_LEAF_TEXTURE_SIZE):
		for x in range(DEFAULT_LEAF_TEXTURE_SIZE):
			var dx := (float(x) - center.x) / radius_x
			var dy := (float(y) - center.y) / radius_y
			var distance := sqrt(dx * dx + dy * dy)
			if distance <= 1.0:
				var alpha := 1.0
				if distance > 0.92:
					alpha = (1.0 - distance) / 0.08
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))


static func _draw_heart(image: Image, center: Vector2) -> void:
	var scale := 0.36
	for y in range(DEFAULT_LEAF_TEXTURE_SIZE):
		for x in range(DEFAULT_LEAF_TEXTURE_SIZE):
			var u := (float(x) - center.x) / (DEFAULT_LEAF_TEXTURE_SIZE * 0.5) / scale
			var v := (float(y) - center.y) / (DEFAULT_LEAF_TEXTURE_SIZE * 0.5) / scale
			var heart_value := pow(u * u + v * v - 1.0, 3.0) - u * u * v * v * v
			if heart_value <= 0.0:
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0))


static func _texture_key(texture: Texture2D, fallback_color: Color) -> String:
	if texture == null:
		return "color:" + fallback_color.to_html(false)
	var resource_path := texture.resource_path
	if resource_path != "":
		return "texture:" + resource_path
	return "texture:" + str(texture.get_rid())