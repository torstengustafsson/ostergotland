class_name OsmRailway
extends OsmFeature

## Railways from OSM: ways tagged railway=* (rail, tram, narrow_gauge, the
## disused and abandoned ones). Drawn like roads, i.e. stroked as lines of a
## width taken from the tags, because a railway covers its track rather than
## the ground inside a ring -- a closed loop is still just track.

## Width in metres per railway class, for ways without a `width` tag. A
## "standard" track is 3.4 m between the rails of one track; the gauge ones are
## narrower and the abandoned ones are what is left of the above.
const DEFAULT_WIDTH_M := {
	"rail": 3.4, "light_rail": 3.0, "subway": 3.4, "tram": 2.4,
	"narrow_gauge": 2.0, "monorail": 3.0, "funicular": 2.0, "miniature": 1.0,
	"preserved": 2.0, "disused": 2.0, "abandoned": 2.0, "razed": 2.0,
	"proposed": 0.0, "construction": 0.0, "platform": 0.0,
}


static func feature_name() -> String:
	return "railways"


static func accepts(way: OsmWay) -> bool:
	return way.has_tag("railway")


static func from_way(_dataset: OsmDataset, way: OsmWay) -> OsmFeature:
	var r := OsmRailway.new()
	r.way = way
	return r


## Track covers ground even when it is a ring (a loop or a headshunt), so this
## is never an area.
func is_area() -> bool:
	return false


## OSM railway tag, e.g. "rail", "tram", "narrow_gauge".
func railway_class() -> String:
	return get_tag("railway")


## Width of the track in metres, 0.0 for a class that is not track yet
## (proposed, under construction) and so has nothing to draw.
func width_m() -> float:
	var tagged := explicit_width_m()
	if tagged > 0.0:
		return tagged
	return DEFAULT_WIDTH_M.get(railway_class(), 0.0)
