extends Node

var osm_dataset: OsmDataset = OsmDataset.new()
var forest_generator: ForestGen = ForestGen.new()
var audio_manager: AudioManager = AudioManager.new()

func _ready() -> void:
	var start_time = Time.get_ticks_msec()

	osm_dataset.load("assets/heightmap/ways.json")

	var load_time = Time.get_ticks_msec() - start_time
	print("Time to load ways.json: ", str(load_time / 1000.0), " seconds")


	debug_prints()

	add_child(forest_generator)
	add_child(audio_manager)

	# Add some test sounds and models
	audio_manager.play_sound(AudioManager.SoundID.BIRD_SONG1, Vector3(0.0, 10.0, 0.0), 1.0, 0.0)
	audio_manager.play_sound_on_object(AudioManager.SoundID.WIND, $ProtoController, 1.0, -35.0, true)

	var i = 0
	for forest_nodes in osm_dataset.features["forests"]:
		if i > 100:
			break
		i += 1
		var forest1_bounds := OsmLanduseBounds.from_feature(
			osm_dataset,
			forest_nodes,
			osm_dataset.bounds, # approximate: the OSM download bounds stand in for the
			# terrain's own lon/lat extent, which is not recorded in this repo yet
			# (see AGENTS.md), so the area can land slightly off the terrain.
			$Heightmap.width,
			$Heightmap.height,
			Vector2($Heightmap.scale.x, $Heightmap.scale.z))
		forest_generator.add_forest(ForestGen.ForestType.OakForest, forest1_bounds.world_rect)

	var generate_time = Time.get_ticks_msec() - load_time
	print("Time to generate objects: ", str(generate_time / 1000.0), " seconds")


func _process(_delta: float) -> void:
	$HUD.text = str($ProtoController.position)

func debug_prints():
	print("keys = ", osm_dataset.features.keys())
	print("ways = ", osm_dataset.ways.size())
	print("roads = ", osm_dataset.features["roads"].size())
	print("water = ", osm_dataset.features["water"].size())
	print("forests = ", osm_dataset.features["forests"].size())
	# print("Forest areas = ")
	# for forest in osm_dataset.features["forests"]:
	# 	print(" - ", forest.way.id, ": ", forest.way.tags)
	# 	var nodes = []
	# 	for node in forest.way.nd:
	# 		nodes.append(osm_dataset.node_position(node))
	# 	print("   ", nodes)
