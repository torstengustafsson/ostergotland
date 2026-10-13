class_name OsmProjection
extends RefCounted

## The lon/lat -> terrain pixel -> world XZ projection chain, with the terrain
## parameters captured once:
##   bounds:    OsmBounds   lon/lat extent covered by the terrain grid
##   grid_size: Vector2i    grid resolution in pixels (the heightmap's size)
##   cell_size: Vector2     world size of one grid cell (the heightmap's scale)
##
## The grid is assumed centred on the world origin, as built by heightmap.gd, so
## Heightmap._grid_origin_offset() and world_origin_offset() have to stay the same
## number. World positions are Vector2(x, z).
##
## **+X is east and +Z is SOUTH.** Godot is right-handed with Y up and the camera
## looking down -Z, so a non-mirrored world needs forward (-Z) = north and right
## (+X) = east, i.e. +Z = south. Placing the grid the other way round -- what a map
## with north at the top wants -- reflects the whole world: every number stays
## right, a lon/lat round trip still returns, and the terrain and the features
## still mirror *together*, so nothing catches it except looking at where the
## player ends up facing.
##
## Unlike OsmBounds.to_pixel(), which rounds to Vector2i and clamps for rasterizing,
## this keeps full float precision and does not clamp, so spatial queries stay
## sub-cell accurate and ways that continue past the heightmap keep their real
## offset instead of piling up on the border.

var bounds: OsmBounds = null
var grid_size: Vector2i = Vector2i.ZERO
var cell_size: Vector2 = Vector2.ZERO

## Metres per world unit on each horizontal axis, i.e. the scale from world XZ to
## real metres. Scaling both axes by their own factor makes an ordinary Euclidean
## distance the real distance, so a circle stays a circle on the ground instead of
## turning into the ellipse the grid's aspect would give. (1, 1) until there is a
## valid terrain to measure against.
var metres_per_unit: Vector2 = Vector2.ONE:
	get:
		return _compute_metres_per_unit()


## `terrain_bounds` is the lon/lat extent of a terrain grid described by
## `grid_width` x `grid_height` pixels of `grid_cell_size` metres each -- in this
## world, world units. `Heightmap.bounds` and `Heightmap.cell_size` are exactly
## those two things, which is what keeps them from drifting apart.
static func from_terrain(terrain_bounds: OsmBounds, grid_width: int, grid_height: int,
		grid_cell_size: Vector2) -> OsmProjection:
	var p := OsmProjection.new()
	p.bounds = terrain_bounds
	p.grid_size = Vector2i(grid_width, grid_height)
	p.cell_size = grid_cell_size
	return p


func is_valid() -> bool:
	return bounds != null and grid_size.x > 1 and grid_size.y > 1


## The world rect the whole terrain grid covers, centred on the origin.
func world_bounds() -> Rect2:
	return Rect2(
		-world_origin_offset(),
		Vector2(float(grid_size.x - 1), float(grid_size.y - 1)) * cell_size)


## Half the grid's extent in metres, per axis. It is the *magnitude* rather than a
## position: which sign each axis gets is the mirror's business, not this
## function's, because the two axes disagree.
func world_origin_offset() -> Vector2:
	return Vector2(float(grid_size.x - 1), float(grid_size.y - 1)) * cell_size * 0.5


## Float pixel coordinates of a lon/lat position on the terrain grid.
func to_pixel(lon: float, lat: float) -> Vector2:
	var uv := bounds.to_uv(lon, lat)
	return Vector2(
		uv.x * float(grid_size.x - 1),
		uv.y * float(grid_size.y - 1))


## World XZ position of a float pixel position. The row term is *not* negated,
## because the DEM's row 0 is its northern edge and the world's +Z is south: row 0
## therefore lands at the lowest world z.
func to_world_pixel(pixel: Vector2) -> Vector2:
	return Vector2(
		pixel.x * cell_size.x - world_origin_offset().x,
		pixel.y * cell_size.y - world_origin_offset().y)


## World XZ position of a lon/lat position, i.e. lon/lat and pixel in one step.
func to_world(lon: float, lat: float) -> Vector2:
	return to_world_pixel(to_pixel(lon, lat))


## Lon/lat of a world XZ position: the inverse of to_world(), and the only way back
## out of this class. Exact rather than re-derived -- it undoes to_world_pixel()
## and to_pixel() by the same divisions. Clamping is deliberately absent, so a
## position off the terrain reports the lon/lat it would really be at rather than
## being pinned to the border, which is what makes "I have walked off the map"
## visible as a number rather than as a stuck one.
func to_lonlat(world: Vector2) -> Vector2:
	if not is_valid() or cell_size.x <= 0.0 or cell_size.y <= 0.0:
		return Vector2.ZERO
	var offset := world_origin_offset()
	var uv := Vector2(
		(world.x + offset.x) / cell_size.x,
		(world.y + offset.y) / cell_size.y) / Vector2(grid_size - Vector2i(1, 1))
	return Vector2(
		bounds.min_lon + uv.x * bounds.lon_span(),
		bounds.max_lat - uv.y * bounds.lat_span())


## World XZ as real metres from the grid's centre, the space the ground shader
## measures in. Scaling by metres per unit per axis means distances come out
## metrically right on a grid whose cells are not square in metres.
func to_metres(world: Vector2) -> Vector2:
	return world * metres_per_unit


## The inverse of to_metres(): metres from the grid's centre back to world XZ.
func from_metres(metres: Vector2) -> Vector2:
	return metres / metres_per_unit


## A way's geometry in world XZ, one point per node the dataset knows. Unknown node
## ids are skipped, so a way that lost part of its geometry does not get stretched
## towards the lon/lat origin. As everywhere else here, the closing vertex of a
## closed way is included.
func way_points(dataset: OsmDataset, way: OsmWay) -> PackedVector2Array:
	var points := PackedVector2Array()
	for ref in way.nd:
		if not dataset.has_node(ref):
			continue
		var lon_lat := dataset.node_position(ref)
		points.append(to_world(lon_lat.x, lon_lat.y))
	return points


## Same mapping for a lon/lat bounding box, e.g. OsmBounds from a feature.
func osm_bounds_to_world(osm_box: OsmBounds) -> Rect2:
	var a := to_world(osm_box.min_lon, osm_box.max_lat)
	var b := to_world(osm_box.max_lon, osm_box.min_lat)
	return Rect2(a, b - a).abs()


## Maps a pixel rect (or any rect in pixel space) to world space.
func pixel_rect_to_world(rect: Rect2) -> Rect2:
	var a := to_world_pixel(rect.position)
	var b := to_world_pixel(rect.position + rect.size)
	return Rect2(a, b - a).abs()


## Metres per world unit, worked out from the lon/lat extent the grid spans and how
## big the grid is in world units. The extent goes through the same
## OsmBounds.cell_size_m() the terrain's own scale comes from, so this is the
## reciprocal of that scale by construction: a terrain whose cell_size *is*
## cell_size_m() lands on (1, 1), i.e. a world in metres.
func _compute_metres_per_unit() -> Vector2:
	if bounds == null or grid_size.x < 2 or grid_size.y < 2:
		return Vector2.ONE
	if cell_size.x <= 0.0 or cell_size.y <= 0.0:
		return Vector2.ONE
	return bounds.cell_size_m(grid_size) / cell_size
