class_name BuildingGen
extends Node3D

## Builds a building as real geometry from its OSM footprint: the ring is
## extruded into walls with a flat cap, and a gable roof goes on top.
##
##   var gen := BuildingGen.new()
##   gen.bind($Heightmap)
##   var node := gen.build(feature, gen_index.entry_points(feature), seed_value)
##
## This is the half that makes buildings, and it knows nothing about which
## buildings should exist -- BuildingStreamer decides that, the way
## ForestStreamer does for trees.
##
## **Buildings are geometry where they used to be a shader fill**, so what this
## has to get right is different from what the trees have to get right. A tree is
## a known mesh instanced thousands of times; a building is a unique mesh drawn
## once, so the cost here is the mesh and not the instance count.
##
## The walls follow the actual ring, so a footprint that is not a rectangle still
## comes out right, and the roof follows it too: both are laid out on the
## footprint's own axis, taken from its longest edge, rather than on the world's.
## What is still a simplification is that the roof is a rectangle over that
## footprint rather than the footprint itself, so an L-shape gets straight eaves
## across its notch. That is a deliberate stopping point and not an oversight --
## a real hip roof has to be inset from the eaves and capped by a ridge -- and it
## is far less visible than the roof sitting at the wrong angle. Swap _roof() for
## something that takes the ring when it matters.

## Metres per storey. Storeys come from the building:levels tag when it is there
## and from the type otherwise, since most ways are tagged only building=yes.
const STOREY_M := 4.0

## Storeys per building type, for the ways with no building:levels tag. The OSM
## vocabulary is wide and most of it is missing, so the default below carries
## most of the weight; anything not listed gets DEFAULT_STOREYS.
const STOREYS_BY_TYPE := {
	"house": 1, "detached": 1, "semidetached_house": 1, "terrace": 3,
	"bungalow": 1, "hut": 1, "cabin": 1, "farm": 1,
	"garage": 1, "shed": 1, "carport": 1, "greenhouse": 1, "roof": 1,
	"barn": 2, "stable": 1, "silo": 1, "storage_tank": 1,
	"church": 1, "chapel": 1, "cathedral": 2, "hangar": 1,
	"retail": 1, "commercial": 2, "warehouse": 2, "industrial": 2,
	"office": 3, "apartments": 4, "hotel": 4, "school": 2, "university": 3,
}

## Storeys when the type says nothing: a plain house, which is what building=yes
## almost always is.
const DEFAULT_STOREYS := 1

## Roof height as a fraction of the wall height, and the bounds that keep it
## readable on both a bungalow and a four-storey block.
const ROOF_HEIGHT_RATIO := 0.35
const ROOF_HEIGHT_MIN := 1.2
const ROOF_HEIGHT_MAX := 4.0

## How far the roof overhangs the walls, in metres. A roof flush with the wall
## reads as a box, and the overhang also hides the seam where a roof meets walls
## that are not perfectly flat on the ground.
const ROOF_OVERHANG := 0.4

## The floor of how far the walls are carried below the building's own ground
## height, in metres. The base height comes from Heightmap.height_at_world(),
## which rounds to a pixel centre where the collider interpolates across the
## cell, so a building placed exactly on it can leave a visible gap. Sinking it
## hides the error rather than measuring around it.
const GROUND_SINK := 0.25

## Ceiling on the same, so a footprint straddling a cliff does not grow walls
## down to bedrock. Well past anything a real slope produces -- the steepest
## ground here moves a few metres over one footprint -- and past it the building
## is buried in a hillside anyway, so giving up the gap costs nothing.
const MAX_BURY_M := 25.0

## Ridge lengths below this are a pyramid rather than a gable: a footprint that is
## square in metres would otherwise degenerate into a zero-length ridge and two
## of the four roof faces would vanish.
const PYRAMID_RIDGE_EPS := 0.05

## A footprint smaller than this is noise in the OSM data, not a building.
const MIN_FOOTPRINT_M := 0.5

## Types that get a flat roof. Everything else gets the gable. These are the
## shapes that actually are flat, so this is a shape tag rather than a style one.
const FLAT_ROOF_TYPES := [
	"warehouse", "industrial", "retail", "commercial", "office", "apartments",
	"hotel", "hangar", "greenhouse", "storage_tank", "school",
]

## Wall and roof palettes, picked per building so a street is not one colour.
## Materials are cached by palette entry rather than per building, so the number
## of distinct ones stays at the palette size and not at the building count.
const WALL_COLORS := ["b6ada0", "a49b8f", "c4bcb0", "9c9284", "cfc7b8"]
const ROOF_COLORS := ["5c3a30", "45312a", "6b4536", "3f3a36", "70503f"]

## The terrain, for ground height. Set by bind().
var heightmap: Heightmap = null

static var _materials: Dictionary = {}


## Points the generator at the terrain it is standing on. Without it a building
## would have no ground height and build() would return nothing.
func bind(p_heightmap: Heightmap) -> void:
	heightmap = p_heightmap


## One building as a StaticBody3D carrying its mesh and a box collider, or null
## when there is no footprint to build from.
##
## `points` is the footprint's world XZ outline including the closing vertex
## (OsmQuadtree.entry_points). `seed_value` only picks the palette entry, so a
## building does not change colour if the streamer happens to rebuild it.
##
## The node sits at the footprint's centre on the ground, and the mesh is in
## local coordinates centred there, so the rotation is free for later use.
func build(feature: OsmFeature, points: PackedVector2Array,
		seed_value: int) -> Node3D:
	if heightmap == null:
		return null
	var ring := _body_ring(points)
	if ring.size() < 3:
		return null
	if _area(ring) < MIN_FOOTPRINT_M * MIN_FOOTPRINT_M:
		return null

	var building := feature as OsmBuilding
	var wall_m := _wall_height(building)
	var pitched := not _is_flat(building)

	var body := StaticBody3D.new()
	body.name = "Building"
	var centre := _centre(ring)
	body.position = Vector3(centre.x,
			heightmap.height_at_world(Vector3(centre.x, 0.0, centre.y)) - GROUND_SINK,
			centre.y)
	var bury_m := _bury_depth(ring, body.position.y)

	# The mesh is built around the origin and the node carries the world position,
	# rather than the other way round. The world here is up to 23 km from the
	# origin and a mesh vertex is a float32, so carrying the offset in the node
	# keeps the precision where it is needed.
	var local := _translate(ring, -centre)
	var axis := _ridge_axis(local)
	var along_across := _oriented_bounds(local, axis)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = _mesh(local, wall_m, _roof_height(wall_m, pitched), pitched,
			seed_value, axis, bury_m)
	body.add_child(mesh_instance)

	# A box over the footprint rather than the ring itself: the footprint is
	# nearly always convex, a convex decomposition would be absurd for a demo,
	# and the player only ever walks into the walls from outside.
	#
	# It is rotated onto the same axis as the roof. An axis-aligned box around a
	# building that is not square to the world sticks out past two of its walls,
	# which is a collision the player walks into in empty air.
	#
	# It reaches down as far as the walls do, so the collider and the mesh agree
	# about where the building is on a slope.
	var shape := CollisionShape3D.new()
	shape.name = "Collider"
	var box := BoxShape3D.new()
	box.size = Vector3(along_across.size.x, wall_m + bury_m, along_across.size.y)
	shape.shape = box
	shape.position = Vector3(0.0, (wall_m - bury_m) * 0.5, 0.0)
	# Negated because a Y rotation takes +X to (cos, 0, -sin) while a Vector2
	# here is (x, z), so the world Z is the negated one.
	shape.rotation.y = -axis.angle()
	body.add_child(shape)

	return body


## How far below `base_y` the walls have to reach for the whole footprint to be
## buried, in metres.
##
## **The lowest ground under the footprint, not the highest.** A flat base plane
## cut off at the centre's height leaves a gap on the downhill side, where the
## ground has fallen away below it, and you can see under the building there.
## Burying to the lowest point instead puts the base under the terrain everywhere,
## so the ground meets the wall face at every corner and the mesh looks filled --
## and the uphill side is buried by as much as the site slopes, which is what a
## real building on a slope looks like.
##
## A wall is a flat face between two footprint vertices, so the ground under its
## base is the two heights at its ends and nothing in between. Sampling the ring
## vertices is therefore exact for the geometry that gets built, not an
## approximation of it, and on flat ground this comes out as just GROUND_SINK.
func _bury_depth(world_ring: PackedVector2Array, base_y: float) -> float:
	var lowest := INF
	for point in world_ring:
		lowest = minf(lowest,
				heightmap.height_at_world(Vector3(point.x, 0.0, point.y)))
	return clampf(base_y - lowest, GROUND_SINK, MAX_BURY_M)


## The footprint's ring ready to extrude: no repeated closing vertex, and wound
## so that the signed area is positive.
##
## The winding is normalised rather than handled per face because the outward
## normal of an edge is only correct for one of the two orientations, and half
## of the real footprints are wound the other way.
static func _body_ring(points: PackedVector2Array) -> PackedVector2Array:
	var ring := points
	if ring.size() > 1 and ring[0] == ring[ring.size() - 1]:
		ring = ring.slice(0, ring.size() - 1)
	if ring.size() < 3:
		return PackedVector2Array()
	if _signed_area(ring) < 0.0:
		ring.reverse()
	return ring


## Wall height in metres for a building: its storeys from the levels tag, else
## from its type, else the default.
static func _wall_height(building: OsmBuilding) -> float:
	if building == null:
		return DEFAULT_STOREYS * STOREY_M
	var tagged := building.levels()
	var storeys := tagged if tagged > 0 \
			else int(STOREYS_BY_TYPE.get(building.building_type(), DEFAULT_STOREYS))
	return maxf(float(storeys), 1.0) * STOREY_M


static func _roof_height(wall_m: float, pitched: bool) -> float:
	if not pitched:
		return 0.0
	return clampf(wall_m * ROOF_HEIGHT_RATIO, ROOF_HEIGHT_MIN, ROOF_HEIGHT_MAX)


static func _is_flat(building: OsmBuilding) -> bool:
	return building != null and building.building_type() in FLAT_ROOF_TYPES


## Two surfaces, so the roof can be a different colour from the walls: surface 0
## is the walls and their cap, surface 1 the roof. A flat-roofed building gets
## only the first. `axis` is the footprint's own ridge direction, which the roof
## and the collider both line up with, and `bury_m` is how far the wall bases are
## carried below the building's ground height.
static func _mesh(ring: PackedVector2Array, wall_m: float, roof_m: float, pitched: bool,
		seed_value: int, axis: Vector2, bury_m: float) -> ArrayMesh:
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := wall_m
	var bottom := -bury_m
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		# The outward normal of a positively wound edge is its direction turned a
		# quarter turn clockwise seen from above (+Z is south, see OsmProjection).
		var outward := Vector3(b.y - a.y, 0.0, a.x - b.x).normalized()
		_tri(walls, _v(a, bottom), _v(b, bottom), _v(b, top), outward)
		_tri(walls, _v(a, bottom), _v(b, top), _v(a, top), outward)
	for i in range(1, ring.size() - 1):
		_tri(walls, _v(ring[0], top), _v(ring[i], top), _v(ring[i + 1], top), Vector3.UP)

	var mesh := walls.commit()
	mesh.surface_set_material(0, _material("wall", seed_value, WALL_COLORS))

	if pitched and roof_m > 0.0:
		var roof := SurfaceTool.new()
		roof.begin(Mesh.PRIMITIVE_TRIANGLES)
		_roof(roof, ring, wall_m, roof_m, axis)
		var roof_mesh := roof.commit()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
				roof_mesh.surface_get_arrays(0))
		mesh.surface_set_material(mesh.get_surface_count() - 1,
				_material("roof", seed_value, ROOF_COLORS))
	return mesh


## A gable laid out on the footprint's **own** axis rather than the world's: two
## slopes, two triangular ends and a flat soffit underneath, which together close
## the roof into a solid. The ridge runs along `axis` and stops short of the ends
## by the across half-extent, which is what turns it into a gable rather than a
## long triangle.
##
## The frame here is `axis` and its perpendicular, not X and Z. Laying the roof
## out on the world-axis bounding box instead put a visibly rotated roof on every
## building that is not square to the world, which is most of them: OSM ways
## follow whatever the building's wall does, not the grid.
static func _roof(st: SurfaceTool, ring: PackedVector2Array, eave_m: float,
		roof_m: float, axis: Vector2) -> void:
	var across_axis := Vector2(-axis.y, axis.x)
	var box := _oriented_bounds(ring, axis)
	var along := box.size.x * 0.5 + ROOF_OVERHANG
	var across := box.size.y * 0.5 + ROOF_OVERHANG
	var origin := box.get_center()
	var eave := eave_m
	var ridge := eave_m + roof_m

	# Outward normals in this frame. The two "across" ones lean up into the two
	# slopes and the two "along" ones are the vertical gable ends; the pyramid
	# below uses a leaning version of all four as its four faces.
	var along_pos := Vector3(axis.x, 0.0, axis.y)
	var along_neg := -along_pos
	var across_pos := Vector3(across_axis.x, 0.0, across_axis.y)
	var across_neg := -across_pos

	# Corners in the footprint's frame, named for the quadrant they sit in: the
	# letter is which way along the ridge, the sign which way across it.
	var e0 := _v(origin - axis * along - across_axis * across, eave)
	var e1 := _v(origin + axis * along - across_axis * across, eave)
	var e2 := _v(origin + axis * along + across_axis * across, eave)
	var e3 := _v(origin - axis * along + across_axis * across, eave)

	# The soffit, across the whole eave rectangle overhang included. Every other
	# face of a roof faces up or outward, so someone standing under the eaves
	# looking up finds all of them back-facing and sees straight through the
	# building and out through the far side.
	#
	# It is coplanar with the walls' cap on purpose, and that is safe rather than
	# z-fighting: the two face opposite ways, so backface culling draws one from
	# above and the other from below and never both at once. Skipping the cap on
	# pitched buildings instead would also work and would cost a triangle less.
	_tri(st, e0, e1, e2, Vector3.DOWN)
	_tri(st, e0, e2, e3, Vector3.DOWN)

	if absf(along - across) <= PYRAMID_RIDGE_EPS:
		var apex := _v(origin, ridge)
		_tri(st, e1, e0, apex, (across_neg + Vector3.UP).normalized())
		_tri(st, e2, e1, apex, (along_pos + Vector3.UP).normalized())
		_tri(st, e3, e2, apex, (across_pos + Vector3.UP).normalized())
		_tri(st, e0, e3, apex, (along_neg + Vector3.UP).normalized())
		return

	if along >= across:
		var r0 := _v(origin - axis * (along - across), ridge)
		var r1 := _v(origin + axis * (along - across), ridge)
		_tri(st, e0, r0, r1, (across_neg + Vector3.UP).normalized())
		_tri(st, e0, r1, e1, (across_neg + Vector3.UP).normalized())
		_tri(st, e3, r1, r0, (across_pos + Vector3.UP).normalized())
		_tri(st, e3, e2, r1, (across_pos + Vector3.UP).normalized())
		_tri(st, e0, e3, r0, along_neg)
		_tri(st, e1, r1, e2, along_pos)
	else:
		var r0 := _v(origin - across_axis * (across - along), ridge)
		var r1 := _v(origin + across_axis * (across - along), ridge)
		_tri(st, e0, r0, r1, (along_neg + Vector3.UP).normalized())
		_tri(st, e0, r1, e3, (along_neg + Vector3.UP).normalized())
		_tri(st, e1, r0, r1, (along_pos + Vector3.UP).normalized())
		_tri(st, e1, r1, e2, (along_pos + Vector3.UP).normalized())
		_tri(st, e0, e1, r0, across_neg)
		_tri(st, e3, e2, r1, across_pos)


## The footprint's own ridge direction: along its longest edge.
##
## That is the right answer for almost every real footprint, and it costs one pass
## over a ring that has already been built. A rectangle's longest edge is a main
## wall, and an L-shape's is one of its two long runs -- both cases where a person
## drawing the roof would put the ridge the same way. A least-squares fit would be
## more robust on paper and would need explaining; the longest edge is the thing
## you can see.
static func _ridge_axis(ring: PackedVector2Array) -> Vector2:
	var longest := 0.0
	var axis := Vector2.RIGHT
	for i in ring.size():
		var edge := ring[(i + 1) % ring.size()] - ring[i]
		var length_sq := edge.length_squared()
		if length_sq > longest:
			longest = length_sq
			axis = edge
	return axis.normalized()


## The footprint's extent along `axis` and its perpendicular, as a Rect2 in that
## frame: x is along the axis, y across it. Dot products, so it does not care
## where the ring happens to be centred.
static func _oriented_bounds(ring: PackedVector2Array, axis: Vector2) -> Rect2:
	var across_axis := Vector2(-axis.y, axis.x)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point in ring:
		var p := Vector2(point.dot(axis), point.dot(across_axis))
		low = low.min(p)
		high = high.max(p)
	return Rect2(low, high - low)


## One triangle with `outward` as its flat normal, wound so that it is front
## facing when seen from there.
##
## **Godot's front face is clockwise seen from the camera**, which means the
## right-hand-rule normal has to point *away* from the viewer, so the order is
## checked per triangle rather than being a convention each caller has to get
## right. Winding a wall the other way renders the building invisible from
## outside and solid from within, which is exactly how it looks, so it is worth
## the branch.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		outward: Vector3) -> void:
	if (b - a).cross(c - a).dot(outward) > 0.0:
		var swap := b
		b = c
		c = swap
	for vertex in [a, b, c]:
		st.set_normal(outward)
		st.add_vertex(vertex)


## One cached material per palette entry, picked off the seed so a street is not
## one colour. Cached because a material per building would be a unique draw
## state per building, which is the one cost this cannot afford.
static func _material(kind: String, seed_value: int, palette: Array) -> StandardMaterial3D:
	var key := "%s:%d" % [kind, absi(seed_value) % palette.size()]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(palette[absi(seed_value) % palette.size()])
	material.roughness = 0.9
	_materials[key] = material
	return material


static func _v(point: Vector2, y: float) -> Vector3:
	return Vector3(point.x, y, point.y)


static func _bounds(ring: PackedVector2Array) -> Rect2:
	var bounds := Rect2(ring[0], Vector2.ZERO)
	for i in range(1, ring.size()):
		bounds = bounds.expand(ring[i])
	return bounds


static func _centre(ring: PackedVector2Array) -> Vector2:
	return _bounds(ring).get_center()


## The ring moved by `offset`, for building the mesh around the origin.
static func _translate(ring: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var moved := PackedVector2Array()
	moved.resize(ring.size())
	for i in ring.size():
		moved[i] = ring[i] + offset
	return moved


## Twice the signed area, by the shoelace sum. Godot 4 dropped
## Geometry2D.compute_polygon_area(), and the sign is what says which way round
## the ring runs.
static func _signed_area(ring: PackedVector2Array) -> float:
	var twice := 0.0
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		twice += a.x * b.y - b.x * a.y
	return twice


static func _area(ring: PackedVector2Array) -> float:
	return absf(_signed_area(ring)) * 0.5
