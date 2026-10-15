class_name FeatureProbe
extends RefCounted

## What the player is standing in or on, as OSM features, for the debug overlay.
##
## The index answers "what is near here", not "what am I in", so the two halves are
## split: OsmQuadtree.query_circle() narrows the dump to the features whose geometry
## comes within REACH_M -- and, exactly and however far off its outline the point is,
## to every filled area that contains it -- and the ranking below turns that set into
## an order, the feature at the front being the one underfoot.
##
## A distance of 0 means the point is inside the feature, so an area outranks the
## roads and watercourses that merely pass through it, which is the order a person
## would answer "what am I standing in".

## How near a line feature has to be to count as underfoot. Areas ignore it:
## containment is exact, so standing in the middle of a lake matches the lake
## however big it is.
const REACH_M := 5.0

## Cached because the overlay asks every frame and formatting a building's tags does
## not change while the player stands in it.
var _described: OsmFeature = null
var _described_text := ""


## Every feature `point` (world XZ) is inside or on, nearest first, so underfoot[0]
## is the one to describe.
func at(index: OsmQuadtree, point: Vector2) -> Array[OsmFeature]:
	var found := index.query_circle(point, REACH_M, "", true)
	var distances := {}
	for feature in found:
		distances[feature] = _distance_to(index, feature, point)
	found.sort_custom(func(a: OsmFeature, b: OsmFeature) -> bool:
		var da: float = distances[a]
		var db: float = distances[b]
		if da != db:
			return da < db
		# A tie is two features at the same distance -- a road through a forest, a
		# building on a road -- and without this the order would follow the query's
		# instead of anything the reader can see.
		return str(a.way.id) < str(b.way.id))
	return found


## A feature as the overlay shows it: the group it came from, the way behind it, and
## every tag the extract holds for it, since a tag nothing reads is often the one
## being looked for.
func describe(feature: OsmFeature) -> String:
	if feature != _described:
		_described = feature
		_described_text = _describe(feature)
	return _described_text


## How far `point` is from the feature's own geometry, 0 when the point is inside it.
func _distance_to(index: OsmQuadtree, feature: OsmFeature, point: Vector2) -> float:
	var points := index.entry_points(feature)
	if points.is_empty():
		return INF
	# Only a filled area is something to be *inside*. A closed roundabout or a
	# cul-de-sac loop is a ring of tarmac with ordinary ground in the middle, which
	# is what OsmRoad.is_area() is for (see OsmFeature.is_area).
	if feature.is_area() and Geometry2D.is_point_in_polygon(point, points):
		return 0.0
	var nearest := INF
	for i in points.size():
		if i == 0:
			nearest = minf(nearest, point.distance_to(points[0]))
			continue
		nearest = minf(nearest, point.distance_to(
				Geometry2D.get_closest_point_to_segment(point, points[i - 1], points[i])))
	return nearest


func _describe(feature: OsmFeature) -> String:
	var way := feature.way
	var text := "%s  (way %s)\n" % [feature.group_name(), way.id]
	text += "%d nodes, %s, area=%s, width %.2f m, rank %d\n" % [
		way.nd.size(),
		"closed" if way.is_closed() else "open",
		str(feature.is_area()),
		feature.width_m(),
		feature.class_rank()]
	var keys := way.tags.keys()
	keys.sort()
	for key in keys:
		text += "%s=%s\n" % [key, way.tags[key]]
	return text