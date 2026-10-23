class_name TreeGenPresetsUndergrowth
extends RefCounted

## Procedurally generated undergrowth: a tuft of tall grass and a fern.
##
## Both are built directly into a SurfaceTool rather than through TreeGenTree. A
## tuft has no trunk to grow and a fern is a fan of fronds, not a branching
## skeleton, so the tree generator would contribute little but its bookkeeping.
## What the two do share with the trees is the leaf material, which is what puts
## them in the same light and behind the same alpha cutout.
##
## ForestGen bakes one mesh per variant and instances it, so the geometry here is
## paid for at bake time only and each tuft can spend a few hundred triangles on
## looking like a plant rather than like a billboard.

## How much a baked mesh is scaled per instance; ForestGen reads it when it
## plants an undergrowth stand.
const SIZE_RANGE := Vector2(0.8, 1.4)

## Every strip here -- the grass blades, the fern's rachis and its pinnae --
## samples the middle of the leaf material's stencil, where its ellipse is opaque
## from base to tip. Sampling the full 0..1 uv would cut each strip into the
## stencil's leaf shape instead of leaving the silhouette to the geometry.
const OPAQUE_UV := Rect2(0.42, 0.15, 0.16, 0.68)

const GRASS_COLOR := Color(0.30, 0.50, 0.22)
const GRASS_TIP_COLOR := Color(0.52, 0.58, 0.26)
const FERN_COLOR := Color(0.4, 1.0, 0.2) # The "leaves"
const RACHIS_COLOR := Color(0.34, 0.36, 0.16) # The "stems"


## A tuft of grass: a number of blades leaning out from a common base, the
## tallest around three quarters of a metre before the instance scale.
static func create_tall_grass_mesh(p_seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for _blade in rng.randi_range(1, 3):
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


## One blade: a strip that rises and then arches over, tapering to a point. The
## rise follows sin(t * PI/2) so the blade stands up before it leans, which is
## what separates a blade of grass from a straight spike.
static func _add_grass_blade(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	const SEGMENTS := 4
	var azimuth := rng.randf() * TAU
	var outward := Vector3(cos(azimuth), 0.0, sin(azimuth))
	var side := outward.cross(Vector3.UP)
	var base := outward * rng.randf_range(0.0, 0.05)
	var height := rng.randf_range(0.7, 1.1)
	var reach := rng.randf_range(0.05, 0.20)
	var width := rng.randf_range(0.02, 0.03)
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
