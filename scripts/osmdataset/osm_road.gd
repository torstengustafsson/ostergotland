class_name OsmRoad
extends OsmFeature

## A road/street/path from OSM (ways tagged highway=*).

## Width in metres per highway class, for ways without a `width` or `lanes`
## tag. Roughly what the class is on the ground: a motorway is a motorway's
## worth of tarmac, a service road is one lane plus its verges, and a path is
## barely wider than a person.
const DEFAULT_WIDTH_M := {
	"motorway": 12.0, "motorway_link": 7.0,
	"trunk": 11.0, "trunk_link": 6.0,
	"primary": 9.0, "primary_link": 6.0,
	"secondary": 8.0, "secondary_link": 5.0,
	"tertiary": 7.0, "tertiary_link": 5.0,
	"unclassified": 6.0, "residential": 6.0, "living_street": 5.0,
	"raceway": 8.0, "road": 6.0, "pedestrian": 5.0, "platform": 4.0,
	"service": 3.5, "track": 3.5,
	"path": 1.5, "footway": 1.8, "cycleway": 2.5, "bridleway": 1.5,
	"steps": 2.0, "corridor": 1.5,
}

## Width of one lane, for the `lanes` tag. A lane is a bit under 3.25 m.
const LANE_WIDTH_M := 3.25

## Highway classes big enough to keep their rank when the ground shader runs
## out of room, and the ones in between.
const RANK_MAJOR := ["motorway", "motorway_link", "trunk", "trunk_link",
	"primary", "primary_link"]
const RANK_MEDIUM := ["secondary", "secondary_link", "tertiary", "tertiary_link"]

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


static func accepts(p_way: OsmWay) -> bool:
	return p_way.has_tag("highway")


static func from_way(_dataset: OsmDataset, p_way: OsmWay) -> OsmFeature:
	var r := OsmRoad.new()
	r.way = p_way
	return r


## Roads are lines even when closed: a roundabout ring or a cul-de-sac loop does
## not cover the ground inside it, unless it says otherwise.
func is_area() -> bool:
	return get_tag("area") == "yes"


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


## Stroke width of the carriageway in metres: the way's own `width` tag wins, then
## its `lanes` tag, then the class default. This is what the ground shader strokes the
## road with, so the highway tag decides what the road looks like rather than a
## resolution-dependent raster width. A class with no width here (highway=proposed)
## returns 0.0 and is not drawn.
func width_m() -> float:
	var tagged := explicit_width_m()
	if tagged > 0.0:
		return tagged
	var lanes_tag := get_tag("lanes")
	if not lanes_tag.is_empty():
		# lanes=2, or lanes=2;3 for a carriageway counted both ways round. The
		# directional spellings (lanes:forward, lanes:backward) fall through to the
		# class default rather than counting one side twice.
		var lanes := 0.0
		for part in lanes_tag.split(";", false):
			lanes += part.to_float()
		if lanes > 0.0:
			return lanes * LANE_WIDTH_M
	return DEFAULT_WIDTH_M.get(highway_class(), 0.0)


## 2 for the trunk roads, 1 for the middle classes, 0 for the rest, so a motorway
## outranks a service road when the ground shader's arrays are full.
func class_rank() -> int:
	var highway := highway_class()
	if highway in RANK_MAJOR:
		return 2
	if highway in RANK_MEDIUM:
		return 1
	return 0
