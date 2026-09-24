class_name OsmFeature
extends RefCounted

## Base class for extracted OSM feature groups (roads, water, forest, ...).
## Each subclass declares:
##   - a feature group name (the key used in OsmDataset.features)
##   - a filter deciding which OsmWays belong to the group
##   - a constructor wrapping the matching way
## Adding a new kind of feature (railways, fields, power lines, ...) means
## subclassing OsmFeature and appending the class to
## OsmDataset.feature_classes.

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
