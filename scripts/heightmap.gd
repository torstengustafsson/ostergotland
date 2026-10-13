class_name Heightmap
extends StaticBody3D

## Terrain streamed from the heightmap EXR as square tiles around a focus point.
##
## **One world unit is one metre on all three axes.** The node's X/Z scale comes
## from the DEM's own lon/lat extent (see OsmBounds.cell_size_m) and its Y scale
## is HEIGHT_SCALE, so nothing here hardcodes a scale.
##
## Row 0 of the grid is the northern edge and sits at the **lowest** world Z: +X is
## east and +Z is south, the same convention OsmProjection uses. Several places
## below depend on it; see the mirror notes on _build_shape, _normal_at,
## _build_mesh and _tile_world_rect.
##
## A tile's mesh is TILE_SIZE + 1 columns so neighbours share the vertices of
## their common edge, its collision shape is one cell wider again so shapes
## overlap, and its normals come from the analytic height-field gradient rather
## than SurfaceTool.generate_normals(), which would light shared edges
## differently and draw the tile grid onto the landscape.

const SOURCE_PATH := "res://assets/heightmap/output_hh.exr"
## The DEM's lon/lat extent, the georeferencing the EXR itself does not carry.
const BOUNDS_PATH := "res://assets/heightmap/coordinates_bounds"
## Metres per raw height value: the EXR holds millimetres, so this is what turns
## a raw value into a real elevation. Nothing else may divide the raw values.
const HEIGHT_NORMALIZATION := 1000.0
## World height of a fully normalized (1.0) value, i.e. the node's Y scale. 1.0
## is real-world metres with no exaggeration; _normal_at() scales its 2.0 by it
## so the lighting follows.
const HEIGHT_SCALE := 1.0

## Source pixels per tile edge. 64 is about a kilometre east-west here, which
## keeps a tile's build down to a few milliseconds.
const TILE_SIZE := 64
## Tiles are built inside LOAD_RADIUS of the focus and freed past UNLOAD_RADIUS,
## the larger of the two so a tile on the rim of the disc is not rebuilt every
## frame.
##
## LOAD_RADIUS is the view distance in metres and what the frame budget scales
## with; the cost is linear in its area. main.gd derives the camera's far plane
## from it so the disc's edge stays off screen.
const LOAD_RADIUS := 2500.0
const UNLOAD_RADIUS := 3200.0

## Mesh vertices per source pixel for tiles further than LOD_DISTANCE away, and
## how far that is. Coarse tiles are a quarter of the vertices, and a coarse
## tile keeps its coarse mesh until it comes this much closer again (a multiple
## of LOD_DISTANCE), so a tile on the boundary is not rebuilt every step.
const LOD_STRIDE := 2
const LOD_DISTANCE := 700.0
const LOD_HYSTERESIS := 1.35

## World height range the shader fades ground_color into hill_color over, in
## metres. The grid's highest point is about 154.2 m.
const MIN_HEIGHT := 0.0
const MAX_HEIGHT := 160.0

## One built tile: the mesh and the collision shape, both at the tile's centre
## in this node's local (unscaled) space.
class Tile extends RefCounted:
	var mesh_instance: MeshInstance3D = null
	var collision_shape: CollisionShape3D = null
	## Source pixels between this tile's mesh vertices: 1 is full resolution, 2 is
	## the coarse LOD. Its collision shape is always full resolution.
	var stride: int = 1

	func _init(p_mesh_instance: MeshInstance3D, p_collision_shape: CollisionShape3D,
			p_stride: int = 1) -> void:
		mesh_instance = p_mesh_instance
		collision_shape = p_collision_shape
		stride = p_stride


## Source grid size in pixels, read from the EXR. The whole grid, not the loaded
## part of it, so main.gd can build the projection from it directly.
var width: int = 0
var height: int = 0
## The grid's lon/lat extent, as shipped with the DEM. Public because the OSM
## features have to be projected through the terrain's own extent rather than
## the OSM download's, which is a slightly different box.
var bounds: OsmBounds = null
## World size of one source cell as (x, z), i.e. the node's X and Z scale, in
## metres. Derived from `bounds` once the EXR has been read, so it is zero until
## then; nothing may read `scale` before _ready() has run.
var cell_size: Vector2 = Vector2.ZERO
## Tiles currently in the scene, keyed by their tile coordinate.
var tiles: Dictionary = {}
## Node the terrain is streamed after, set by set_stream_target().
var target: Node3D = null

var _heights: PackedFloat32Array = PackedFloat32Array()
## Floats per source pixel in _heights; 1 for the plain red float EXR.
var _channels: int = 1
var _columns: int = 0
var _rows: int = 0
## The one material every tile uses, so the shader's uniforms are shared and set
## once. Public because OsmGroundData uploads the OSM features into it.
var material: ShaderMaterial = null


func _ready() -> void:
	var start_time := Time.get_ticks_msec()
	_load_source()
	_load_bounds()
	_apply_scale()
	print("Time to load heightmap: ", str((Time.get_ticks_msec() - start_time) / 1000.0),
			" seconds")
	print("Terrain: ", width, "x", height, " px = ", _columns, "x", _rows, " tiles of ",
			TILE_SIZE, " px, streamed within ", LOAD_RADIUS, " m")
	_build_material()
	_fill_water_noise()


func _apply_scale() -> void:
	scale = Vector3(cell_size.x, HEIGHT_SCALE, cell_size.y)


func _process(_delta: float) -> void:
	if target != null and is_instance_valid(target):
		update_stream(target.global_position)


## Streams the terrain after `node` from now on, and builds the tiles around it
## right away, so anything placing things on the ground in the same frame finds
## terrain to raycast against.
func set_stream_target(node: Node3D) -> void:
	target = node
	if node == null:
		return
	var start_time := Time.get_ticks_msec()
	var built := update_stream(node.global_position)
	print("Time to stream terrain around ", node.name, ": ",
			str((Time.get_ticks_msec() - start_time) / 1000.0), " seconds (", built,
			" of ", _columns * _rows, " tiles)")


## Makes the tiles around `focus` (world space) exist and drops the ones too far
## away, building the new ones nearest first. Safe to call every frame: it only
## touches what moved in or out of range.
func update_stream(focus: Vector3) -> int:
	if width <= 0:
		return 0

	var focus_xz := Vector2(focus.x, focus.z)
	var wanted: Array[Vector2i] = []
	for tj in _rows:
		for ti in _columns:
			var key := Vector2i(ti, tj)
			# In world metres, not source pixels: the two axes are a different
			# number of metres per cell, so one radius measured in pixels would
			# load twice as far east-west as north-south.
			var distance := _rect_distance(_tile_world_rect(key), focus_xz)
			var built := -1
			if tiles.has(key):
				built = tiles[key].stride
			var stride := _stride_for(distance, built)
			if distance <= LOAD_RADIUS:
				if tiles.has(key):
					# Only rebuilt when it crosses the LOD boundary.
					if tiles[key].stride != stride:
						_free_tile(key)
						wanted.append(key)
				else:
					wanted.append(key)
			elif distance > UNLOAD_RADIUS and tiles.has(key):
				_free_tile(key)

	# Nearest first, so the ground under the focus exists before the far rim of
	# the disc after a long jump.
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _rect_distance(_tile_world_rect(a), focus_xz) \
				< _rect_distance(_tile_world_rect(b), focus_xz))
	for key in wanted:
		_build_tile(key, _stride_for(_rect_distance(_tile_world_rect(key), focus_xz), -1))
	return wanted.size()


## The mesh resolution a tile at `distance` should have. `built` is its current
## stride, or -1 if it is not loaded yet; carrying it is what makes the band
## between the two thresholds a "leave it alone" rather than two rules that
## contradict each other, which would rebuild every tile in the band every frame.
func _stride_for(distance: float, built: int) -> int:
	if distance < LOD_DISTANCE:
		return 1
	if distance > LOD_DISTANCE * LOD_HYSTERESIS:
		return LOD_STRIDE
	return LOD_STRIDE if built <= 1 else built


## Loaded tiles and the grid they come from, for debugging.
func stats() -> Dictionary:
	return {
		"source": Vector2i(width, height),
		"tiles_loaded": tiles.size(),
		"tiles_total": _columns * _rows,
		"tile_size_px": TILE_SIZE,
		"cell_size": cell_size,
		"lod_tiles": _lod_tiles(),
	}


func _lod_tiles() -> int:
	var n := 0
	for tile in tiles.values():
		if tile.stride > 1:
			n += 1
	return n


## World XZ position as source pixel coordinates (float, outside the grid where
## the position is off the terrain). The inverse of what the tile meshes do.
func world_to_pixel(world: Vector3) -> Vector2:
	return Vector2(
		world.x / cell_size.x + (width - 1) * 0.5,
		world.z / cell_size.y + (height - 1) * 0.5)


## Terrain height at a world position, in metres. Needs no physics, so it works
## anywhere on the grid; placement that must match the collider should raycast,
## since that is what the physics engine sees.
func height_at_world(world: Vector3) -> float:
	var pixel := world_to_pixel(world)
	return _height(
		clampi(roundi(pixel.x), 0, width - 1),
		clampi(roundi(pixel.y), 0, height - 1))


## Reads the EXR into _heights once. The image itself is not kept.
func _load_source() -> void:
	var img := Image.load_from_file(SOURCE_PATH)
	if img == null:
		push_error("Heightmap: could not read %s" % SOURCE_PATH)
		return
	img.convert(Image.FORMAT_RF)
	width = img.get_width()
	height = img.get_height()
	_heights = img.get_data().to_float32_array()
	_channels = maxi(1, _heights.size() / maxi(1, width * height))
	_columns = (width + TILE_SIZE - 1) / TILE_SIZE
	_rows = (height + TILE_SIZE - 1) / TILE_SIZE
	img = null


## Reads the grid's lon/lat extent and turns it into the size of one cell. This
## is where the horizontal world scale comes from, and the two axes differ
## because a degree of longitude is cos(latitude) times as long as a degree of
## latitude, so a cell here is 16.1 m by 30.9 m rather than square.
func _load_bounds() -> void:
	bounds = OsmBounds.from_file(BOUNDS_PATH)
	if bounds == null or not bounds.is_valid():
		push_error("Heightmap: no lon/lat extent in %s, cannot scale the terrain" % BOUNDS_PATH)
		cell_size = Vector2.ONE
		return
	cell_size = bounds.cell_size_m(Vector2i(width, height))
	var extent_m := cell_size * Vector2(float(width - 1), float(height - 1))
	print("Heightmap extent: ", extent_m.x, " x ", extent_m.y, " m (",
			bounds.min_lon, ", ", bounds.min_lat, " to ", bounds.max_lon, ", ",
			bounds.max_lat, "), cell ", cell_size.x, " x ", cell_size.y, " m")


func _build_material() -> void:
	var shader: Shader = preload("res://scripts/ground.gdshader")
	material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("min_height", MIN_HEIGHT)
	material.set_shader_parameter("max_height", MAX_HEIGHT)


## Started rather than awaited, so the first tiles can be built before the noise
## exists.
func _fill_water_noise() -> void:
	var water_noise_texture := NoiseTexture3D.new()
	water_noise_texture.noise = FastNoiseLite.new()
	await water_noise_texture.changed
	material.set_shader_parameter("water_noise", water_noise_texture)


## Builds a tile's mesh and collision shape and adds both to the scene.
func _build_tile(key: Vector2i, stride: int = 1) -> void:
	var rect := _tile_rect(key)
	var x0 := int(rect.position.x)
	var y0 := int(rect.position.y)
	# TILE_SIZE + 1 columns, so a tile reaches one cell *into* its neighbour's
	# first column and the two meet on a shared edge of vertices. The last
	# column/row of the grid is a short tile when it is not a multiple of
	# TILE_SIZE + 1.
	var cols := mini(TILE_SIZE + 1, width - x0)
	var tile_rows := mini(TILE_SIZE + 1, height - y0)

	# The tile's centre in this node's local space, which is the source grid
	# shifted so the whole grid is centred on the origin, with the row index
	# counted *up* from the north edge so that world +Z is south.
	var center := Vector3(
		x0 + (cols - 1) * 0.5 - (width - 1) * 0.5, 0.0,
		(y0 + (tile_rows - 1) * 0.5) - (height - 1) * 0.5)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _build_mesh(x0, y0, cols, tile_rows, center, stride)
	mesh_instance.material_override = material
	mesh_instance.position = center
	add_child(mesh_instance)

	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = _build_shape(x0, y0, cols, tile_rows)
	collision_shape.position = center
	add_child(collision_shape)

	tiles[key] = Tile.new(mesh_instance, collision_shape, stride)


func _free_tile(key: Vector2i) -> void:
	var tile: Tile = tiles[key]
	tiles.erase(key)
	tile.mesh_instance.queue_free()
	tile.collision_shape.queue_free()


## The tile's own pixels as vertices centred on the tile, sampled from the source
## grid outside the tile where needed so a tile edge matches its neighbour's.
func _build_mesh(x0: int, y0: int, cols: int, tile_rows: int, center: Vector3,
		stride: int = 1) -> ArrayMesh:
	# `stride` samples every stride'th source pixel but still spans the full
	# cols x tile_rows, so the tile keeps reaching one cell past its neighbour's
	# first column. TILE_SIZE 64 divides by 2 and 4, so coarse tiles line up.
	var out_cols := int(ceil(float(cols - 1) / float(stride))) + 1
	var out_rows := int(ceil(float(tile_rows - 1) / float(stride))) + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(out_cols * out_rows)
	normals.resize(out_cols * out_rows)
	uvs.resize(out_cols * out_rows)
	var x_center := float(cols - 1) * 0.5
	var y_center := float(tile_rows - 1) * 0.5
	for oy in out_rows:
		for ox in out_cols:
			var i := oy * out_cols + ox
			var x := mini(ox * stride, cols - 1)
			var y := mini(oy * stride, tile_rows - 1)
			var pixel := Vector2i(x0 + x, y0 + y)
			vertices[i] = Vector3(float(x) - x_center, _height(pixel.x, pixel.y),
					float(y) - y_center)
			# From the full resolution gradient either way, so a coarse tile is lit
			# like a fine one rather than flattened where it is least noticeable.
			normals[i] = _normal_at(pixel)
			# UVs stay global (over the whole source grid); V is flipped with the
			# rows so it grows southward like the world does.
			uvs[i] = Vector2(
				float(pixel.x) / float(width - 1),
				1.0 - float(pixel.y) / float(height - 1))

	# Clockwise seen from above, so the front faces point up. The row index counts
	# *up* the z axis here, which is the same handedness the unmirrored grid has, so
	# this is the original order: the reverse renders a fully culled, invisible
	# terrain whose collision still works.
	var triangles := PackedInt32Array()
	triangles.resize((out_cols - 1) * (out_rows - 1) * 6)
	var at := 0
	for y in out_rows - 1:
		for x in out_cols - 1:
			var i0 := y * out_cols + x
			triangles[at] = i0
			triangles[at + 1] = i0 + 1
			triangles[at + 2] = i0 + out_cols
			triangles[at + 3] = i0 + 1
			triangles[at + 4] = i0 + out_cols + 1
			triangles[at + 5] = i0 + out_cols
			at += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = triangles
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The collision half of a tile: the same heights as its mesh plus one cell on
## every side, so neighbours overlap instead of meeting at a seam a raycast (or
## a falling player) could slip through. Reading outside the grid clamps to the
## border, which keeps the short tiles at the edge aligned.
##
## The rows go in in order, like the mesh's own z: the row index counts *up* the z
## axis, which is the direction a HeightMapShape3D data index already runs in.
## Reversing them puts every collision height against the wrong end of the tile.
func _build_shape(x0: int, y0: int, cols: int, tile_rows: int) -> HeightMapShape3D:
	var map_width := cols + 2
	var map_depth := tile_rows + 2
	var data := PackedFloat32Array()
	data.resize(map_width * map_depth)
	for y in map_depth:
		for x in map_width:
			var pixel := Vector2i(clampi(x0 + x - 1, 0, width - 1), clampi(y0 + y - 1, 0, height - 1))
			data[y * map_width + x] = _height(pixel.x, pixel.y)

	var shape := HeightMapShape3D.new()
	shape.map_width = map_width
	shape.map_depth = map_depth
	shape.map_data = data
	return shape


## Upward normal of the height field at a source pixel: the central difference of
## the surrounding heights, in the mesh's own (unscaled) units so the node scale
## still applies, and identical for both tiles sharing an edge.
##
## The 2.0 is 2 * HEIGHT_SCALE. A difference in X spans one cell and the node's
## X scale *is* the cell size in metres, so the cell size cancels out of the
## horizontal part and only the middle component scales with HEIGHT_SCALE.
##
## The z term is `back - front` because the row *below* the pixel is at higher
## local z: get it backwards and the normals point down.
func _normal_at(pixel: Vector2i) -> Vector3:
	var left := _height(pixel.x - 1, pixel.y)
	var right := _height(pixel.x + 1, pixel.y)
	var back := _height(pixel.x, pixel.y - 1)
	var front := _height(pixel.x, pixel.y + 1)
	return Vector3(left - right, 2.0 * HEIGHT_SCALE, back - front).normalized()


## A source pixel, clamped to the grid, as a height in metres. The single place
## the EXR's raw values are scaled, so the mesh, the collision shapes and the
## normals cannot drift apart.
func _height(x: int, y: int) -> float:
	return _heights[(clampi(y, 0, height - 1) * width + clampi(x, 0, width - 1)) * _channels] \
			/ HEIGHT_NORMALIZATION


## The tile's rectangle in source pixels (float, since the streaming code measures
## distances against it).
func _tile_rect(key: Vector2i) -> Rect2:
	return Rect2(Vector2(key.x * TILE_SIZE, key.y * TILE_SIZE),
			Vector2(TILE_SIZE, TILE_SIZE))


## World XZ of source pixel (0, 0), i.e. the grid's corner: the grid is centred on
## this node's origin, so the corner is half the grid's extent off to one side.
## The same value as OsmProjection.world_origin_offset(), which the projection
## has to agree with or the OSM features drift off the terrain.
func _grid_origin_offset() -> Vector2:
	return Vector2(float(width - 1), float(height - 1)) * cell_size * 0.5


## The same tile in world metres, the space LOAD_RADIUS is in.
##
## The origin offset is subtracted because without it the rect is measured from
## the grid's own corner, which on a 23 km grid puts even the tiles under the
## focus 6 km "away" and streams the wrong corner. The row term starts at row 0,
## the grid's northern edge, which sits at the *lowest* world z: tile row 0 covers
## the z range from -offset up to -offset plus one tile. Get it wrong and a
## mirrored disc is streamed.
func _tile_world_rect(key: Vector2i) -> Rect2:
	var tile := _tile_rect(key)
	return Rect2(
		Vector2(
			tile.position.x * cell_size.x - _grid_origin_offset().x,
			tile.position.y * cell_size.y - _grid_origin_offset().y),
		Vector2(TILE_SIZE, TILE_SIZE) * cell_size)


## Distance from a point to the nearest spot of a rect, 0 when inside it.
static func _rect_distance(rect: Rect2, point: Vector2) -> float:
	var outside := (rect.get_center() - point).abs() - rect.size * 0.5
	return Vector2(maxf(outside.x, 0.0), maxf(outside.y, 0.0)).length()
