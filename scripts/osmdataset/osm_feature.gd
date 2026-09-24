class_name OsmFeature
extends RefCounted

## Base class for extracted OSM feature groups (roads, water, forest, ...). Each
## subclass declares a group name (the key used in OsmDataset.features), a filter
## deciding which OsmWays belong to it, and a constructor wrapping the matching way.
##
## A feature also describes itself to the ground shader by *how* it covers the
## ground, which is the pair width_m()/is_area():
##   - width_m() > 0: the way is a line of that width in metres, stroked by the
##     shader. This is how roads, railways and watercourses are drawn, so a motorway
##     really is wider than a footway.
##   - is_area(): the way is a closed polygon that covers the ground inside it,
##     filled by the shader. Buildings and lakes.
## A feature with neither is not drawn on the ground at all (forests: they are
## trees, see ForestGen).

## The source OSM way this feature wraps. Node ids are strings.
var way: OsmWay = null


## Group name under which instances land in OsmDataset.features.
static func feature_name() -> String:
	return "feature"


## Whether `way` belongs to this feature group.
static func accepts(_way: OsmWay) -> bool:
	return false


## Builds a feature instance wrapping `way`. Override to attach extra state.
static func from_way(_dataset: OsmDataset, way: OsmWay) -> OsmFeature:
	var f := OsmFeature.new()
	f.way = way
	return f


func get_tag(key: String) -> String:
	return way.get_tag(key)


func name() -> String:
	return get_tag("name")


func is_closed() -> bool:
	return way.is_closed()


## Whether the way covers a filled 2D area rather than being a line, i.e. a closed
## landuse/water polygon. Spatial queries use this to decide if a point inside the
## ring counts as a hit; line-like classes that happen to be closed (a roundabout, a
## cul-de-sac loop) must override this to false.
func is_area() -> bool:
	return is_closed()


## Width of the way in metres, for the features the ground shader strokes as lines.
## 0.0 (the default) means "not a line", either because the feature is an area or
## because the kind of way has no width on the ground. The way's own `width` tag
## wins over the per-class defaults in the subclasses.
func width_m() -> float:
	return 0.0


## How important this feature is compared to others of its kind, 0 (a path) to 2 (a
## motorway). Used by OsmGroundData to keep the bigger features when the shader's
## arrays are full, and to tint them.
func class_rank() -> int:
	return 0


## The way's own `width` tag in metres, or 0.0 when it has none or it is not a width
## in metres. OSM writes widths as a bare number ("3", "3.5") sometimes with a unit
## ("3.5 m"), but just as often imperial or a range ("12'", "3-4"), which are skipped
## rather than guessed at so the caller falls back to the class default.
func explicit_width_m() -> float:
	var text := get_tag("width")
	if text.is_empty():
		return 0.0
	if text.ends_with("m"):
		text = text.substr(0, text.length() - 1).strip_edges()
	if not text.is_valid_float():
		return 0.0
	var value := text.to_float()
	return value if value > 0.0 else 0.0


## Lon/lat bounding box of this feature's vertices. Node ids the dataset does
## not know are skipped; the result is a degenerate box if none resolve.
func osm_bounds(dataset: OsmDataset) -> OsmBounds:
	var box := OsmBounds.new()
	var found := false
	for ref in way.nd:
		if not dataset.has_node(ref):
			continue
		var pos := dataset.node_position(ref)
		if not found:
			box.min_lon = pos.x
			box.max_lon = pos.x
			box.min_lat = pos.y
			box.max_lat = pos.y
			found = true
			continue
		box.min_lon = minf(box.min_lon, pos.x)
		box.max_lon = maxf(box.max_lon, pos.x)
		box.min_lat = minf(box.min_lat, pos.y)
		box.max_lat = maxf(box.max_lat, pos.y)
	return box


## Bounding box of this feature's vertices in pixel space on an image of the
## given size covering `bounds`. Returns an empty Rect2 for unknown nodes.
func pixel_rect(dataset: OsmDataset, bounds: OsmBounds, width: int, height: int) -> Rect2:
	var pts := pixel_points(dataset, bounds, width, height)
	if pts.is_empty():
		return Rect2()
	var minv := Vector2(pts[0])
	var maxv := Vector2(pts[0])
	for p in pts:
		minv = minv.min(p)
		maxv = maxv.max(p)
	return Rect2(minv, maxv - minv)


func pixel_points(dataset: OsmDataset, bounds: OsmBounds, width: int, height: int) -> PackedVector2Array:
	return OsmRaster.pixel_points(dataset, way, bounds, width, height)
