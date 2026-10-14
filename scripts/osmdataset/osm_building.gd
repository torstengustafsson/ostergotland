class_name OsmBuilding
extends OsmFeature

## Building footprints from OSM: closed ways tagged building=*. Unlike a road,
## the ring *is* the ground it covers, so these are real areas rather than lines.
##
## **A building is geometry, not paint.** It used to be uploaded to the ground
## shader as a filled ring drawn flat on the terrain; it is built as walls and a
## roof by BuildingGen and streamed by BuildingStreamer now. What is left here is
## the footprint and the tags that decide what gets built from it.
##
## is_area() still matters even so: it is what makes the index test a point
## against the ring rather than against its bounding box, so a building is not
## reported as being somewhere it only touches with one corner.

static func feature_name() -> String:
	return "buildings"


static func accepts(way: OsmWay) -> bool:
	return way.has_tag("building")


static func from_way(_dataset: OsmDataset, way: OsmWay) -> OsmFeature:
	var b := OsmBuilding.new()
	b.way = way
	return b


## A closed building ring covers the ground inside it; an unclosed one is a
## mistake in the data, and there is nothing to build without a ring.
func is_area() -> bool:
	return is_closed()


## The building's type as tagged, e.g. "yes", "house", "retail", "barn". Most
## ways are "yes", which says nothing beyond "a building". BuildingGen reads this
## for its storeys and for whether it gets a pitched roof.
func building_type() -> String:
	return get_tag("building")


## Floors, when the data has building:levels or roof:levels; 0 when it has not.
## What BuildingGen scales a building by when the tag is there.
func levels() -> int:
	var text := get_tag("building:levels")
	if text.is_empty():
		text = get_tag("roof:levels")
	if not text.is_valid_float():
		return 0
	var count := int(text.to_float())
	return maxi(count, 0)
