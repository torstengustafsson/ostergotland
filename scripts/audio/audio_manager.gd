class_name AudioManager extends Node

enum SoundID {
	BIRD_FLIGHT,
	BIRD_SONG1,
	BIRD_SONG2,
	CAR_DRIVING,
	WIND,
}

static var sounds: Dictionary[SoundID, Resource]= {
	SoundID.BIRD_FLIGHT: load("res://assets/audio/bird-flight.mp3"),
	SoundID.BIRD_SONG1: load("res://assets/audio/bird-song2.mp3"),
	SoundID.BIRD_SONG2: load("res://assets/audio/bird-song1.mp3"),
	SoundID.CAR_DRIVING: load("res://assets/audio/car-driving.mp3"),
	SoundID.WIND: load("res://assets/audio/wind.mp3"),
}

var audio_pool: AudioPool = AudioPool.new()

func _ready() -> void:
	add_child(audio_pool)

func play_sound(sound_id: SoundID, global_position: Vector3, pitch: float = 1.0, volume_db: float = 0.0, loop: bool = false):
	audio_pool.play(sounds[sound_id], global_position, pitch, volume_db, loop)

func play_sound_on_object(sound_id: SoundID, object: Node3D, pitch: float = 1.0, volume_db: float = 0.0, loop: bool = false):
	if not is_instance_valid(object):
		return
	var player = audio_pool.play(sounds[sound_id], Vector3.ZERO, pitch, volume_db, loop)
	audio_pool.attach_to_object(player, object)


func destroy():
	audio_pool.destroy()