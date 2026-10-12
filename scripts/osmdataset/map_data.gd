class_name MapData
extends RefCounted

## Every vector source in assets/mapdata, merged into one OsmDataset.
##
##   var map_data := MapData.new()
##   map_data.load_dir()                     # every .json in the directory
##   osm_index.build(map_data.dataset, projection)
##
## **Adding map data is dropping a file in.** Any `.json` here is loaded, in name
## order, and merged into the one dataset everything downstream already reads
## (OsmQuadtree, OsmGroundData, ForestStreamer), so there is no wiring to add.
## The shape is whatever `osm_to_json.py` writes, which is also what a hand-
## written file may use: bounds, nodes, ways and relations, with node ids as
## strings. A `.osm` file needs converting first; a `.json` one does not.
##
## **Ids are prefixed with the source's name** ("lakes:7919", not "7919"), so two
## extracts that both number their nodes from 1 cannot be mistaken for each
## other. That is also why a feature cannot be looked up by the id it has in its
## own file: the prefix is part of the id.
##
## A source may supersede another one's features by listing their ids in a
## "replaces" array -- a way id, or the id of a `type=multipolygon` relation, and
## for the latter it is what stops its rings being stitched at all. Every source
## is searched, so a listing does not care which file the id came from and
## renaming a file cannot quietly change what it matches; nothing is dropped if
## the source holding that id is not loaded, so a stale entry costs the
## replacement rather than the features it was meant to replace.
##
## Superseding rather than adding matters for filled areas in particular: the
## shader's even-odd test cancels two rings of the same kind exactly, so a lake
## drawn a second time is a lake that is not drawn.

## Where the sources live. Every `.json` directly in here is a source.
const DIRECTORY := "res://assets/mapdata"

## The merged result: one dataset holding every source's ways, nodes, relations
## and extracted features.
var dataset: OsmDataset = OsmDataset.new()
## One entry per file found, in load order: {name, path, ok, replaces, ways}.
## ways is how many ways the file itself contributed, not counting the rings
## extract_features() builds from its relations.
var sources: Array[Dictionary] = []


## Loads every `.json` in `directory`, merged and extracted. Returns whether
## anything loaded: one unreadable file is reported and skipped rather than
## leaving the rest of the map data out too.
func load_dir(directory: String = DIRECTORY) -> bool:
	dataset.clear()
	sources.clear()
	var dir := DirAccess.open(directory)
	if dir == null:
		push_error("MapData: could not open %s" % directory)
		return false

	var names := PackedStringArray()
	for file in dir.get_files():
		if file.to_lower().ends_with(".json"):
			names.append(file)
	# Name order, so the prefixes and the order sources are merged in are the
	# same from run to run.
	names.sort()

	var prefixes := PackedStringArray()
	var replaces := PackedStringArray()
	for name in names:
		var entry := _append_source("%s/%s" % [directory, name], name)
		sources.append(entry)
		if entry["ok"]:
			prefixes.append("%s:" % name.get_basename())
			for id in entry["replaces"]:
				replaces.append(id)

	_drop_replaced(replaces, prefixes)
	dataset.extract_features()
	return not sources.is_empty()


## One file into the merged dataset. A file that does not parse is an error and
## nothing else: the rest of the map data is still worth having.
func _append_source(path: String, name: String) -> Dictionary:
	var before := dataset.ways.size()
	var result := dataset.append_file(path, name.get_basename())
	var replaces: PackedStringArray = result["replaces"] if result["ok"] \
			else PackedStringArray()
	return {
		"name": name, "path": path, "ok": result["ok"],
		"replaces": replaces,
		"ways": dataset.ways.size() - before if result["ok"] else 0,
	}


## Removes the ways and relations whose prefixed id is one the sources replace.
## Relations matter as much as ways here: a multipolygon's rings are stitched in
## extract_features(), so a replaced relation stops its rings existing at all,
## which is the only way a replacement can be complete.
func _drop_replaced(replaces: PackedStringArray, prefixes: PackedStringArray) -> void:
	if replaces.is_empty():
		return
	var hidden := PackedStringArray()
	for id in replaces:
		for prefix in prefixes:
			hidden.append(prefix + id)

	var kept_ways: Array[OsmWay] = []
	for way in dataset.ways:
		if not hidden.has(way.id):
			kept_ways.append(way)
	dataset.ways = kept_ways

	var kept_relations: Array = []
	for relation in dataset.relations:
		if relation is Dictionary and not hidden.has(str(relation.get("id", ""))):
			kept_relations.append(relation)
	dataset.relations = kept_relations


## Per-source counts and the merged totals, for a load-time summary.
func stats() -> Dictionary:
	var counts := {}
	for entry in sources:
		counts[entry["name"]] = entry["ways"]
	var groups := {}
	for name in dataset.features:
		groups[name] = (dataset.features[name] as Array).size()
	return {"sources": counts, "ways": dataset.ways.size(), "groups": groups}