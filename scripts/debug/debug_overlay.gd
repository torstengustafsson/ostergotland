class_name DebugOverlay
extends Node

## The debug overlay: where the player is, that as lon/lat, the frame rate, the
## OSM feature they are standing in or on, and a slider for the free-fly speed.
## Toggled with the debugmode action (F3) and off until then, so while it is shut all
## that runs is the action test in _input() and the drag test in _unhandled_input().
##
## It builds its own widgets, reads the toggle and ticks itself, so main.gd only
## creates the node and hands it the index, projection and player.

## The action that toggles the overlay.
const ACTION := "debugmode"
## Width of the label, so a building's tag list wraps instead of running off the
## screen.
const WIDTH_PX := 520.0
## How far round the player features_nearby() reaches, which is a different
## question from what is underfoot (FeatureProbe.REACH_M): this is the sample query
## a listener or a fog-of-war system would ask.
const NEARBY_RADIUS_M := 500.0

## The ends of the free-fly slider, in metres a second, which is also world units a
## second. Wide: roughly 320 px for the whole 995, so a pixel is about 3 m/s and the
## low end cannot be picked out by dragging to it.
const SPEED_MIN_MPS := 5.0
const SPEED_MAX_MPS := 1000.0
## Widths of the slider and its readout, the readout's wide enough for the longest
## value so the slider does not change width as the digits change.
const SPEED_WIDTH_PX := 220.0
const SPEED_READOUT_PX := 90.0

var _index: OsmQuadtree = null
var _projection: OsmProjection = null
var _player: Node3D = null
var _root: VBoxContainer = null
var _label: Label = null
var _speed: HSlider = null
var _speed_readout: Label = null
var _probe: FeatureProbe = FeatureProbe.new()
var _speed_dragging := false
var _on := false


func _ready() -> void:
	_root = VBoxContainer.new()
	# PASS rather than the default STOP, on both containers: they are as wide as the
	# label, and their empty space has to let clicks through to the world behind them.
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root)

	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(WIDTH_PX, 0.0)
	_root.add_child(_label)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(row)

	var title := Label.new()
	title.text = "Freefly speed"
	row.add_child(title)

	_speed = HSlider.new()
	_speed.min_value = SPEED_MIN_MPS
	_speed.max_value = SPEED_MAX_MPS
	_speed.custom_minimum_size = Vector2(SPEED_WIDTH_PX, 0.0)
	_speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_speed)
	_speed.drag_started.connect(_on_drag_started)
	_speed.drag_ended.connect(_on_drag_ended)

	_speed_readout = Label.new()
	_speed_readout.custom_minimum_size = Vector2(SPEED_READOUT_PX, 0.0)
	row.add_child(_speed_readout)


## What the overlay reads: the index and projection that turn a position into a
## description, and the node it follows.
func bind(p_index: OsmQuadtree, p_projection: OsmProjection, p_player: Node3D) -> void:
	_index = p_index
	_projection = p_projection
	_player = p_player
	# Seeded from the player rather than left at the slider's own default, which is
	# the minimum: main.tscn's override should be the number shown, and a speed
	# outside the slider's ends is taken as its nearest end.
	_speed.value = clampf(_freefly_speed(), SPEED_MIN_MPS, SPEED_MAX_MPS)


## The toggle, on the built-in input hook rather than an action poll in update():
## the input phase runs before the process phase, so the label is rewritten on the
## frame the key lands rather than the frame after. allow_echo is left off, so
## holding the key does not flip it back and forth.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION):
		_on = not _on


## Keeps a slider drag away from the controller, which captures the mouse on any
## event it sees while the left button is down, and a captured cursor is pinned to
## the middle of the window, which would freeze the drag where it started. The GUI
## pass runs before this one, so the flag is already up for the press that begins
## the drag.
func _unhandled_input(_event: InputEvent) -> void:
	if _speed_dragging:
		get_viewport().set_input_as_handled()


## Rewrites the label and hands the slider's value to the player while the overlay is
## on, on the node's own _process rather than a call from main.gd. Safe to run every
## frame; that is all it is for.
func _process(delta: float) -> void:
	_root.visible = _on
	if not _on:
		return
	_label.text = _text(delta)
	_apply_speed()


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


## Read every frame instead of off value_changed, which a Slider blocks for the whole
## of a drag and reports once on release: a click on the groove changes the value with
## that signal suppressed, so listening for it would miss the common case entirely.
## Written back unconditionally so the readout can never disagree with the player.
func _apply_speed() -> void:
	var speed: float = _speed.value
	_speed_readout.text = "%.1f m/s" % speed
	_player.set("freefly_speed", speed)


## The controller is a vendored script with no class_name, so its speed is reached by
## property name rather than through a typed member. Checked rather than assumed,
## because a null here would be a slider that silently does nothing.
func _freefly_speed() -> float:
	var speed: Variant = _player.get("freefly_speed")
	if not speed is float:
		push_warning("DebugOverlay: the player has no freefly_speed to adjust")
		return SPEED_MIN_MPS
	return speed


func _on_drag_started() -> void:
	_speed_dragging = true


func _on_drag_ended(_changed: bool) -> void:
	_speed_dragging = false


func _lonlat(xz: Vector2) -> String:
	var lonlat := _projection.to_lonlat(xz)
	return "%.5f, %.5f" % [lonlat.x, lonlat.y]
