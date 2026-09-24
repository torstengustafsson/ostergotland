class_name TreeGenMesher
## Turns a TreeGenSkeleton into an ArrayMesh: one bark surface (surface 0) plus
## one leaf surface per distinct leaf texture. Bark is built as tapered
## cylinders around each branch polyline with smooth, transport-following ring
## frames; leaves are double-sided quads using an alpha-cutout material.

const BARK_UV_TILE := 0.5   ## bark texture tiles per world unit along a branch
const MIN_BARK_RADIUS := 0.001

## Builds the full mesh for `skeleton` on behalf of `tree` (bark texture, bark
## color and ring count come from the tree).
static func build_mesh(skeleton: TreeGenSkeleton.BranchNode, tree: TreeGenTree) -> ArrayMesh:
	var bark_surface := SurfaceTool.new()
	bark_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark_vertex_start := 0

	var leaf_surface_textures: Array = []
	var leaf_surfaces: Array[SurfaceTool] = []

	var stack: Array[TreeGenSkeleton.BranchNode] = [skeleton]
	while not stack.is_empty():
		var branch: TreeGenSkeleton.BranchNode = stack.pop_back()
		bark_vertex_start = _add_branch_cylinder(bark_surface, branch, tree.bark_rings, bark_vertex_start)
		_add_branch_leaves(branch, leaf_surface_textures, leaf_surfaces)
		for child in branch.child_branches:
			stack.append(child)

	var mesh := bark_surface.commit()
	mesh.surface_set_material(0, TreeGenMaterialLibrary.bark_material(tree.bark_texture, tree.bark_color))

	for surface_index in range(leaf_surfaces.size()):
		var leaf_mesh := leaf_surfaces[surface_index].commit()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, leaf_mesh.surface_get_arrays(0))
		mesh.surface_set_material(
			mesh.get_surface_count() - 1,
			TreeGenMaterialLibrary.leaf_material(leaf_surface_textures[surface_index])
		)
	return mesh


## Extrudes one branch as a tapered tube: a ring of `ring_count` vertices at
## every polyline point, stitched into outward-facing triangles. The trunk gets
## a cap on its base. Returns the running vertex count for the surface.
static func _add_branch_cylinder(
	surface_tool: SurfaceTool,
	branch: TreeGenSkeleton.BranchNode,
	ring_count: int,
	vertex_start: int
) -> int:
	var segment_count := branch.points.size() - 1
	if segment_count < 1:
		return vertex_start

	var ring_vertices: Array = []   ## ring_vertices[segment][side] = vertex index
	var added_vertices := 0

	# Propagate a perpendicular frame along the polyline so rings don't twist.
	var first_tangent := (branch.points[1] - branch.points[0]).normalized()
	var frame_u := TreeGenSkeleton.perpendicular(first_tangent)
	var frame_v := first_tangent.cross(frame_u)

	var arc_length := 0.0
	for segment_index in range(segment_count + 1):
		var point := branch.points[segment_index]
		var radius := maxf(branch.radii[segment_index], MIN_BARK_RADIUS)
		if segment_index > 0:
			arc_length += branch.points[segment_index - 1].distance_to(point)

		var tangent: Vector3
		if segment_index < segment_count:
			tangent = (branch.points[segment_index + 1] - point).normalized()
		else:
			tangent = (point - branch.points[segment_index - 1]).normalized()

		frame_u = frame_u - tangent * frame_u.dot(tangent) ## project off the new tangent
		if frame_u.length_squared() < 0.01:
			frame_u = TreeGenSkeleton.perpendicular(tangent)
		else:
			frame_u = frame_u.normalized()
		frame_v = tangent.cross(frame_u)

		var ring: Array[int] = []
		for side_index in range(ring_count):
			var side_angle := TAU * float(side_index) / float(ring_count)
			var radial := (frame_u * cos(side_angle) + frame_v * sin(side_angle)).normalized()
			surface_tool.set_normal(radial)
			surface_tool.set_uv(Vector2(float(side_index) / float(ring_count), arc_length / BARK_UV_TILE))
			surface_tool.add_vertex(point + radial * radius)
			ring.append(vertex_start + added_vertices)
			added_vertices += 1
		ring_vertices.append(ring)

	if branch.is_trunk:
		# Close the trunk base with a flat cap.
		var cap_center := vertex_start + added_vertices
		added_vertices += 1
		surface_tool.set_normal(-first_tangent)
		surface_tool.set_uv(Vector2.ZERO)
		surface_tool.add_vertex(branch.points[0])
		var base_ring: Array = ring_vertices[0]
		for side_index in range(ring_count):
			var next_side := (side_index + 1) % ring_count
			surface_tool.add_index(cap_center)
			surface_tool.add_index(base_ring[side_index])
			surface_tool.add_index(base_ring[next_side])

	# Stitch consecutive rings into quads (two triangles each).
	for segment_index in range(segment_count):
		var ring_a: Array = ring_vertices[segment_index]
		var ring_b: Array = ring_vertices[segment_index + 1]
		for side_index in range(ring_count):
			var next_side := (side_index + 1) % ring_count
			var a0: int = ring_a[side_index]
			var a1: int = ring_a[next_side]
			var b0: int = ring_b[side_index]
			var b1: int = ring_b[next_side]
			surface_tool.add_index(a0)
			surface_tool.add_index(b0)
			surface_tool.add_index(b1)
			surface_tool.add_index(a0)
			surface_tool.add_index(b1)
			surface_tool.add_index(a1)

	return vertex_start + added_vertices


## Collects each stored leaf instance into the leaf surface that uses the same
## texture.
static func _add_branch_leaves(
	branch: TreeGenSkeleton.BranchNode,
	leaf_surface_textures: Array,
	leaf_surfaces: Array[SurfaceTool]
) -> void:
	for leaf in branch.leaf_instances:
		var surface := _leaf_surface_for(leaf.texture, leaf_surface_textures, leaf_surfaces)
		_add_leaf_card(surface, leaf)


static func _leaf_surface_for(
	leaf_texture: Texture2D,
	leaf_surface_textures: Array,
	leaf_surfaces: Array[SurfaceTool]
) -> SurfaceTool:
	for index in range(leaf_surface_textures.size()):
		if leaf_surface_textures[index] == leaf_texture:
			return leaf_surfaces[index]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	leaf_surface_textures.append(leaf_texture)
	leaf_surfaces.append(surface)
	return surface


## Adds one double-sided quad for `leaf`. The card's length axis follows
## `leaf.direction`, so the bottom of the texture sits against the branch and
## the top points away from it; the blade faces as close to horizontal as
## possible, is twisted by `leaf.roll`, and its tip droops by `leaf.bend`.
static func _add_leaf_card(surface_tool: SurfaceTool, leaf: TreeGenSkeleton.LeafInstance) -> void:
	var length_axis := leaf.direction.normalized()

	# Blade plane normal: project world up onto the plane perpendicular to the
	# length axis so leaves face the sky (degenerate when the leaf points
	# straight up or down).
	var normal := Vector3.UP - length_axis * length_axis.dot(Vector3.UP)
	if normal.length_squared() < 0.01:
		normal = Vector3.FORWARD - length_axis * length_axis.dot(Vector3.FORWARD)
	normal = normal.normalized()
	var right_axis := normal.cross(length_axis).normalized()

	# Twist the blade around its length axis, then droop the tip toward the
	# ground. Rolling keeps the bottom/top orientation along `length_axis`.
	normal = normal.rotated(length_axis, leaf.roll)
	right_axis = right_axis.rotated(length_axis, leaf.roll)
	if leaf.bend != 0.0:
		length_axis = TreeGenSkeleton.rotate_toward(length_axis, Vector3.DOWN, leaf.bend)

	var half_height := leaf.size * 0.5
	var half_width := half_height * maxf(leaf.aspect, 0.01)
	var corners := [
		leaf.position - length_axis * half_height - right_axis * half_width,
		leaf.position - length_axis * half_height + right_axis * half_width,
		leaf.position + length_axis * half_height + right_axis * half_width,
		leaf.position + length_axis * half_height - right_axis * half_width,
	]
	var uvs := [Vector2(1.0, 1.0), Vector2(0.0, 1.0), Vector2(0.0, 0.0), Vector2(1.0, 0.0)]
	for triangle_corner in [0, 1, 2, 0, 2, 3]:
		surface_tool.set_normal(normal)
		surface_tool.set_uv(uvs[triangle_corner])
		surface_tool.set_color(leaf.color)
		surface_tool.add_vertex(corners[triangle_corner])