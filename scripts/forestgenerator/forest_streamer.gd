class_name ForestStreamer extends RefCounted

## Plants the trees around the player and takes away the ones left behind, so
## there is woodland wherever the player walks rather than only where they
## started.
##
## The unit is a **cell**, not a forest. A stand in this data is up to 31 ha, so
## planting one per stand means walking toward it and seeing nothing until its far
## edge comes within range and the whole thing arrives at once, including the parts
## hundreds of metres away that were already on screen. Streaming cells fixes
## that, and it culls better: each cell's MultiMeshes have a small AABB, where a
## stand-sized one either could not be rejected or would take the whole stand with
## it. A cell is also seeded on its own key, so a tree never moves because a
## neighbour streamed in or out.
##
## This is the same shape as OsmGroundData: bind() once, then update() every frame
## with the player's position. Which cells are in range is throttled by how far the
## focus has moved; the growing is not, because it has to be able to finish while
## the player stands still.
##
##   var forests := ForestStreamer.new()
##   forests.bind(forest_generator, osm_index)
##   forests.update($ProtoController.position)   # every frame is fine

## How near the player a tree has to come to be planted, in metres. It is the
## distance at which woodland appears and disappears, so it trades seeing it coming
## against the cost of growing it.
const RADIUS := 200.0

## Side of one streaming cell, in metres. Two things set it and they pull against
## each other:
##  - **The tree spacing.** A cell gets `density * cell_area` trees, so it has to
##    be big enough to hold one: at 0.001/m^2 a 16 m cell gets floori(0.256) = 0
##    trees and the forest silently disappears, while 32 m gets exactly 1. This is
##    the binding constraint, and it is why CELL is not smaller.
##  - **The AABB a cell's MultiMeshes present to the frustum culler.** Bigger cells
##    cull worse.
const CELL := 32.0

## How far the player has to move before the cells are looked at again. A cell only
## costs anything when it is new, so this can be coarse.
const REBUILD_MOVE := 50.0

## Milliseconds of work one update() will do before stopping, with the rest left for
## the next call. Baking the tree meshes is the expensive half and one tree always
## spends the whole budget, so planting is not gated on it -- otherwise nothing
## would be grown while anything was left to bake.
const WORK_BUDGET_MS := 6.0

## Index group the forests come from; OsmForestArea.feature_name().
const GROUP := "forests"

## Where the trees go.
var generator: ForestGen = null
## Where the forests come from, and through it the projection.
var index: OsmQuadtree = null
## cell key -> the nodes planted for it, so it can be taken away again.
var _live: Dictionary = {}
## Cells in range that have not been planted yet, nearest first.
var _pending: Array[Vector2i] = []
var _focus := Vector3.ZERO
var _packed := false


## Points `generator` at `p_index`'s forests. Anything the generator already has
## planted is left alone: this only remembers what it plants, so it can only remove
## what it planted.
func bind(p_generator: ForestGen, p_index: OsmQuadtree) -> void:
	generator = p_generator
	index = p_index
	_live.clear()
	_pending.clear()
	_packed = false


## Repacks the cells around `focus` (world space) if it has moved far enough since
## the last time, then grows whatever can be grown. Returns whether the query ran;
## safe to call every frame, which is what the growing needs.
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


## Which cells are in range, which queued ones are gone, and which live ones are.
## Cheap -- a fixed-size loop and a dictionary pass -- so it is throttled.
func _repack() -> void:
	var wanted := _cells_in_range()
	_pending = _pending.filter(func(key: Vector2i) -> bool: return wanted.has(key))
	for key in _live.keys():
		if not wanted.has(key):
			_unplant(key)
	for key in wanted:
		if not _live.has(key) and not _pending.has(key):
			_pending.append(key)
	# Nearest first, so the trees that arrive first are the ones being walked into.
	var focus_xz := Vector2(_focus.x, _focus.z)
	_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _cell_rect(a).get_center().distance_squared_to(focus_xz) \
				< _cell_rect(b).get_center().distance_squared_to(focus_xz))


## Every cell whose rectangle comes within RADIUS of the focus, as keys. The count
## is fixed by RADIUS/CELL, so this is a small loop and not a query.
func _cells_in_range() -> Dictionary:
	var focus_xz := Vector2(_focus.x, _focus.z)
	var wanted: Dictionary = {}
	var first := Vector2i(floori((focus_xz.x - RADIUS) / CELL), floori((focus_xz.y - RADIUS) / CELL))
	var last := Vector2i(floori((focus_xz.x + RADIUS) / CELL), floori((focus_xz.y + RADIUS) / CELL))
	for cz in range(first.y, last.y + 1):
		for cx in range(first.x, last.x + 1):
			var key := Vector2i(cx, cz)
			if _rect_distance(_cell_rect(key), focus_xz) <= RADIUS:
				wanted[key] = true
	return wanted


## Grows whatever is ready, on a frame budget, leaving the rest for the next call.
## Deliberately not throttled: a cell cannot be grown until its tree meshes exist.
func _work() -> void:
	var started := Time.get_ticks_usec()
	var deadline := int(WORK_BUDGET_MS * 1000.0)

	# Baking is most of the cost, and one tree is 30-60 ms against a 6 ms budget, so
	# a single bake always spends the whole budget. Which species to bake is decided
	# by what has been asked for so far, which _plant asks for below.
	while generator.bake_next() and Time.get_ticks_usec() - started < deadline:
		pass

	# Growing stops on the budget only when a *second* cell is waiting, which is
	# where the real per-frame cost is.
	while not _pending.is_empty():
		var key: Vector2i = _pending[0]
		var features: Array[OsmFeature] = index.query_rect(
				_cell_rect(key), GROUP, true)
		var area := _cell_rect(key).get_area()
		var ready := true
		for feature in features:
			if not generator.needs_ready(ForestGen.type_for(feature), area):
				ready = false
		if not ready:
			break
		_pending.pop_front()
		_live[key] = _plant(key, features)
		if Time.get_ticks_usec() - started >= deadline:
			break


func _plant(key: Vector2i, features: Array[OsmFeature]) -> Array[MultiMeshInstance3D]:
	var nodes: Array[MultiMeshInstance3D] = []
	var rect := _cell_rect(key)
	for feature in features:
		nodes.append_array(generator.plant_forest_in_rect(
				ForestGen.type_for(feature), index.entry_points(feature), rect,
				_seed_for(key, feature)))
	return nodes


## A cell's own trees depend only on the cell and the feature, so planting one twice
## gives the same trees. The way id is a string and is stable across runs; the cell
## key is what separates one cell's trees from the next.
func _seed_for(key: Vector2i, feature: OsmFeature) -> int:
	return hash("%s:%d:%d" % [feature.way.id, key.x, key.y])


## Drops a cell's trees. The nodes go back to ForestGen's pool rather than being
## freed, since a cell leaving the radius is usually one that will come back.
func _unplant(key: Vector2i) -> void:
	var nodes: Array = _live[key]
	_live.erase(key)
	generator.recycle(nodes)


## What is planted, what is waiting and how many trees that is, for debugging.
func stats() -> Dictionary:
	var trees := 0
	for nodes in _live.values():
		for node in nodes:
			trees += node.multimesh.instance_count
	return {
		"cells_live": _live.size(),
		"cells_pending": _pending.size(),
		"trees": trees,
		"meshes_to_bake": generator.baking(),
		"radius": RADIUS,
		"cell": CELL,
		"rebuild_move": REBUILD_MOVE,
		"focus": _focus,
	}


static func _cell_rect(key: Vector2i) -> Rect2:
	return Rect2(Vector2(key) * CELL, Vector2(CELL, CELL))


static func _rect_distance(rect: Rect2, point: Vector2) -> float:
	var outside := (rect.get_center() - point).abs() - rect.size * 0.5
	return Vector2(maxf(outside.x, 0.0), maxf(outside.y, 0.0)).length()
