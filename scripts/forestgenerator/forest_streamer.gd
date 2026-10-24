class_name ForestStreamer extends RefCounted

## Plants the trees around the player and takes away the ones left behind, so
## there is woodland wherever the player walks rather than only where they
## started.
##
## A cell holds two ages of tree, the adults and the young ones under them
## (ForestGen.TreeAge). Both are streamed: the generator grows both from the
## same outline and the cell waits for both sets of meshes before it is planted,
## so a stand never arrives as a bare canopy with the understory trailing in
## behind it.
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
## The cell is also what the trees are kept apart by. ForestCell gathers the
## roads, the railways, the water, the buildings and the fields on the cell's
## ground and keeps the trees off them, and it holds the trees already planted
## so that no two trunks grow into each other -- including across a cell
## boundary, which the cell's own margin arranges (ForestCell.BORDER_MARGIN_M).
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

## Side of one streaming cell, in metres. Two things set it:
##  - **When woodland arrives.** A cell is grown only once the player comes within
##    RADIUS of it, so a smaller cell plants closer to the horizon.
##  - **The AABB a cell's MultiMeshes present to the frustum culler.** Bigger cells
##    cull worse.
##
## Tree spacing used to bound this from below -- a cell had to be big enough to
## hold a whole tree or a sparse forest vanished -- but ForestGen now rounds a
## fraction of a tree stochastically, so no density is out of reach and only
## culling holds CELL up.
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

## What one cell is made of: the ground it covers, with the things on it
## gathered, and the part of each forest that falls inside it.
class CellPlan extends RefCounted:
	var cell: ForestCell = null
	var regions: Array[ForestRegion] = []

## Where the trees go.
var generator: ForestGen = null
## Where the forests come from, and through it the projection.
var index: OsmQuadtree = null
## cell key -> the nodes planted for it, so it can be taken away again.
var _live: Dictionary = {}
## cell key -> its CellPlan, so the clipping is done once per cell rather than
## once per frame.
var _plans: Dictionary[Vector2i, CellPlan] = {}
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
	_plans.clear()
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
	for key in _plans.keys():
		if not wanted.has(key):
			_plans.erase(key)
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

	# Baking is most of the cost, and one tree is 30-60 ms against our work budget,
	# so a single bake often spends the whole budget. Which species to bake is
	# decided by what has been asked for so far, which _plant asks for below.
	while generator.bake_next() and Time.get_ticks_usec() - started < deadline:
		pass

	# Growing stops on the budget only when a *second* cell is waiting, which is
	# where the real per-frame cost is.
	while not _pending.is_empty():
		var key: Vector2i = _pending[0]
		var plan := _plan_for(key)
		var ready := true
		for region in plan.regions:
			if not generator.needs_ready(ForestGen.type_for(region.feature),
					region.forest_area):
				ready = false
		if not ready:
			break
		_pending.pop_front()
		_live[key] = _plant(key, plan)
		if Time.get_ticks_usec() - started >= deadline:
			break


## What is in a cell: its ground, with the things on it gathered, and the part
## of each forest that falls inside it.
##
## Cached, because it is the same for as long as the cell is in range and the
## clipping is the expensive half -- it is done once per cell rather than once
## per frame.
##
## **A hole in a forest is not forest.** A multipolygon relation is stitched
## into one way per ring, and the rings that are holes come out as forests of
## their own with the relation's tags, so the clearing in the middle of a wood
## would be planted with the wood. The ground shader gets this right by
## itself, because the forest floor is one parity count over every forest edge
## and a hole crosses it twice; the trees have to be told.
func _plan_for(key: Vector2i) -> CellPlan:
	if _plans.has(key):
		return _plans[key]
	var rect := _cell_rect(key)
	var plan := CellPlan.new()
	plan.cell = ForestCell.new(rect)
	plan.cell.gather(index)
	for feature in index.query_rect(rect, GROUP, true):
		if feature.is_hole():
			continue
		var outline := index.entry_points(feature)
		if outline.size() < 3:
			continue
		plan.regions.append(ForestRegion.clip(feature, outline, rect))
	_plans[key] = plan
	return plan


func _plant(key: Vector2i, plan: CellPlan) -> Array[MultiMeshInstance3D]:
	var nodes: Array[MultiMeshInstance3D] = []
	for region in plan.regions:
		nodes.append_array(generator.plant_region(
				ForestGen.type_for(region.feature), region,
				_seed_for(key, region.feature), plan.cell))
	return nodes


## A cell's own trees depend only on the cell and the feature, so planting one twice
## gives the same trees. The way id is a string and is stable across runs; the cell
## key is what separates one cell's trees from the next.
func _seed_for(key: Vector2i, feature: OsmFeature) -> int:
	return hash("%s:%d:%d" % [feature.way.id, key.x, key.y])


## Drops a cell's trees. The nodes go back to ForestGen's pool rather than being
## freed, since a cell leaving the radius is usually one that will come back.
## The plan goes with them: the cell is clipped again when it comes back.
func _unplant(key: Vector2i) -> void:
	var nodes: Array = _live[key]
	_live.erase(key)
	_plans.erase(key)
	generator.recycle(nodes)


## What is planted, what is waiting and how many trees that is, for debugging.
## The trees are counted per age, so a stand that lost its understory shows up
## here as adults without young ones.
func stats() -> Dictionary:
	var adults := 0
	var young := 0
	var undergrowth := 0
	for nodes in _live.values():
		for node in nodes:
			var count: int = node.multimesh.instance_count
			var age_val := int(node.get_meta(ForestGen.TREETYPE_META, ForestGen.TreeType.Adult))
			if age_val == ForestGen.TreeType.Young:
				young += count
			elif age_val == ForestGen.TreeType.Undergrowth:
				undergrowth += count
			else:
				adults += count
	return {
		"cells_live": _live.size(),
		"cells_pending": _pending.size(),
		"trees": adults + young + undergrowth,
		"trees_adult": adults,
		"trees_young": young,
		"trees_undergrowth": undergrowth,
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
