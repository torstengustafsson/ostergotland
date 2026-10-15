class_name DebugOverlay
extends Node

## The debug overlay: where the player is, that as lon/lat, the frame rate, and the
## OSM feature they are standing in or on. Toggled with the debugmode action (F3)
## and off until then, so the only thing that runs while it is shut is the one
## action test in _input().
##
## It builds its own label, reads the toggle and ticks itself, so main.gd only
## creates the node and hands it the index, projection and player. Nothing here runs
## unless the overlay is on, apart from the action test in _input().

## The action that toggles the overlay.
const ACTION := "debugmode"
## Width of the label, so a building's tag list wraps instead of running off the
## screen.
const WIDTH_PX := 520.0
## How far round the player features_nearby() reaches, which is a different
## question from what is underfoot (FeatureProbe.REACH_M): this is the sample query
## a listener or a fog-of-war system would ask.
const NEARBY_RADIUS_M := 500.0

var _index: OsmQuadtree = null
var _projection: OsmProjection = null
var _player: Node3D = null
var _label: Label = null
var _probe: FeatureProbe = FeatureProbe.new()
var _on := false


func _ready() -> void:
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(WIDTH_PX, 0.0)
	add_child(_label)


## What the overlay reads: the index and projection that turn a position into a
## description, and the node it follows.
func bind(p_index: OsmQuadtree, p_projection: OsmProjection, p_player: Node3D) -> void:
	_index = p_index
	_projection = p_projection
	_player = p_player


## The toggle, on the built-in input hook rather than an action poll in update():
## the input phase runs before the process phase, so the label is rewritten on the
## frame the key lands rather than the frame after. allow_echo is left off, so
## holding the key does not flip it back and forth.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION):
		_on = not _on


## Rewrites the label while the overlay is on, on the node's own _process rather
## than a call from main.gd. Safe to run every frame; that is all it is for.
func _process(delta: float) -> void:
	_label.visible = _on
	if _on:
		_label.text = _text(delta)


## Everything the index knows about within NEARBY_RADIUS_M of the player: the kind
## of query a listener or a fog-of-war system would do.
func features_nearby() -> Array[OsmFeature]:
	var p: Vector3 = _player.position
	return _index.query_circle(Vector2(p.x, p.z), NEARBY_RADIUS_M)


func _text(delta: float) -> String:
	var p: Vector3 = _player.position
	var text := "Position = %s\n" % p
	text += "GPS = %s\n" % _lonlat(Vector2(p.x, p.z))
	text += "FPS = %s\n" % snapped(1.0 / delta, 0.01)

	var underfoot := _probe.at(_index, Vector2(p.x, p.z))
	if underfoot.is_empty():
		return text + "Standing in: nothing (within %.0f m)\n" % FeatureProbe.REACH_M
	text += "Standing in:\n" + _probe.describe(underfoot[0])
	# The rest of the overlaps, since the one on top is not always the interesting
	# one: standing on a road inside a forest, the road wins on distance.
	var others := PackedStringArray()
	for i in range(1, underfoot.size()):
		others.append("%s %s" % [underfoot[i].group_name(), underfoot[i].way.id])
	if not others.is_empty():
		text += "also underfoot: %s\n" % ", ".join(others)
	return text


func _lonlat(xz: Vector2) -> String:
	var lonlat := _projection.to_lonlat(xz)
	return "%.5f, %.5f" % [lonlat.x, lonlat.y]