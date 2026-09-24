class_name OsmBounds
extends RefCounted

## Lon/lat bounding box, used to project OSM coordinates onto the terrain
## grid. The terrain's actual world extent (TERRAIN_BOUNDS) may differ from
## the OSM download bounds; pass the terrain bounds to the rasterizer so OSM
## features line up with the heightmap and water mask in world space.

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


func lon_span() -> float:
	return max_lon - min_lon


func lat_span() -> float:
	return max_lat - min_lat


## Normalized 0..1 coordinates in (lon, lat) axes, ready to use as a mesh UV.
func to_uv(lon: float, lat: float) -> Vector2:
	var u := (lon - min_lon) / lon_span()
	var v := (lat - min_lat) / lat_span()
	return Vector2(u, v)


## Pixel coordinates on an image of the given size covering the bounds.
func to_pixel(lon: float, lat: float, width: int, height: int) -> Vector2i:
	var uv := to_uv(lon, lat)
	return Vector2i(
		int(clampf(uv.x, 0.0, 1.0) * float(width - 1)),
		int(clampf(uv.y, 0.0, 1.0) * float(height - 1))
	)