class_name OsmGroundData
extends RefCounted

## Packs the OSM ways near the player into the flat uniform arrays
## ground.gdshader draws from. Roads, railways and water come out of the dump's
## own points and widths, so road widths come from the tags and there is no mask
## to rasterize and keep in step with the terrain.
##
## **Buildings are not here.** They were, as filled rings painted flat on the
## terrain, and they are geometry now -- see BuildingGen, which is where a
## building's shape and height live. That is the whole reason the area layer is
## water and nothing else: a filled ring is flat paint, so anything that should
## stand up cannot use it.
##
##   var ground := OsmGroundData.new()
##   ground.bind($Heightmap.material, osm_index)
##   ground.update($ProtoController.position)   # every frame is fine
##
## The arrays hold the features closest to the focus (MAX_LINES,
## MAX_AREA_EDGES) so the shader's loops stay bounded; whatever does not fit is
## not drawn at all, which is what makes the *cap* the visible distance. See
## the constants for what each size buys.
##
## Everything is uploaded in metres (OsmProjection.to_metres), so the tags are
## usable as they are: the shader measures a fragment's distance to a segment
## against half of width_m().

## Must match the four `uniform vec4 ...[n]` declarations in ground.gdshader,
## which is the only place they appear: the loops bound themselves on
## line_count / area_count. A uniform array's size has to be a literal there, so
## this is by hand -- and a resize that misses one side fails silently, drawing
## the old number's worth of features.
##
## Each entry costs 32 bytes against the device's
## LIMIT_MAX_UNIFORM_BUFFER_SIZE, so the caps are bounded by the GPU and not by
## taste. upload() keeps the *nearest* N, so the visible horizon is how far the
## marginal entry reaches, not the cap itself.
const MAX_LINES := 1408
const MAX_AREA_EDGES := 512

## Which feature an uploaded entry is; mirrored in ground.gdshader. The area
## kinds are water only, since the buildings that used to be here are geometry
## (see BuildingGen); the kind stays a per-entry value because the area layer is
## otherwise generic and the next filled kind should not mean rewriting it.
const KIND_ROAD := 0
const KIND_RAIL := 1
const KIND_WATERWAY := 2
const AREA_WATER := 1

## How far around the focus features are gathered, in metres, and how far the
## focus has to move before the arrays are rebuilt. The two together are what
## the CPU pays every REBUILD_MOVE metres of walking, and DETAIL_RADIUS only has
## to be a little past the reach the caps buy -- every candidate in the square
## costs a distance test here whether it is uploaded or not.
const DETAIL_RADIUS := 1800.0
const REBUILD_MOVE := 50.0

## Longest segment the arrays will hold, in metres (the detail square's
## diagonal). Anything longer is a way with no shape in it -- a two-node
## `waterway=flowline` 19 km apart -- and would be stroked as a straight stripe
## out to the horizon.
const MAX_SEGMENT_UNITS := DETAIL_RADIUS * 2.0 * 1.4142136

## A filled ring's own edge budget and how close a vertex may be to its own
## chord before it is worth keeping. See _simplify_ring: this is what makes a
## lake drawable at all, since a 12 km shoreline is 2594 edges and no area cap
## can hold that.
const MAX_RING_EDGES := 160
const RING_SIMPLIFY_M := 3.0
## How far a boundary may be moved by simplification before the result stops
## being a shape. Also bounds the tolerance search, and it is what makes the
## reach pre-test in _fit_ring exact: simplification only ever pulls a boundary
## inwards, so a ring whose every *vertex* is further from the focus than
## reach_m plus this cannot come into reach by being simplified.
const RING_TOLERANCE_CEILING := DETAIL_RADIUS

## Metres a feature is worth while its layer is full, by kind and per step of
## class_rank(). Only ever a tie-breaker between kinds, since the two layers are
## capped separately: a railway or a lake is a handful of features in a village
## full of roads and would otherwise never make it in.
##
## The water bonus is in metres rather than a nudge because that is what decides
## whether a lake 1.5 km away beats a shed 1 km away, and the area layer is the
## only one the two compete for.
const KIND_BONUS_M := { KIND_ROAD: 0.0, KIND_RAIL: 100.0, KIND_WATERWAY: 150.0 }
const AREA_BONUS_M := { AREA_WATER: 1200.0 }
const RANK_BONUS_M := 150.0

## One of the shader's array pairs, the candidates waiting to be chosen for it
## and the cap it uploads. `points` holds one (ax, az, bx, bz) edge in metres per
## candidate edge and `attrs` its (half_width, kind, rank), with the fourth
## component carrying the group's reach until upload and then the score slot the
## shader does not read.
##
## Candidates are *groups* of those edges -- one segment for a line layer, a
## whole ring for an area layer -- and a group is uploaded whole or not at all,
## because the shader's crossing test needs a closed ring (see _fill).
class Layer extends RefCounted:
	var points: PackedVector4Array = PackedVector4Array()
	var attrs: PackedVector4Array = PackedVector4Array()
	## Group i is points[starts[i]] .. + sizes[i], scored by scores[i].
	var starts: PackedInt32Array = PackedInt32Array()
	var sizes: PackedInt32Array = PackedInt32Array()
	var scores: PackedFloat32Array = PackedFloat32Array()
	## How far from the focus the farthest point of group i reaches, in metres.
	## This is the shader's fourth attrs component, so it can reject an entry
	## with one compare instead of measuring the segment. Uniform across a
	## group, so a ring's is the ring's own `farthest`.
	var reaches: PackedFloat32Array = PackedFloat32Array()
	var prefix: String = ""
	var limit: int = 0
	## What the last upload() put in the shader.
	var count: int = 0
	## Groups that did not fit in the last upload().
	var dropped: int = 0
	## Furthest point of anything the last upload() chose, in metres. The shader
	## skips its loops entirely past this.
	var reach: float = 0.0

	func _init(p_prefix: String, p_limit: int) -> void:
		prefix = p_prefix
		limit = p_limit

	func clear() -> void:
		points.clear()
		attrs.clear()
		starts.clear()
		sizes.clear()
		scores.clear()
		reaches.clear()
		count = 0
		dropped = 0
		reach = 0.0

	## One stroked segment, which is the whole candidate for a line layer.
	## `p_reach` is how far the focus is from the segment's farther end.
	func add_segment(a: Vector2, b: Vector2, attr: Vector4, score: float,
			p_reach: float) -> void:
		starts.append(points.size())
		sizes.append(1)
		scores.append(score)
		reaches.append(p_reach)
		points.append(Vector4(a.x, a.y, b.x, b.y))
		attrs.append(attr)

	## A whole filled ring, one vec4 per side.
	func add_ring(ring: PackedVector4Array, attr: Vector4, score: float,
			p_reach: float) -> void:
		if ring.is_empty():
			return
		starts.append(points.size())
		sizes.append(ring.size())
		scores.append(score)
		reaches.append(p_reach)
		for edge in ring:
			points.append(edge)
			attrs.append(attr)

	## Keeps the groups near the focus, best (lowest scoring) first, and skips
	## any that will not fit whole rather than truncating one. Both arrays are
	## sized to the shader's declared size whether or not they are full, so an
	## upload never leaves the shader reading stale entries.
	func upload(material: ShaderMaterial) -> void:
		var points_out := PackedVector4Array()
		var attrs_out := PackedVector4Array()
		points_out.resize(limit)
		attrs_out.resize(limit)
		var written := 0
		var taken := 0
		reach = 0.0
		for group in _order():
			var start: int = starts[group]
			var size: int = sizes[group]
			if written + size > limit:
				continue
			var attr: Vector4 = attrs[start]
			for i in size:
				points_out[written] = points[start + i]
				# The fourth component is the group's reach: a fragment further
				# from the focus than that plus the feature's own width cannot be
				# inside it, so the shader can skip it without measuring.
				attrs_out[written] = Vector4(attr.x, attr.y, attr.z, reaches[group])
				written += 1
			reach = maxf(reach, reaches[group])
			taken += 1
		count = written
		dropped = scores.size() - taken
		material.set_shader_parameter(prefix + "_points", points_out)
		material.set_shader_parameter(prefix + "_attrs", attrs_out)
		material.set_shader_parameter(prefix + "_count", count)
		material.set_shader_parameter(prefix + "_reach", reach)

	## Group indices, best first: the score is the distance to the focus less the
	## feature's bonus, so the sort is also what drops the far end of the detail
	## radius once a layer is full.
	func _order() -> Array[int]:
		var order: Array[int] = []
		order.resize(scores.size())
		for i in scores.size():
			order[i] = i
		order.sort_custom(func(a: int, b: int) -> bool:
			return scores[a] < scores[b])
		return order

## Material the arrays are uploaded to; every terrain tile shares it (see
## Heightmap.material).
var material: ShaderMaterial = null
## Where the features come from; its projection supplies the metre scale.
var index: OsmQuadtree = null
## Metres per world unit, what the shader needs to read a world position as
## metres. See OsmProjection.to_metres().
var metres_per_unit: Vector2 = Vector2.ONE
## What the layers currently hold, which is also what the shader loops over.
var lines: Layer = Layer.new("line", MAX_LINES)
var areas: Layer = Layer.new("area", MAX_AREA_EDGES)

var _focus := Vector3.ZERO
var _packed: bool = false


## Points `material`'s shader at `index`'s features. Both are needed: the
## material to upload to, and the index for the features *and* for the
## projection the metre conversion goes through.
func bind(p_material: ShaderMaterial, p_index: OsmQuadtree) -> void:
	material = p_material
	index = p_index
	metres_per_unit = Vector2.ONE
	if index != null:
		metres_per_unit = index.projection.metres_per_unit
	if material == null:
		return
	material.set_shader_parameter("metres_per_unit", metres_per_unit)
	# Nothing is gathered yet, so there is nothing to reach: a shader with no
	# features must skip its loops, not read them as covering everywhere.
	material.set_shader_parameter("focus_metres", Vector2.ZERO)
	material.set_shader_parameter("line_reach", 0.0)
	material.set_shader_parameter("area_reach", 0.0)
	lines.upload(material)
	areas.upload(material)


## Repacks the arrays around `focus` (world space) if it has moved far enough
## since the last time. Returns whether it did, and is safe to call every frame.
func update(focus: Vector3, force: bool = false) -> bool:
	if material == null or index == null:
		return false
	if _packed and not force and focus.distance_to(_focus) < REBUILD_MOVE:
		return false
	_focus = focus
	_packed = true
	_rebuild(focus)
	return true


## What the arrays hold and what did not fit, for debugging.
func stats() -> Dictionary:
	return {
		"lines": lines.count, "line_cap": MAX_LINES, "lines_dropped": lines.dropped,
		"area_edges": areas.count, "area_cap": MAX_AREA_EDGES,
		"area_edges_dropped": areas.dropped,
		"detail_radius": DETAIL_RADIUS, "rebuild_move": REBUILD_MOVE,
		"metres_per_unit": metres_per_unit,
		"focus": _focus,
	}


## Gathers every feature near `focus` and uploads the nearest ones. The query is
## a square in world units, so the larger of the two axes' scales is what bounds
## how far a candidate can be once it is in metres.
func _rebuild(focus: Vector3) -> void:
	var focus_xz := Vector2(focus.x, focus.z)
	var radius := Vector2.ONE * DETAIL_RADIUS
	var rect := Rect2(focus_xz - radius, radius * 2.0)
	var focus_m := focus_xz * metres_per_unit
	var reach_m := DETAIL_RADIUS * maxf(metres_per_unit.x, metres_per_unit.y)

	lines.clear()
	areas.clear()
	# The water group holds both, and is asked twice: width_m() and is_area() are
	# what tell a watercourse from a lake.
	_stroke(index.query_rect(rect, "roads"), KIND_ROAD, focus_m, reach_m)
	_stroke(index.query_rect(rect, "railways"), KIND_RAIL, focus_m, reach_m)
	_stroke(index.query_rect(rect, "water"), KIND_WATERWAY, focus_m, reach_m)
	_fill(index.query_rect(rect, "water"), AREA_WATER, focus_m, reach_m)

	# Where they were gathered from, so the shader can skip its loops for
	# everything past them.
	material.set_shader_parameter("focus_metres", focus_m)

	lines.upload(material)
	areas.upload(material)


## Adds one segment per polyline step for every feature in `features` that has a
## width, stroked at half of it. A feature with no width is skipped: a
## highway=proposed has nothing on the ground yet, and a lake's width_m() is 0
## because it goes into the area arrays instead.
func _stroke(features: Array[OsmFeature], kind: int, focus_m: Vector2,
		reach_m: float) -> void:
	var max_segment_m := MAX_SEGMENT_UNITS * maxf(metres_per_unit.x, metres_per_unit.y)
	for feature in features:
		var width := feature.width_m()
		if width <= 0.0:
			continue
		var points := _in_metres(index.entry_points(feature))
		var rank := float(feature.class_rank())
		var bonus: float = KIND_BONUS_M[kind] + rank * RANK_BONUS_M
		var attr := Vector4(width * 0.5, float(kind), rank, 0.0)
		for i in points.size() - 1:
			var a := points[i]
			var b := points[i + 1]
			# A two-node way kilometres long is a placeholder, not a shape, and
			# stroking it paints a perfectly straight stripe to the horizon.
			if a.distance_to(b) > max_segment_m:
				continue
			var distance := focus_m.distance_to(
					Geometry2D.get_closest_point_to_segment(focus_m, a, b))
			if distance > reach_m + attr.x:
				continue
			# The reach is the distance to the segment's far *end*, not
			# `distance`: a long way has its middle close by and its ends far out,
			# and the ends are what can still be in front of a distant fragment.
			lines.add_segment(a, b, attr, distance - bonus,
					maxf(focus_m.distance_to(a), focus_m.distance_to(b)))


## Adds a whole ring per filled area in `features`. The index's points repeat the
## closing vertex of a closed way, so a ring is size - 1 edges and the shader's
## crossing test closes it by itself.
##
## The ring goes in whole or not at all, and only if part of it is within reach.
## The crossing test counts how many ring sides a ray crosses, so one missing side
## inverts the answer everywhere it used to close the ring -- the fill then floods
## to infinity past the feature's real edge, which reads as a straight coloured
## line across the map. Skipping a ring that does not fit is the only way to keep
## that test meaningful under the cap.
##
## **Reach is measured to the ring's *nearest* side, not its farthest**, which is
## the whole question for a lake. A ring is uploaded whole either way, so nothing
## about the fill is gained by holding back its far half; what reach decides is
## whether *any* of it could be on screen, and a fragment inside a lake is inside
## it whether or not its opposite shore is 12 km away. Testing the farthest side
## instead caps a drawable area at about twice the radius -- 3.6 km across at
## DETAIL_RADIUS -- and that is exactly why Roxen (12.6 km) and Glan (9.6 km) were
## never drawn at any position on the map. The reach that *is* uploaded is still
## the farthest one, so the shader's gate stays exact for every fragment it draws.
func _fill(features: Array[OsmFeature], kind: int, focus_m: Vector2,
		reach_m: float) -> void:
	for feature in features:
		if not feature.is_area():
			continue
		var points := _fit_ring(_in_metres(index.entry_points(feature)), focus_m, reach_m)
		if points.size() < 3:
			continue
		# The kind goes in x, because that is where the shader reads it: the area
		# arrays are (kind, 0, 0, reach), unlike the line arrays' (half_width,
		# kind, rank, reach).
		var attr := Vector4(float(kind), 0.0, 0.0, 0.0)
		var bonus: float = AREA_BONUS_M[kind]
		var ring := PackedVector4Array()
		var nearest := INF
		var farthest := 0.0
		for i in points.size() - 1:
			var distance := focus_m.distance_to(
					Geometry2D.get_closest_point_to_segment(focus_m, points[i], points[i + 1]))
			nearest = minf(nearest, distance)
			farthest = maxf(farthest, distance)
			ring.append(Vector4(points[i].x, points[i].y,
					points[i + 1].x, points[i + 1].y))
		if nearest > reach_m:
			continue
		areas.add_ring(ring, attr, nearest - bonus, farthest)


## A ring's points ready for the edge loop: cut down to what the area array can
## afford, or empty if the ring cannot be in reach.
##
## The size test comes first because it is the one that decides the cost: a
## pond is a dozen edges and a small lake a few hundred, so only a ring big
## enough to need simplifying pays for either half.
static func _fit_ring(points: PackedVector2Array, focus_m: Vector2,
		reach_m: float) -> PackedVector2Array:
	if points.size() < 3 or points.size() - 1 <= MAX_RING_EDGES:
		return points
	# The reach test comes before the simplification because that is the expensive
	# half and _fill's own reach gate would throw the result away anyway.
	var nearest_vertex := INF
	for i in points.size():
		nearest_vertex = minf(nearest_vertex, focus_m.distance_to(points[i]))
	if nearest_vertex > reach_m + RING_TOLERANCE_CEILING:
		return PackedVector2Array()
	return _simplify_ring(points)


## A filled ring with its vertex count cut down to what the area array can afford,
## by Douglas-Peucker at a tolerance in metres. Returns the ring closed the way
## `_fill` wants it (first point repeated last), and returns short rings untouched.
##
## **A closed ring has to be cut in two.** Douglas-Peucker splits on the two
## endpoints of the curve, so a closed ring has none: run it on the whole loop and
## it is free to collapse half the shoreline onto the chord from first to last,
## which for a lake is a straight line across the middle of it. So the ring is cut
## in two at its two most distant points and each arc is simplified on its own,
## which also keeps the artificial closing segment `_multipolygon_ways()` adds over
## a missing way, since both split points survive by construction.
##
## **The tolerance is a starting point, not the rule.** At RING_SIMPLIFY_M a
## 2594-edge shoreline still comes out around 650 edges, which no area cap can
## hold, so it doubles until the ring is under MAX_RING_EDGES or the tolerance is
## plainly beyond saving. RING_TOLERANCE_CEILING stops it, and upload() will drop
## the ring rather than truncate it, like every other area edge.
static func _simplify_ring(points: PackedVector2Array) -> PackedVector2Array:
	var n := points.size()
	if n < 5 or n - 1 <= MAX_RING_EDGES:
		return points
	# A closed way repeats its first node last; drop the duplicate while the two
	# arcs are simplified separately and put it back at the end.
	var body := points
	if points[0] == points[n - 1]:
		body = points.slice(0, n - 1)
	if body.size() < 5:
		return points

	var split := 1
	var furthest := 0.0
	for i in body.size():
		var d: float = body[i].distance_squared_to(body[0])
		if d > furthest:
			furthest = d
			split = i

	var tolerance := RING_SIMPLIFY_M
	var out := _simplified_at(body, split, tolerance)
	while out.size() - 1 > MAX_RING_EDGES and tolerance < RING_TOLERANCE_CEILING:
		tolerance = minf(tolerance * 2.0, RING_TOLERANCE_CEILING)
		out = _simplified_at(body, split, tolerance)
	out.append(out[0])
	return out


## The two arcs either side of `split`, simplified at `tolerance` and rejoined
## into one closed ring without a repeated point.
static func _simplified_at(body: PackedVector2Array, split: int,
		tolerance: float) -> PackedVector2Array:
	var closing := body.slice(split)
	closing.append(body[0])
	var first := _douglas_peucker(body.slice(0, split + 1), tolerance)
	var second := _douglas_peucker(closing, tolerance)
	var out := first
	# `first` and `second` share both endpoints, so the joins are the two points
	# between them.
	for i in range(1, second.size() - 1):
		out.append(second[i])
	return out


## Douglas-Peucker, iterative. Recursive is the textbook form and would blow the
## stack on a 4000-point ring, which is exactly the input this exists for.
static func _douglas_peucker(points: PackedVector2Array,
		tolerance: float) -> PackedVector2Array:
	var n := points.size()
	if n < 3:
		return points
	var keep := PackedByteArray()
	keep.resize(n)
	keep[0] = 1
	keep[n - 1] = 1
	var tol_sq := tolerance * tolerance
	var stack: Array[Vector2i] = [Vector2i(0, n - 1)]
	while not stack.is_empty():
		var seg: Vector2i = stack.pop_back()
		var a := points[seg.x]
		var b := points[seg.y]
		var ab := b - a
		var len_sq := ab.length_squared()
		var worst := -1.0
		var worst_i := -1
		for i in range(seg.x + 1, seg.y):
			var p := points[i]
			var d := (p - a).length_squared()
			if len_sq > 0.0:
				var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
				d = (p - (a + ab * t)).length_squared()
			if d > worst:
				worst = d
				worst_i = i
		if worst > tol_sq:
			keep[worst_i] = 1
			stack.push_back(Vector2i(seg.x, worst_i))
			stack.push_back(Vector2i(worst_i, seg.y))
	var out := PackedVector2Array()
	for i in n:
		if keep[i]:
			out.append(points[i])
	return out


## A feature's world polyline in metres, which is the space the shader works in.
func _in_metres(points: PackedVector2Array) -> PackedVector2Array:
	var metres := PackedVector2Array()
	metres.resize(points.size())
	for i in points.size():
		metres[i] = points[i] * metres_per_unit
	return metres
