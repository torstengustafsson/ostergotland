class_name TreeGenMaterialLibrary
## Caches and builds the two materials used by TreeGenMesh:
## - bark: albedo is the tree's bark texture (or a plain color as fallback)
## - leaves: alpha-cutout, double-sided, vertex-colored, with either the leaf
##   set's own texture or a procedural leaf shape. A ShaderMaterial rather than
##   a StandardMaterial3D, because only a shader can tint a back face.

const DEFAULT_LEAF_TEXTURE_SIZE := 64
const LEAF_ALPHA_CUTOFF := 0.4

## What the pale side of every leaf is tinted with: the underside of a fern
## pinna, and the side a grass blade leans toward -- tree leaves share the
## material and the same treatment. The meshes hold no per-side colour: each
## strip is one double-sided quad carrying a single up-tilted normal, and the
## engine flips that normal for the back face, so the front face is the one
## lit by the up-tilted normal and the back face is the dark one. That is
## backwards from a real leaf, and it is what puts a pale green under the
## ferns. Measured on the scene's own sky, the front face comes out 2.1-3.9x
## the brightness of the back and takes the sky's blue; on one pinna, its
## underside renders (72, 123, 72) against its top's (38, 57, 21). This is the
## knob for it: a tint over the pale face only, and white leaves the lighting
## exactly as it was.
const UNDERSIDE_TINT := Color(0.6, 0.6, 0.6)

const LEAF_SHADER := preload("res://scripts/treegenerator/leaf.gdshader")

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


## The leaf material, one per texture (or per colour key when there is none).
## The alpha cutoff is a literal in leaf.gdshader, since a shader uniform would
## be one more thing to keep in step by hand for no gain.
static func leaf_material(texture: Texture2D) -> ShaderMaterial:
	var cache_key := _texture_key(texture, Color.WHITE)
	if leaf_material_cache.has(cache_key):
		return leaf_material_cache[cache_key]

	var material := ShaderMaterial.new()
	material.shader = LEAF_SHADER
	material.set_shader_parameter("albedo_tex",
			texture if texture != null else procedural_leaf_texture(2))
	material.set_shader_parameter("underside_tint", UNDERSIDE_TINT)
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
