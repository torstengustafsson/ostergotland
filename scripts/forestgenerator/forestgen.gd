class_name ForestGen extends Node3D

enum ForestType {
	OakForest,
	SpruceForest,
}

func add_forest(type: ForestType, bounds: Rect2):
	var square_meters = bounds.size.x * bounds.size.y

	match type:
		ForestType.OakForest:
			add_tree_multimesh(TreeGenPresets.oak, floori(0.0001 * square_meters), bounds)
			add_tree_multimesh(TreeGenPresets.spruce, floori(0.000001 * square_meters), bounds)
			add_tree_multimesh(TreeGenPresets.maple, floori(0.000005 * square_meters), bounds)
		ForestType.SpruceForest:
			add_tree_multimesh(TreeGenPresets.oak, floori(0.000005 * square_meters), bounds)
			add_tree_multimesh(TreeGenPresets.spruce, floori(0.0001 * square_meters), bounds)
			add_tree_multimesh(TreeGenPresets.maple, floori(0.000005 * square_meters), bounds)


func add_tree_multimesh(preset: Callable, amount: int, bounds: Rect2) -> void:
	var tree: TreeGenTree = preset.call(randi())
	tree.regenerate() ## bake the mesh without the node ever entering the scene tree

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = tree.mesh
	multimesh.instance_count = amount

	for i in range(amount):
		multimesh.set_instance_transform(i, _random_tree_transform(bounds))

	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	add_child(instance)
	tree.free()


func _random_tree_transform(bounds: Rect2) -> Transform3D:
	var x := randf_range(bounds.position.x, bounds.position.x + bounds.size.x)
	var z := randf_range(bounds.position.y, bounds.position.y + bounds.size.y)
	var position := Vector3(x, _ground_height_at(x, z), z)
	var scale := randf_range(0.9, 1.1)
	var basis := Basis(Vector3.UP, randf_range(0.0, TAU)).scaled(Vector3.ONE * scale)
	return Transform3D(basis, position)


func _ground_height_at(x: float, z: float) -> float:
	var ray := PhysicsRayQueryParameters3D.create(
		Vector3(x, 500.0, z),
		Vector3(x, -500.0, z)
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return 5.0
	return hit.position.y
