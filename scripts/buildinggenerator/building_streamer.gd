class_name BuildingStreamer
extends RefCounted

## Builds the buildings near the player and takes away the ones left behind, so
## a village is there wherever they walk instead of only where they started.
##
##   var buildings := BuildingStreamer.new()
##   buildings.bind(building_generator, osm_index)
##   buildings.update($ProtoController.position)   # every frame is fine
##
## This is the same shape as ForestStreamer, and deliberately so, but **the
## streaming unit is the building rather than a cell.** A stand of trees here is
## up to 31 ha, so planting one per stand meant walking toward it and seeing
## nothing until its far edge came within range and the whole thing arrived at
## once. A building is a few metres across: it appearing as you come over the
## crest is the correct behaviour, not a fault, so there is nothing for a cell to
## fix.
##
## Which buildings exist is decided on REBUILD_MOVE; making them is not
## throttled, because a building cannot be half built and the work is on a frame
## budget so that a village arriving at once does not hitch.

## How near the player a building has to come to be built, in metres. Far enough
## to see the street before reaching it, near enough that the count stays in the
## hundreds rather than the tens of thousands the dump holds.
const RADIUS := 250.0

## How far the player has to move before the buildings around them are looked at
## again. Only the query is throttled, so this is the cost of walking into a
## village, and it is the same trade ForestStreamer makes.
const REBUILD_MOVE := 50.0

## Milliseconds of work one update() will do before stopping, with the rest left
## for the next call. Unlike a tree bake this is genuinely spread over several
## frames: a building is a few hundred vertices, so a hundred of them is real
## work even though any one of them is nothing.
const WORK_BUDGET_MS := 4.0

## Index group the buildings come from; OsmBuilding.feature_name().
const GROUP := "buildings"

## Where the buildings are made. It owns the terrain, so it owns ground height.
var generator: BuildingGen = null
## Where the buildings come from, and the footprints through it.
var index: OsmQuadtree = null
## Way id -> the node built for it, so it can be taken away again. Ids are
## unique across the merged dataset (MapData prefixes them per source).
var _live: Dictionary = {}
## Buildings in range that have not been built yet, nearest first.
var _pending: Array[OsmFeature] = []
## Kept so a building can be rebuilt identically: the palette entry is the only
## thing the seed reaches, but nothing else may start depending on it later.
var _seeds: Dictionary = {}
var _focus := Vector3.ZERO
var _packed := false
## Build and remove counts since the last repack, for stats().
var _built := 0
var _removed := 0


## Points `generator` at `p_index`'s buildings. Anything the generator has already
## built is left alone: this only remembers what it builds, so it can only remove
## what it built.
func bind(p_generator: BuildingGen, p_index: OsmQuadtree) -> void:
	generator = p_generator
	index = p_index
	_live.clear()
	_pending.clear()
	_seeds.clear()
	_packed = false


## Rebuilds the set around `focus` (world space) if it has moved far enough since
## the last time, then builds whatever is left to build. Returns whether the query
## ran; safe to call every frame, which is what the building needs.
func update(focus: Vector3, force: bool = false) -> bool:
	if index == null or generator == null:
		return false
	var repacked := false
	if not _packed or force or focus.distance_to(_focus) >= REBUILD_MOVE:
		_focus = focus
		_packed = true
		_repack()
		repacked = true
	_work()
	return repacked


## Which buildings are in range, which queued ones are gone, and which live ones
## are. Cheap enough to throttle, unlike the building.
func _repack() -> void:
	_built = 0
	_removed = 0
	var wanted := _buildings_in_range()
	_pending = _pending.filter(
			func(feature: OsmFeature) -> bool: return wanted.has(feature.way.id))
	for id in _live.keys():
		if not wanted.has(id):
			_destroy(id)
	for id in wanted:
		if not _live.has(id):
			_pending.append(wanted[id])
	# Nearest first, so the street being walked into is the street that arrives.
	var focus_xz := Vector2(_focus.x, _focus.z)
	_pending.sort_custom(func(a: OsmFeature, b: OsmFeature) -> bool:
		return _distance_to_focus(a, focus_xz) < _distance_to_focus(b, focus_xz))


## Every building within RADIUS of the focus, keyed by way id. The query is
## precise, so a footprint whose bounding box reaches into the disc but whose
## ring does not is left out -- which matters here more than for the trees,
## because a building just outside the radius drawn at the radius looks wrong in
## a way a tree just outside it does not.
func _buildings_in_range() -> Dictionary:
	var focus_xz := Vector2(_focus.x, _focus.z)
	var wanted: Dictionary = {}
	for feature in index.query_circle(focus_xz, RADIUS, GROUP, true):
		wanted[feature.way.id] = feature
	return wanted


## Builds whatever is queued, on a frame budget, leaving the rest for the next
## call. Deliberately not throttled by REBUILD_MOVE: a building cannot be
## partially built, so it has to be able to finish while the player stands still.
func _work() -> void:
	var started := Time.get_ticks_usec()
	var deadline := int(WORK_BUDGET_MS * 1000.0)
	while not _pending.is_empty():
		var feature: OsmFeature = _pending.pop_front()
		_build(feature)
		if Time.get_ticks_usec() - started >= deadline:
			break


func _build(feature: OsmFeature) -> void:
	var id := feature.way.id
	if _live.has(id):
		return
	var seed_value := _seed_for(feature)
	var points := index.entry_points(feature)
	var node := generator.build(feature, points, seed_value)
	if node == null:
		# Too small or degenerate to build from; there is nothing to wait for, so
		# it is left out rather than retried on every repack.
		return
	generator.add_child(node)
	_live[id] = node
	_seeds[id] = seed_value
	_built += 1


## A building's palette entry depends only on its own way id, so it does not
## change colour because the set was rebuilt. The way id is a string and is
## stable across runs.
static func _seed_for(feature: OsmFeature) -> int:
	return hash(feature.way.id)


func _destroy(id: String) -> void:
	var node: Node3D = _live[id]
	_live.erase(id)
	_seeds.erase(id)
	_removed += 1
	node.queue_free()


## Distance from the focus to a footprint, for the nearest-first order. The
## footprint's centre rather than its nearest edge: buildings are small against
## RADIUS, so the difference cannot change the order by much and the centre is
## the cheaper of the two.
func _distance_to_focus(feature: OsmFeature, focus_xz: Vector2) -> float:
	var points := index.entry_points(feature)
	if points.is_empty():
		return INF
	var bounds := Rect2(points[0], Vector2.ZERO)
	for i in range(1, points.size()):
		bounds = bounds.expand(points[i])
	return bounds.get_center().distance_to(focus_xz)


## What is built, what is waiting and how much work the last repack did, for
## debugging.
func stats() -> Dictionary:
	return {
		"buildings_live": _live.size(),
		"buildings_pending": _pending.size(),
		"built_last_repack": _built,
		"removed_last_repack": _removed,
		"radius": RADIUS,
		"rebuild_move": REBUILD_MOVE,
		"focus": _focus,
	}
