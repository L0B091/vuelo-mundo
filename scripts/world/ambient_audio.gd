class_name AmbientAudio
extends Node
## Sonido ambiente: olas de playa (CC0, jasinski / OpenGameArt) que suben cerca del agua y a
## baja altura; bajo el agua, filtro pasa-bajos en el bus maestro (sonido apagado) y burbujeo
## procedural. Barato: un reproductor en bucle + un generador chico.

const WAVES := "res://assets/audio/olas_playa_cc0.ogg"

var avatar: Avatar
var tod: TimeOfDay
var underwater: bool = false
var shore_level: float = 0.0
var _shore: AudioStreamPlayer
var _lp: AudioEffectLowPassFilter
var _bub: AudioStreamPlayer
var _bub_pb: AudioStreamGeneratorPlayback
var _rng := RandomNumberGenerator.new()
var _bub_env: float = 0.0


func setup(p_avatar: Avatar, p_tod: TimeOfDay) -> void:
	avatar = p_avatar
	tod = p_tod
	_shore = AudioStreamPlayer.new()
	var st: AudioStreamOggVorbis = load(WAVES)
	st.loop = true
	_shore.stream = st
	_shore.volume_db = -60.0
	add_child(_shore)
	_shore.play()
	_lp = AudioEffectLowPassFilter.new()
	_lp.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(0, _lp)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.1
	_bub = AudioStreamPlayer.new()
	_bub.stream = gen
	add_child(_bub)
	_bub.play()
	_bub_pb = _bub.get_stream_playback() as AudioStreamGeneratorPlayback


func _process(dt: float) -> void:
	if avatar == null:
		return
	underwater = tod != null and tod.underwater
	var low := 1.0 - smoothstep(5.0, 160.0, avatar.agl)
	var want := low * (1.0 if avatar.surface == "agua" or avatar.state == Avatar.State.WALK else 0.6)
	if underwater:
		want = 0.35
	shore_level = lerpf(shore_level, want, clampf(dt * 1.5, 0.0, 1.0))
	_shore.volume_db = linear_to_db(maxf(shore_level, 0.0005)) - 4.0
	_lp.cutoff_hz = lerpf(_lp.cutoff_hz, 550.0 if underwater else 20000.0, clampf(dt * 6.0, 0.0, 1.0))
	_bubbles()


## Burbujas: barridos senoidales cortos ascendentes (como al exhalar), solo bajo el agua.
func _bubbles() -> void:
	if _bub_pb == null:
		return
	var n := _bub_pb.get_frames_available()
	for i in n:
		if underwater and _bub_env <= 0.0 and _rng.randf() < 0.0009:
			_bub_env = 1.0
		var s := 0.0
		if _bub_env > 0.0:
			_bub_env -= 1.0 / 1500.0
			var f := 500.0 + 1400.0 * (1.0 - _bub_env)
			s = sin(float(Time.get_ticks_usec() % 1000000) * 1e-6 * TAU * f + float(i) * TAU * f / 22050.0)
			s *= _bub_env * 0.25
		_bub_pb.push_frame(Vector2(s, s))
