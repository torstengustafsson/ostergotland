class_name ForestCell
extends RefCounted

## One streaming cell's ground: the things on it that a tree may not stand on,
## and the trees that already stand in it.
##
## Both are per cell rather than per forest, and that is the point. A cell is
## what streams, so it is what is asked the question, and two forests that
## overlap in the same cell have to share one answer about where a tree may go
## -- otherwise they grow into each other.
##
## The cell also owns the **margin**. A tree may not stand closer than half the
## trunk gap to the cell's own edge, and that is what makes the gap hold across
## a cell boundary: the two cells never have to know about each other, because
## each tree keeps half a gap from the edge they share.
##
## The undergrowth planted with a stand is a third thing: kept apart by its own
## patch gap (MIN_UNDERGROWTH_GAP_M) in a grid of its own, since it has no
## trunks to grow into and grows at a tree's foot. It is also the one plant
## allowed to stand in the margin band along a cell's edge -- trees keep out of
## it to hold the trunk gap, but a band of ground with no grass in it is a bare
## lane down every cell boundary.

## The smallest distance between two trunks, in metres. The widest trunk is a
## pine's: 0.7 m at the base, one and a bit again at its widest, and an
## instance is scaled up to 1.1 -- so 0.83 m of trunk, and two of them have to
## stand 1.66 m apart not to grow into each other. 1.7 m leaves a little air.
const MIN_TRUNK_GAP_M := 1.7

## How far apart two patches of undergrowth are kept, in metres. Grass has no
## trunks to grow into each other, and a patch at a tree's foot is where grass
## grows, so undergrowth answers to this and not to the trunk gap -- holding
## every tuft 1.7 m from every other is what made a wood's floor a sparse
## lattice of tufts rather than dense grass. This is patch spacing, not a
## no-overlap rule: patches are meant to crowd and overlap, so it is kept near
## TreeGenPresetsUndergrowth.PATCH_RADIUS_M, which is what one patch covers.
const MIN_UNDERGROWTH_GAP_M := 0.35

## How far inside its own cell a tree has to stand, in metres: half the gap,
## plus a cushion. Two trees in neighbouring cells are then a whole gap apart,
## because each of them keeps half a gap from the edge they share -- and a
## little more than that, so the guarantee does not rest on the last bit of a
## float: at exactly half a gap the two trees would be 1.7 m apart to within
## rounding, and the check for the gap is a strict one.
const BORDER_MARGIN_M := MIN_TRUNK_GAP_M * 0.5 + 0.05

## How close to a road, a railway, a watercourse, a lake, a building or a field
## a plant may stand, in metres. A tree on the tarmac is a tree in the road.
## Undergrowth adds its own reach to this (can_plant_undergrowth()), because
## this is measured to the plant's origin and its body extends past that.
const CLEARANCE_M := 1.0

## How far beyond the cell the blockers are gathered from, in metres. It has to
## be more than half the widest way plus the clearance, or a wide road whose
## tarmac reaches into the cell would not be gathered and the trees standing
## on it would not know. The widest way in this extract is 40 m wide, so half
## of it plus the clearance is 21.
const GATHER_MARGIN_M := 24.0

## Side of one bucket of the tree grid, in metres. It has to be bigger than
## the trunk gap, so that every tree close enough to matter is in the nine
## buckets around a spot.
const BUCKET_M := 8.0

## The groups whose features a tree may not stand on. The water group holds
## both kinds: a lake is an area and a stream is a line of a width.
const BLOCKER_GROUPS: Array[String] = [
	"roads", "railways", "water", "buildings", "cover",
]

## The distance reported when no plant of the kind asked about stands near at
## all. It only has to be bigger than any real distance, and the cell is 32 m
## across.
const NO_PLANT := 1.0e9

## A thing on the ground a tree may not stand on. A line has a width and is
## kept off by that width plus the clearance; an area has none and is simply
## not to be stood in. The plant's own reach is added by the caller.
class Blocker extends RefCounted:
	var points: PackedVector2Array = PackedVector2Array()
	var half_width := 0.0
	var is_area := false
	var box := Rect2()

	func _init(p_points: PackedVector2Array, p_is_area: bool, p_half_width: float) -> void:
		points = p_points
		is_area = p_is_area
		half_width = p_half_width
		box = _box_of(p_points)

	static func _box_of(p_points: PackedVector2Array) -> Rect2:
		var p_box := Rect2(p_points[0], Vector2.ZERO)
		for p in p_points:
			p_box = p_box.expand(p)
		return p_box


## The cell's rectangle, and the part of it a tree may stand in.
var _rect := Rect2()
var _plant_rect := Rect2()
## The things on the ground, split by kind: a line has a width, an area has
## none.
var _lines: Array[Blocker] = []
var _areas: Array[Blocker] = []
## The trees planted in the cell, in buckets of BUCKET_M: bucket -> the trees
## in it. One grid for the whole cell, so two forests in it keep away from
## each other.
var _trees: Dictionary = {}
## The undergrowth planted in the cell, in buckets of BUCKET_M, apart from the
## trees' grid on purpose: a patch of grass is not a trunk, so it keeps its
## distance from other grass only and grows right up to a tree.
var _undergrowth: Dictionary = {}


func _init(p_rect: Rect2) -> void:
	_rect = p_rect
	_plant_rect = plant_rect(p_rect)


## The part of a cell a tree may stand in: the cell with a margin taken off
## every side.
static func plant_rect(rect: Rect2) -> Rect2:
	return rect.grow(-BORDER_MARGIN_M)


## Gathers the things on the ground around the cell that a tree may not stand
## on: the roads, the railways, the water (a lake as an area, a stream as a
## line), the buildings and the ground cover.
##
## Once per cell. The answer is the same for every forest in the cell, and
## gathering it per forest would gather it several times over.
func gather(index: OsmQuadtree) -> void:
	var rect := _rect.grow(GATHER_MARGIN_M)
	for group in BLOCKER_GROUPS:
		for feature in index.query_rect(rect, group, true):
			_add_blocker(index, feature)


## Whether a tree may stand at `spot`: inside the cell's margin, clear of
## everything on the ground, and a trunk gap away from every tree already
## planted in the cell. The margin is what makes the trunk gap hold across a
## cell boundary, so it is a rule and not something the region is cut by --
## see ForestRegion.clip().
func can_plant(spot: Vector2) -> bool:
	if not _clear_of_ground(spot, _plant_rect, 0.0):
		return false
	return nearest_tree_distance(spot) >= MIN_TRUNK_GAP_M


## Whether a patch of undergrowth may stand at `spot`: the same ground rules as
## a tree, but the **whole cell rather than the margin**, and kept a patch gap
## away from the undergrowth only -- not a trunk gap, because grass grows at a
## tree's foot.
##
## `reach_m` is how far the plant's own geometry reaches from its origin (see
## TreeGenPresetsUndergrowth.GRASS_REACH_M and friends), and it is added to the
## clearance. The clearance alone is measured to the origin, while the blades,
## fronds and lobes lean out past it: at a bare CLEARANCE_M a patch's origin is
## a metre from the water and its blades are standing in it.
##
## The whole cell is the point: the margin band along a cell edge is a tenth of
## the ground, and grass that stood clear of it would leave a bare lane down
## every cell boundary, visible from above as a grid of squares. Overlapping
## patches across a boundary are harmless -- two patches of grass do not grow
## into each other.
func can_plant_undergrowth(spot: Vector2, reach_m: float) -> bool:
	if not _clear_of_ground(spot, _rect, reach_m):
		return false
	return nearest_undergrowth_distance(spot) >= MIN_UNDERGROWTH_GAP_M


## The part of the rules that every kind of plant answers to: inside `rect` --
## the cell or the cell's margin, depending on the plant -- and clear of
## everything lying on the ground, with the plant's own reach (`reach_m`, 0 for
## a tree) standing out from its origin inside that clearance.
func _clear_of_ground(spot: Vector2, rect: Rect2, reach_m: float) -> bool:
	if not rect.has_point(spot):
		return false
	for blocker in _lines:
		if _line_blocks(blocker, spot, reach_m):
			return false
	for blocker in _areas:
		if _area_blocks(blocker, spot, reach_m):
			return false
	return true


## The distance to the nearest tree already planted in the cell, or NO_PLANT
## when there is none near. The grid is in buckets, so every tree that can be
## closer than the gap is in the nine buckets around the spot.
func nearest_tree_distance(spot: Vector2) -> float:
	return _nearest_distance(_trees, spot)


## The distance to the nearest patch of undergrowth, or NO_PLANT when there is
## none near. Same bucketed grid as the trees'; the gap it is measured against
## is MIN_UNDERGROWTH_GAP_M, which is smaller than a bucket.
func nearest_undergrowth_distance(spot: Vector2) -> float:
	return _nearest_distance(_undergrowth, spot)


func _nearest_distance(grid: Dictionary, spot: Vector2) -> float:
	var bucket := _bucket_of(spot)
	var best := NO_PLANT
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var plants: PackedVector2Array = grid.get(
					Vector2i(bucket.x + dx, bucket.y + dz), PackedVector2Array())
			for plant in plants:
				best = minf(best, spot.distance_to(plant))
	return best


## Records a tree planted in the cell, so the next one keeps its distance.
func add_tree(spot: Vector2) -> void:
	_record_plant(_trees, spot)


## Records a patch of undergrowth, so the next one keeps its distance -- from
## this and not from the trees'.
func add_undergrowth(spot: Vector2) -> void:
	_record_plant(_undergrowth, spot)


func _record_plant(grid: Dictionary, spot: Vector2) -> void:
	var bucket := _bucket_of(spot)
	var plants: PackedVector2Array = grid.get(bucket, PackedVector2Array())
	plants.append(spot)
	grid[bucket] = plants


## Whether a line blocker reaches `spot`: the line's own width, the clearance
## and the plant's reach, measured to the line itself.
static func _line_blocks(blocker: Blocker, spot: Vector2, reach_m: float) -> bool:
	var reach := blocker.half_width + CLEARANCE_M + reach_m
	if not blocker.box.grow(reach).has_point(spot):
		return false
	return _distance_to_polyline(spot, blocker.points) < reach


## Whether an area blocker reaches `spot`: inside it, or within the clearance
## and the plant's reach of its edge.
static func _area_blocks(blocker: Blocker, spot: Vector2, reach_m: float) -> bool:
	var reach := CLEARANCE_M + reach_m
	if not blocker.box.grow(reach).has_point(spot):
		return false
	if Geometry2D.is_point_in_polygon(spot, blocker.points):
		return true
	return _distance_to_polyline(spot, blocker.points) < reach


## Adds one feature to the blockers: an area if it covers the ground inside
## its ring, a line of a width if it does not.
##
## A feature with no width is not on the ground yet -- a proposed road, a
## stream of an unknown class -- and there is nothing to keep the trees off.
func _add_blocker(index: OsmQuadtree, feature: OsmFeature) -> void:
	var points := index.entry_points(feature)
	if feature.is_area():
		if points.size() < 3:
			return
		_areas.append(Blocker.new(points, true, 0.0))
		return
	if points.size() < 2:
		return
	var width := feature.width_m()
	if width <= 0.0:
		return
	_lines.append(Blocker.new(points, false, width * 0.5))


static func _distance_to_polyline(p: Vector2, points: PackedVector2Array) -> float:
	var best := INF
	for i in points.size() - 1:
		best = minf(best, _distance_to_segment(p, points[i], points[i + 1]))
	return best


static func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_squared := ab.length_squared()
	if length_squared <= 0.0:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / length_squared, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _bucket_of(spot: Vector2) -> Vector2i:
	return Vector2i(floori(spot.x / BUCKET_M), floori(spot.y / BUCKET_M))
