class_name OsmQuadtree
extends RefCounted

## Spatial index over the features extracted from an OsmDataset, so gameplay can ask
## "what is around here?" instead of walking every way in the dump.
##
## The index lives in *world* space: a Vector2 is (x, z) on the terrain, the same
## space ForestGen and OsmLanduseBounds.world_points use. The lon/lat -> world
## mapping comes from an OsmProjection built from the terrain.
##
##   var qt := OsmQuadtree.new()
##   qt.build(osm_dataset, projection)
##
##   var roads := qt.query_rect(area, "roads")        # everything touching `area`
##   var near := qt.query_circle(player_pos, 200.0)  # ...or within 200 units
##
## Queries are *complete*: a feature that touches the area is never missed. By
## default they are broad phase, i.e. a feature is returned when its world bounding
## box overlaps the area, which is cheap and slightly over-inclusive (a long
## diagonal road is reported near its bounding box corners). Pass `precise = true`
## to test the real geometry instead; that is exact and still complete.

## Entries per leaf before it is split into four children.
const MAX_ENTRIES := 8
## Depth limit, so features spanning the whole map stay in a usable node.
const MAX_DEPTH := 16

## One indexed feature: the feature itself, its group, its world bounding box and
## its world-space polyline (XZ, one point per way node, closing vertex included for
## closed ways).
class Entry extends RefCounted:
	var feature: OsmFeature = null
	var group: String = ""
	var rect: Rect2 = Rect2()
	var points: PackedVector2Array = PackedVector2Array()
	var is_area: bool = false

	func _init(p_feature: OsmFeature, p_group: String, p_rect: Rect2,
			p_points: PackedVector2Array, p_is_area: bool) -> void:
		feature = p_feature
		group = p_group
		rect = p_rect
		points = p_points
		is_area = p_is_area


## A single query, carried down the tree so the recursion does not need eight
## parameters. `circle` is set for query_circle(), which refines with the disc
## instead of the disc's bounding box.
class Query extends RefCounted:
	var rect: Rect2 = Rect2()
	var group: String = ""
	var precise: bool = false
	var circle: bool = false
	var center: Vector2 = Vector2.ZERO
	var radius: float = 0.0

	func _init(p_rect: Rect2, p_group: String, p_precise: bool) -> void:
		rect = p_rect
		group = p_group
		precise = p_precise


## The index node. A node is a leaf until it holds more than MAX_ENTRIES entries and
## is shallower than MAX_DEPTH; entries straddling a split stay in the parent, so a
## feature is stored exactly once and a query cannot return it twice. Every entry in
## a node overlaps that node's bounds.
var _bounds: Rect2 = Rect2()
var _depth: int = 0
var _entries: Array = []
var _children: Array = []
var _entry_rects: Dictionary = {}
var _entry_points: Dictionary = {}

var dataset: OsmDataset = null
var projection: OsmProjection = null
var entry_count: int = 0
var max_depth_reached: int = 0


## Indexes every feature of `dataset` (or only the given group names, e.g.
## ["roads", "water"]; empty means all groups) into a fresh tree.
func build(p_dataset: OsmDataset, p_projection: OsmProjection,
		groups: PackedStringArray = PackedStringArray()) -> void:
	clear()
	dataset = p_dataset
	projection = p_projection
	if dataset == null or not projection.is_valid():
		push_error("OsmQuadtree: needs a dataset and a valid projection")
		return

	var pending: Array = []
	var total := Rect2()
	var has_any := false
	for group in _group_names(groups):
		for feature in dataset.features.get(group, []):
			var entry := _make_entry(str(group), feature)
			if entry == null:
				continue
			pending.append(entry)
			total = entry.rect if not has_any else total.merge(entry.rect)
			has_any = true

	# The root spans the terrain, grown to reach features hanging over its edge.
	_bounds = projection.world_bounds()
	if has_any:
		_bounds = _bounds.merge(total)
	entry_count = pending.size()
	for entry in pending:
		_insert(entry)
	max_depth_reached = _deepest_depth()


## Empties the tree but keeps the dataset and projection, so the same tree can be
## rebuilt for a different area.
func clear() -> void:
	_bounds = Rect2()
	_depth = 0
	_entries = []
	_children = []
	_entry_rects = {}
	_entry_points = {}
	entry_count = 0
	max_depth_reached = 0


## Every feature whose bounding box touches `rect` (world XZ). `group` limits the
## result to one feature group, e.g. "roads"; empty means all groups. With
## `precise`, the feature's real geometry is tested instead of its bounding box.
func query_rect(rect: Rect2, group: String = "", precise: bool = false) -> Array[OsmFeature]:
	var result: Array[OsmFeature] = []
	_collect(Query.new(rect, group, precise), result)
	return result


## Every feature touching the disc of `radius` around `center` (world XZ). Uses the
## disc's bounding box as broad phase, then refines with the real geometry unless
## `precise` is false (bounding-box only, which over-reports).
func query_circle(center: Vector2, radius: float, group: String = "",
		precise: bool = true) -> Array[OsmFeature]:
	var result: Array[OsmFeature] = []
	var query := Query.new(circle_rect(center, radius), group, precise)
	query.circle = true
	query.center = center
	query.radius = radius
	_collect(query, result)
	return result


## Every feature at `position` (world XZ), i.e. whose geometry runs through the point
## or whose filled area contains it.
func query_point(position: Vector2, group: String = "", precise: bool = true) -> Array[OsmFeature]:
	return query_rect(Rect2(position, Vector2.ZERO), group, precise)


## The world bounding box of an indexed feature, or an empty Rect2 if the feature was
## never indexed.
func entry_rect(feature: OsmFeature) -> Rect2:
	return _entry_rects.get(feature, Rect2())


## The world-space polyline (XZ) of an indexed feature, or an empty array if the
## feature was never indexed. Same geometry entry_rect() bounds, unboxed: for a
## filled area this is the area's full outline, which is what placement code such
## as ForestGen wants.
func entry_points(feature: OsmFeature) -> PackedVector2Array:
	return _entry_points.get(feature, PackedVector2Array())


## The world rect the index spans: the terrain it was built for, grown to reach the
## features that hang over the terrain edge.
func world_bounds() -> Rect2:
	return _bounds


## Entry count, node count and depth, for debugging a build.
func stats() -> Dictionary:
	return {
		"entries": entry_count,
		"nodes": _count_nodes(),
		"depth": max_depth_reached,
		"max_entries": MAX_ENTRIES,
	}


## The disc's bounding box, handy for the many places that want a Rect2 anyway.
static func circle_rect(center: Vector2, radius: float) -> Rect2:
	var d := Vector2(radius, radius)
	return Rect2(center - d, d * 2.0)


## The feature groups to index: the requested ones, or all of the dataset's.
func _group_names(groups: PackedStringArray) -> PackedStringArray:
	if not groups.is_empty():
		return groups
	var names := PackedStringArray()
	for group in dataset.features.keys():
		names.append(str(group))
	return names


## Projects a feature into the index, or null when it has no usable geometry.
func _make_entry(group: String, feature: OsmFeature) -> Entry:
	var points := projection.way_points(dataset, feature.way)
	if points.is_empty():
		return null
	var rect := _points_rect(points)
	_entry_rects[feature] = rect
	_entry_points[feature] = points
	return Entry.new(feature, group, rect, points, feature.is_area())


static func _points_rect(points: PackedVector2Array) -> Rect2:
	var rect := Rect2(points[0], Vector2.ZERO)
	for p in points:
		rect = rect.expand(p)
	return rect


## Recursive insert; an entry only descends into a child that fully encloses it,
## otherwise it stays here and the split is undone.
func _insert(entry: Entry) -> void:
	if not _children.is_empty():
		var index := _child_index_for(entry.rect)
		if index >= 0:
			_children[index]._insert(entry)
			return
		_entries.append(entry)
		return

	_entries.append(entry)
	if _entries.size() > MAX_ENTRIES and _depth < MAX_DEPTH:
		_split()


func _split() -> void:
	if minf(_bounds.size.x, _bounds.size.y) <= 0.0:
		return
	_children = [
		_new_child(0), _new_child(1), _new_child(2), _new_child(3),
	]
	var staying: Array = []
	for entry in _entries:
		var index := _child_index_for(entry.rect)
		if index >= 0:
			_children[index]._insert(entry)
		else:
			staying.append(entry)
	_entries = staying


func _new_child(index: int) -> OsmQuadtree:
	var child := OsmQuadtree.new()
	child._bounds = _quadrant_rect(index)
	child._depth = _depth + 1
	return child


## Quadrant the rect belongs to (0..3, x bit 1, y bit 2), or -1 when it does not fit
## entirely inside any of the four.
func _child_index_for(rect: Rect2) -> int:
	var center := _bounds.position + _bounds.size * 0.5
	var index := 0
	if rect.get_center().x >= center.x:
		index |= 1
	if rect.get_center().y >= center.y:
		index |= 2
	return index if _quadrant_rect(index).encloses(rect) else -1


func _quadrant_rect(index: int) -> Rect2:
	var center := _bounds.position + _bounds.size * 0.5
	var x0 := _bounds.position.x if (index & 1) == 0 else center.x
	var y0 := _bounds.position.y if (index & 2) == 0 else center.y
	var x1 := center.x if (index & 1) == 0 else _bounds.end.x
	var y1 := center.y if (index & 2) == 0 else _bounds.end.y
	return Rect2(Vector2(x0, y0), Vector2(x1 - x0, y1 - y0))


## Collects every stored entry whose geometry (or bounding box) touches the query
## area. Nodes that do not reach into the area are skipped whole; entries kept in a
## node always overlap the node, so they are cheap to test.
func _collect(query: Query, result: Array[OsmFeature]) -> void:
	if not _overlaps(_bounds, query.rect):
		return
	if not _children.is_empty():
		for child in _children:
			child._collect(query, result)
	for entry in _entries:
		if not query.group.is_empty() and entry.group != query.group:
			continue
		if _touches(entry, query):
			result.append(entry.feature)


func _count_nodes() -> int:
	var count := 1
	for child in _children:
		count += child._count_nodes()
	return count


func _deepest_depth() -> int:
	var deepest := _depth
	for child in _children:
		deepest = maxi(deepest, child._deepest_depth())
	return deepest


static func _touches(entry: Entry, query: Query) -> bool:
	# The bounding box is both the whole answer in broad mode and a cheap reject
	# before the geometry work: a box that misses the area hides its geometry.
	if not _overlaps(entry.rect, query.rect):
		return false
	if not query.precise:
		return true
	if query.circle:
		return _touches_circle(entry, query.center, query.radius)
	# Local copies: entry.points is a property lookup plus a reference count bump
	# per access, which the per-segment loop below would pay for every vertex.
	var points := entry.points
	var count := points.size()
	if count == 0:
		return false
	for i in count - 1:
		if _segment_hits_rect(points[i], points[i + 1], query.rect):
			return true
	# A filled area can also swallow the whole rect without an edge crossing it.
	return entry.is_area and _point_in_polygon(points, query.rect.get_center())


static func _touches_circle(entry: Entry, center: Vector2, radius: float) -> bool:
	# The bounding box only got us here as part of the disc's own box, so reject
	# the corners the disc does not cover before touching geometry.
	if _rect_distance(entry.rect, center) > radius:
		return false
	var points := entry.points
	var count := points.size()
	if count == 0:
		return false
	# The disc can also sit entirely inside a filled area.
	if entry.is_area and _point_in_polygon(points, center):
		return true
	if count == 1:
		return center.distance_to(points[0]) <= radius
	for i in count - 1:
		if _distance_to_segment(center, points[i], points[i + 1]) <= radius:
			return true
	return false


## Bounding-box overlap, counting shared borders as touching.
static func _overlaps(a: Rect2, b: Rect2) -> bool:
	return a.position.x <= b.end.x and b.position.x <= a.end.x \
		and a.position.y <= b.end.y and b.position.y <= a.end.y


## Distance from a point to the nearest spot of a rect, 0 when inside it.
static func _rect_distance(rect: Rect2, p: Vector2) -> float:
	var d := (rect.get_center() - p).abs() - rect.size * 0.5
	return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length()


static func _segment_hits_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var low := a.min(b)
	var high := a.max(b)
	if low.x > rect.end.x or high.x < rect.position.x \
			or low.y > rect.end.y or high.y < rect.position.y:
		return false
	var corner := rect.position
	var opposite := rect.end
	# The rect's four edges. A segment that misses both endpoints and all four
	# edges cannot reach into the rect.
	return Geometry2D.segment_intersects_segment(a, b, corner, Vector2(opposite.x, corner.y)) != null \
		or Geometry2D.segment_intersects_segment(a, b, Vector2(opposite.x, corner.y), opposite) != null \
		or Geometry2D.segment_intersects_segment(a, b, opposite, Vector2(corner.x, opposite.y)) != null \
		or Geometry2D.segment_intersects_segment(a, b, Vector2(corner.x, opposite.y), corner) != null


## Even-odd point in polygon test, tolerant of the duplicated closing vertex.
static func _point_in_polygon(points: PackedVector2Array, p: Vector2) -> bool:
	var inside := false
	var previous := points.size() - 1
	for i in points.size():
		var a: Vector2 = points[i]
		var b: Vector2 = points[previous]
		if (a.y > p.y) != (b.y > p.y):
			var crossing := (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
			if p.x < crossing:
				inside = not inside
		previous = i
	return inside


static func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_squared := ab.length_squared()
	if length_squared <= 0.0:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / length_squared, 0.0, 1.0)
	return p.distance_to(a + ab * t)
