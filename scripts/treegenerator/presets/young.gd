class_name TreeGenPresetsYoung
extends TreeGenPresetsCommon

## Static builders for the young trees: the saplings of the species in
## TreeGenPresetsAdult. The elm and the palm have no sapling here because
## nothing in the forest asks for them.
##
## A sapling is not the grown tree scaled down. It is a different tree, written
## here from scratch with its own branches, and what makes it read as one is:
##   - a short, thin stem,
##   - a crown that starts low down, so it is foliage from near the ground up
##     instead of a bare stem with a hat on it,
##   - one branch level fewer than the adult has, which is what a tree this
##     size actually has,
##   - more leaves on each of them, because a small crown needs them to read
##     as foliage at all,
##   - smaller leaves, so their share of the tree stays the same.
##
## The two files share only the textures and the base-tree helper, in
## TreeGenPresetsCommon, so a change to a grown tree cannot quietly change a
## sapling. Every builder takes an optional `random_seed`; the default 0 makes
## a new, unique tree on each call, and passing a fixed seed reproduces the
## same tree.

## A sapling's twigs are thinner than the floor an adult tree needs, or the
## taper bottoms out and the crown is a handful of stubs.
const MIN_BRANCH_RADIUS := 0.015


## A sapling: a tree with a stem, and twigs thin enough to stay twigs.
static func _sapling_tree(trunk_height: float, trunk_radius: float,
		bark_texture: Texture2D) -> TreeGenTree:
	var tree := base_tree(trunk_height, trunk_radius, bark_texture)
	tree.min_branch_radius = MIN_BRANCH_RADIUS
	return tree


## -- Oak ---------------------------------------------------------------------

## Builds a sapling oak. Pass a fixed `random_seed` to reproduce the exact same
## tree; the default 0 generates a new, unique tree on every call.
static func oak(random_seed: int = 0) -> TreeGenTree:
	var tree := _sapling_tree(8.0, 0.12, BARK_TEXTURE_OAK)
	tree.random_seed = random_seed
	tree.trunk_segments = 4
	tree.trunk_tip_taper = 0.45
	tree.branch_sets = [_oak_crown_set()]
	return tree


static func _oak_crown_set() -> TreeGenBranchSet:
	var crown := TreeGenBranchSet.new()
	crown.branch_length = 0.45
	crown.branch_length_variation = 0.2
	crown.branch_radius_fraction = 0.55
	crown.branch_tip_taper = 0.35
	crown.branch_angle = deg_to_rad(45.0)
	crown.branch_angle_variation = deg_to_rad(18.0)
	crown.rotate_variation = deg_to_rad(25.0)
	crown.density = 2.2
	crown.start_offset = 0.12
	crown.length_taper = 0.9
	crown.segments = 2
	crown.child_branch_sets = [_oak_twig_set()]
	return crown


static func _oak_twig_set() -> TreeGenBranchSet:
	var twig := TreeGenBranchSet.new()
	twig.branch_length = 0.45
	twig.branch_length_variation = 0.2
	twig.branch_radius_fraction = 0.45
	twig.branch_tip_taper = 0.35
	twig.branch_angle = deg_to_rad(60.0)
	twig.branch_angle_variation = deg_to_rad(15.0)
	twig.rotate_variation = deg_to_rad(30.0)
	twig.density = 3.0
	twig.start_offset = 0.05
	twig.segments = 2
	twig.leaf_sets = [_oak_leaves()]
	return twig


static func _oak_leaves() -> TreeGenLeafSet:
	var leaves := TreeGenLeafSet.new()
	leaves.leaf_count = 48
	leaves.leaf_count_variation = 0.3
	leaves.leaf_size = 0.5
	leaves.leaf_size_variation = 0.15
	leaves.leaf_aspect = 1.0
	leaves.leaf_aspect_variation = 0.15
	leaves.leaf_shape = 2
	leaves.start_dist = 0.25
	leaves.leaf_angle = deg_to_rad(40.0)
	leaves.leaf_angle_variation = deg_to_rad(12.0)
	leaves.leaf_bend = deg_to_rad(20.0)
	leaves.leaf_texture = LEAF_TEXTURE_OAK
	return leaves


## -- Spruce -------------------------------------------------------------------

## Builds a sapling spruce.
static func spruce(random_seed: int = 0) -> TreeGenTree:
	var tree := _sapling_tree(6.0, 0.1, BARK_TEXTURE_SPRUCE)
	tree.random_seed = random_seed
	tree.trunk_segments = 6
	tree.trunk_tip_taper = 0.25
	tree.branch_sets = [_spruce_main_set()]
	return tree


static func _spruce_main_set() -> TreeGenBranchSet:
	var main := TreeGenBranchSet.new()
	main.branch_length = 0.5
	main.branch_length_variation = 0.1
	main.branch_radius_fraction = 0.3
	main.branch_tip_taper = 0.3
	main.branch_angle = deg_to_rad(78.0)
	main.branch_angle_variation = deg_to_rad(10.0)
	main.rotate_variation = deg_to_rad(25.0)
	main.curve_variation = deg_to_rad(40.0)
	main.density = 3.0
	main.start_offset = 0.06
	main.length_taper = 0.6
	main.angle_taper = 0.85
	main.segments = 2
	main.child_branch_sets = [_spruce_twig_set()]
	return main


static func _spruce_twig_set() -> TreeGenBranchSet:
	var twig := TreeGenBranchSet.new()
	twig.branch_length = 0.35
	twig.branch_length_variation = 0.15
	twig.branch_radius_fraction = 0.5
	twig.branch_tip_taper = 0.3
	twig.branch_angle = deg_to_rad(40.0)
	twig.branch_angle_variation = deg_to_rad(20.0)
	twig.rotate_variation = deg_to_rad(40.0)
	twig.curve = -deg_to_rad(15.0)
	twig.density = 2.2
	twig.start_offset = 0.05
	twig.segments = 2
	twig.leaf_sets = [_spruce_needles()]
	return twig


static func _spruce_needles() -> TreeGenLeafSet:
	var needles := TreeGenLeafSet.new()
	needles.leaf_count = 48
	needles.leaf_count_variation = 0.2
	needles.leaf_size = 0.45
	needles.leaf_size_variation = 0.15
	needles.leaf_aspect = 1.0
	needles.leaf_aspect_variation = 0.1
	needles.leaf_shape = 0
	needles.start_dist = 0.12
	needles.leaf_texture = LEAF_TEXTURE_SPRUCE
	return needles


## -- Maple --------------------------------------------------------------------

## Builds a sapling maple.
static func maple(random_seed: int = 0) -> TreeGenTree:
	var tree := _sapling_tree(7.0, 0.1, BARK_TEXTURE_MAPLE)
	tree.random_seed = random_seed
	tree.trunk_segments = 4
	tree.trunk_tip_taper = 0.45
	tree.branch_sets = [_maple_crown_set()]
	return tree


static func _maple_crown_set() -> TreeGenBranchSet:
	var crown := TreeGenBranchSet.new()
	crown.branch_length = 0.5
	crown.branch_length_variation = 0.2
	crown.branch_radius_fraction = 0.5
	crown.branch_tip_taper = 0.5
	crown.branch_angle = deg_to_rad(48.0)
	crown.branch_angle_variation = deg_to_rad(18.0)
	crown.rotate_variation = deg_to_rad(22.0)
	crown.density = 2.0
	crown.start_offset = 0.14
	crown.length_taper = 0.85
	crown.segments = 2
	crown.child_branch_sets = [_maple_twig_set()]
	return crown


static func _maple_twig_set() -> TreeGenBranchSet:
	var twig := TreeGenBranchSet.new()
	twig.branch_length = 0.45
	twig.branch_length_variation = 0.2
	twig.branch_radius_fraction = 0.5
	twig.branch_tip_taper = 0.3
	twig.branch_angle = deg_to_rad(65.0)
	twig.branch_angle_variation = deg_to_rad(15.0)
	twig.rotate_variation = deg_to_rad(35.0)
	twig.density = 2.8
	twig.start_offset = 0.05
	twig.segments = 2
	twig.leaf_sets = [_maple_leaves()]
	return twig


static func _maple_leaves() -> TreeGenLeafSet:
	var leaves := TreeGenLeafSet.new()
	leaves.leaf_count = 44
	leaves.leaf_count_variation = 0.25
	leaves.leaf_size = 0.55
	leaves.leaf_size_variation = 0.18
	leaves.leaf_aspect = 1.0
	leaves.leaf_aspect_variation = 0.15
	leaves.leaf_shape = 1
	leaves.start_dist = 0.25
	leaves.leaf_angle = deg_to_rad(42.0)
	leaves.leaf_angle_variation = deg_to_rad(10.0)
	leaves.leaf_bend = deg_to_rad(15.0)
	leaves.leaf_texture = LEAF_TEXTURE_MAPLE
	return leaves


## -- Aspen --------------------------------------------------------------------

## Builds a sapling aspen.
static func aspen(random_seed: int = 0) -> TreeGenTree:
	var tree := _sapling_tree(8.0, 0.085, BARK_TEXTURE_ASPEN)
	tree.random_seed = random_seed
	tree.trunk_segments = 5
	tree.trunk_tip_taper = 0.4
	tree.branch_sets = [_aspen_crown_set()]
	return tree


static func _aspen_crown_set() -> TreeGenBranchSet:
	var crown := TreeGenBranchSet.new()
	crown.branch_length = 0.42
	crown.branch_length_variation = 0.15
	crown.branch_radius_fraction = 0.45
	crown.branch_tip_taper = 0.5
	crown.branch_angle = deg_to_rad(38.0)
	crown.branch_angle_variation = deg_to_rad(12.0)
	crown.rotate_variation = deg_to_rad(20.0)
	crown.density = 2.2
	crown.start_offset = 0.18
	crown.length_taper = 0.9
	crown.segments = 2
	crown.child_branch_sets = [_aspen_twig_set()]
	return crown


static func _aspen_twig_set() -> TreeGenBranchSet:
	var twig := TreeGenBranchSet.new()
	twig.branch_length = 0.45
	twig.branch_length_variation = 0.2
	twig.branch_radius_fraction = 0.5
	twig.branch_tip_taper = 0.3
	twig.branch_angle = deg_to_rad(60.0)
	twig.branch_angle_variation = deg_to_rad(15.0)
	twig.rotate_variation = deg_to_rad(35.0)
	twig.density = 2.8
	twig.start_offset = 0.05
	twig.segments = 2
	twig.leaf_sets = [_aspen_leaves()]
	return twig


static func _aspen_leaves() -> TreeGenLeafSet:
	var leaves := TreeGenLeafSet.new()
	leaves.leaf_count = 48
	leaves.leaf_count_variation = 0.25
	leaves.leaf_size = 0.45
	leaves.leaf_size_variation = 0.18
	leaves.leaf_aspect = 1.0
	leaves.leaf_aspect_variation = 0.15
	leaves.leaf_shape = 1
	leaves.start_dist = 0.25
	leaves.leaf_angle = deg_to_rad(42.0)
	leaves.leaf_angle_variation = deg_to_rad(10.0)
	leaves.leaf_bend = deg_to_rad(15.0)
	leaves.leaf_texture = LEAF_TEXTURE_ASPEN
	return leaves


## -- Birch --------------------------------------------------------------------

## Builds a sapling birch.
static func birch(random_seed: int = 0) -> TreeGenTree:
	var tree := _sapling_tree(8.5, 0.095, BARK_TEXTURE_BIRCH)
	tree.random_seed = random_seed
	tree.trunk_segments = 5
	tree.trunk_tip_taper = 0.4
	tree.branch_sets = [_birch_crown_set()]
	return tree


static func _birch_crown_set() -> TreeGenBranchSet:
	var crown := TreeGenBranchSet.new()
	crown.branch_length = 0.45
	crown.branch_length_variation = 0.15
	crown.branch_radius_fraction = 0.45
	crown.branch_tip_taper = 0.5
	crown.branch_angle = deg_to_rad(42.0)
	crown.branch_angle_variation = deg_to_rad(15.0)
	crown.rotate_variation = deg_to_rad(20.0)
	crown.density = 2.4
	crown.start_offset = 0.2
	crown.length_taper = 0.9
	crown.segments = 2
	crown.child_branch_sets = [_birch_twig_set()]
	return crown


static func _birch_twig_set() -> TreeGenBranchSet:
	var twig := TreeGenBranchSet.new()
	twig.branch_length = 0.42
	twig.branch_length_variation = 0.18
	twig.branch_radius_fraction = 0.5
	twig.branch_tip_taper = 0.3
	twig.branch_angle = deg_to_rad(62.0)
	twig.branch_angle_variation = deg_to_rad(15.0)
	twig.rotate_variation = deg_to_rad(35.0)
	twig.density = 2.8
	twig.start_offset = 0.05
	twig.segments = 2
	twig.leaf_sets = [_birch_leaves()]
	return twig


static func _birch_leaves() -> TreeGenLeafSet:
	var leaves := TreeGenLeafSet.new()
	leaves.leaf_count = 48
	leaves.leaf_count_variation = 0.25
	leaves.leaf_size = 0.5
	leaves.leaf_size_variation = 0.18
	leaves.leaf_aspect = 1.0
	leaves.leaf_aspect_variation = 0.15
	leaves.leaf_shape = 1
	leaves.start_dist = 0.25
	leaves.leaf_angle = deg_to_rad(42.0)
	leaves.leaf_angle_variation = deg_to_rad(10.0)
	leaves.leaf_bend = deg_to_rad(15.0)
	leaves.leaf_texture = LEAF_TEXTURE_BIRCH
	return leaves


## -- Pine ---------------------------------------------------------------------

## Builds a sapling pine.
static func pine(random_seed: int = 0) -> TreeGenTree:
	var tree := _sapling_tree(9.0, 0.11, BARK_TEXTURE_PINE)
	tree.random_seed = random_seed
	tree.trunk_segments = 6
	tree.trunk_tip_taper = 0.35
	tree.branch_sets = [_pine_crown_set()]
	return tree


static func _pine_crown_set() -> TreeGenBranchSet:
	var crown := TreeGenBranchSet.new()
	crown.branch_length = 0.4
	crown.branch_length_variation = 0.15
	crown.branch_radius_fraction = 0.45
	crown.branch_tip_taper = 0.5
	crown.branch_angle = deg_to_rad(62.0)
	crown.branch_angle_variation = deg_to_rad(12.0)
	crown.rotate_variation = deg_to_rad(22.0)
	crown.density = 2.6
	crown.start_offset = 0.12
	crown.length_taper = 0.9
	crown.segments = 2
	crown.child_branch_sets = [_pine_twig_set()]
	return crown


static func _pine_twig_set() -> TreeGenBranchSet:
	var twig := TreeGenBranchSet.new()
	twig.branch_length = 0.45
	twig.branch_length_variation = 0.18
	twig.branch_radius_fraction = 0.5
	twig.branch_tip_taper = 0.3
	twig.branch_angle = deg_to_rad(58.0)
	twig.branch_angle_variation = deg_to_rad(15.0)
	twig.rotate_variation = deg_to_rad(35.0)
	twig.density = 2.8
	twig.start_offset = 0.05
	twig.segments = 2
	twig.leaf_sets = [_pine_leaves()]
	return twig


static func _pine_leaves() -> TreeGenLeafSet:
	var leaves := TreeGenLeafSet.new()
	leaves.leaf_count = 48
	leaves.leaf_count_variation = 0.25
	leaves.leaf_size = 0.55
	leaves.leaf_size_variation = 0.18
	leaves.leaf_aspect = 1.0
	leaves.leaf_aspect_variation = 0.15
	leaves.leaf_shape = 1
	leaves.start_dist = 0.25
	leaves.leaf_angle = deg_to_rad(42.0)
	leaves.leaf_angle_variation = deg_to_rad(10.0)
	leaves.leaf_bend = deg_to_rad(15.0)
	leaves.leaf_texture = LEAF_TEXTURE_PINE
	return leaves
