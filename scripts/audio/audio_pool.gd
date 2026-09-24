class_name AudioPool extends Node

const POOL_SIZE = 16
const LOOP_FADE_DURATION := 0.5   # seconds of fade during a loop point
const LOOP_FADE_RANGE := 50.0     # dB below the target volume at full fade

var _players: Array[AudioStreamPlayer3D] = []
var _play_times: Array[float] = []       # when each player started (ms)
var _attached_to: Array[Node3D] = []     # Node3D a player is attached to, null = pool-owned
var _looping: Array[bool] = []           # restart on finished instead of releasing
var _fade_target_db: Array[float] = []   # full volume_db the fade ramps back to
var _fade_out_time: Array[float] = []    # remaining fade-out seconds (0 = inactive)
var _fade_in_time: Array[float] = []     # remaining fade-in seconds (0 = inactive)
var _prefade_time: Array[float] = []     # countdown until the fade-out should start (s)

func _ready() -> void:
	for i in POOL_SIZE:
		_add_player()

func _add_player() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	add_child(p)
	p.finished.connect(_on_player_finished.bind(p))
	_players.append(p)
	_play_times.append(0.0)
	_attached_to.append(null)
	_looping.append(false)
	_fade_target_db.append(0.0)
	_fade_out_time.append(0.0)
	_fade_in_time.append(0.0)
	_prefade_time.append(0.0)
	return p

func play(stream: AudioStream, pos: Vector3, pitch: float = 1.0, volume_db: float = 0.0, loop: bool = false) -> AudioStreamPlayer3D:
	var player := _acquire(pos)
	player.stream = stream
	player.position = pos
	player.bus = &"Master"
	player.pitch_scale = pitch
	player.volume_db = volume_db
	var idx := _players.find(player)
	_play_times[idx] = Time.get_ticks_msec()
	_looping[idx] = loop
	_fade_target_db[idx] = volume_db
	_fade_out_time[idx] = 0.0
	_fade_in_time[idx] = LOOP_FADE_DURATION if loop else 0.0
	# Start fading out LOOP_FADE_DURATION before the loop point
	_prefade_time[idx] = maxf(stream.get_length() - LOOP_FADE_DURATION, 0.0) if loop else 0.0
	if loop:
		player.volume_db = _fade_target_db[idx] - LOOP_FADE_RANGE
	player.play()
	return player

func attach_to_object(player: AudioStreamPlayer3D, object: Node3D) -> void:
	var idx := _players.find(player)
	if idx == -1:
		return
	_attached_to[idx] = object
	if player.get_parent() != object:
		if player.get_parent() != null:
			player.get_parent().remove_child(player)
		object.add_child(player)
	player.position = Vector3.ZERO

func _acquire(pos: Vector3) -> AudioStreamPlayer3D:
	for i in _players.size():
		_ensure_valid(i)

	var idx := -1
	# 1. Reuse a pool-owned player still playing at this position
	for i in _players.size():
		var p := _players[i]
		if _attached_to[i] == null and p.playing and p.position.is_equal_approx(pos):
			idx = i
			break
	# 2. Reuse a free (finished/stopped) pool-owned player
	if idx == -1:
		for i in _players.size():
			var p := _players[i]
			if _attached_to[i] == null and not p.playing:
				idx = i
				break
	# 3. Reuse any free player, even if still attached to an object
	if idx == -1:
		for i in _players.size():
			if not _players[i].playing:
				idx = i
				break
	# 4. Cut the oldest playing player
	if idx == -1:
		idx = 0
		for i in _players.size():
			if _play_times[i] < _play_times[idx]:
				idx = i
	_players[idx].stop()
	_detach(idx)
	return _players[idx]

func _ensure_valid(idx: int) -> void:
	if is_instance_valid(_players[idx]):
		return
	var p := AudioStreamPlayer3D.new()
	add_child(p)
	p.finished.connect(_on_player_finished.bind(p))
	_players[idx] = p
	_play_times[idx] = 0.0
	_looping[idx] = false
	_fade_target_db[idx] = 0.0
	_fade_out_time[idx] = 0.0
	_fade_in_time[idx] = 0.0
	_prefade_time[idx] = 0.0

func _detach(idx: int) -> void:
	var p := _players[idx]
	_attached_to[idx] = null
	if p.get_parent() == self:
		return
	if p.get_parent() != null:
		p.get_parent().remove_child(p)
	add_child(p)

func _process(delta: float) -> void:
	for i in _players.size():
		var player := _players[i]
		if not is_instance_valid(player):
			continue
		if not _looping[i] or not player.playing:
			continue

		# Fade-in: ramp from silent up to the target volume
		if _fade_in_time[i] > 0.0:
			_fade_in_time[i] = maxf(_fade_in_time[i] - delta, 0.0)
			var t: float = 1.0 - _fade_in_time[i] / LOOP_FADE_DURATION
			player.volume_db = lerpf(_fade_target_db[i] - LOOP_FADE_RANGE, _fade_target_db[i], t)

		# Countdown to the loop end, then start the fade-out
		if _prefade_time[i] > 0.0:
			_prefade_time[i] = maxf(_prefade_time[i] - delta, 0.0)
			if _prefade_time[i] <= 0.0:
				_fade_out_time[i] = LOOP_FADE_DURATION
		if _fade_out_time[i] > 0.0:
			_fade_out_time[i] = maxf(_fade_out_time[i] - delta, 0.0)
			var t: float = _fade_out_time[i] / LOOP_FADE_DURATION
			player.volume_db = lerpf(_fade_target_db[i] - LOOP_FADE_RANGE, _fade_target_db[i], t)

func _on_player_finished(p: AudioStreamPlayer3D) -> void:
	var idx := _players.find(p)
	if idx == -1:
		return
	if _looping[idx]:
		_fade_out_time[idx] = 0.0
		_fade_in_time[idx] = LOOP_FADE_DURATION
		_prefade_time[idx] = maxf(p.stream.get_length() - LOOP_FADE_DURATION, 0.0)
		p.volume_db = _fade_target_db[idx] - LOOP_FADE_RANGE
		_play_times[idx] = Time.get_ticks_msec()
		p.play()
		return
	_detach(idx)

func destroy():
	for i in _players.size():
		if not is_instance_valid(_players[i]):
			continue
		_players[i].stop()
		_detach(i)