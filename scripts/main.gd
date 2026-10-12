extends Node

## Where the player starts, as (longitude, latitude), and how far either way the
## ray that finds the ground under them reaches. A lon/lat because the world is
## in metres from the centre of the DEM's own box, so a world position would
## quietly mean a different spot the moment that box or the resolution changed.
const SPAWN_LONLAT := Vector2(15.96651, 58.55193)
const GROUND_PROBE := 500.0

## Every vector source in assets/mapdata, merged into one dataset: the OSM
## extract, plus whatever else has been added since. See MapData.
var map_data: MapData = MapData.new()
var osm_index: OsmQuadtree = OsmQuadtree.new()
## The terrain's lon/lat -> world XZ chain, built from the heightmap's own extent.
## A member because the spawn is a lon/lat and this is what turns it into metres.
var projection: OsmProjection = null
## The OSM features the ground shader draws, kept up to date around the player.
## See OsmGroundData.
var osm_ground: OsmGroundData = OsmGroundData.new()
var forest_generator: ForestGen = ForestGen.new()
## The forests around the player, planted and dropped as they walk. See
## ForestStreamer; forest_generator is where its trees go.
var forest_streamer: ForestStreamer = ForestStreamer.new()
var audio_manager: AudioManager = AudioManager.new()
var _spawn_settled := false


func _ready() -> void:
	var start_time = Time.get_ticks_msec()

	map_data.load_dir()
	var load_time = Time.get_ticks_msec()
	print("Time to load map data: ", str((load_time - start_time) / 1000.0), " seconds ",
			map_data.stats())

	# The terrain's own lon/lat box, which heightmap.gd read to work out its
	# scale, is what the features have to be projected through: a download's
	# own bounds are a slightly different box and would put them off the ground.
	projection = OsmProjection.from_terrain(
		$Heightmap.bounds,
		$Heightmap.width,
		$Heightmap.height,
		Vector2($Heightmap.scale.x, $Heightmap.scale.z))
	osm_index.build(map_data.dataset, projection)

	var index_time = Time.get_ticks_msec()
	print("Time to index features: ", str((index_time - load_time) / 1000.0), " seconds")

	# The spawn's horizontal position first, because it decides which tiles get
	# streamed and everything else follows the player there. Only the vertical
	# half has to wait for a frame; see _snap_player_to_ground().
	_place_player_at_lonlat(SPAWN_LONLAT)

	$Heightmap.set_stream_target($ProtoController)

	# The ground shader's arrays go in now that the material exists, and the first
	# set is packed so the ground is not bare on the first frame.
	osm_ground.bind($Heightmap.material, osm_index)
	var ground_time := Time.get_ticks_msec()
	osm_ground.update($ProtoController.position, true)
	var ground_stats := osm_ground.stats()
	print("Time to pack ground features: ", str(Time.get_ticks_msec() - ground_time),
			" ms (", ground_stats["lines"], " lines, ", ground_stats["area_edges"],
			" area edges, ", ground_stats["lines_dropped"] + ground_stats["area_edges_dropped"],
			" dropped)")

	add_child(forest_generator)
	add_child(audio_manager)
	# Named so it can be reached from the scene tree rather than only through the
	# script: an unnamed Node3D added in code ends up called "@Node3D@78".
	forest_generator.name = "ForestGen"

	# The terrain only exists out to LOAD_RADIUS, so the camera has to stop inside
	# that or the loaded disc's rim comes into view. Deriving it keeps the two
	# from drifting apart; the 4% is margin for the disc's edge being ragged at
	# tile granularity.
	$ProtoController/Head/Camera3D.far = Heightmap.LOAD_RADIUS * 0.96
	print("Camera far plane: ", $ProtoController/Head/Camera3D.far, " m")

	forest_streamer.bind(forest_generator, osm_index)
	var forest_time := Time.get_ticks_msec()
	forest_streamer.update($ProtoController.position, false)
	print("Time to plant the first forests: ",
			str(Time.get_ticks_msec() - forest_time), " ms ", forest_streamer.stats())

	# Add some test sounds and models
	audio_manager.play_sound(AudioManager.SoundID.BIRD_SONG1, $ProtoController.position, 1.0, 0.0)
	audio_manager.play_sound_on_object(AudioManager.SoundID.WIND, $ProtoController, 1.0, -35.0, true)

	var generate_time = Time.get_ticks_msec()
	print("Time to generate objects: ", str((generate_time - index_time) / 1000.0), " seconds")


func _process(_delta: float) -> void:
	# The spawn's height, on the first frame after the tiles under it were
	# streamed in. See _snap_player_to_ground() for why it cannot be in _ready().
	if not _spawn_settled:
		_spawn_settled = true
		_snap_player_to_ground()

	$HUD.text = "Position = " + str($ProtoController.position) + "\n"
	$HUD.text += "GPS = " + _lonlat_text() + "\n"
	$HUD.text += "FPS = " + str(snapped(1.0 / _delta, 0.01))
	# Repacks the shader's feature arrays, but only once the player has walked
	# OsmGroundData.REBUILD_MOVE units away from the last pack.
	osm_ground.update($ProtoController.position)
	# Same deal for the forests, though update() plants what has come into range
	# and stops at its budget, so it needs calling every frame.
	forest_streamer.update($ProtoController.position)


## Everything the index knows about within 500 units of the player: the kind of
## query a listener or a fog-of-war system would do.
func features_near_player() -> Array[OsmFeature]:
	var p: Vector3 = $ProtoController.position
	return osm_index.query_circle(Vector2(p.x, p.z), 500.0)

func _lonlat_text() -> String:
	var p: Vector3 = $ProtoController.global_position
	var lonlat := projection.to_lonlat(Vector2(p.x, p.z))
	return "%.5f, %.5f" % [lonlat.x, lonlat.y]

func _place_player_at_lonlat(lonlat: Vector2) -> void:
	var xz := projection.to_world(lonlat.x, lonlat.y)
	$ProtoController.global_position = Vector3(xz.x, 0.0, xz.y)

func _snap_player_to_ground() -> void:
	var player := $ProtoController as CharacterBody3D
	var at := player.global_position
	var probe := PhysicsRayQueryParameters3D.create(
			at + Vector3.UP * GROUND_PROBE, at - Vector3.UP * GROUND_PROBE)
	probe.exclude = [player.get_rid()]
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(probe)
	if hit.is_empty():
		# Nothing streamed under the spawn, which should not happen. The height
		# map needs no collider, so it can still answer, and beats dropping the
		# player through the world.
		push_warning("Spawn: nothing streamed under ", at, ", using the height map")
		player.global_position.y = $Heightmap.height_at_world(at)
		return
	player.global_position.y = hit.position.y
	print("Spawn ", SPAWN_LONLAT, " -> ", player.global_position,
			" (ground at ", hit.position.y, " m)")
