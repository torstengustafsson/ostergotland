class_name OsmWay
extends RefCounted

## A single OSM way: ordered node references plus tag metadata.
## Node ids are kept as strings (JSON object keys are strings).

var id: String = ""
var nd: Array[String] = []
var tags: Dictionary = {}

## The role this way had in the multipolygon relation it came from: "outer" for
## the ring that describes the shape, "inner" for a hole in it, and "" for a way
## that was not part of a relation. See OsmDataset._multipolygon_ways().
var role := ""


## `prefix` is prepended to the way's id and to every node reference, so ways
## from two sources can share a node id without being confused for each other.
## See OsmDataset.append_file.
static func from_dict(data: Dictionary, prefix: String = "") -> OsmWay:
	var way := OsmWay.new()
	way.id = prefix + str(data.get("id", ""))
	for ref in data.get("nd", []):
		way.nd.append(prefix + str(ref))
	way.tags = data.get("tags", {})
	return way


func has_tag(key: String) -> bool:
	return tags.has(key)


func get_tag(key: String) -> String:
	return str(tags.get(key, ""))


func is_closed() -> bool:
	return nd.size() > 1 and nd[0] == nd[nd.size() - 1]


## Whether this way is a hole in the shape its relation describes, i.e. an
## `inner` ring of a multipolygon. What a hole *means* is not the same for
## every group: the inner ring of a lake is an island and its interior is land,
## the inner ring of a forest is a clearing and its interior is not forest.
func is_hole() -> bool:
	return role == "inner"
