class_name TreeGenPresets
## Static builders for a handful of classic trees, styled after the reference
## species in "Creation and Rendering of Realistic Trees" (Weber & Penn, 1995):
## an oak, a maple, a spruce, a weeping willow, an elm (vase form) and a palm.
## Every builder takes an optional `random_seed`; the default 0 makes a new,
## unique tree on each call, and passing a fixed seed reproduces the same tree.

static var BARK_TEXTURE_OAK: Texture2D = load("res://assets/textures/bark/Bark001_1K-JPG_Color.jpg")
static var BARK_TEXTURE_SPRUCE: Texture2D = load("res://assets/textures/bark/Bark008_1K-JPG_Color.jpg")
static var BARK_TEXTURE_MAPLE: Texture2D = load("res://assets/textures/bark/Bark005_1K-JPG_Color.jpg")
static var BARK_TEXTURE_WEEPING_WILLOW: Texture2D = load("res://assets/textures/bark/Bark003_1K-JPG_Color.jpg")
static var BARK_TEXTURE_PINE: Texture2D = load("res://assets/textures/bark/Bark004_1K-JPG_Color.jpg")
static var LEAF_TEXTURE_OAK: Texture2D = load("res://assets/textures/leaves/leaf-oak.png")
static var LEAF_TEXTURE_SPRUCE: Texture2D = load("res://assets/textures/leaves/leaf-spruce.png")
static var LEAF_TEXTURE_MAPLE: Texture2D = load("res://assets/textures/leaves/leaf-maple.png")

static func _base_tree(trunk_height: float, trunk_radius: float, bark_texture: Texture2D) -> TreeGenTree:
	var tree := TreeGenTree.new()
	tree.trunk_height = trunk_height
	tree.trunk_radius = trunk_radius
	tree.bark_texture = bark_texture
	return tree


## -- Oak ---------------------------------------------------------------------

## Builds an oak tree. Pass a fixed `random_seed` to reproduce the exact same
## tree; the default 0 generates a new, unique tree on every call.
static func oak(random_seed: int = 0) -> TreeGenTree:
	var tree := _base_tree(9.0, 0.55, BARK_TEXTURE_OAK)
	tree.seed = random_seed
	tree.trunk_segments = 5
	tree.trunk_tip_taper = 0.5
	tree.bark_color = Color(0.42, 0.28, 0.15)
	tree.branch_sets = [
		_oak_scaffold_set(),
		_oak_apex_set(),
	]
	return tree


static func _oak_scaffold_set() -> TreeGenBranchSet:
	var scaffold := TreeGenBranchSet.new()
	scaffold.set_name = "Oak main scaffold"
	scaffold.branch_length = 0.65
	scaffold.branch_length_variation = 0.25
	scaffold.branch_radius_fraction = 0.6
	scaffold.branch_tip_taper = 0.55
	scaffold.branch_angle = deg_to_rad(38.0)
	scaffold.branch_angle_variation = deg_to_rad(8.0)
	scaffold.rotate_variation = deg_to_rad(18.0)
	scaffold.curve = deg_to_rad(12.0)
	scaffold.curve_variation = deg_to_rad(4.0)
	scaffold.density = 1.2
	scaffold.start_offset = 0.3
	scaffold.length_taper = 0.8
	scaffold.segments = 4
	scaffold.child_branch_sets = [_oak_canopy_set()]
	return scaffold


static func _oak_canopy_set() -> TreeGenBranchSet:
	var canopy := TreeGenBranchSet.new()
	canopy.set_name = "Oak canopy"
	canopy.branch_length = 0.65
	canopy.branch_length_variation = 0.15
	canopy.branch_radius_fraction = 0.5
	canopy.branch_tip_taper = 0.45
	canopy.branch_angle = deg_to_rad(50.0)
	canopy.branch_angle_variation = deg_to_rad(10.0)
	canopy.rotate_variation = deg_to_rad(25.0)
	canopy.curve = deg_to_rad(8.0)
	canopy.spread = 0.15
	canopy.spread_variation = 0.1
	canopy.density = 2.0
	canopy.start_offset = 0.1
	canopy.length_taper = 0.95
	canopy.segments = 3
	canopy.child_branch_sets = [_oak_twig_set()]
	return canopy


static func _oak_twig_set() -> TreeGenBranchSet:
	var twig := TreeGenBranchSet.new()
	twig.set_name = "Oak leaf twigs"
	twig.branch_length = 0.4
	twig.branch_length_variation = 0.2
	twig.branch_radius_fraction = 0.45
	twig.branch_tip_taper = 0.35
	twig.branch_angle = deg_to_rad(65.0)
	twig.branch_angle_variation = deg_to_rad(15.0)
	twig.rotate_variation = deg_to_rad(30.0)
	twig.density = 3.0
	twig.start_offset = 0.05
	twig.segments = 2
	twig.leaf_sets = [_oak_leaves()]
	return twig


static func _oak_apex_set() -> TreeGenBranchSet:
	var apex := TreeGenBranchSet.new()
	apex.set_name = "Oak crown leader"
	apex.branch_length = 0.32
	apex.branch_length_variation = 0.2
	apex.branch_radius_fraction = 0.5
	apex.branch_tip_taper = 0.5
	apex.branch_angle = deg_to_rad(18.0)
	apex.branch_angle_variation = deg_to_rad(6.0)
	apex.rotate_variation = deg_to_rad(30.0)
	apex.curve = deg_to_rad(18.0)
	apex.density = 1.0
	apex.start_offset = 0.55
	apex.segments = 3
	apex.child_branch_sets = [_oak_canopy_set()]
	return apex


static func _oak_leaves() -> TreeGenLeafSet:
	var leaves := TreeGenLeafSet.new()
	leaves.set_name = "Oak leaves"
	leaves.leaf_count = 20
	leaves.leaf_count_variation = 0.3
	leaves.leaf_size = 0.3
	leaves.leaf_size_variation = 0.15
	leaves.leaf_aspect = 1.0 # 0.75
	leaves.leaf_aspect_variation = 0.15
	leaves.leaf_shape = 2
	leaves.start_dist = 0.3
	leaves.leaf_angle = deg_to_rad(40.0)
	leaves.leaf_angle_variation = deg_to_rad(12.0)
	leaves.leaf_bend = deg_to_rad(20.0)
	leaves.leaf_texture = LEAF_TEXTURE_OAK
	# leaves.leaf_color = Color(0.3, 0.55, 0.2)
	# leaves.leaf_color_variation = 0.12
	return leaves


## -- Maple -------------------------------------------------------------------

static func maple(random_seed: int = 0) -> TreeGenTree:
	var tree := _base_tree(10.0, 0.5, BARK_TEXTURE_MAPLE)
	tree.seed = random_seed
	tree.trunk_segments = 5
	tree.trunk_tip_taper = 0.55
	tree.bark_color = Color(0.32, 0.24, 0.17)
	tree.branch_sets = [_maple_scaffold_set()]
	return tree


static func _maple_scaffold_set() -> TreeGenBranchSet:
	var scaffold := TreeGenBranchSet.new()
	scaffold.set_name = "Maple scaffold"
	scaffold.branch_length = 0.7
	scaffold.branch_length_variation = 0.2
	scaffold.branch_radius_fraction = 0.5
	scaffold.branch_tip_taper = 0.6
	scaffold.branch_angle = deg_to_rad(30.0)
	scaffold.branch_angle_variation = deg_to_rad(6.0)
	scaffold.rotate_variation = deg_to_rad(20.0)
	scaffold.curve = deg_to_rad(15.0)
	scaffold.density = 1.0
	scaffold.start_offset = 0.35
	scaffold.length_taper = 0.85
	scaffold.segments = 4
	scaffold.child_branch_sets = [_maple_canopy_set()]
	return scaffold


static func _maple_canopy_set() -> TreeGenBranchSet:
	var canopy := TreeGenBranchSet.new()
	canopy.set_name = "Maple canopy"
	canopy.branch_length = 0.6
	canopy.branch_length_variation = 0.12
	canopy.branch_radius_fraction = 0.5
	canopy.branch_tip_taper = 0.5
	canopy.branch_angle = deg_to_rad(55.0)
	canopy.branch_angle_variation = deg_to_rad(8.0)
	canopy.rotate_variation = deg_to_rad(22.0)
	canopy.curve = deg_to_rad(10.0)
	canopy.density = 2.0
	canopy.start_offset = 0.08
	canopy.segments = 3
	canopy.child_branch_sets = [_maple_twig_set()]
	return canopy


static func _maple_twig_set() -> TreeGenBranchSet:
	var twig := TreeGenBranchSet.new()
	twig.set_name = "Maple leaf twigs"
	twig.branch_length = 0.38
	twig.branch_length_variation = 0.18
	twig.branch_radius_fraction = 0.5
	twig.branch_tip_taper = 0.3
	twig.branch_angle = deg_to_rad(70.0)
	twig.branch_angle_variation = deg_to_rad(12.0)
	twig.rotate_variation = deg_to_rad(35.0)
	twig.density = 3.5
	twig.start_offset = 0.05
	twig.segments = 2
	twig.leaf_sets = [_maple_leaves()]
	return twig


static func _maple_leaves() -> TreeGenLeafSet:
	var leaves := TreeGenLeafSet.new()
	leaves.set_name = "Maple leaves"
	leaves.leaf_count = 18
	leaves.leaf_count_variation = 0.25
	leaves.leaf_size = 0.34
	leaves.leaf_size_variation = 0.18
	leaves.leaf_aspect = 1.0 # 0.8
	leaves.leaf_aspect_variation = 0.15
	leaves.leaf_shape = 1
	leaves.start_dist = 0.25
	leaves.leaf_angle = deg_to_rad(42.0)
	leaves.leaf_angle_variation = deg_to_rad(10.0)
	leaves.leaf_bend = deg_to_rad(15.0)
	leaves.leaf_texture = LEAF_TEXTURE_MAPLE
	# leaves.leaf_color = Color(0.33, 0.5, 0.22)
	# leaves.leaf_color_variation = 0.15
	return leaves


## -- Spruce ------------------------------------------------------------------

static func spruce(random_seed: int = 0) -> TreeGenTree:
	var tree := _base_tree(12.0, 0.5, BARK_TEXTURE_SPRUCE)
	tree.seed = random_seed
	tree.trunk_segments = 9
	tree.trunk_tip_taper = 0.25
	tree.bark_color = Color(0.35, 0.27, 0.2)
	tree.branch_sets = [
		_spruce_main_set(),
		_spruce_apex_set(),
	]
	return tree


static func _spruce_main_set() -> TreeGenBranchSet:
	var main := TreeGenBranchSet.new()
	main.set_name = "Spruce whorls"
	main.branch_length = 0.45
	main.branch_length_variation = 0.1
	main.branch_radius_fraction = 0.3
	main.branch_tip_taper = 0.4
	main.branch_angle = deg_to_rad(60.0)
	main.branch_angle_variation = deg_to_rad(8.0)
	main.rotate_variation = deg_to_rad(25.0)
	main.curve = -deg_to_rad(35.0)
	main.curve_variation = deg_to_rad(10.0)
	main.density = 2.5
	main.start_offset = 0.06
	main.length_taper = 0.65
	main.angle_taper = 0.9
	main.segments = 3
	main.child_branch_sets = [_spruce_twig_set()]
	#main.leaf_sets = [_spruce_needles(256, 0.5)]
	return main


static func _spruce_apex_set() -> TreeGenBranchSet:
	var apex := TreeGenBranchSet.new()
	apex.set_name = "Spruce leader"
	apex.branch_length = 0.22
	apex.branch_length_variation = 0.15
	apex.branch_radius_fraction = 0.5
	apex.branch_tip_taper = 0.4
	apex.branch_angle = deg_to_rad(20.0)
	apex.branch_angle_variation = deg_to_rad(6.0)
	apex.rotate_variation = deg_to_rad(40.0)
	apex.curve = deg_to_rad(10.0)
	apex.density = 1.2
	apex.start_offset = 0.6
	apex.segments = 3
	apex.child_branch_sets = [_spruce_twig_set(false)]
	return apex


static func _spruce_twig_set(has_more_twigs=true) -> TreeGenBranchSet:
	var twig := TreeGenBranchSet.new()
	twig.set_name = "Spruce twigs"
	twig.branch_length = 0.4
	twig.branch_length_variation = 0.15
	twig.branch_radius_fraction = 0.5
	twig.branch_tip_taper = 0.3
	twig.branch_angle = deg_to_rad(75.0)
	twig.branch_angle_variation = deg_to_rad(12.0)
	twig.rotate_variation = deg_to_rad(40.0)
	twig.curve = -deg_to_rad(15.0)
	twig.density = 2.0
	twig.start_offset = 0.05
	twig.segments = 2
	if has_more_twigs:
		twig.child_branch_sets = [_spruce_twig_set(false)]
	twig.leaf_sets = [_spruce_needles(64, 0.25)]
	return twig


static func _spruce_needles(leaf_count, leaf_size) -> TreeGenLeafSet:
	var needles := TreeGenLeafSet.new()
	needles.set_name = "Spruce needles"
	needles.leaf_count = leaf_count
	needles.leaf_count_variation = 0.2
	needles.leaf_size = leaf_size
	needles.leaf_size_variation = 0.15
	needles.leaf_aspect = 1.0 # 0.3
	needles.leaf_aspect_variation = 0.1
	needles.leaf_shape = 0
	needles.start_dist = 0.12
	needles.leaf_angle = 0.0 # deg_to_rad(28.0)
	needles.leaf_angle_variation = 0.0 # deg_to_rad(8.0)
	needles.leaf_texture = LEAF_TEXTURE_SPRUCE
	# needles.leaf_color = Color(0.25, 0.5, 0.22)
	# needles.leaf_color_variation = 0.15
	return needles


## -- Weeping willow ----------------------------------------------------------

static func weeping_willow(random_seed: int = 0) -> TreeGenTree:
	var tree := _base_tree(7.0, 0.7, BARK_TEXTURE_WEEPING_WILLOW)
	tree.seed = random_seed
	tree.trunk_segments = 4
	tree.trunk_tip_taper = 0.6
	tree.bark_color = Color(0.28, 0.24, 0.18)
	tree.branch_sets = [_willow_scaffold_set()]
	return tree


static func _willow_scaffold_set() -> TreeGenBranchSet:
	var scaffold := TreeGenBranchSet.new()
	scaffold.set_name = "Willow scaffold"
	scaffold.branch_length = 0.32
	scaffold.branch_length_variation = 0.1
	scaffold.branch_radius_fraction = 0.45
	scaffold.branch_tip_taper = 0.5
	scaffold.branch_angle = deg_to_rad(40.0)
	scaffold.branch_angle_variation = deg_to_rad(8.0)
	scaffold.rotate_variation = deg_to_rad(20.0)
	scaffold.density = 0.8
	scaffold.start_offset = 0.3
	scaffold.segments = 3
	scaffold.child_branch_sets = [_willow_droop_set()]
	return scaffold


static func _willow_droop_set() -> TreeGenBranchSet:
	var droop := TreeGenBranchSet.new()
	droop.set_name = "Willow hanging branches"
	droop.branch_length = 0.7
	droop.branch_length_variation = 0.12
	droop.branch_radius_fraction = 0.45
	droop.branch_tip_taper = 0.35
	droop.branch_angle = deg_to_rad(20.0)
	droop.branch_angle_variation = deg_to_rad(6.0)
	droop.down_angle = deg_to_rad(55.0)
	droop.down_angle_variation = deg_to_rad(12.0)
	droop.rotate_variation = deg_to_rad(30.0)
	droop.curve = -deg_to_rad(60.0)
	droop.curve_variation = deg_to_rad(20.0)
	droop.density = 2.0
	droop.start_offset = 0.05
	droop.segments = 4
	droop.child_branch_sets = [_willow_twig_set()]
	return droop


static func _willow_twig_set() -> TreeGenBranchSet:
	var twig := TreeGenBranchSet.new()
	twig.set_name = "Willow curtain twigs"
	twig.branch_length = 0.45
	twig.branch_length_variation = 0.15
	twig.branch_radius_fraction = 0.4
	twig.branch_tip_taper = 0.15
	twig.branch_angle = deg_to_rad(25.0)
	twig.branch_angle_variation = deg_to_rad(10.0)
	twig.down_angle = deg_to_rad(70.0)
	twig.down_angle_variation = deg_to_rad(15.0)
	twig.rotate_variation = deg_to_rad(40.0)
	twig.curve = -deg_to_rad(80.0)
	twig.curve_variation = deg_to_rad(30.0)
	twig.density = 3.0
	twig.start_offset = 0.05
	twig.segments = 2
	twig.leaf_sets = [_willow_leaves()]
	return twig


static func _willow_leaves() -> TreeGenLeafSet:
	var leaves := TreeGenLeafSet.new()
	leaves.set_name = "Willow leaves"
	leaves.leaf_count = 16
	leaves.leaf_count_variation = 0.25
	leaves.leaf_size = 0.14
	leaves.leaf_size_variation = 0.15
	leaves.leaf_aspect = 0.35
	leaves.leaf_aspect_variation = 0.1
	leaves.leaf_shape = 0
	leaves.start_dist = 0.15
	leaves.leaf_angle = deg_to_rad(30.0)
	leaves.leaf_angle_variation = deg_to_rad(10.0)
	leaves.leaf_bend = deg_to_rad(45.0)
	leaves.leaf_color = Color(0.45, 0.62, 0.3)
	leaves.leaf_color_variation = 0.12
	return leaves


## -- Elm (vase form) ----------------------------------------------------------

static func elm(random_seed: int = 0) -> TreeGenTree:
	var tree := _base_tree(9.0, 0.5, BARK_TEXTURE_MAPLE) # TODO
	tree.seed = random_seed
	tree.trunk_segments = 5
	tree.trunk_tip_taper = 0.5
	tree.bark_color = Color(0.3, 0.25, 0.18)
	tree.branch_sets = [_elm_scaffold_set()]
	return tree


static func _elm_scaffold_set() -> TreeGenBranchSet:
	var scaffold := TreeGenBranchSet.new()
	scaffold.set_name = "Elm vase branches"
	scaffold.branch_length = 0.42
	scaffold.branch_length_variation = 0.1
	scaffold.branch_radius_fraction = 0.45
	scaffold.branch_tip_taper = 0.5
	scaffold.branch_angle = deg_to_rad(22.0)
	scaffold.branch_angle_variation = deg_to_rad(6.0)
	scaffold.rotate_variation = deg_to_rad(18.0)
	scaffold.curve = deg_to_rad(20.0)
	scaffold.curve_variation = deg_to_rad(5.0)
	scaffold.density = 0.9
	scaffold.start_offset = 0.4
	scaffold.length_taper = 0.9
	scaffold.segments = 4
	scaffold.child_branch_sets = [_elm_canopy_set()]
	return scaffold


static func _elm_canopy_set() -> TreeGenBranchSet:
	var canopy := TreeGenBranchSet.new()
	canopy.set_name = "Elm canopy"
	canopy.branch_length = 0.55
	canopy.branch_length_variation = 0.12
	canopy.branch_radius_fraction = 0.5
	canopy.branch_tip_taper = 0.45
	canopy.branch_angle = deg_to_rad(35.0)
	canopy.branch_angle_variation = deg_to_rad(8.0)
	canopy.rotate_variation = deg_to_rad(25.0)
	canopy.curve = deg_to_rad(12.0)
	canopy.density = 2.0
	canopy.start_offset = 0.08
	canopy.segments = 3
	canopy.child_branch_sets = [_elm_twig_set()]
	return canopy


static func _elm_twig_set() -> TreeGenBranchSet:
	var twig := TreeGenBranchSet.new()
	twig.set_name = "Elm leaf twigs"
	twig.branch_length = 0.35
	twig.branch_length_variation = 0.18
	twig.branch_radius_fraction = 0.45
	twig.branch_tip_taper = 0.35
	twig.branch_angle = deg_to_rad(60.0)
	twig.branch_angle_variation = deg_to_rad(12.0)
	twig.rotate_variation = deg_to_rad(30.0)
	twig.density = 3.5
	twig.start_offset = 0.05
	twig.segments = 2
	twig.leaf_sets = [_elm_leaves()]
	return twig


static func _elm_leaves() -> TreeGenLeafSet:
	var leaves := TreeGenLeafSet.new()
	leaves.set_name = "Elm leaves"
	leaves.leaf_count = 16
	leaves.leaf_count_variation = 0.25
	leaves.leaf_size = 0.24
	leaves.leaf_size_variation = 0.15
	leaves.leaf_aspect = 0.8
	leaves.leaf_aspect_variation = 0.15
	leaves.leaf_shape = 2
	leaves.start_dist = 0.3
	leaves.leaf_angle = deg_to_rad(38.0)
	leaves.leaf_angle_variation = deg_to_rad(10.0)
	leaves.leaf_bend = deg_to_rad(18.0)
	leaves.leaf_color = Color(0.3, 0.5, 0.25)
	leaves.leaf_color_variation = 0.15
	return leaves


## -- Palm ---------------------------------------------------------------------

static func palm(random_seed: int = 0) -> TreeGenTree:
	var tree := _base_tree(8.0, 0.3, BARK_TEXTURE_MAPLE) # TODO
	tree.seed = random_seed
	tree.trunk_segments = 6
	tree.trunk_tip_taper = 0.7
	tree.bark_color = Color(0.4, 0.3, 0.18)
	tree.branch_sets = [_palm_crown_set()]
	return tree


static func _palm_crown_set() -> TreeGenBranchSet:
	var crown := TreeGenBranchSet.new()
	crown.set_name = "Palm fronds"
	crown.branch_length = 0.55
	crown.branch_length_variation = 0.1
	crown.branch_radius_fraction = 0.55
	crown.branch_tip_taper = 0.5
	crown.branch_angle = deg_to_rad(75.0)
	crown.branch_angle_variation = deg_to_rad(8.0)
	crown.rotate_variation = deg_to_rad(30.0)
	crown.curve = -deg_to_rad(25.0)
	crown.curve_variation = deg_to_rad(10.0)
	crown.density = 1.5
	crown.start_offset = 0.85
	crown.segments = 3
	crown.leaf_sets = [_palm_frond_leaves()]
	return crown


static func _palm_frond_leaves() -> TreeGenLeafSet:
	var leaves := TreeGenLeafSet.new()
	leaves.set_name = "Palm frond leaflets"
	leaves.leaf_count = 7
	leaves.leaf_count_variation = 0.2
	leaves.leaf_size = 0.5
	leaves.leaf_size_variation = 0.2
	leaves.leaf_aspect = 0.4
	leaves.leaf_aspect_variation = 0.1
	leaves.leaf_shape = 0
	leaves.start_dist = 0.1
	leaves.leaf_angle = deg_to_rad(20.0)
	leaves.leaf_angle_variation = deg_to_rad(6.0)
	leaves.leaf_bend = deg_to_rad(40.0)
	leaves.leaf_color = Color(0.3, 0.62, 0.25)
	leaves.leaf_color_variation = 0.12
	return leaves
