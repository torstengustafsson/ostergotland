class_name ForestGen extends Node3D

## Plants trees on a forest's outline. It knows nothing about where forests come
## from or when they should exist -- that is ForestStreamer's job, and this is the
## half that does the growing, so that half can be reused on its own.
##
## Everything is in real metres (see Heightmap), so the densities below really are
## plants per square metre. They are demo values: an oak stand at 0.001/m^2 is one
## tree every ~32 m, which reads as woodland from a distance without being a
## forest.
##
## The unit of planting is a *cell*, not a forest: plant_region() grows only the
## part of an outline that falls inside the cell it is given, clipped and
## measured (ForestRegion). That is what lets a 31 ha stand appear as the player
## walks into it instead of arriving whole the moment its far edge comes within
## range.
##
## Where a tree may stand is the cell's business, not this one's: ForestCell
## holds the roads, the buildings and the water on the ground, and the trees
## already planted, so that no two trunks grow into each other and none of them
## stands in a road.
##
## The tree meshes are procedural and baked lazily, because that is the whole
## cost: baking one oak is ~30 ms against ~2 ms to place a tree. Baking is
## therefore one mesh per bake_next() call rather than per stand, and only for the
## species something actually needs.
##
## A stand holds trees of two ages (Type), and they are separate meshes: a
## sapling is a tree of its own, grown from its own preset, never a scaled
## adult, so a (species, type) pair is what a mesh is baked for and what a
## density is counted per. The undergrowth under them is not a tree at all --
## TreeGenPresetsUndergrowth builds it -- but it is planted and streamed with the
## stand, so it is planned the same way.

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
	TallGrass,
	Fern,
	Rock,
	NoSpecies,
}

## What a stand plants. A young tree is the same species grown small -- its own
## preset, its own mesh, see TreeGenPresetsYoung -- and a stand holds both: the
## adults carry the canopy, the young ones the understory under it. Undergrowth
## is not a tree: its species are the tall grass, the fern and the boulder, and
## its mesh comes from TreeGenPresetsUndergrowth.
enum TreeType {
	Adult,
	Young,
	Undergrowth,
}

## Each forest type's plants per square metre per species: the six trees (oak,
## spruce, maple, aspen, birch, pine) for the adults and for the young ones
## separately, and the undergrowth (tall grass, fern and rock).
## Nothing here is restricted to one tree per cell -- see _plan() and _extra().
##
## Tall grass is counted in **patches**, not blades: one instance of one baked
## mesh carries a whole patch of blades (TreeGenPresetsUndergrowth), so 0.6
## patches/m2 is ~8 blades and ~60 triangles per m2 -- the same order as the
## trees standing over it, which is the budget this density is picked against.
## A rock is counted per boulder, and it shares the undergrowth's 0.35 m gap, so
## two boulders may overlap: a glacial erratic field is clusters of stones, and
## the gap is there to spread grass, not to isolate rocks.
const FOREST_TYPE_TREES = {
	ForestType.LeafyForest: {
		TreeType.Adult: {
			TreeSpecies.Oak: 0.001,
			TreeSpecies.Spruce: 0.0002,
			TreeSpecies.Maple: 0.0004,
			TreeSpecies.Aspen: 0.0005,
			TreeSpecies.Birch: 0.0005,
			TreeSpecies.Pine: 0.00025,
		},
		TreeType.Young: {
			TreeSpecies.Oak: 0.002,
			TreeSpecies.Spruce: 0.0004,
			TreeSpecies.Maple: 0.0008,
			TreeSpecies.Aspen: 0.001,
			TreeSpecies.Birch: 0.001,
			TreeSpecies.Pine: 0.0003,
		},
		TreeType.Undergrowth: {
			TreeSpecies.Fern: 0.018,
			TreeSpecies.TallGrass: 0.3,
			TreeSpecies.Rock: 0.002,
		},
	},
	ForestType.ConiferousForest: {
		TreeType.Adult: {
			TreeSpecies.Oak: 0.0001,
			TreeSpecies.Spruce: 0.0005,
			TreeSpecies.Maple: 0.00005,
			TreeSpecies.Aspen: 0.0001,
			TreeSpecies.Birch: 0.001,
			TreeSpecies.Pine: 0.003,
		},
		TreeType.Young: {
			TreeSpecies.Oak: 0.0001,
			TreeSpecies.Spruce: 0.001,
			TreeSpecies.Maple: 0.00005,
			TreeSpecies.Aspen: 0.0001,
			TreeSpecies.Birch: 0.002,
			TreeSpecies.Pine: 0.004,
		},
		TreeType.Undergrowth: {
			TreeSpecies.Fern: 0.022,
			TreeSpecies.TallGrass: 0.15,
			TreeSpecies.Rock: 0.003,
		},
	}
}

class ForestSectionPlan:
	var species: TreeSpecies
	var treetype: TreeType
	var count := 0       ## whole plants this rectangle gets for certain
	var remainder := 0.0 ## chance of one more, from the fractional part
	func _init(_species: TreeSpecies, _treetype: TreeType, expected: float):
		species = _species
		treetype = _treetype
		count = floori(expected)
		remainder = expected - float(count)

## Baked meshes per species and type. One tree costs tens of milliseconds to
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

## How many spots are drawn for one tree, and the best of them taken. One draw
## lands where it lands, and a stand of them comes out in patches; taking the
## best of a batch spreads them out instead, at the cost of a few more draws.
const CANDIDATES := 12

## Spare nodes kept for reuse, capped so that walking through one enormous stand
## does not leave hundreds of nodes parked for the rest of the session.
const POOL_MAX := 96

## Tags that mean coniferous in OSM's leaf_type (and species) vocabulary.
const CONIFEROUS := ["needleleaved", "spruce", "pine", "conifer"]

## How far above and below a spot to cast for the ground, in metres. It has to
## clear the tallest terrain.
const GROUND_PROBE := 500.0

## The metadata key under which a tree node records its type, so a caller can
## tell the adults of a stand from the understory planted with them.
const TREETYPE_META := "tree_type"

## Recycled MultiMeshInstance3Ds, emptied. See recycle().
var _pool: Array[MultiMeshInstance3D] = []
## Baked meshes per (species, type), filled by bake_next(). The pair is the key
## because a sapling is its own mesh, not a scaled adult.
var _meshes: Dictionary = {}
## The (species, type) pairs that have been asked for, in the order they were
## first needed, which is the order _next_wanted() round-robins them in.
var _wanted: Array[Vector2i] = []
## How many meshes each (species, type) is wanted for, at most VARIANTS but no
## more than the trees it is wanted for: a stand with one spruce in it does not
## need ten different spruce meshes. It only ever goes up, so a species that
## turns out to be common gets its full set.
var _wanted_count: Dictionary = {}
## Where _next_wanted() starts looking, i.e. the one after the last one baked.
var _cursor := 0
## One raycast, reused for every tree: a stand is thousands of them and a fresh
## PhysicsRayQueryParameters3D each time is thousands of allocations.
var _ground_ray := PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.UP)


## Grows the part of one forest that falls inside one streaming cell, as one
## MultiMeshInstance3D per baked variant the trees land on.
##
## `region` is the forest's share of the cell (ForestRegion): where the trees
## may stand and how much forest there is to spread them over. `cell` is the
## cell they are planted in (ForestCell): what is on its ground, and the trees
## already standing in it.
##
## Both ages are grown: the adults at the stand's own density and the young ones
## at theirs, each from its own meshes, so a stand comes up with an understory
## under its canopy rather than with only the canopy. The undergrowth is grown
## with them, at its own density and from TreeGenPresetsUndergrowth's meshes.
##
## `seed_value` is what makes this safe to re-enter: the same cell of the same
## forest gives the same trees every time, so a tree never moves because a
## neighbour streamed in or out. It should come from the feature and the cell
## (ForestStreamer hashes the way id with the cell key).
##
## The count of trees comes from the forest's area in the cell, not from the
## cell's area: a cell that only clips the corner of a wood gets that corner's
## worth of trees and no more. Getting this wrong is what used to grow one
## trunk through another -- the corner was given a whole cell's worth of trees
## to stand in.
func plant_region(type: ForestType, region: ForestRegion, seed_value: int,
		cell: ForestCell) -> Array[MultiMeshInstance3D]:
	var added: Array[MultiMeshInstance3D] = []
	if region.polygons.is_empty() or region.forest_area <= 0.0:
		return added
	var plan := _plan(type, region.forest_area)
	if plan.is_empty() or not needs_ready(type, region.forest_area):
		return added

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for entry in plan:
		# Undergrowth is recorded in its own grid and spread by its own gap --
		# see ForestCell.can_plant_undergrowth().
		var undergrowth: bool = entry.treetype == TreeType.Undergrowth
		# How far the plant's body reaches from its origin, so that its body and
		# not just its origin keeps the ground clearance.
		var reach_m := _reach_m(entry.species) if undergrowth else 0.0
		var transforms: Array = []
		for _i in entry.count + _extra(entry.remainder, rng):
			var spot := _pick_spot(region, cell, rng, undergrowth, reach_m)
			if spot != Vector2.INF:
				if undergrowth:
					cell.add_undergrowth(spot)
				else:
					cell.add_tree(spot)
				transforms.append(_tree_transform(spot, entry.species, entry.treetype, rng))
		if transforms.is_empty():
			continue
		var meshes := _baked(_key(entry.species, entry.treetype))
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
				added.append(_multimesh(meshes[i], groups[i], entry.treetype))
	return added


## Queues the meshes a stand of `type` covering `area` m2 would need and returns
## whether they are all there, i.e. whether plant_region() would now grow it.
## Cheap: nothing is grown and no raycast is cast.
##
## It waits for all of a stand's meshes rather than just the first. Otherwise the
## stand in front of the player is planted two frames in, when one variant exists,
## and every tree in it is that one mesh, which makes VARIANTS pointless. The wait
## costs no real time: the baking happens either way.
##
## A stand needs every mesh it plans to plant, so nothing is planted until the
## saplings and the undergrowth are baked too.
func needs_ready(type: ForestType, area: float) -> bool:
	var all_baked := true
	for entry in _plan(type, area):
		request_baking(entry)
		var key := _key(entry.species, entry.treetype)
		if _baked(key).size() < _wanted_count[key]:
			all_baked = false
	return all_baked


## What a stand of this type covering `area` m2 would grow, as one
## [species, type, tree count] per species and type that gets at least one tree, in
## drawing order.
##
## The count is the floor of `density * area` and the fraction is carried in
## `remainder` rather than dropped, so a density below 1/cell_area does not round
## away to nothing in every cell. See _extra().
func _plan(foresttype: ForestType, area: float) -> Array:
	var densities: Dictionary = FOREST_TYPE_TREES[foresttype]
	var plan: Array = []
	for treetype in densities.keys():
		for species in densities[treetype].keys():
			var density = densities[treetype][species]
			var expected := float(density) * area
			if expected > 0.0:
				plan.append(ForestSectionPlan.new(species, treetype, expected))
	return plan


## One more plant with probability `remainder` -- the fractional part of the
## expected count, rounded stochastically instead of down. Without it a density
## under 1/cell_area floors to zero in every cell and the forest silently
## disappears, and the only densities that worked were the ones that happened to
## clear one plant per cell. The draw comes from the cell's own rng, so a cell
## still replants exactly the plants it planted before.
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
	var treetype := key.y as TreeType
	if treetype == TreeType.Undergrowth:
		var mesh_call := _preset(key.x as TreeSpecies, treetype)
		var mesh: ArrayMesh = mesh_call.call(randi())
		_baked(key).append(mesh)
		return true
	var tree: TreeGenTree = _preset(key.x as TreeSpecies, treetype).call(randi())
	_apply_lod(tree)
	tree.regenerate()
	_baked(key).append(tree.mesh)
	tree.free()
	return true


## Which (species, type) to bake next: the one *after* the last one baked, so
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
	return Vector2i(TreeSpecies.NoSpecies, TreeType.Adult)


## Meshes still to bake, for a progress print.
func baking() -> int:
	var left := 0
	for key in _wanted:
		left += maxi(0, _wanted_count[key] - _baked(key).size())
	return left


## Asks for up to VARIANTS meshes of the plan's species and type, or as many as
## the plan calls for if that is fewer -- variety is only worth baking for a
## species that actually appears more than once. A plan can call for a fraction
## of a plant per cell, and the floor of 1 still applies to it: without a mesh
## there is nothing to plant the occasional one with.
func request_baking(plan: ForestSectionPlan) -> void:
	var want := clampi(plan.count, 1, VARIANTS)
	var key := _key(plan.species, plan.treetype)
	if _wanted_count.has(key):
		_wanted_count[key] = maxi(int(_wanted_count[key]), want)
		return
	_wanted_count[key] = want
	_wanted.append(key)


## The key a species and an type are stored under, as one Vector2i so it can be a
## dictionary key: the mesh of a sapling is not the mesh of the tree it grows
## into, so the type is part of the key and not a detail of the species.
static func _key(species: TreeSpecies, type: TreeType) -> Vector2i:
	return Vector2i(species, type)


## The forest type an OSM forest feature should grow as, from its leaf_type or
## species tag. Coniferous means spruce; everything else, including an untagged
## stand, is broadleaved.
static func type_for(feature: OsmFeature) -> ForestType:
	var leaf := (feature as OsmForestArea).species().to_lower()
	for conifer in CONIFEROUS:
		if leaf.contains(conifer):
			return ForestType.ConiferousForest
	return ForestType.LeafyForest


## The spot for one plant: the best of a batch of candidates, each scored by how
## far it is from the nearest plant of the same kind already planted in the cell.
##
## A candidate that would break the gap, or that stands on a road or in a lake,
## is not a candidate at all -- the cell answers that -- so the batch is only
## ever made of spots a plant could stand in. `reach_m` is how far an
## undergrowth plant's body reaches from its origin, which the cell adds to the
## ground clearance; a tree's reach is not counted, so it is 0.
##
## The best of several is what keeps a stand from clumping. Without it the
## plants are a plain random walk, and a wood comes out in patches with bare
## ground between them rather than evenly spread.
##
## `undergrowth` selects the cell's rule: patches of grass keep their distance
## from other grass only, so they can crowd a trunk and each other, while trees
## answer to the trunk gap.
func _pick_spot(region: ForestRegion, cell: ForestCell,
		rng: RandomNumberGenerator, undergrowth: bool, reach_m: float) -> Vector2:
	var best := Vector2.INF
	var best_score := -1.0
	for _candidate in CANDIDATES:
		var spot := region.sample(rng)
		if spot == Vector2.INF:
			continue
		if not (cell.can_plant_undergrowth(spot, reach_m) if undergrowth
				else cell.can_plant(spot)):
			continue
		var score := cell.nearest_undergrowth_distance(spot) if undergrowth \
				else cell.nearest_tree_distance(spot)
		if score > best_score:
			best_score = score
			best = spot
	return best


## How much a tree's baked size is scaled per instance. A young tree varies
## more: the understory is full of saplings of every size, while the adults of
## a stand are all roughly grown. The undergrowth's ranges are their own, see
## TreeGenPresetsUndergrowth.SIZE_RANGE and ROCK_SIZE_RANGE.
const ADULT_SIZE_RANGE := Vector2(0.9, 1.1)
const YOUNG_SIZE_RANGE := Vector2(0.7, 1.3)


func _tree_transform(spot: Vector2, species: TreeSpecies, type: TreeType,
		rng: RandomNumberGenerator) -> Transform3D:
	var origin := Vector3(spot.x, _ground_height_at(spot.x, spot.y), spot.y)
	var limits := _size_range(species, type)
	var size := rng.randf_range(limits.x, limits.y)
	var rot := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * size)
	return Transform3D(rot, origin)


static func _size_range(species: TreeSpecies, type: TreeType) -> Vector2:
	if type == TreeType.Undergrowth:
		if species == TreeSpecies.Rock:
			return TreeGenPresetsUndergrowth.ROCK_SIZE_RANGE
		return TreeGenPresetsUndergrowth.SIZE_RANGE
	return YOUNG_SIZE_RANGE if type == TreeType.Young else ADULT_SIZE_RANGE


## How far an undergrowth plant's geometry reaches from its origin, in metres, at
## the largest instance size: what ForestCell adds to the ground clearance, so
## it is the plant's body that keeps the clearance and not only the origin the
## placement test measures from. One constant per undergrowth species, derived
## from its own geometry -- see TreeGenPresetsUndergrowth.GRASS_REACH_M.
static func _reach_m(species: TreeSpecies) -> float:
	if species == TreeSpecies.Rock:
		return TreeGenPresetsUndergrowth.ROCK_REACH_M
	if species == TreeSpecies.Fern:
		return TreeGenPresetsUndergrowth.FERN_REACH_M
	return TreeGenPresetsUndergrowth.GRASS_REACH_M


## One MultiMeshInstance3D holding `transforms` instances of `mesh`, taken from the
## pool if there is one spare. See recycle().
##
## The node records its type, so a caller can tell an adult stand from the
## understory planted with it without having to look at the mesh.
func _multimesh(mesh: ArrayMesh, transforms: Array, type: TreeType) -> MultiMeshInstance3D:
	var instance := _take()
	instance.multimesh.mesh = mesh
	instance.multimesh.instance_count = transforms.size()
	for i in transforms.size():
		instance.multimesh.set_instance_transform(i, transforms[i])
	instance.set_meta(TREETYPE_META, type)
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


## The baked meshes of one species and type, in the order they were baked.
func _baked(key: Vector2i) -> Array:
	if not _meshes.has(key):
		_meshes[key] = []
	return _meshes[key]


## The builder for one species and type: the adult tree, the sapling of the same
## species, or the plant that is not a tree at all.
static func _preset(species: TreeSpecies, type: TreeType) -> Callable:
	match species:
		TreeSpecies.Oak:
			return TreeGenPresetsYoung.oak if type == TreeType.Young else TreeGenPresetsAdult.oak
		TreeSpecies.Spruce:
			return TreeGenPresetsYoung.spruce if type == TreeType.Young else TreeGenPresetsAdult.spruce
		TreeSpecies.Maple:
			return TreeGenPresetsYoung.maple if type == TreeType.Young else TreeGenPresetsAdult.maple
		TreeSpecies.Aspen:
			return TreeGenPresetsYoung.aspen if type == TreeType.Young else TreeGenPresetsAdult.aspen
		TreeSpecies.Birch:
			return TreeGenPresetsYoung.birch if type == TreeType.Young else TreeGenPresetsAdult.birch
		TreeSpecies.Pine:
			return TreeGenPresetsYoung.pine if type == TreeType.Young else TreeGenPresetsAdult.pine
		TreeSpecies.TallGrass:
			return TreeGenPresetsUndergrowth.create_tall_grass_mesh
		TreeSpecies.Fern:
			return TreeGenPresetsUndergrowth.create_fern_mesh
		TreeSpecies.Rock:
			return TreeGenPresetsUndergrowth.create_rock_mesh
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
