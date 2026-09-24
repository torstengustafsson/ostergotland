class_name OsmRoad
extends OsmFeature

## A road/street/path from OSM (ways tagged highway=*).

## Default stroke width in pixels when rasterizing a highway class that has no
## explicit `width` tag, on the base resolution (929x406).
const DEFAULT_WIDTH_PX := {
	"motorway": 3, "motorway_link": 2,
	"trunk": 3, "trunk_link": 2,
	"primary": 3, "primary_link": 2,
	"secondary": 3, "secondary_link": 2,
	"tertiary": 2, "tertiary_link": 2,
	"unclassified": 2, "residential": 2, "living_street": 2,
	"service": 1, "track": 1,
	"path": 1, "footway": 1, "cycleway": 1, "steps": 1, "platform": 1,
}

const DRIVABLE := [
	"motorway", "motorway_link",
	"trunk", "trunk_link",
	"primary", "primary_link",
	"secondary", "secondary_link",
	"tertiary", "tertiary_link",
	"unclassified", "residential", "living_street", "service",
]


static func feature_name() -> String:
	return "roads"


static func accepts(way: OsmWay) -> bool:
	return way.has_tag("highway")


static func from_way(_dataset: OsmDataset, way: OsmWay) -> OsmFeature:
	var r := OsmRoad.new()
	r.way = way
	return r


## OSM highway tag, e.g. "motorway", "residential", "footway".
func highway_class() -> String:
	return get_tag("highway")


func surface() -> String:
	return get_tag("surface")


func maxspeed() -> String:
	return get_tag("maxspeed")


func ref() -> String:
	return get_tag("ref")


func is_drivable() -> bool:
	return highway_class() in DRIVABLE


## Stroke width in pixels when drawing this road on the base-resolution grid.
func line_width_px() -> int:
	return DEFAULT_WIDTH_PX.get(highway_class(), 1)
