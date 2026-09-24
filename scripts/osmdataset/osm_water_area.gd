class_name OsmWaterArea
extends OsmFeature

## Water features from OSM: closed areas (natural=water, water=*) as well as
## linear watercourses (waterway=stream/river/ditch/canal/...).

## Default stroke width in pixels for linear watercourses on base resolution.
const WATERWAY_WIDTH_PX := {
	"river": 3, "canal": 2, "stream": 2, "ditch": 1, "flowline": 1, "drain": 1,
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


func is_navigable() -> bool:
	return area_type() in ["river", "canal"]


## Stroke width in pixels when rasterizing a linear watercourse on base res.
func line_width_px() -> int:
	return WATERWAY_WIDTH_PX.get(area_type(), 1)