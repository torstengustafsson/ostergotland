class_name TreeGenGenerator
## Grows the branch skeleton of a TreeGenTree using the method described in
## J. Weber and J. Penn, "Creation and Rendering of Realistic Trees" (1995):
##
## - A trunk is a tapered polyline subdivided into segments.
## - Every branch set spawns `density * parent_segments` branches, spread evenly
##   along (and rotated around) the parent. Each branch is divided into
##   `segments` steps whose direction is progressively bent by `curve`, `spread`
##   and `curve_back`.
## - Child branch sets attach recursively to the new branches; leaf sets scatter
##   leaf cards over the outer ones.

const LEAF_TILT_JITTER := deg_to_rad(12.0)   ## max random tilt off the perpendicular plane, radians

static func generate_skeleton(tree: TreeGenTree) -> TreeGenSkeleton.BranchNode:
	var random := _new_random(tree.seed)

	var trunk := TreeGenSkeleton.BranchNode.new()
	trunk.is_trunk = true
	trunk.depth = 0
	trunk.length = tree.trunk_height
	trunk.points = _build_trunk_points(tree)
	trunk.radii = _build_trunk_radii(tree)
	trunk.child_branches = []

	for branch_set in tree.branch_sets:
		_expand_branch_set(trunk, branch_set, tree, 1, random)
	return trunk


static var _auto_seed_rng: RandomNumberGenerator = null

static func _new_random(seed: int) -> RandomNumberGenerator:
	var random := RandomNumberGenerator.new()
	if seed == 0:
		# 0 means "auto": draw a unique seed from one shared, time-seeded RNG so
		# that trees created in the same instant (same tick) still differ, and
		# re-running the scene produces new trees.
		if _auto_seed_rng == null:
			_auto_seed_rng = RandomNumberGenerator.new()
			_auto_seed_rng.randomize()
		random.seed = _auto_seed_rng.randi()
	else:
		random.seed = seed
	return random


static func _build_trunk_points(tree: TreeGenTree) -> PackedVector3Array:
	var segment_count := maxi(tree.trunk_segments, 1)
	var points := PackedVector3Array()
	var height_step := tree.trunk_height / float(segment_count)
	for segment_index in range(segment_count + 1):
		points.append(Vector3(0.0, segment_index * height_step, 0.0))
	return points


static func _build_trunk_radii(tree: TreeGenTree) -> PackedFloat32Array:
	var segment_count := maxi(tree.trunk_segments, 1)
	var radii := PackedFloat32Array()
	for segment_index in range(segment_count + 1):
		var fraction := float(segment_index) / float(segment_count)
		var base_bulge := 1.0 + 0.08 * sin(fraction * PI) ## widest just above the ground
		radii.append(tree.trunk_radius * lerpf(1.0, tree.trunk_tip_taper, fraction) * base_bulge)
	return radii


## Grows every branch of `branch_set` along `parent_branch`, scatters the set's
## leaves, then expands each child branch set on the new branches. `depth` is the
## recursion level relative to the trunk (trunk = 0).
static func _expand_branch_set(
	parent_branch: TreeGenSkeleton.BranchNode,
	branch_set: TreeGenBranchSet,
	tree: TreeGenTree,
	depth: int,
	random: RandomNumberGenerator
) -> void:
	if depth > tree.max_depth:
		return

	var parent_segment_count := parent_branch.points.size() - 1
	var stem_count_float := branch_set.density * float(parent_segment_count)
	stem_count_float *= 1.0 + random.randf_range(-branch_set.density_variation, branch_set.density_variation) * 0.5
	var stem_count := int(round(stem_count_float))
	if branch_set.max_branches > 0:
		stem_count = mini(stem_count, branch_set.max_branches)
	if stem_count < 1:
		return

	var first_offset := clampf(branch_set.start_offset, 0.0, 0.99)
	var attach_fractions := _build_attach_fractions(first_offset, stem_count, branch_set, random)
	var stem_azimuths := _build_stem_azimuths(stem_count, branch_set, random)

	for stem_index in range(stem_count):
		var branch := _grow_branch(
			parent_branch, branch_set, depth, attach_fractions[stem_index], stem_azimuths[stem_index], random
		)
		parent_branch.child_branches.append(branch)

		for leaf_set in branch_set.leaf_sets:
			scatter_leaves(branch, leaf_set, random)

		for child_set in branch_set.child_branch_sets:
			_expand_branch_set(branch, child_set, tree, depth + 1, random)


## Builds the attach points along a parent as irregular, ever-rising positions
## from `first_offset` to the tip. Random step sizes create natural clumping
## instead of the evenly spaced rings that read as an artificial spiral.
static func _build_attach_fractions(
	first_offset: float,
	stem_count: int,
	branch_set: TreeGenBranchSet,
	random: RandomNumberGenerator
) -> Array:
	var raw_positions: Array = []
	var running_position := 0.0
	for _index in range(stem_count):
		running_position += 0.5 + random.randf() ## random step, mean 1.0
		raw_positions.append(running_position)
	var total_span: float = raw_positions[raw_positions.size() - 1]
	var usable_length := 1.0 - first_offset

	var fractions: Array = []
	for raw_position in raw_positions:
		var raw_value: float = raw_position
		var fraction := first_offset + (raw_value / total_span) * usable_length
		if branch_set.attach_jitter > 0.0:
			fraction += random.randf_range(-branch_set.attach_jitter, branch_set.attach_jitter)
		fractions.append(clampf(fraction, 0.0, 1.0))
	return fractions


## Builds balanced azimuths around the parent: an even spread rotated by a
## per-tree random phase, shuffled so a branch's azimuth is uncorrelated with
## its height (this is what removes the upward helix), then jittered.
static func _build_stem_azimuths(
	stem_count: int,
	branch_set: TreeGenBranchSet,
	random: RandomNumberGenerator
) -> Array:
	var even_spread: Array = []
	var set_rotation := branch_set.rotate + random.randf() * TAU
	for stem_index in range(stem_count):
		even_spread.append(fmod(TAU * float(stem_index) / float(stem_count) + set_rotation, TAU))

	# Fisher-Yates shuffle: decouples azimuth order from stem order.
	for index in range(stem_count - 1, 0, -1):
		var swap_index := random.randi_range(0, index)
		var held: float = even_spread[index]
		even_spread[index] = even_spread[swap_index]
		even_spread[swap_index] = held

	var azimuths: Array = []
	for index in range(stem_count):
		azimuths.append(even_spread[index] + random.randf_range(-branch_set.rotate_variation, branch_set.rotate_variation) * 0.5)
	return azimuths


## Builds a single branch of `branch_set` attached to `parent_branch` at
## `attach_fraction`, pointing away at `azimuth`.
static func _grow_branch(
	parent_branch: TreeGenSkeleton.BranchNode,
	branch_set: TreeGenBranchSet,
	depth: int,
	attach_fraction: float,
	azimuth: float,
	random: RandomNumberGenerator
) -> TreeGenSkeleton.BranchNode:
	var branch := TreeGenSkeleton.BranchNode.new()
	branch.parent = parent_branch
	branch.depth = depth

	var attach_point := TreeGenSkeleton.point_at(parent_branch, attach_fraction)
	var parent_radius := TreeGenSkeleton.radius_at(parent_branch, attach_fraction)
	var parent_tangent := TreeGenSkeleton.tangent_at(parent_branch, attach_fraction)

	# Length: the chosen base fraction of the parent, tapered up the parent and
	# with a per-branch random variation.
	var branch_length := parent_branch.length * branch_set.branch_length
	branch_length *= pow(branch_set.length_taper, attach_fraction)
	branch_length *= 1.0 + random.randf_range(-branch_set.branch_length_variation, branch_set.branch_length_variation) * 0.5
	branch.length = maxf(branch_length, 0.01)

	# Radius: relative to the parent's radius at the attach point.
	var base_radius := maxf(parent_radius * branch_set.branch_radius_fraction * random.randf_range(0.9, 1.1), 0.002)
	var tip_radius := base_radius * branch_set.branch_tip_taper

	# Direction:
	#   - elevation deviates from the parent tangent (tapered toward upright at
	#     the top); azimuth is passed in already balanced, phase-rotated and
	#     decoupled from the attach height.
	#   - a positive down_angle pulls the branch toward hanging straight down.
	var elevation := branch_set.branch_angle * pow(branch_set.angle_taper, attach_fraction)
	elevation += random.randf_range(-branch_set.branch_angle_variation, branch_set.branch_angle_variation) * 0.5
	var base_direction := TreeGenSkeleton.tilt_toward(parent_tangent, azimuth, elevation)
	if branch_set.down_angle > 0.0:
		var hang_angle := branch_set.down_angle + random.randf_range(-branch_set.down_angle_variation, branch_set.down_angle_variation) * 0.5
		var hang_direction := TreeGenSkeleton.tilt_toward(Vector3.DOWN, azimuth, hang_angle)
		var hang_weight := clampf(branch_set.down_angle / (PI * 0.5), 0.0, 1.0)
		base_direction = base_direction.slerp(hang_direction, hang_weight)
	base_direction = base_direction.normalized()

	var curve_total := branch_set.curve + random.randf_range(-branch_set.curve_variation, branch_set.curve_variation) * 0.5
	var curve_target := Vector3.UP if curve_total >= 0.0 else Vector3.DOWN
	var curve_step := curve_total / float(maxi(1, branch_set.segments))
	var spread_effective := branch_set.spread * (1.0 + random.randf_range(-branch_set.spread_variation, branch_set.spread_variation) * 0.5)

	# Embeds the base a little way into the parent so branch joints show no gap.
	var embed_distance := minf(parent_radius * 0.2, base_radius * 0.6)
	var segment_count := maxi(1, branch_set.segments)
	var segment_step := branch_length / float(segment_count)

	branch.points.append(attach_point - parent_tangent * embed_distance)
	var direction := base_direction
	for segment_index in range(segment_count + 1):
		var fraction := float(segment_index) / float(segment_count)
		branch.radii.append(lerpf(base_radius, tip_radius, fraction))
		if segment_index == segment_count:
			break
		branch.points.append(branch.points[segment_index] + direction * segment_step)

		# Curve: bend toward vertical over the whole length.
		if absf(curve_step) > 1.0e-5:
			direction = TreeGenSkeleton.rotate_toward(direction, curve_target, curve_step)
		# Curve back: re-straighten toward the base direction near the tip.
		if branch_set.curve_back > 0.0 and fraction > 0.4:
			var back_step := branch_set.curve_back * ((fraction - 0.4) / 0.6)
			direction = TreeGenSkeleton.rotate_toward(direction, base_direction, back_step)
		# Spread: splay outward (toward horizontal) along the length.
		if spread_effective > 0.0:
			var outward := Vector3(direction.x, 0.0, direction.z)
			if outward.length_squared() > 1.0e-6:
				var outward_step := minf(0.6, spread_effective * fraction)
				direction = TreeGenSkeleton.rotate_toward(direction, outward.normalized(), outward_step)
		direction = direction.normalized()
	return branch


## Scatters `leaf_count` leaf cards over `branch` between `start_dist` and its
## tip, storing them on the branch for the mesher.
static func scatter_leaves(branch: TreeGenSkeleton.BranchNode, leaf_set: TreeGenLeafSet, random: RandomNumberGenerator) -> void:
	if branch.points.size() < 2:
		return
	var leaf_count := int(round(leaf_set.leaf_count * (1.0 + random.randf_range(-leaf_set.leaf_count_variation, leaf_set.leaf_count_variation))))
	leaf_count = clampi(leaf_count, 0, 400)
	if leaf_count <= 0:
		return
	var start := clampf(
		leaf_set.start_dist + random.randf_range(-leaf_set.start_dist_variation, leaf_set.start_dist_variation) * 0.5,
		0.0, 0.99
	)
	for _leaf_index in range(leaf_count):
		var leaf_fraction := lerpf(start, 1.0, random.randf())
		var tangent := TreeGenSkeleton.tangent_at(branch, leaf_fraction)
		var azimuth := random.randf() * TAU

		var leaf := TreeGenSkeleton.LeafInstance.new()
		leaf.size = leaf_set.leaf_size * (1.0 + random.randf_range(-leaf_set.leaf_size_variation, leaf_set.leaf_size_variation) * 0.5)
		leaf.aspect = leaf_set.leaf_aspect * (1.0 + random.randf_range(-leaf_set.leaf_aspect_variation, leaf_set.leaf_aspect_variation) * 0.5)
		leaf.bend = leaf_set.leaf_bend * random.randf_range(0.6, 1.0)
		leaf.color = leaf_set.leaf_color.lerp(
			Color(1.0, 1.0, 1.0, 1.0), random.randf_range(-leaf_set.leaf_color_variation, leaf_set.leaf_color_variation)
		)
		leaf.texture = leaf_set.leaf_texture if leaf_set.leaf_texture != null \
			else TreeGenMaterialLibrary.procedural_leaf_texture(leaf_set.leaf_shape)
		# Full spin around the leaf's length axis so clumped leaves fan out in
		# all directions around the branch instead of sharing one orientation.
		leaf.roll = random.randf() * TAU
		# Leaves stick out perpendicular to the branch: `azimuth` gives a full
		# rotation around the branch axis, so neighboring leaves all point in
		# different radial directions.
		leaf.direction = _radial_outward(tangent, azimuth)
		# Give each leaf a small random tilt off the perfect perpendicular so
		# leaves don't stand at exactly right angles to the branch. Rotating
		# around a random axis perpendicular to the direction.
		leaf.direction = leaf.direction.rotated(
			_radial_outward(leaf.direction, random.randf() * TAU),
			random.randf_range(-LEAF_TILT_JITTER, LEAF_TILT_JITTER)
		).normalized()
		# Seat the leaf on the branch surface instead of its centerline: lift the
		# card base radially off the axis by the local bark radius plus a little
		# extra, otherwise small leaves on thick branches are swallowed by bark.
		var outward := _radial_outward(tangent, azimuth)
		var lift := TreeGenSkeleton.radius_at(branch, leaf_fraction) + leaf.size * 0.3
		leaf.position = TreeGenSkeleton.point_at(branch, leaf_fraction) + outward * lift
		branch.leaf_instances.append(leaf)

	_add_tip_leaf(branch, leaf_set, random)


## Adds a single leader leaf at the very tip of a leaf-bearing branch, pointing
## straight out along the branch direction. Only one per branch, even when
## several leaf sets scatter onto it.
static func _add_tip_leaf(
	branch: TreeGenSkeleton.BranchNode,
	leaf_set: TreeGenLeafSet,
	random: RandomNumberGenerator
) -> void:
	for existing in branch.leaf_instances:
		if existing.is_tip_leaf:
			return

	var tangent := TreeGenSkeleton.tangent_at(branch, 1.0)
	var leaf := TreeGenSkeleton.LeafInstance.new()
	leaf.is_tip_leaf = true
	leaf.direction = tangent
	leaf.size = leaf_set.leaf_size * (1.0 + random.randf_range(-leaf_set.leaf_size_variation, leaf_set.leaf_size_variation) * 0.5)
	leaf.aspect = leaf_set.leaf_aspect
	leaf.bend = 0.0   ## keep flying straight along the branch
	leaf.color = leaf_set.leaf_color.lerp(
		Color(1.0, 1.0, 1.0, 1.0), random.randf_range(-leaf_set.leaf_color_variation, leaf_set.leaf_color_variation)
	)
	leaf.texture = leaf_set.leaf_texture if leaf_set.leaf_texture != null \
		else TreeGenMaterialLibrary.procedural_leaf_texture(leaf_set.leaf_shape)
	leaf.roll = random.randf_range(-0.4, 0.4)
	# Seat the leaf's base exactly on the branch tip so it grows straight out
	# beyond the end of the branch.
	leaf.position = TreeGenSkeleton.point_at(branch, 1.0) + tangent * (leaf.size * 0.5)
	branch.leaf_instances.append(leaf)


## Unit vector perpendicular to `tangent`, pointing radially outward around the
## branch axis at the given azimuth (used to seat leaves on the bark surface and
## as the leaf's sticking-out direction).
static func _radial_outward(tangent: Vector3, azimuth: float) -> Vector3:
	var axis := tangent.normalized()
	var helper := Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	var right := axis.cross(helper).normalized()
	var up := right.cross(axis)
	return (right * cos(azimuth) + up * sin(azimuth)).normalized()