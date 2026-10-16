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

## Which of the ground shader's road scans this way is drawn with, keyed by
## OsmGroundData.ROAD_LOOKS. The tags do not say "which scan", only how big the
## road is and how loose its surface is, so the split is made here and the scans
## are bound to the answers there.
##
## **`surface` beats the class, because where both are present the surface is
## the one that was surveyed.** It is also the only signal that separates a gravel
## service road from a tarmac one, since both are `highway=service` and the width
## table cannot tell them apart.
##
## The order between the two is the other half of that: an explicitly loose
## surface beats the class too, so `highway=residential` + `surface=unpaved` is a
## dirt street rather than tarmac.
const SURFACE_LOOSE := [
	"unpaved", "gravel", "fine_gravel", "compacted", "gravel_turf",
	"dirt", "dirt_track", "ground", "earth", "earth_track",
	"grass", "sand", "mud", "soil",
]

## Surfaces that are a made carriageway whatever the class says, so they
## outrank CLASS_LOOSE below. Without this the paved paths are the casualty:
## **380 ways in this extract are explicitly paved and were still drawn as gravel**,
## almost all of them `highway=path`/`footway`/`cycleway` + `surface=asphalt` —
## which is how a cycleway alongside a road is tagged, so the whole 312 of them
## came out as a dirt track beside the tarmac they share a surface with.
##
## `wood`, `metal` and `rubber` are deliberately not here: a boardwalk is not a
## carriageway at all, and asphalt is no more honest for one than gravel is.
const SURFACE_PAVED := [
	"asphalt", "paved", "pavement",
	"paving_stones", "paved_stone", "cobblestone", "unhewn_cobblestone",
	"sett", "pebblestone", "brick", "chipseal",
	"concrete", "concrete:lanes", "concrete:plates",
]

## Highway classes that are loose unless the way says otherwise, because that is
## what the tag means on its own: `highway=track` *is* an unpaved road and
## `highway=path` is not a carriageway at all. Without this, the tracks are also
## the largest group of ways in this extract (303 of 1239) and they would all come
## out as tarmac.
##
## A way that names its own surface never reaches this: SURFACE_PAVED above puts
## an asphalt path back on tarmac, and SURFACE_LOOSE takes a dirt track that
## says so. This is only the default for the ways that say nothing.
##
## `highway=platform` is deliberately not here: it is a bus stop's pad, not a
## track, and asphalt is the better guess for it.
const CLASS_LOOSE := [
	"track", "path", "footway", "cycleway", "bridleway", "steps",
	"pedestrian", "corridor",
]

## The classes wide enough to be a big road, i.e. the ones that get the coarse
## asphalt rather than the fine. RANK_MAJOR + RANK_MEDIUM: a residential street
## and a farm track are both "small", and the difference between them is the
## surface, not the size.
const CLASS_LARGE := RANK_MAJOR + RANK_MEDIUM


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


## Which road surface this way is drawn as: a key into OsmGroundData.ROAD_LOOKS.
##
## Loose first, then paved: either way a `surface` tag outranks the class, since a
## survey is worth more than a default. Only a way that says nothing about its
## surface falls back to the class, and there the split is whether the class
## *is* a carriageway. Size picks between the two asphalts, which is all that is
## left to separate them.
func surface_look() -> String:
	var surf := surface()
	if surf in SURFACE_LOOSE:
		return "gravel"
	if surf in SURFACE_PAVED:
		return _asphalt_look()
	if highway_class() in CLASS_LOOSE:
		return "gravel"
	return _asphalt_look()


## Which of the two asphalts, by the size of the road rather than anything it says
## about its surface: a track that is tarmac is still a narrow one.
func _asphalt_look() -> String:
	if highway_class() in CLASS_LARGE:
		return "asphalt_large"
	return "asphalt_small"
