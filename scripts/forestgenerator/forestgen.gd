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

enum ForestType {
	OakForest,
	SpruceForest,
}

## Trees per square metre per species (oak, spruce, maple) for each stand type.
const DENSITY_OAK_FOREST := [0.001, 0.00002, 0.00005]
const DENSITY_SPRUCE_FOREST := [0.000001, 0.00002, 0.000001]

## Species; the values are indices into _preset() and the bake queues.
const SPECIES_OAK := 0
const SPECIES_SPRUCE := 1

## Baked meshes per species. One tree costs tens of milliseconds to generate and
## they are all identical apart from their seed, so they are baked once for the
## whole run and shared. Several rather than one so neighbouring stands do not all
## get the same tree.
##
## This number is nearly free, which is worth knowing before anyone tries to raise
## it: a frame pays for instances x vertices-per-tree, and splitting those
## instances over more meshes changes neither. Variety is bought with bake time
## and memory only.
const VARIANTS := 10

## A forest is hundreds of these and the presets are authored as one hero tree, so
## they get cut down before baking: leaves are 82% of an oak's 107 691 vertices
## and 94% of a spruce's 299 377. Same silhouette, far fewer leaves and twigs --
## the only sensible thing to do with a tree 20-200 m away. TreeGenPresets is used
## nowhere else, so the knobs live here rather than in the presets to keep the
## hero tree available.
const LOD_MAX_DEPTH := 4
const LOD_BARK_RINGS := 4
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

## Recycled MultiMeshInstance3Ds, emptied. See recycle().
var _pool: Array[MultiMeshInstance3D] = []
## Baked meshes per species, filled by bake_next().
var _meshes: Dictionary = {}
## Species that have been asked for, in the order they were first needed, which is
## the order _next_species() round-robins them in.
var _wanted: Array[int] = []
## How many meshes each species is wanted for, at most VARIANTS but no more than
## the trees it is wanted for: a stand with one spruce in it does not need ten
## different spruce meshes. It only ever goes up, so a species that turns out to
## be common gets its full set.
var _wanted_count: Dictionary = {}
## Where _next_species() starts looking, i.e. the one after the last one baked.
var _cursor := 0
## One raycast, reused for every tree: a stand is thousands of them and a fresh
## PhysicsRayQueryParameters3D each time is thousands of allocations.
var _ground_ray := PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.UP)


## Grows the part of one forest that falls inside `rect`, as one
## MultiMeshInstance3D per baked variant the trees land on.
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
		for _i in entry[1]:
			var spot := _random_point_in(points, rect, rng)
			if spot != Vector2.INF:
				transforms.append(_tree_transform(spot, rng))
		if transforms.is_empty():
			continue
		# Spread over the variants, so a cell is not one tree repeated. The split
		# costs one draw call each, which measured as free (see VARIANTS).
		var groups: Array = []
		for _v in _baked(entry[0]).size():
			groups.append([])
		for transform in transforms:
			var group: Array = groups[randi() % groups.size()]
			group.append(transform)
		for i in groups.size():
			if not groups[i].is_empty():
				added.append(_multimesh(_baked(entry[0])[i], groups[i]))
	return added


## Queues the meshes a stand of `type` covering `area` m2 would need and returns
## whether they are all there, i.e. whether plant_forest_in_rect() would now grow
## it. Cheap: nothing is grown and no raycast is cast.
##
## It waits for all of a stand's meshes rather than just the first. Otherwise the
## stand in front of the player is planted two frames in, when one variant exists,
## and every tree in it is that one mesh, which makes VARIANTS pointless. The wait
## costs no real time: the baking happens either way.
func needs_ready(type: ForestType, area: float) -> bool:
	var ready := true
	for entry in _plan(type, area):
		request_baking(entry[0], entry[1])
		if _baked(entry[0]).size() < _wanted_count[entry[0]]:
			ready = false
	return ready


## What a stand of this type covering `area` m2 would grow, as one
## [species, tree count] per species that gets at least one tree, in drawing order.
func _plan(type: ForestType, area: float) -> Array:
	var densities: Array = DENSITY_OAK_FOREST
	if type == ForestType.SpruceForest:
		densities = DENSITY_SPRUCE_FOREST
	var plan: Array = []
	for i in densities.size():
		var count := floori(float(densities[i]) * area)
		if count > 0:
			plan.append([i, count])
	return plan


## Bakes the next wanted mesh and returns whether it did one. A caller with a
## per-frame budget should keep calling while this returns true; it is what spreads
## the procedural geometry over frames instead of dropping it all into the first
## one.
func bake_next() -> bool:
	var species := _next_species()
	if species < 0:
		return false
	var tree: TreeGenTree = _preset(species).call(randi())
	_apply_lod(tree)
	tree.regenerate()
	_baked(species).append(tree.mesh)
	tree.free()
	return true


## Which species to bake next: the one *after* the last one baked, so every species
## reaches its first mesh before any of them reaches its second. Taking simply the
## first species with room left is not round-robin: a cell holding one spruce and
## four oaks would then wait for all ten oak variants.
func _next_species() -> int:
	var n := _wanted.size()
	for i in n:
		var species: int = _wanted[(_cursor + i) % n]
		if _baked(species).size() < _wanted_count[species]:
			_cursor = (_cursor + i + 1) % n
			return species
	return -1


## Meshes still to bake, for a progress print.
func baking() -> int:
	var left := 0
	for species in _wanted:
		left += maxi(0, _wanted_count[species] - _baked(species).size())
	return left


## Asks for up to VARIANTS meshes of `species`, or `trees` if that is fewer --
## variety is only worth baking for a species that actually appears more than once.
func request_baking(species: int, trees: int) -> void:
	var want := clampi(trees, 1, VARIANTS)
	if _wanted_count.has(species):
		_wanted_count[species] = maxi(int(_wanted_count[species]), want)
		return
	_wanted_count[species] = want
	_wanted.append(species)


## The forest type an OSM forest feature should grow as, from its leaf_type or
## species tag. Coniferous means spruce; everything else, including an untagged
## stand, is broadleaved.
static func type_for(feature: OsmFeature) -> ForestType:
	var leaf := (feature as OsmForestArea).species().to_lower()
	for conifer in CONIFEROUS:
		if leaf.contains(conifer):
			return ForestType.SpruceForest
	return ForestType.OakForest


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


func _tree_transform(spot: Vector2, rng: RandomNumberGenerator) -> Transform3D:
	var position := Vector3(spot.x, _ground_height_at(spot.x, spot.y), spot.y)
	var scale := rng.randf_range(0.9, 1.1)
	var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale)
	return Transform3D(basis, position)


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
func _multimesh(mesh: ArrayMesh, transforms: Array) -> MultiMeshInstance3D:
	var instance := _take()
	instance.multimesh.mesh = mesh
	instance.multimesh.instance_count = transforms.size()
	for i in transforms.size():
		instance.multimesh.set_instance_transform(i, transforms[i])
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


func _baked(species: int) -> Array:
	if not _meshes.has(species):
		_meshes[species] = []
	return _meshes[species]


static func _preset(species: int) -> Callable:
	if species == SPECIES_SPRUCE:
		return TreeGenPresets.spruce
	return TreeGenPresets.oak


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
