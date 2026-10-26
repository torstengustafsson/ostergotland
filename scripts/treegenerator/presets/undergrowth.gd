class_name TreeGenPresetsUndergrowth
extends RefCounted

## Procedurally generated undergrowth: a patch of tall grass, a fern, and a
## boulder.
##
## The plants are built directly into a SurfaceTool rather than through
## TreeGenTree. A patch of grass has no trunk to grow and a fern is a fan of
## fronds, not a branching skeleton, so the tree generator would contribute
## little but its bookkeeping. What the plants share with the trees is the leaf
## material, which is what puts them in the same light and behind the same
## alpha cutout.
## The boulder is here for the same reason -- it has no skeleton either -- but
## it is not a plant: it keeps its own shape rules (a lumpy closed blob, flat
## underneath) and takes the rock material, opaque and triplanar-mapped,
## rather than the leaf one.
##
## ForestGen bakes one mesh per variant and instances it, so the geometry here is
## paid for at bake time only and each patch can spend a few hundred triangles on
## looking like a plant rather than like a billboard.

## How much a baked mesh is scaled per instance; ForestGen reads it when it
## plants an undergrowth stand.
const SIZE_RANGE := Vector2(0.8, 1.4)

## A boulder's own scale range: the mesh is built around a half-metre radius, so
## this draws anything from a half-metre stone to a two-metre boulder. It is
## wider than the plants' range on purpose -- a field of identical footballs is
## what a boulder field must not look like, and size is most of the difference
## between one boulder and the next.
const ROCK_SIZE_RANGE := Vector2(1.0, 2.2)

## The radius a boulder is built at, before the instance scale.
const ROCK_RADIUS_M := 1.0

## Every strip here -- the grass blades, the fern's rachis and its pinnae --
## samples the middle of the leaf material's stencil, where its ellipse is opaque
## from base to tip. Sampling the full 0..1 uv would cut each strip into the
## stencil's leaf shape instead of leaving the silhouette to the geometry.
const OPAQUE_UV := Rect2(0.42, 0.15, 0.16, 0.68)

## How many blades one patch holds. A patch is one instance of one baked mesh --
## ForestGen plants patches, not blades -- and a batch of blades in one instance
## is what makes a dense stand affordable: the triangles are the same either way,
## but every extra instance costs a transform and a ground raycast on top of
## them.
const PATCH_BLADES := Vector2i(20, 32)

## How far a patch's blade bases are spread, in metres: the radius of ground one
## patch covers. ForestCell.MIN_UNDERGROWTH_GAP_M is the spacing of the patches
## themselves and is kept near this, so the two have to be changed together.
const PATCH_RADIUS_M := 1.0

## How far a blade may lean past its own base, and how wide its strip is at the
## base, in metres: the ranges _add_grass_blade() draws from, kept here because
## GRASS_REACH_M adds them up and has to see the same numbers the blade does.
const BLADE_LEAN_RANGE := Vector2(0.05, 0.20)
const BLADE_WIDTH_RANGE := Vector2(0.02, 0.03)

## How far a grass patch's geometry reaches from its origin, in metres, at the
## largest instance size. ForestCell holds a full CLEARANCE_M between this and
## anything drawn on the ground -- otherwise the blades lean out over the
## tarmac or the waterline while the patch's origin sits clear of it, and the
## plant stands on what it is not allowed to stand on.
##
## It is arithmetic over the blade's own numbers rather than a measurement: a
## base on the rim of the patch, leaning its full BLADE_LEAN_RANGE.y out, plus
## BLADE_WIDTH_RANGE.y for the strip's half-width, times SIZE_RANGE.y. Baked
## meshes measured 1.107 of local reach over 500 seeds, under the 1.23 this
## allows -- the extra is the base-at-the-rim case that sampling rarely hits.
const GRASS_REACH_M := (PATCH_RADIUS_M + BLADE_LEAN_RANGE.y + BLADE_WIDTH_RANGE.y) \
		* SIZE_RANGE.y

## The fern's reach at the largest instance size: fronds radiate from a crown
## and their pinnae reach sideways, so there is no disc to add up. Measured at
## 1.194 of local reach over 500 seeds (1.67 at SIZE_RANGE.y); the arithmetic
## worst case -- longest rachis at the widest angle, biggest pinna widest too --
## is about 1.5 local, and this holds to that: 1.5 * SIZE_RANGE.y.
const FERN_REACH_M := 2.1

## The boulder's reach at the largest instance size: ROCK_RADIUS_M pushed out
## by three lobes of up to 0.5 each, times ROCK_SIZE_RANGE.y. Measured at 1.541
## of local reach over 3000 seeds (3.39 at ROCK_SIZE_RANGE.y). The lobes summing
## to their full 2.5 m would need all three aimed the same way, which is why
## this is the measured worst with room on top rather than 5.5.
const ROCK_REACH_M := 3.6

const GRASS_COLOR := Color(0.1, 0.2, 0.1)
const GRASS_TIP_COLOR := Color(0.2, 0.4, 0.1)
const FERN_COLOR := Color(0.4, 1.0, 0.2) # The "leaves"
const RACHIS_COLOR := Color(0.34, 0.36, 0.16) # The "stems"


## A patch of grass: a batch of blades whose bases are scattered over a small
## disc of ground rather than all radiating from one point, the tallest around
## three quarters of a metre before the instance scale. A real tuft covers
## ground, and a patch wider than one base is also what lets a stand come up
## dense without one instance per blade.
static func create_tall_grass_mesh(p_seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades := rng.randi_range(PATCH_BLADES.x, PATCH_BLADES.y)
	for _blade in blades:
		_add_grass_blade(st, rng)
	return _commit(st)


## A fern: a number of fronds radiating from a common crown, each a rachis that
## rises and arches out, carrying paired pinnae that shorten toward the tip.
static func create_fern_mesh(p_seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fronds := rng.randi_range(1, 3)
	var first := rng.randf() * TAU
	# Evenly spaced rather than drawn independently, or the fronds clump to one
	# side of the crown and the fern reads as half a plant.
	for frond in fronds:
		var azimuth := first + TAU * float(frond) / float(fronds) \
				+ rng.randf_range(-0.8, 0.8)
		_add_frond(st, rng, azimuth)
	return _commit(st)


## A boulder: a lumpy closed blob over a flat base, ~80 triangles. It is a
## lat-long sphere whose radius is pushed out by a few random lobes, squashed
## and then cut off underneath, so it sits in the ground the way a glacial
## erratic does rather than balancing on a point.
##
## The triangles are emitted with unshared vertices and flat normals: a boulder
## at this budget is faceted, and the facets are what make it read as broken
## rock rather than as a lump of clay. It gets the rock material, not the leaf
## one -- opaque, triplanar-mapped, so the mesh carries no uv at all.
static func create_rock_mesh(p_seed: int) -> ArrayMesh:
	const SEGS := 8
	const RINGS := 6
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	# Three lobes break the sphere's silhouette from every angle without
	# turning it into a star; each is a smooth bump toward one random direction.
	var lobes: Array[Vector3] = []
	var amps: Array[float] = []
	for _i in 3:
		lobes.append(Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0),
				rng.randf_range(-1.0, 1.0)).normalized())
		amps.append(rng.randf_range(0.25, 0.5))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for band in RINGS - 1:
		var theta := PI * float(band + 1) / float(RINGS)
		var row: Array = []
		for seg in SEGS:
			var phi := TAU * float(seg) / float(SEGS)
			row.append(_rock_point(Vector3(sin(theta) * cos(phi), cos(theta),
					sin(theta) * sin(phi)), lobes, amps))
		rings.append(row)
	var top := _rock_point(Vector3.UP, lobes, amps)
	var bottom := _rock_point(Vector3.DOWN, lobes, amps)
	# Winding is clockwise seen from outside (Godot's front face), which is what
	# keeps generate_normals() pointing the facets outward instead of inward --
	# the inward version renders as a hole in the ground with the light on it.
	for band in rings.size() - 1:
		for seg in SEGS:
			var a: Vector3 = rings[band][seg]
			var b: Vector3 = rings[band][(seg + 1) % SEGS]
			var c: Vector3 = rings[band + 1][seg]
			var d: Vector3 = rings[band + 1][(seg + 1) % SEGS]
			for vertex: Vector3 in [a, c, d, a, d, b]:
				st.add_vertex(vertex)
	for seg in SEGS:
		for vertex: Vector3 in [top, rings[0][seg], rings[0][(seg + 1) % SEGS]]:
			st.add_vertex(vertex)
		for vertex: Vector3 in [bottom, rings[rings.size() - 1][(seg + 1) % SEGS],
				rings[rings.size() - 1][seg]]:
			st.add_vertex(vertex)
	st.generate_normals()
	return _commit_rock(st)


## One point of a boulder's surface: the sphere's, pushed out by the lobes, then
## squashed and finally cut off underneath. The cut is last and in world
## metres, not a fraction of the radius, so the base is flat ground to sit on at
## every instance size -- and the small sink keeps a scaled-up boulder from
## hovering where the terrain dips under it.
static func _rock_point(dir: Vector3, lobes: Array[Vector3],
		amps: Array[float]) -> Vector3:
	var radius := ROCK_RADIUS_M
	for i in lobes.size():
		radius += ROCK_RADIUS_M * amps[i] * pow(maxf(dir.dot(lobes[i]), 0.0), 2.0)
	var point := dir * radius
	point.y = maxf(point.y * 0.7, -0.08)
	return point


## One blade: a strip that rises and then arches over, tapering to a point. The
## rise follows sin(t * PI/2) so the blade stands up before it leans, which is
## what separates a blade of grass from a straight spike.
static func _add_grass_blade(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	const SEGMENTS := 4
	var azimuth := rng.randf() * TAU
	var outward := Vector3(cos(azimuth), 0.0, sin(azimuth))
	var side := outward.cross(Vector3.UP)
	# The base is drawn from the patch's disc, independent of the lean: a patch
	# is grass over a piece of ground, not a fan from one stem.
	var base := _disc_point(rng, PATCH_RADIUS_M)
	# Shorter at the patch's edge, so a patch has a silhouette instead of a flat
	# top of equal blades.
	var height := rng.randf_range(0.7, 1.3) \
			* lerpf(1.0, 0.6, base.length() / PATCH_RADIUS_M)
	var reach := rng.randf_range(BLADE_LEAN_RANGE.x, BLADE_LEAN_RANGE.y)
	var width := rng.randf_range(BLADE_WIDTH_RANGE.x, BLADE_WIDTH_RANGE.y)
	var shade := rng.randf_range(0.8, 1.15)
	var normal := (Vector3.UP + outward * 0.3).normalized()
	var tip_color := GRASS_COLOR.lerp(GRASS_TIP_COLOR, rng.randf_range(0.0, 0.5))
	for segment in SEGMENTS:
		var t0 := float(segment) / float(SEGMENTS)
		var t1 := float(segment + 1) / float(SEGMENTS)
		var p0 := base + outward * reach * t0 * t0 \
				+ Vector3.UP * height * sin(t0 * PI * 0.5)
		var p1 := base + outward * reach * t1 * t1 \
				+ Vector3.UP * height * sin(t1 * PI * 0.5)
		# The floor keeps the tip a narrow point rather than a zero-width pair of
		# vertices, which would be a degenerate quad with no normal.
		var w0 := maxf(width * (1.0 - t0 * t0), 0.001)
		var w1 := maxf(width * (1.0 - t1 * t1), 0.001)
		_add_strip(st, p0, p1, side * w0, side * w1, t0, t1, normal,
				GRASS_COLOR.lerp(tip_color, t0) * shade,
				GRASS_COLOR.lerp(tip_color, t1) * shade)


## A point uniformly distributed over a disc of `radius`, in the patch's ground
## plane. sqrt() on the radius is what makes it uniform: a plain uniform draw
## piles the bases into the middle of the patch.
static func _disc_point(rng: RandomNumberGenerator, radius: float) -> Vector3:
	var angle := rng.randf() * TAU
	var r := radius * sqrt(rng.randf())
	return Vector3(cos(angle) * r, 0.0, sin(angle) * r)


## One frond: its rachis, and a pair of pinnae at every step along it. The pinnae
## are longest near the crown and shorten toward the tip, as a real frond's do.
static func _add_frond(st: SurfaceTool, rng: RandomNumberGenerator,
		azimuth: float) -> void:
	var rachis_angle: float = rng.randf_range(0.3, 0.6) # Smaller value means more staight
	var direction := Vector3(cos(azimuth), 0.0, sin(azimuth)) * rachis_angle
	var side := direction.cross(Vector3.UP)
	var length := rng.randf_range(1.5, 2.0)
	var lift := length * rng.randf_range(0.5, 1.0)
	var normal := (Vector3.UP + direction * 0.25).normalized()
	var shade := rng.randf_range(0.85, 1.1)
	_add_rachis(st, direction, side, length, lift, normal, shade)

	var pairs := rng.randi_range(6, 9)
	for pair in pairs:
		const START_PERCENT = 0.4
		const END_PERCENT = 0.95
		var t := lerpf(START_PERCENT, END_PERCENT, float(pair) / float(pairs - 1))
		var root := _frond_point(direction, length, lift, t)
		var pinna_length := length * lerpf(0.5, 0.1, t) \
				* rng.randf_range(0.85, 1.15)
		for side_sign: float in [-1.0, 1.0]:
			# The forward part sweeps each pinna toward the tip, so the pairs
			# overlap the way a fern's do instead of standing square to the rachis.
			var outward := (direction * 0.5 + side * side_sign
					+ Vector3.UP * 0.12).normalized()
			_add_pinna(st, root, outward, pinna_length, normal,
					FERN_COLOR * shade * rng.randf_range(0.9, 1.1))


## The rachis of one frond: a thin strip along the same curve the pinnae are
## hung on, tapering with it.
static func _add_rachis(st: SurfaceTool, direction: Vector3, side: Vector3,
		length: float, lift: float, normal: Vector3, shade: float) -> void:
	const SEGMENTS := 5
	var color := RACHIS_COLOR * shade
	for segment in SEGMENTS:
		var t0 := float(segment) / float(SEGMENTS)
		var t1 := float(segment + 1) / float(SEGMENTS)
		var p0 := _frond_point(direction, length, lift, t0)
		var p1 := _frond_point(direction, length, lift, t1)
		var w0 := maxf(0.04 * (1.0 - t0), 0.0015)
		var w1 := maxf(0.04 * (1.0 - t1), 0.0015)
		_add_strip(st, p0, p1, side * w0, side * w1, t0, t1, normal,
				color, color)


## Where a frond's rachis is at `t` along it: it rises quickly and then arches
## over, so the tip sits lower than the highest point.
static func _frond_point(direction: Vector3, length: float, lift: float,
		t: float) -> Vector3:
	const BEND = 0.4 # Larger value means more bending of the rachis (or "stems")
	return direction * (length * t) + Vector3.UP * (lift * sin(t * PI * BEND))


## One pinna: a small tapered strip like a blade of grass, solid rather than cut
## from the leaf stencil -- at this size the stencil's ellipse is mostly
## transparent and the pinnae come out as a dotted line at any distance.
static func _add_pinna(st: SurfaceTool, root: Vector3, outward: Vector3,
		length: float, normal: Vector3, color: Color) -> void:
	var across := outward.cross(Vector3.UP).normalized()
	var tip := root + outward * length
	_add_strip(st, root, tip, across * length * 0.2, across * length * 0.03,
			0.0, 1.0, normal, color, color)


## One quad of a tapered strip, from `p0` to `p1` with half-widths `h0`/`h1`,
## textured between `v0` and `v1` of OPAQUE_UV.
static func _add_strip(st: SurfaceTool, p0: Vector3, p1: Vector3,
		h0: Vector3, h1: Vector3, v0: float, v1: float, normal: Vector3,
		color0: Color, color1: Color) -> void:
	var u0 := OPAQUE_UV.position.x
	var u1 := OPAQUE_UV.position.x + OPAQUE_UV.size.x
	var y0 := OPAQUE_UV.position.y + OPAQUE_UV.size.y * v0
	var y1 := OPAQUE_UV.position.y + OPAQUE_UV.size.y * v1
	_vertex(st, p0 - h0, Vector2(u0, y0), normal, color0)
	_vertex(st, p0 + h0, Vector2(u1, y0), normal, color0)
	_vertex(st, p1 + h1, Vector2(u1, y1), normal, color1)
	_vertex(st, p0 - h0, Vector2(u0, y0), normal, color0)
	_vertex(st, p1 + h1, Vector2(u1, y1), normal, color1)
	_vertex(st, p1 - h1, Vector2(u0, y1), normal, color1)


static func _vertex(st: SurfaceTool, vertex: Vector3, uv: Vector2,
		normal: Vector3, color: Color) -> void:
	st.set_uv(uv)
	st.set_normal(normal)
	st.set_color(color)
	st.add_vertex(vertex)


## Gives a finished mesh the shared leaf material: both kinds are green
## vegetation, their colour comes from the vertices and their shape from the
## geometry.
static func _commit(st: SurfaceTool) -> ArrayMesh:
	var mesh := st.commit()
	mesh.surface_set_material(0, TreeGenMaterialLibrary.leaf_material(null))
	return mesh


## Gives a finished boulder the rock material: its colour is the scan's, so
## nothing of it lives in the vertices.
static func _commit_rock(st: SurfaceTool) -> ArrayMesh:
	var mesh := st.commit()
	mesh.surface_set_material(0, TreeGenMaterialLibrary.rock_material())
	return mesh
