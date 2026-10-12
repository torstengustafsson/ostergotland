class_name OsmDataset
extends RefCounted

## Loads map data (converted to .json with osm_to_json.py, e.g. ways.json),
## keeping everything so ways can be picked by tag at runtime:
##   bounds:    OsmBounds       { min_lon, min_lat, max_lon, max_lat }
##   ways:      Array[OsmWay]   [{ id: String, nd: [node_id, ...], tags: {...} }]
##   relations: Array           raw relation dicts
##   features:  Dictionary      feature group name -> Array of OsmFeature
##                              (e.g. "roads", "railways", "buildings",
##                              "water", "forests")
## Node ids are strings.
##
## One dataset holds any number of source files: append_file() adds one with all
## its ids prefixed by the source's name, which is what stops two extracts from
## colliding on node 1. MapData does that for a whole directory; load() is the
## single-file version and replaces whatever was in the dataset.
##
## Adding a new kind of feature (fields, power lines, ...) means subclassing
## OsmFeature, appending it to `feature_classes` and calling extract_features()
## again.

var bounds: OsmBounds = null
var ways: Array[OsmWay] = []
var relations: Array = []
var features: Dictionary = {}
var feature_classes: Array = [OsmRoad, OsmRailway, OsmBuilding, OsmWaterArea, OsmForestArea]
var _nodes: Dictionary = {}
## Way id -> OsmWay, so a relation's members can be resolved without a scan.
## Built by extract_features(), which is the only thing that reads relations.
var _ways_by_id: Dictionary = {}


## Loads one source file into a dataset of its own, replacing anything already in
## it, and extracts its features. MapData appends instead, so that several files
## can share one dataset and one extraction over all of them.
func load(path: String) -> bool:
	clear()
	var result := append_file(path, "")
	if not result["ok"]:
		return false
	extract_features()
	return true


## Adds one source file's nodes, ways and relations to this dataset without
## touching `features`, so a caller can append every file first and then extract
## once. `p_prefix` (the source's name) is prepended to every id, and a prefix
## means the same thing to the nodes, the ways and the relations' member
## references, so nothing from another source can be resolved by accident.
##
## Returns `{"ok": bool, "replaces": PackedStringArray}`. `replaces` is the
## file's own list of way ids it supersedes, which MapData acts on; nothing here
## does, because a file cannot know which of the others it is replacing.
func append_file(path: String, p_prefix: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("OsmDataset: could not read %s" % path)
		return {"ok": false, "replaces": PackedStringArray()}

	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("OsmDataset: invalid JSON in %s" % path)
		return {"ok": false, "replaces": PackedStringArray()}

	var prefix := "" if p_prefix.is_empty() else p_prefix + ":"
	_merge_bounds(OsmBounds.from_dict(parsed.get("bounds", {})))
	var source_nodes: Dictionary = parsed.get("nodes", {})
	for id in source_nodes:
		_nodes[prefix + str(id)] = source_nodes[id]
	for data in parsed.get("ways", []):
		if data is Dictionary:
			ways.append(OsmWay.from_dict(data, prefix))
	for relation in parsed.get("relations", []):
		if relation is Dictionary:
			relations.append(_prefixed_relation(relation, prefix))

	var replaces := PackedStringArray()
	for entry in parsed.get("replaces", []):
		replaces.append(str(entry))
	return {"ok": true, "replaces": replaces}


## Empties the dataset, so the same object can be filled from a different set of
## sources.
func clear() -> void:
	bounds = null
	ways.clear()
	relations.clear()
	features.clear()
	_nodes.clear()
	_ways_by_id.clear()


## Union of what the sources cover, which for a single file is its own `<bounds>`.
## Only ever a record of the download(s): the terrain's extent is the DEM's, and
## is what has to be projected through.
func _merge_bounds(source: OsmBounds) -> void:
	if not source.is_valid():
		return
	if bounds == null:
		bounds = source
		return
	bounds.min_lon = minf(bounds.min_lon, source.min_lon)
	bounds.min_lat = minf(bounds.min_lat, source.min_lat)
	bounds.max_lon = maxf(bounds.max_lon, source.max_lon)
	bounds.max_lat = maxf(bounds.max_lat, source.max_lat)


## A relation with its own id and its member references prefixed, which is what
## keeps a multipolygon's members resolving to its own source's ways.
func _prefixed_relation(data: Dictionary, prefix: String) -> Dictionary:
	if prefix.is_empty():
		return data
	var out := data.duplicate()
	out["id"] = prefix + str(data.get("id", ""))
	var members: Array = []
	for member in data.get("members", []):
		if member is Dictionary:
			var prefixed: Dictionary = member.duplicate()
			prefixed["ref"] = prefix + str(member.get("ref", ""))
			members.append(prefixed)
	out["members"] = members
	return out


## (Re)builds `features` from `ways` **and from the multipolygon relations**, using
## `feature_classes`. A way may end up in several groups if it matches several
## filters.
func extract_features() -> void:
	features.clear()
	_ways_by_id.clear()
	for way in ways:
		_ways_by_id[way.id] = way
	var all_ways: Array[OsmWay] = []
	all_ways.append_array(ways)
	all_ways.append_array(_multipolygon_ways())
	for fclass in feature_classes:
		var fname: String = fclass.feature_name()
		if not features.has(fname):
			features[fname] = []
		var bucket: Array = features[fname]
		for way in all_ways:
			if fclass.accepts(way):
				bucket.append(fclass.from_way(self, way))


## Every `type=multipolygon` relation as ordinary closed ways, one per ring, each
## carrying the relation's own tags. This runs before the tag filter so the classes
## still only ever see a way, and it is what brings the big lakes in: **a lake the
## size of Roxen is a multipolygon relation in OSM, not a closed way**, so nothing
## built from `relations` directly made all 327 multipolygons here invisible.
##
## Three things make a multipolygon a multipolygon, and all three have to be undone:
##
##  - **Its member ways are open segments of the ring, not closed ways.** So there
##    is nothing to read in the order the relation lists them; they get stitched by
##    shared endpoint instead (_stitch()).
##  - **It can still be open afterwards**, because this extract is missing some
##    member ways. Rather than drop the feature, the open chain is closed by joining
##    its last point back to its first, so the boundary is closed and the shader's
##    crossing test means what it says. That segment is a straight line across the
##    gap, so the shape is an approximation of the shoreline, bounded by the two
##    real endpoints either side of it.
##  - **Holes are separate rings.** Each `inner` member chain becomes its own way
##    with the same tags, and that is what makes an island read as land: the
##    crossing test counts water edges against each other, so a point inside both the
##    lake and one of its islands crosses twice and comes out outside.
func _multipolygon_ways() -> Array[OsmWay]:
	var out: Array[OsmWay] = []
	for relation in relations:
		if not relation is Dictionary:
			continue
		var rel_tags: Dictionary = relation.get("tags", {})
		if str(rel_tags.get("type", "")) != "multipolygon":
			continue
		var outer: Array[OsmWay] = []
		var inner: Array[OsmWay] = []
		var outer_count := 0
		var inner_count := 0
		for member in relation.get("members", []):
			if not member is Dictionary or str(member.get("type", "")) != "way":
				continue
			var way: OsmWay = _ways_by_id.get(str(member.get("ref", "")), null)
			if way == null:
				continue
			if str(member.get("role", "")) == "inner":
				inner.append(way)
			else:
				outer.append(way)
		for chain in _stitch(outer):
			_ring_way(chain, rel_tags, str(relation.get("id", "")), "outer",
					outer_count, out)
			outer_count += 1
		for chain in _stitch(inner):
			_ring_way(chain, rel_tags, str(relation.get("id", "")), "inner",
					inner_count, out)
			inner_count += 1
	return out


## Joins a multipolygon's member ways into whole rings by shared endpoint, returning
## whatever chains are left. One relation normally yields one chain; several come
## back when the ways genuinely do not connect. A way may join at either end of the
## chain and in either direction, which is why each of the four combinations is
## spelled out rather than indexed.
func _stitch(segments: Array[OsmWay]) -> Array:
	var pending: Array[OsmWay] = []
	for way in segments:
		if not way.nd.is_empty():
			pending.append(way)
	var chains: Array = []
	while not pending.is_empty():
		var chain: Array[String] = pending.pop_front().nd.duplicate()
		var grew := true
		while grew and not pending.is_empty():
			grew = false
			for i in pending.size():
				var nd: Array[String] = pending[i].nd
				if chain[chain.size() - 1] == nd[0]:
					chain.append_array(nd.slice(1))
				elif chain[chain.size() - 1] == nd[nd.size() - 1]:
					chain.append_array(_reversed(nd).slice(1))
				elif chain[0] == nd[nd.size() - 1]:
					chain = nd + chain.slice(1)
				elif chain[0] == nd[0]:
					var head: Array[String] = _reversed(nd)
					head.append_array(chain.slice(1))
					chain = head
				else:
					continue
				pending.remove_at(i)
				grew = true
				break
		chains.append(chain)
	return chains


func _reversed(nd: Array[String]) -> Array[String]:
	var out: Array[String] = []
	out.resize(nd.size())
	for i in nd.size():
		out[i] = nd[nd.size() - 1 - i]
	return out


## One stitched chain as a closed OsmWay carrying the relation's tags. Closed by
## repeating the first node at the end, which is what OsmWay.is_closed() and the
## shader's crossing test both want. The id says which relation and ring this is, so
## a feature is traceable back to its source.
func _ring_way(chain: Array[String], rel_tags: Dictionary, relation_id: String,
		role: String, index: int, out: Array[OsmWay]) -> void:
	if chain.size() < 3:
		return
	var way := OsmWay.new()
	way.id = "relation:%s:%s:%d" % [relation_id, role, index]
	way.nd = chain.duplicate()
	if way.nd[0] != way.nd[way.nd.size() - 1]:
		way.nd.append(way.nd[0])
	way.tags = rel_tags.duplicate()
	out.append(way)


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


## Vector2i pixel coordinates on an image of the given size covering the given
## bounds (usually the terrain bounds, see OsmBounds).
func to_pixel(node_id: String, bounds_to_use: OsmBounds, width: int, height: int) -> Vector2i:
	var pos := node_position(node_id)
	return bounds_to_use.to_pixel(pos.x, pos.y, width, height)
