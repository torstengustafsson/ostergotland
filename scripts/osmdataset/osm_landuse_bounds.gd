class_name OsmLanduseBounds
extends RefCounted

## Bounding box of an OSM landuse area (forest, wood, farmland, ...) kept in
## every space needed at runtime:
##   osm_bounds:  lon/lat extent of the area's vertices
##   pixel_rect:  the same extent on the terrain pixel grid
##   world_rect:  the same extent in world units (XZ), i.e. the Rect2
##                ForestGen.add_forest() and other placement code wants
##
## Build it from an extracted feature, e.g.
##   OsmLanduseBounds.from_feature(dataset, dataset.features["forests"][0], ...)
##
## The projection is driven by the *terrain* bounds, not the OSM download's own
## bounds: the two differ, and projecting with the wrong ones puts the area off
## the terrain. `grid_cell_size` is the terrain's world size of one pixel per
## axis, and the terrain grid is assumed centred on the world origin (as built
## by load_heightmap.gd).

var feature: OsmFeature = null
var kind: String = ""
var area_name: String = ""
var osm_bounds: OsmBounds = null
var pixel_rect: Rect2 = Rect2()
var world_rect: Rect2 = Rect2()


## Wraps `feature` and computes its bounds. `terrain_bounds` is the lon/lat
## extent of the terrain grid described by `grid_width`, `grid_height` and
## `grid_cell_size`.
static func from_feature(dataset: OsmDataset, feature: OsmFeature, terrain_bounds: OsmBounds,
		grid_width: int, grid_height: int, grid_cell_size: Vector2) -> OsmLanduseBounds:
	var area := OsmLanduseBounds.new()
	area.feature = feature
	area.area_name = feature.name()
	area.kind = _kind_of(feature)
	area.osm_bounds = feature.osm_bounds(dataset)
	area.pixel_rect = feature.pixel_rect(dataset, terrain_bounds, grid_width, grid_height)
	area.world_rect = _grid_rect_to_world(area.pixel_rect, grid_width, grid_height, grid_cell_size)
	return area


## True when the area resolved to no usable geometry.
func is_empty() -> bool:
	return pixel_rect.size.x <= 0.0 or pixel_rect.size.y <= 0.0


## The landuse/natural value the area is tagged with, e.g. "forest", "wood".
static func _kind_of(feature: OsmFeature) -> String:
	for key in ["landuse", "natural"]:
		var value := feature.get_tag(key)
		if not value.is_empty():
			return value
	return ""


## Maps a pixel rect on a grid centred on the origin to world space, keeping
## the axes: pixel x -> world X, pixel y -> world Z.
static func _grid_rect_to_world(rect: Rect2, grid_width: int, grid_height: int,
		grid_cell_size: Vector2) -> Rect2:
	var center := Vector2(float(grid_width - 1) * 0.5, float(grid_height - 1) * 0.5) * grid_cell_size
	return Rect2(rect.position * grid_cell_size - center, rect.size * grid_cell_size)
