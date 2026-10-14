class_name OsmLanduseBounds
extends RefCounted

## Bounds -- and outline -- of an OSM landuse area (forest, wood, farmland, ...) kept
## in every space needed at runtime:
##   osm_bounds:   lon/lat extent of the area's vertices
##   pixel_rect:   the same extent on the terrain pixel grid
##   world_rect:   the same extent in world units (XZ)
##   world_points: the area's actual outline in world units (XZ), i.e. the polygon
##                 ForestGen and other placement code wants. The three boxes above
##                 are a simplification of it.
##
## The projection is driven by the *terrain* bounds, not the OSM download's own
## bounds: the two differ, and projecting with the wrong ones puts the area off the
## terrain.
##
## Note the asymmetry between the boxes and the outline: the boxes come from
## OsmBounds.to_pixel(), which rounds and clamps, so an area overhanging the terrain
## is squashed onto the border, while `world_points` keeps its real offset (as
## OsmQuadtree does, see OsmProjection).

var feature: OsmFeature = null
var kind: String = ""
var area_name: String = ""
var osm_bounds: OsmBounds = null
var pixel_rect: Rect2 = Rect2()
var world_rect: Rect2 = Rect2()
var world_points: PackedVector2Array = PackedVector2Array()


## Wraps `feature` and computes its bounds. `terrain_bounds` is the lon/lat
## extent of the terrain grid described by `grid_width`, `grid_height` and
## `grid_cell_size`.
static func from_feature(dataset: OsmDataset, p_feature: OsmFeature, terrain_bounds: OsmBounds,
		grid_width: int, grid_height: int, grid_cell_size: Vector2) -> OsmLanduseBounds:
	var area := OsmLanduseBounds.new()
	var projection := OsmProjection.from_terrain(
		terrain_bounds, grid_width, grid_height, grid_cell_size)
	area.feature = p_feature
	area.area_name = p_feature.name()
	area.kind = _kind_of(p_feature)
	area.osm_bounds = p_feature.osm_bounds(dataset)
	area.pixel_rect = p_feature.pixel_rect(dataset, terrain_bounds, grid_width, grid_height)
	area.world_rect = projection.pixel_rect_to_world(area.pixel_rect)
	area.world_points = projection.way_points(dataset, p_feature.way)
	return area


## True when the area resolved to no usable geometry.
func is_empty() -> bool:
	return pixel_rect.size.x <= 0.0 or pixel_rect.size.y <= 0.0


## The landuse/natural value the area is tagged with, e.g. "forest", "wood".
static func _kind_of(p_feature: OsmFeature) -> String:
	for key in ["landuse", "natural"]:
		var value := p_feature.get_tag(key)
		if not value.is_empty():
			return value
	return ""
