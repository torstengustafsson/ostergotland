class_name TreeGenSkeleton
## Data model for the branch skeleton produced by TreeGenGenerator. A branch is
## a polyline (points) with a radius at every point. Leaf instances hang off the
## outer branches. The static helpers sample the polyline at an arbitrary
## fraction and build tilted direction vectors.

class BranchNode:
	var parent: BranchNode = null
	var depth := 0
	var is_trunk := false
	var length := 0.0
	var points: PackedVector3Array = PackedVector3Array()    ## points[0] is the base (embedded in the parent)
	var radii: PackedFloat32Array = PackedFloat32Array()     ## radii[i] belongs to points[i]
	var child_branches: Array[BranchNode] = []
	var leaf_instances: Array[LeafInstance] = []

class LeafInstance:
	var position := Vector3.ZERO
	var direction := Vector3.UP      ## where the leaf tip points away from the branch (card length axis)
	var roll := 0.0                  ## twist of the blade around its length axis, radians (does NOT move the tip; full spin fans clumped leaves around the branch)
	var size := 0.3
	var aspect := 0.7                ## width / height
	var bend := 0.0                  ## droop of the leaf tip, radians
	var color := Color.WHITE
	var texture: Texture2D = null    ## null selects the procedural leaf texture
	var is_tip_leaf := false         ## leader leaf at the branch tip, pointing along the branch


## Returns a point on the branch polyline at fraction `fraction` (0..1).
static func point_at(branch: BranchNode, fraction: float) -> Vector3:
	if branch.points.is_empty():
		return Vector3.ZERO
	var segment_pairs := branch.points.size() - 1
	var travel := clampf(fraction, 0.0, 1.0) * float(segment_pairs)
	var segment_index := mini(int(travel), segment_pairs - 1)
	var local := travel - float(segment_index)
	return branch.points[segment_index].lerp(branch.points[segment_index + 1], local)


## Returns the radius at fraction `fraction` (0..1) along the branch.
static func radius_at(branch: BranchNode, fraction: float) -> float:
	if branch.radii.is_empty():
		return 0.0
	var segment_pairs := branch.radii.size() - 1
	var travel := clampf(fraction, 0.0, 1.0) * float(segment_pairs)
	var segment_index := mini(int(travel), segment_pairs - 1)
	var local := travel - float(segment_index)
	return lerpf(branch.radii[segment_index], branch.radii[segment_index + 1], local)


## Returns the tangent (unit growth direction) at fraction `fraction` along the
## branch. Uses the segment straddling the fraction for a smooth result.
static func tangent_at(branch: BranchNode, fraction: float) -> Vector3:
	var segment_pairs := branch.points.size() - 1
	if segment_pairs <= 0:
		return Vector3.UP
	var travel := clampf(fraction, 0.0, 1.0) * float(segment_pairs)
	var segment_index := clampf(floor(travel), 0.0, float(segment_pairs - 1))
	var start_point := branch.points[int(segment_index)]
	var end_point := branch.points[int(segment_index) + 1]
	var tangent := end_point - start_point
	if tangent.length_squared() < 1.0e-9:
		return Vector3.UP
	return tangent.normalized()


## Rotates `reference_axis` by `tilt_angle` away from itself, then spins it
## `azimuth` radians around the axis. With reference UP this gives an outward
## horizontal tilt at `azimuth`; with reference DOWN it produces a hanging bend.
static func tilt_toward(reference_axis: Vector3, azimuth: float, tilt_angle: float) -> Vector3:
	var normalized_axis := reference_axis.normalized()
	if normalized_axis.length_squared() < 0.5:
		normalized_axis = Vector3.UP
	var horizontal := normalized_axis.cross(Vector3.UP)
	if horizontal.length_squared() < 1.0e-6:
		horizontal = normalized_axis.cross(Vector3.FORWARD)
	horizontal = horizontal.normalized().rotated(normalized_axis, azimuth)
	return normalized_axis.rotated(horizontal, tilt_angle).normalized()


## Rotates `direction` by `angle_radians` toward `target` (used for curve and
## spread bends along a branch). Handles collinear directions safely.
static func rotate_toward(direction: Vector3, target: Vector3, angle_radians: float) -> Vector3:
	if absf(angle_radians) < 1.0e-6:
		return direction
	var pivot_axis := direction.cross(target)
	if pivot_axis.length_squared() < 1.0e-9:
		if direction.dot(target) > 0.0:
			return direction
		pivot_axis = perpendicular(direction)
	return direction.rotated(pivot_axis.normalized(), clampf(angle_radians, -PI * 0.5, PI * 0.5)).normalized()


## Any unit vector perpendicular to `vector`.
static func perpendicular(vector: Vector3) -> Vector3:
	if absf(vector.dot(Vector3.UP)) < 0.9:
		return vector.cross(Vector3.UP).normalized()
	return vector.cross(Vector3.FORWARD).normalized()


## Total number of branch nodes under `root`, including the root itself.
static func count_branches(root: BranchNode) -> int:
	var total := 0
	var stack: Array[BranchNode] = [root]
	while not stack.is_empty():
		var branch: BranchNode = stack.pop_back()
		total += 1
		for child in branch.child_branches:
			stack.append(child)
	return total