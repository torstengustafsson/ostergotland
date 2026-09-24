class_name OsmDataset
extends RefCounted

## Loads an OSM dump (converted to .json with osm_to_json.py, e.g.
## ways.json), keeping everything so ways can be picked by tag at runtime:
##   bounds:    OsmBounds       { min_lon, min_lat, max_lon, max_lat }
##   ways:      Array[OsmWay]   [{ id: String, nd: [node_id, ...], tags: {...} }]
##   relations: Array           raw relation dicts (kept for completeness)
##   features:  Dictionary      feature group name -> Array of OsmFeature
##                              (e.g. "roads", "water", "forests")
## Node ids are strings.
##
## Features are extracted from `ways` by the classes listed in
## `feature_classes`; each class declares its group name, its tag filter and
## its constructor (see OsmFeature). Adding a new kind of feature (railways,
## fields, power lines, ...) is: subclass OsmFeature, then append the new
## class to `feature_classes` and call extract_features() again.

var bounds: OsmBounds = null
var ways: Array[OsmWay] = []
var relations: Array = []
var features: Dictionary = {}
var feature_classes: Array = [OsmRoad, OsmWaterArea, OsmForestArea]
var _nodes: Dictionary = {}


func load(path: String) -> bool:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("OsmDataset: could not read %s" % path)
		return false

	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("OsmDataset: invalid JSON in %s" % path)
		return false

	bounds = OsmBounds.from_dict(parsed.get("bounds", {}))
	_nodes = parsed.get("nodes", {})
	relations = parsed.get("relations", [])

	ways.clear()
	for data in parsed.get("ways", []):
		if data is Dictionary:
			ways.append(OsmWay.from_dict(data))

	extract_features()
	return true


## (Re)builds `features` from `ways` using `feature_classes`. A way may end up
## in several groups if it matches several filters.
func extract_features() -> void:
	features.clear()
	for fclass in feature_classes:
		var fname: String = fclass.feature_name()
		if not features.has(fname):
			features[fname] = []
		var bucket: Array = features[fname]
		for way in ways:
			if fclass.accepts(way):
				bucket.append(fclass.from_way(self, way))


## The extracted features for a group name, e.g. get_features("roads").
## Returns an empty array if the group is unknown/empty.
func get_features(feature_name: String) -> Array:
	return features.get(feature_name, [])


## Whether a node id is known to the dataset.
func has_node(node_id: String) -> bool:
	return _nodes.has(node_id)


## Returns Vector2(lon, lat) for a node id, or Vector2.ZERO if unknown.
func node_position(node_id: String) -> Vector2:
	if not _nodes.has(node_id):
		return Vector2.ZERO
	var row: Array = _nodes[node_id]
	return Vector2(float(row[0]), float(row[1]))


## All ways carrying the given tag key (e.g. "highway", "waterway", "natural").
func ways_by_tag(key: String) -> Array[OsmWay]:
	var result: Array[OsmWay] = []
	for way in ways:
		if way.has_tag(key):
			result.append(way)
	return result


## All ways carrying a specific key=value pair (e.g. "waterway", "stream").
func ways_by_tag_value(key: String, value: String) -> Array[OsmWay]:
	var result: Array[OsmWay] = []
	for way in ways:
		if way.get_tag(key) == value:
			result.append(way)
	return result


## Returns Vector2i pixel coordinates on an image of the given size covering
## the given bounds (usually the terrain bounds, see OsmBounds).
func to_pixel(node_id: String, bounds_to_use: OsmBounds, width: int, height: int) -> Vector2i:
	var pos := node_position(node_id)
	return bounds_to_use.to_pixel(pos.x, pos.y, width, height)