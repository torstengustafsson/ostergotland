class_name OsmWaterArea
extends OsmFeature

## Water features from OSM: closed areas (natural=water, water=*) as well as
## linear watercourses (waterway=stream/river/ditch/canal/...).

## Width in metres per watercourse class, for ways without a `width` tag. A
## river is a river wide, a ditch is a ditch.
const WATERWAY_WIDTH_M := {
	"river": 12.0, "canal": 6.0, "stream": 3.0,
	"ditch": 1.0, "flowline": 1.0, "drain": 1.0,
}


static func feature_name() -> String:
	return "water"


static func accepts(way: OsmWay) -> bool:
	return way.get_tag("natural") == "water" \
		or way.has_tag("water") \
		or way.has_tag("waterway")


static func from_way(_dataset: OsmDataset, way: OsmWay) -> OsmFeature:
	var w := OsmWaterArea.new()
	w.way = way
	return w


## Coarse classification: "area" (natural=water/water=*) or "waterway".
func kind() -> String:
	if way.has_tag("natural") or way.has_tag("water"):
		return "area"
	return "waterway"


## Which tag describes the kind of water, e.g. "lake", "reservoir", "stream".
func area_type() -> String:
	if way.has_tag("water"):
		return get_tag("water")
	if way.has_tag("natural"):
		return get_tag("natural")
	return get_tag("waterway")


## True if this is a closed polygon area that should be filled (not stroked).
func is_filled_area() -> bool:
	return kind() == "area" and is_closed()


## A filled area covers the ground inside its ring, a watercourse does not.
func is_area() -> bool:
	return is_filled_area()


func is_navigable() -> bool:
	return area_type() in ["river", "canal"]


## Width of a linear watercourse in metres, from the `width` tag or the class
## default. 0.0 for a filled area, which covers the ground inside its ring instead of
## being stroked (is_filled_area()).
func width_m() -> float:
	if is_filled_area():
		return 0.0
	var tagged := explicit_width_m()
	if tagged > 0.0:
		return tagged
	return WATERWAY_WIDTH_M.get(area_type(), 0.0)
