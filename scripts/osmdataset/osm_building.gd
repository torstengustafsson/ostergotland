class_name OsmBuilding
extends OsmFeature

## Building footprints from OSM: closed ways tagged building=*. Unlike a road,
## the ring *is* the ground it covers, so these are filled areas the ground
## shader paints rather than lines it strokes (see OsmGroundData).


static func feature_name() -> String:
	return "buildings"


static func accepts(way: OsmWay) -> bool:
	return way.has_tag("building")


static func from_way(_dataset: OsmDataset, way: OsmWay) -> OsmFeature:
	var b := OsmBuilding.new()
	b.way = way
	return b


## A closed building ring covers the ground inside it; an unclosed one is a
## mistake in the data, and there is nothing to fill without a ring.
func is_area() -> bool:
	return is_closed()


## The building's type as tagged, e.g. "yes", "house", "retail", "barn". Most
## ways are "yes", which says nothing beyond "a building".
func building_type() -> String:
	return get_tag("building")


## Floors, when the data has building:levels or roof:levels; 0 when it has not. Not
## used by the ground shader, which paints footprints flat, but it is what a placed
## building would be scaled by.
func levels() -> int:
	var text := get_tag("building:levels")
	if text.is_empty():
		text = get_tag("roof:levels")
	if not text.is_valid_float():
		return 0
	var count := int(text.to_float())
	return maxi(count, 0)
