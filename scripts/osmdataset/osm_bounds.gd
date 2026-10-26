class_name OsmBounds
extends RefCounted

## Lon/lat bounding box, used to project OSM coordinates onto the terrain grid.
## The terrain's own box (Heightmap.bounds, read from
## assets/heightmap/coordinates_bounds) is what has to be passed to anything that
## lines up with the heightmap in world space; ways.json's own bounds are only the
## extent of the download and differ from it by a couple of hundred metres here.
##
## It also knows the size of the terrain in metres, which is where the world scale
## comes from: cell_size_m() turns a lon/lat box and a grid resolution into the
## real-world size of one grid cell, and Heightmap uses that as its node scale.

## Metres in a degree of latitude, the same figure at every latitude. A degree of
## longitude is cos(latitude) times as long as one of latitude, which is what
## cell_size_m() works that difference out with.
const METRES_PER_DEGREE := 111_320.0

var min_lon: float = 0.0
var min_lat: float = 0.0
var max_lon: float = 0.0
var max_lat: float = 0.0


static func from_dict(data: Dictionary) -> OsmBounds:
	var b := OsmBounds.new()
	b.min_lon = float(data.get("minlon", 0.0))
	b.min_lat = float(data.get("minlat", 0.0))
	b.max_lon = float(data.get("maxlon", 0.0))
	b.max_lat = float(data.get("maxlat", 0.0))
	return b


func is_valid() -> bool:
	return lon_span() > 0.0 and lat_span() > 0.0


func lon_span() -> float:
	return max_lon - min_lon


func lat_span() -> float:
	return max_lat - min_lat


## Real-world size of one cell of a `grid_size` grid covering this box, in metres, as
## (x, z). The lon span is multiplied by cos(latitude) first, so the two axes come
## out in the same units. This is what makes the terrain the size it really is.
func cell_size_m(grid_size: Vector2i) -> Vector2:
	if not is_valid() or grid_size.x < 2 or grid_size.y < 2:
		return Vector2.ZERO
	var centre_lat := deg_to_rad((min_lat + max_lat) * 0.5)
	var east_west := lon_span() * METRES_PER_DEGREE * cos(centre_lat)
	var north_south := lat_span() * METRES_PER_DEGREE
	return Vector2(
		east_west / float(grid_size.x - 1),
		north_south / float(grid_size.y - 1))


## Normalized 0..1 coordinates in (lon, lat) axes, ready to use as a mesh UV.
##
## v runs **down** the image, i.e. v = 0 is `max_lat`, because row 0 of the DEM is
## its northern edge: the grid is stored north-up like every raster heightmap.
## Mapping v from `min_lat` instead reads the whole grid upside down, which moves
## every feature to the grid's mirror image -- the lakes end up on hillsides.
func to_uv(lon: float, lat: float) -> Vector2:
	var u := (lon - min_lon) / lon_span()
	var v := (max_lat - lat) / lat_span()
	return Vector2(u, v)


## Pixel coordinates on an image of the given size covering the bounds.
func to_pixel(lon: float, lat: float, width: int, height: int) -> Vector2i:
	var uv := to_uv(lon, lat)
	return Vector2i(
		int(clampf(uv.x, 0.0, 1.0) * float(width - 1)),
		int(clampf(uv.y, 0.0, 1.0) * float(height - 1))
	)
