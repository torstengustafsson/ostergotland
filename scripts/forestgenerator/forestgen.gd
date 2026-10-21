class_name ForestGen extends Node3D

## Plants trees on a forest's outline. It knows nothing about where forests come
## from or when they should exist -- that is ForestStreamer's job, and this is the
## half that does the growing, so that half can be reused on its own.
##
## Everything is in real metres (see Heightmap), so the densities below really are
## trees per square metre. They are demo values: an oak stand at 0.001/m^2 is one
## tree every ~32 m, which reads as woodland from a distance without being a
## forest.
##
## The unit of planting is a *rectangle*, not a forest: plant_forest_in_rect()
## grows only the part of an outline that falls inside the rectangle it is given.
## That is what lets a 31 ha stand appear as the player walks into it instead of
## arriving whole the moment its far edge comes within range.
##
## The tree meshes are procedural and baked lazily, because that is the whole
## cost: baking one oak is ~30 ms against ~2 ms to place a tree. Baking is
## therefore one mesh per bake_next() call rather than per stand, and only for the
## species something actually needs.
##
## A stand holds trees of two ages (TreeAge), and they are separate meshes: a
## sapling is a tree of its own, grown from its own preset, never a scaled
## adult, so a (species, age) pair is what a mesh is baked for and what a
## density is counted per.

enum ForestType {
	LeafyForest,
	ConiferousForest,
}

enum TreeSpecies {
	Oak,
	Spruce,
	Maple,
	Aspen,
	Birch,
	Pine,
	NoSpecies,
}

## The two ages a tree is planted at. A young tree is the same species grown
## small -- its own preset, its own mesh, see TreeGenPresetsYoung -- and a
## stand holds both: the adults carry the canopy, the young ones the
## understory under it.
enum TreeAge {
	Adult,
	Young,
}

## Each forest type's trees per square metre per species (oak, spruce, maple,
## aspen, birch, pine), for the adults and for the young ones separately.
## Nothing here is restricted to one tree per cell -- see _plan() and _extra().
const FOREST_TYPE_TREES = {
	ForestType.LeafyForest: {
		TreeAge.Adult: {
			TreeSpecies.Oak: 0.001,
			TreeSpecies.Spruce: 0.0002,
			TreeSpecies.Maple: 0.0004,
			TreeSpecies.Aspen: 0.0005,
			TreeSpecies.Birch: 0.0005,
			TreeSpecies.Pine: 0.00025,
		},
		TreeAge.Young: {
			TreeSpecies.Oak: 0.0006,
			TreeSpecies.Spruce: 0.0002,
			TreeSpecies.Maple: 0.0003,
			TreeSpecies.Aspen: 0.0005,
			TreeSpecies.Birch: 0.0004,
			TreeSpecies.Pine: 0.00015,
		},
	},
	ForestType.ConiferousForest: {
		TreeAge.Adult: {
			TreeSpecies.Oak: 0.0001,
			TreeSpecies.Spruce: 0.0005,
			TreeSpecies.Maple: 0.00005,
			TreeSpecies.Aspen: 0.0001,
			TreeSpecies.Birch: 0.0005,
			TreeSpecies.Pine: 0.002,
		},
		TreeAge.Young: {
			TreeSpecies.Oak: 0.0001,
			TreeSpecies.Spruce: 0.0004,
			TreeSpecies.Maple: 0.00005,
			TreeSpecies.Aspen: 0.00015,
			TreeSpecies.Birch: 0.0004,
			TreeSpecies.Pine: 0.001,
		},
	}
}

class ForestSectionPlan:
	var species: TreeSpecies
	var age: TreeAge
	var count := 0       ## whole trees this rectangle gets for certain
	var remainder := 0.0 ## chance of one more, from the fractional part
	func _init(_species: TreeSpecies, _age: TreeAge, expected: float):
		species = _species
		age = _age
		count = floori(expected)
		remainder = expected - float(count)

## Baked meshes per species and age. One tree costs tens of milliseconds to
## generate and they are all identical apart from their seed, so they are baked
## once for the whole run and shared. Several rather than one so neighbouring
## stands do not all get the same tree.
##
## This number is nearly free, which is worth knowing before anyone tries to raise
## it: a frame pays for instances x vertices-per-tree, and splitting those
## instances over more meshes changes neither. Variety is bought with bake time
## and memory only.
const VARIANTS := 10

## A forest is hundreds of these and the presets are authored as one hero tree, so
## they get cut down before baking: leaves are 80-92% of a hero tree (an oak is
## 87%, a spruce 92%). Same silhouette, far fewer leaves and twigs -- the only
## sensible thing to do with a tree 20-200 m away. The presets are used nowhere
## else, so the knobs live here rather than in them to keep the hero tree
## available.
##
## The cut lands the other way up from what it starts as: leaves go to 45-62% and
## bark becomes the larger half (an oak is 18813 bark to 16339 leaves). Nothing
## further is spent on the bark beyond LOD_BARK_RINGS, which is why the twig
## geometry is what is left to draw at distance.
const LOD_MAX_DEPTH := 4
const LOD_BARK_RINGS := 8
const LOD_LEAF_DENSITY := 0.12
const LOD_MIN_LEAVES := 3

## Tries this many random spots per tree before leaving it out, so a tree with
## nowhere to go is dropped rather than piled on the origin.
const MAX_PLACEMENT_TRIES := 32

## Spare nodes kept for reuse, capped so that walking through one enormous stand
## does not leave hundreds of nodes parked for the rest of the session.
const POOL_MAX := 96

## Tags that mean coniferous in OSM's leaf_type (and species) vocabulary.
const CONIFEROUS := ["needleleaved", "spruce", "pine", "conifer"]

## How far above and below a spot to cast for the ground, in metres. It has to
## clear the tallest terrain.
const GROUND_PROBE := 500.0

## The metadata key under which a tree node records its age, so a caller can
## tell the adults of a stand from the understory planted with them.
const AGE_META := "tree_age"

## Recycled MultiMeshInstance3Ds, emptied. See recycle().
var _pool: Array[MultiMeshInstance3D] = []
## Baked meshes per (species, age), filled by bake_next(). The pair is the key
## because a sapling is its own mesh, not a scaled adult.
var _meshes: Dictionary = {}
## The (species, age) pairs that have been asked for, in the order they were
## first needed, which is the order _next_wanted() round-robins them in.
var _wanted: Array[Vector2i] = []
## How many meshes each (species, age) is wanted for, at most VARIANTS but no
## more than the trees it is wanted for: a stand with one spruce in it does not
## need ten different spruce meshes. It only ever goes up, so a species that
## turns out to be common gets its full set.
var _wanted_count: Dictionary = {}
## Where _next_wanted() starts looking, i.e. the one after the last one baked.
var _cursor := 0
## One raycast, reused for every tree: a stand is thousands of them and a fresh
## PhysicsRayQueryParameters3D each time is thousands of allocations.
var _ground_ray := PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.UP)


## Grows the part of one forest that falls inside `rect`, as one
## MultiMeshInstance3D per baked variant the trees land on.
##
## Both ages are grown: the adults at the stand's own density and the young
## ones at theirs, each from its own meshes, so a stand comes up with an
## understory under its canopy rather than with only the canopy.
##
## `seed_value` is what makes this safe to re-enter: the same rectangle of the same
## forest gives the same trees every time, so a tree never moves because a
## neighbour streamed in or out. It should come from the feature and the cell
## (ForestStreamer hashes the way id with the cell key).
##
## Trees are placed by trying to fill `rect` to the density and letting the outline
## reject the ones that fall outside it, so a cell that the forest only clips the
## corner of gets fewer trees rather than a full cell's worth pushed up against
## the edge.
func plant_forest_in_rect(type: ForestType, points: PackedVector2Array, rect: Rect2,
		seed_value: int) -> Array[MultiMeshInstance3D]:
	var added: Array[MultiMeshInstance3D] = []
	if points.size() < 3 or rect.get_area() <= 0.0:
		return added
	var plan := _plan(type, rect.get_area())
	if plan.is_empty() or not needs_ready(type, rect.get_area()):
		return added

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for entry in plan:
		var transforms: Array = []
		for _i in entry.count + _extra(entry.remainder, rng):
			var spot := _random_point_in(points, rect, rng)
			if spot != Vector2.INF:
				transforms.append(_tree_transform(spot, entry.age, rng))
		if transforms.is_empty():
			continue
		var meshes := _baked(_key(entry.species, entry.age))
		# Spread over the variants, so a cell is not one tree repeated. The split
		# costs one draw call each, which measured as free (see VARIANTS).
		var groups: Array = []
		for _v in meshes.size():
			groups.append([])
		for tree_transform in transforms:
			var group: Array = groups[randi() % groups.size()]
			group.append(tree_transform)
		for i in groups.size():
			if not groups[i].is_empty():
				added.append(_multimesh(meshes[i], groups[i], entry.age))
	return added


## Queues the meshes a stand of `type` covering `area` m2 would need and returns
## whether they are all there, i.e. whether plant_forest_in_rect() would now grow
## it. Cheap: nothing is grown and no raycast is cast.
##
## It waits for all of a stand's meshes rather than just the first. Otherwise the
## stand in front of the player is planted two frames in, when one variant exists,
## and every tree in it is that one mesh, which makes VARIANTS pointless. The wait
## costs no real time: the baking happens either way.
##
## A stand needs the meshes of both ages, so nothing is planted until the
## saplings are baked too.
func needs_ready(type: ForestType, area: float) -> bool:
	var all_baked := true
	for entry in _plan(type, area):
		request_baking(entry)
		var key := _key(entry.species, entry.age)
		if _baked(key).size() < _wanted_count[key]:
			all_baked = false
	return all_baked


## What a stand of this type covering `area` m2 would grow, as one
## [species, age, tree count] per species and age that gets at least one tree, in
## drawing order.
##
## The count is the floor of `density * area` and the fraction is carried in
## `remainder` rather than dropped, so a density below 1/cell_area does not round
## away to nothing in every cell. See _extra().
func _plan(type: ForestType, area: float) -> Array:
	var densities: Dictionary = FOREST_TYPE_TREES[type]
	var plan: Array = []
	for age in densities.keys():
		for species in densities[age].keys():
			var density = densities[age][species]
			var expected := float(density) * area
			if expected > 0.0:
				plan.append(ForestSectionPlan.new(species, age, expected))
	return plan


## One more tree with probability `remainder` -- the fractional part of the
## expected count, rounded stochastically instead of down. Without it a density
## under 1/cell_area floors to zero in every cell and the forest silently
## disappears, and the only densities that worked were the ones that happened to
## clear one tree per cell. The draw comes from the cell's own rng, so a cell
## still replants exactly the trees it planted before.
static func _extra(remainder: float, rng: RandomNumberGenerator) -> int:
	if remainder <= 0.0:
		return 0
	return 1 if rng.randf() < remainder else 0


## Bakes the next wanted mesh and returns whether it did one. A caller with a
## per-frame budget should keep calling while this returns true; it is what spreads
## the procedural geometry over frames instead of dropping it all into the first
## one.
func bake_next() -> bool:
	var key := _next_wanted()
	if key.x == TreeSpecies.NoSpecies:
		return false
	var tree: TreeGenTree = _preset(key.x as TreeSpecies, key.y as TreeAge).call(randi())
	_apply_lod(tree)
	tree.regenerate()
	_baked(key).append(tree.mesh)
	tree.free()
	return true


## Which (species, age) to bake next: the one *after* the last one baked, so
## every species reaches its first mesh before any of them reaches its second.
## Taking simply the first one with room left is not round-robin: a cell holding
## one spruce and four oaks would then wait for all ten oak variants.
func _next_wanted() -> Vector2i:
	var n := _wanted.size()
	for i in n:
		var key: Vector2i = _wanted[(_cursor + i) % n]
		if _baked(key).size() < _wanted_count[key]:
			_cursor = (_cursor + i + 1) % n
			return key
	return Vector2i(TreeSpecies.NoSpecies, TreeAge.Adult)


## Meshes still to bake, for a progress print.
func baking() -> int:
	var left := 0
	for key in _wanted:
		left += maxi(0, _wanted_count[key] - _baked(key).size())
	return left


## Asks for up to VARIANTS meshes of the plan's species and age, or as many as
## the plan calls for if that is fewer -- variety is only worth baking for a
## species that actually appears more than once. A plan can call for a fraction
## of a tree per cell, and the floor of 1 still applies to it: without a mesh
## there is nothing to plant the occasional tree with.
func request_baking(plan: ForestSectionPlan) -> void:
	var want := clampi(plan.count, 1, VARIANTS)
	var key := _key(plan.species, plan.age)
	if _wanted_count.has(key):
		_wanted_count[key] = maxi(int(_wanted_count[key]), want)
		return
	_wanted_count[key] = want
	_wanted.append(key)


## The key a species and an age are stored under, as one Vector2i so it can be a
## dictionary key: the mesh of a sapling is not the mesh of the tree it grows
## into, so the age is part of the key and not a detail of the species.
static func _key(species: TreeSpecies, age: TreeAge) -> Vector2i:
	return Vector2i(species, age)


## The forest type an OSM forest feature should grow as, from its leaf_type or
## species tag. Coniferous means spruce; everything else, including an untagged
## stand, is broadleaved.
static func type_for(feature: OsmFeature) -> ForestType:
	var leaf := (feature as OsmForestArea).species().to_lower()
	for conifer in CONIFEROUS:
		if leaf.contains(conifer):
			return ForestType.ConiferousForest
	return ForestType.LeafyForest


## A random point (x, z) inside the polygon and inside `rect`, or Vector2.INF when
## MAX_PLACEMENT_TRIES random spots in `rect` all missed. The polygon is what
## rejects the sample, so a cell the forest only partly covers gets fewer trees.
func _random_point_in(points: PackedVector2Array, rect: Rect2,
		rng: RandomNumberGenerator) -> Vector2:
	for _try in MAX_PLACEMENT_TRIES:
		var spot := Vector2(rng.randf_range(rect.position.x, rect.end.x),
				rng.randf_range(rect.position.y, rect.end.y))
		if Geometry2D.is_point_in_polygon(spot, points):
			return spot
	return Vector2.INF


## How much a tree's baked size is scaled per instance. A young tree varies
## more: the understory is full of saplings of every size, while the adults of
## a stand are all roughly grown.
const ADULT_SIZE_RANGE := Vector2(0.9, 1.1)
const YOUNG_SIZE_RANGE := Vector2(0.7, 1.3)


func _tree_transform(spot: Vector2, age: TreeAge, rng: RandomNumberGenerator) -> Transform3D:
	var origin := Vector3(spot.x, _ground_height_at(spot.x, spot.y), spot.y)
	var limits := YOUNG_SIZE_RANGE if age == TreeAge.Young else ADULT_SIZE_RANGE
	var size := rng.randf_range(limits.x, limits.y)
	var rot := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * size)
	return Transform3D(rot, origin)


## Area of a world-XZ polygon, 0 when it has no usable geometry. Godot 4 dropped
## Geometry2D.compute_polygon_area(), so this is the shoelace formula by hand; the
## last point is joined to the first, so a duplicated closing vertex is fine.
static func polygon_area(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var twice_area := 0.0
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		twice_area += a.x * b.y - b.x * a.y
	return absf(twice_area) * 0.5


## One MultiMeshInstance3D holding `transforms` instances of `mesh`, taken from the
## pool if there is one spare. See recycle().
##
## The node records its age, so a caller can tell an adult stand from the
## understory planted with it without having to look at the mesh.
func _multimesh(mesh: ArrayMesh, transforms: Array, age: TreeAge) -> MultiMeshInstance3D:
	var instance := _take()
	instance.multimesh.mesh = mesh
	instance.multimesh.instance_count = transforms.size()
	for i in transforms.size():
		instance.multimesh.set_instance_transform(i, transforms[i])
	instance.set_meta(AGE_META, age)
	return instance


func _take() -> MultiMeshInstance3D:
	if _pool.is_empty():
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = MultiMesh.new()
		instance.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		add_child(instance)
		return instance
	var reused: MultiMeshInstance3D = _pool.pop_back()
	reused.visible = true
	return reused


## Takes nodes back for reuse, which is what keeps a cell that leaves the radius
## from allocating and freeing a node the next time one arrives. Emptied first, so
## a pooled one draws nothing -- and because it is emptied rather than freed it
## does not linger for the frame that queue_free() would take to retire it.
func recycle(nodes: Array) -> void:
	for node in nodes:
		if _pool.size() >= POOL_MAX:
			node.queue_free()
			continue
		node.multimesh.instance_count = 0
		node.multimesh.mesh = null
		node.visible = false
		_pool.append(node)


## The baked meshes of one species and age, in the order they were baked.
func _baked(key: Vector2i) -> Array:
	if not _meshes.has(key):
		_meshes[key] = []
	return _meshes[key]


## The builder for one species and age: the adult tree, or the sapling of the
## same species.
static func _preset(species: TreeSpecies, age: TreeAge) -> Callable:
	match species:
		TreeSpecies.Oak:
			return TreeGenPresetsYoung.oak if age == TreeAge.Young else TreeGenPresetsAdult.oak
		TreeSpecies.Spruce:
			return TreeGenPresetsYoung.spruce if age == TreeAge.Young else TreeGenPresetsAdult.spruce
		TreeSpecies.Maple:
			return TreeGenPresetsYoung.maple if age == TreeAge.Young else TreeGenPresetsAdult.maple
		TreeSpecies.Aspen:
			return TreeGenPresetsYoung.aspen if age == TreeAge.Young else TreeGenPresetsAdult.aspen
		TreeSpecies.Birch:
			return TreeGenPresetsYoung.birch if age == TreeAge.Young else TreeGenPresetsAdult.birch
		TreeSpecies.Pine:
			return TreeGenPresetsYoung.pine if age == TreeAge.Young else TreeGenPresetsAdult.pine
	print("Warning: Attempted to access unsupported tree (", species, "), using TreeGenPresetsAdult.oak as default..")
	return TreeGenPresetsAdult.oak



## Cuts a preset down to something worth instancing hundreds of times: the shape is
## untouched, only the leaf and twig count.
func _apply_lod(tree: TreeGenTree) -> void:
	tree.max_depth = LOD_MAX_DEPTH
	tree.bark_rings = LOD_BARK_RINGS
	_lod_branch_sets(tree.branch_sets)


func _lod_branch_sets(sets: Array[TreeGenBranchSet]) -> void:
	for branch_set in sets:
		for leaves in branch_set.leaf_sets:
			leaves.leaf_count = maxi(LOD_MIN_LEAVES,
					floori(leaves.leaf_count * LOD_LEAF_DENSITY))
		_lod_branch_sets(branch_set.child_branch_sets)


## Ground height under (x, z), by a downward raycast against the streamed terrain.
## Flat at 0 where there is none -- which is outside LOAD_RADIUS, so a cell placed
## further out than that lands at the wrong height rather than nowhere.
func _ground_height_at(x: float, z: float) -> float:
	_ground_ray.from = Vector3(x, GROUND_PROBE, z)
	_ground_ray.to = Vector3(x, -GROUND_PROBE, z)
	var hit := get_world_3d().direct_space_state.intersect_ray(_ground_ray)
	if hit.is_empty():
		return 0.0
	return hit.position.y
