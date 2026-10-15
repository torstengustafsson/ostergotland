class_name OsmGroundCover
extends OsmFeature

## Ground cover from OSM: closed polygons tagged landuse=farmland, landuse=meadow,
## landuse=grass or natural=beach.
##
## These are the only features whose visual is a *texture* rather than a colour or
## a width, so the class has no geometry of its own to add: it exists to say which
## ground scan belongs to which polygon. cover_kind() names it in OSM's own words
## and OsmGroundData maps that to the shader's area kind and its sampler.
##
## **landuse=forest and natural=wood are not here.** They are OsmForestArea's,
## because a forest is trees (ForestGen) and a green polygon painted on the ground
## under them is not what either of them means.

static func feature_name() -> String:
	return "cover"


static func accepts(p_way: OsmWay) -> bool:
	return p_way.get_tag("landuse") in ["farmland", "meadow", "grass"] \
		or p_way.get_tag("natural") == "beach"


static func from_way(_dataset: OsmDataset, p_way: OsmWay) -> OsmFeature:
	var c := OsmGroundCover.new()
	c.way = p_way
	return c


## The tag value the polygon carries, which is what OsmGroundData looks the
## texture up by: "farmland", "meadow", "grass" or "beach".
func cover_kind() -> String:
	var landuse := get_tag("landuse")
	if not landuse.is_empty():
		return landuse
	return get_tag("natural")