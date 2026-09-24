extends StaticBody3D

const HEIGHT_NORMALIZATION := 56000.0

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

var img: Image
var roads_img: Image
var buildings_img: Image
var railways_img: Image
var width: int
var height: int

func _init() -> void:
	scale = Vector3(10.0, 50.0, 10.0)

func _ready():
	var start_time = Time.get_ticks_msec()

	img = Image.load_from_file("res://assets/heightmap/output_hh.exr")
	img.convert(Image.FORMAT_RF)
	width = img.get_width()
	height = img.get_height()

	_build_collision()
	_build_mesh()
	_apply_material()

	var elapsed = Time.get_ticks_msec() - start_time
	print("Time to generate terrain: ", str(elapsed / 1000.0), " seconds")

func _build_collision():
	var heightmap_shape = HeightMapShape3D.new()
	heightmap_shape.map_width = width
	heightmap_shape.map_depth = height

	var data = PackedFloat32Array()
	data.resize(width * height)
	for y in height:
		for x in width:
			var value = img.get_pixel(x, y).r / HEIGHT_NORMALIZATION
			data[y * width + x] = value

	heightmap_shape.map_data = data
	collision_shape.shape = heightmap_shape

func _build_mesh():
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Build a grid of vertices, one per heightmap pixel
	for y in height:
		for x in width:
			var h = img.get_pixel(x, y).r / HEIGHT_NORMALIZATION
			# Center the mesh around origin, matching HeightMapShape3D's default centering
			var vx = x - (width - 1) / 2.0
			var vz = y - (height - 1) / 2.0
			st.set_uv(Vector2(float(x) / (width - 1), float(y) / (height - 1)))
			st.add_vertex(Vector3(vx, h, vz))

	# Stitch triangles
	for y in height - 1:
		for x in width - 1:
			var i0 = y * width + x
			var i1 = y * width + (x + 1)
			var i2 = (y + 1) * width + x
			var i3 = (y + 1) * width + (x + 1)

			st.add_index(i0)
			st.add_index(i1)
			st.add_index(i2)

			st.add_index(i1)
			st.add_index(i3)
			st.add_index(i2)

	st.generate_normals()
	st.index()

	mesh_instance.mesh = st.commit()

func _apply_material():
	var height_shader: Shader = preload("res://scripts/ground.gdshader")
	var material := ShaderMaterial.new()
	material.shader = height_shader

	material.set_shader_parameter("min_height", 0.0)
	material.set_shader_parameter("max_height", 10.0)


	var water_noise_texture = NoiseTexture3D.new()
	water_noise_texture.noise = FastNoiseLite.new()
	await water_noise_texture.changed
	material.set_shader_parameter("water_noise", water_noise_texture)

	mesh_instance.material_override = material
