class_name OsmForestArea
extends OsmFeature

## Forested land from OSM: closed polygons tagged landuse=forest or
## natural=wood. Greenery that is not forest proper (scrub, grassland,
## orchard, tree_row) is deliberately excluded.


static func feature_name() -> String:
	return "forests"


static func accepts(way: OsmWay) -> bool:
	return way.get_tag("landuse") == "forest" or way.get_tag("natural") == "wood"


static func from_way(_dataset: OsmDataset, way: OsmWay) -> OsmFeature:
	var f := OsmForestArea.new()
	f.way = way
	return f


## "forest" (managed landuse) or "wood" (natural).
func forest_kind() -> String:
	if get_tag("landuse") == "forest":
		return "forest"
	return "wood"


## Species/leaf info if tagged, e.g. "spruce", "mixed", "broadleaved".
func species() -> String:
	var species_tag := get_tag("species")
	if not species_tag.is_empty():
		return species_tag
	return get_tag("leaf_type")