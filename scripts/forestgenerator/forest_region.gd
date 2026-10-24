class_name ForestRegion
extends RefCounted

## One forest's share of one streaming cell: the part of its outline that falls
## inside the cell, and a way to draw a point in it.
##
## The cell clips the forest, and the clip does not come back as one polygon: a
## ring cut by a rectangle is cut into pieces -- a wood with a field in the
## middle, a cell that clips the corner of a stand -- so a region holds a list
## of them and its area is their sum.
##
## **The clip is made in world coordinates, in metres.** The projection's own
## space is degrees, and Clipper resolves to 1e-5 of the input's magnitude
## there: a degree is about a hundredth of a metre, so a cut made in degrees is
## a cut made with a centimetre's worth of precision, and the areas come out
## wrong by tens of percent. In metres the same call is exact.
##
## The area is the point of the class. The tree count used to be computed from
## the *cell*, so a cell that clipped the corner of a wood was given a whole
## cell's worth of trees to plant in that corner -- close enough together to
## grow one trunk through another.

## The forest this is a part of.
var feature: OsmFeature = null
## The pieces of the forest inside the cell, margin band included -- trees keep
## out of that band, but that is ForestCell.can_plant()'s rule, not a cut.
var polygons: Array[PackedVector2Array] = []
## The forest's area inside the cell, in m2. The plant count is computed from
## this, so the densities mean trees (or patches of undergrowth) per square
## metre of forest.
var forest_area := 0.0

## The bounding box of the pieces, and their own boxes. The fill of the first
## is what decides how many draws a sample needs: a cell that clips the corner
## of a wood can be down to a few percent of its own box.
var _box := Rect2()
var _boxes: Array[Rect2] = []
var _draws := 4


## The part of `outline` that falls inside `cell_rect`, as a region ready to
## sample, together with the area the forest covers there.
##
## The region covers the **whole cell, margin and all**. The margin is the band
## along the cell edge that trees may not stand in (ForestCell.BORDER_MARGIN_M,
## half the trunk gap per side), and that is ruled by ForestCell.can_plant()
## rather than cut out of the region here: the undergrowth samples from the same
## region and has no margin to keep, and a band of ground with no grass in it is
## a bare lane down every cell boundary -- a visible 32 m grid of squares.
##
## The area and the pieces are measured in the same pass and are the same
## number, since there is only one rect to clip against.
static func clip(p_feature: OsmFeature, outline: PackedVector2Array,
		cell_rect: Rect2) -> ForestRegion:
	var region := ForestRegion.new()
	region.feature = p_feature
	if outline.size() < 3 or cell_rect.get_area() <= 0.0:
		return region
	var first := true
	for piece in Geometry2D.intersect_polygons(outline, _ring(cell_rect)):
		if piece.size() < 3:
			continue
		var area := polygon_area(piece)
		if area <= 0.0:
			continue
		var box := _points_box(piece)
		region.polygons.append(piece)
		region._boxes.append(box)
		region.forest_area += area
		region._box = box if first else region._box.merge(box)
		first = false
	if not region.polygons.is_empty():
		region._draws = _draws_for(
				region.forest_area / maxf(region._box.get_area(), 0.0001))
	return region


## A point in the region, drawn uniformly over its area, or Vector2.INF when
## every draw missed. The draws are made in the region's own bounding box and
## rejected against its pieces, which is exact: every point of the region is as
## likely to be drawn as any other.
func sample(rng: RandomNumberGenerator) -> Vector2:
	if polygons.is_empty():
		return Vector2.INF
	for _draw in _draws:
		var spot := Vector2(rng.randf_range(_box.position.x, _box.end.x),
				rng.randf_range(_box.position.y, _box.end.y))
		for i in polygons.size():
			if not _boxes[i].has_point(spot):
				continue
			if Geometry2D.is_point_in_polygon(spot, polygons[i]):
				return spot
	return Vector2.INF


## Area of a world-XZ polygon, 0 when it has no usable geometry. Godot 4
## dropped Geometry2D.compute_polygon_area(), so this is the shoelace formula
## by hand; the last point is joined to the first, so a duplicated closing
## vertex is fine.
static func polygon_area(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var twice_area := 0.0
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		twice_area += a.x * b.y - b.x * a.y
	return absf(twice_area) * 0.5


## How many draws a sample gets. The fill is the region's area over the box the
## draws are made in, and a cell that clips the corner of a wood can be down to
## a few percent of its own box -- a fixed budget would drop trees there. The
## budget follows the fill instead: enough draws that the chance of missing
## is about one in a hundred.
static func _draws_for(fill: float) -> int:
	if fill >= 0.9 or fill <= 0.0:
		return 4
	return clampi(int(ceil(log(0.01) / log(1.0 - fill))), 4, 96)


## A rectangle as a ring of four points, which is what the clipper takes.
static func _ring(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])


static func _points_box(points: PackedVector2Array) -> Rect2:
	var box := Rect2(points[0], Vector2.ZERO)
	for p in points:
		box = box.expand(p)
	return box
