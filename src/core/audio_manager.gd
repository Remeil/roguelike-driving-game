extends Node

## Audio Manager with dynamic volume controls, file loading, and procedural synth fallback
## Decoupled via EventBus.sfx_requested

var sound_cache: Dictionary = {}
var players_2d: Array[AudioStreamPlayer] = []
var players_3d: Array[AudioStreamPlayer3D] = []
const POOL_SIZE: int = 12
var next_2d_idx: int = 0
var next_3d_idx: int = 0

const SFX_DIR: String = "res://audio/sfx/"

# Volume state
var master_volume: float = 0.35 # Default to comfortable 35%
var is_muted: bool = false
var prev_volume: float = 0.35

# Per-sound balanced trim in dB
var sfx_volume_trims: Dictionary = {
	"machine_gun_fire": -6.0,
	"bullet_impact": -8.0,
	"missile_launch": -3.0,
	"explosion": -2.0,
	"oil_slick_deploy": -5.0,
	"overheat_warning": -7.0,
	"target_locked": -8.0,
	"target_acquiring": -10.0,
	"weapon_dry": -8.0,
	"turbo_surge": -5.0,
	"gear_shift": -7.0,
	"scrap_pickup": -6.0,
	"missile_pickup": -4.0,
	"van_siren": -5.0,
	"van_dock": -4.0,
	"van_eject": -4.0,
	"upgrade_bought": -5.0,
	"shield_hit": -5.0,
	"shield_break": -3.0,
	"shield_recharged": -5.0,
	"objective_complete": -4.0
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.sfx_requested.connect(play_sfx)

	# Initialize audio player pools
	for i in range(POOL_SIZE):
		var p2d := AudioStreamPlayer.new()
		p2d.bus = "Master"
		add_child(p2d)
		players_2d.append(p2d)

		var p3d := AudioStreamPlayer3D.new()
		p3d.bus = "Master"
		p3d.max_distance = 180.0
		p3d.unit_size = 12.0
		add_child(p3d)
		players_3d.append(p3d)

	# Set initial master bus volume
	apply_volume()

	# Build procedural fallbacks with attenuated headroom
	init_procedural_sounds()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_MINUS:
			set_master_volume(master_volume - 0.05)
		elif event.keycode == KEY_EQUAL: # (+/= key)
			set_master_volume(master_volume + 0.05)
		elif event.keycode == KEY_M:
			toggle_mute()
		elif event.keycode == KEY_0:
			set_master_volume(0.35)

func set_master_volume(new_vol: float) -> void:
	if is_muted and new_vol > master_volume:
		is_muted = false
	master_volume = clamp(new_vol, 0.0, 1.0)
	apply_volume()
	EventBus.volume_changed.emit(int(round(master_volume * 100.0)), is_muted)

func toggle_mute() -> void:
	is_muted = not is_muted
	apply_volume()
	EventBus.volume_changed.emit(int(round(master_volume * 100.0)), is_muted)

func apply_volume() -> void:
	var master_bus_idx := AudioServer.get_bus_index("Master")
	if is_muted or master_volume <= 0.001:
		AudioServer.set_bus_volume_db(master_bus_idx, -80.0)
		AudioServer.set_bus_mute(master_bus_idx, true)
	else:
		AudioServer.set_bus_mute(master_bus_idx, false)
		AudioServer.set_bus_volume_db(master_bus_idx, linear_to_db(master_volume))

func play_sfx(sfx_name: String, pos: Vector3 = Vector3.ZERO) -> void:
	var stream: AudioStream = get_or_load_sound(sfx_name)
	if not stream:
		return

	var trim_db: float = sfx_volume_trims.get(sfx_name, -4.0)

	if pos == Vector3.ZERO:
		var p: AudioStreamPlayer = players_2d[next_2d_idx]
		next_2d_idx = (next_2d_idx + 1) % POOL_SIZE
		p.stream = stream
		p.volume_db = trim_db
		p.pitch_scale = randf_range(0.94, 1.06)
		p.play()
	else:
		var p3: AudioStreamPlayer3D = players_3d[next_3d_idx]
		next_3d_idx = (next_3d_idx + 1) % POOL_SIZE
		p3.stream = stream
		p3.volume_db = trim_db
		p3.global_position = pos
		p3.pitch_scale = randf_range(0.94, 1.06)
		p3.play()

func get_or_load_sound(sfx_name: String) -> AudioStream:
	if sound_cache.has(sfx_name):
		return sound_cache[sfx_name]

	# 1. Check if user provided audio file in audio/sfx/
	for ext: String in [".wav", ".ogg", ".mp3"]:
		var path: String = SFX_DIR + sfx_name + ext
		if ResourceLoader.exists(path):
			var res: AudioStream = load(path) as AudioStream
			if res:
				sound_cache[sfx_name] = res
				return res

	# 2. Check alias mappings (e.g. "machine_gun_fire" -> "machine_gun")
	var simplified_name: String = sfx_name.replace("_fire", "").replace("_deploy", "").replace("_launch", "")
	for ext: String in [".wav", ".ogg", ".mp3"]:
		var path: String = SFX_DIR + simplified_name + ext
		if ResourceLoader.exists(path):
			var res: AudioStream = load(path) as AudioStream
			if res:
				sound_cache[sfx_name] = res
				return res

	return sound_cache.get(sfx_name, null)

func init_procedural_sounds() -> void:
	# Machine Gun: Rapid snappy percussive pop
	sound_cache["machine_gun_fire"] = synth_wav(0.065, func(t: float, dur: float) -> float:
		var env: float = (1.0 - t / dur) ** 2.5
		var noise: float = randf_range(-0.7, 0.7)
		var pop: float = sin(t * 720.0 * TAU) * 0.3
		return env * (noise + pop)
	)

	# Bullet Impact: High-pitched kinetic ricochet ping
	sound_cache["bullet_impact"] = synth_wav(0.045, func(t: float, dur: float) -> float:
		var env: float = (1.0 - t / dur) ** 3.5
		var ping: float = sin(t * 1480.0 * TAU)
		return env * ping * 0.5
	)

	# Missile Launch: Upward rocketing thrust whoosh
	sound_cache["missile_launch"] = synth_wav(0.28, func(t: float, dur: float) -> float:
		var env: float = sin((t / dur) * PI)
		var freq: float = lerp(160.0, 520.0, t / dur)
		var tone: float = sin(t * freq * TAU)
		var hiss: float = randf_range(-0.5, 0.5)
		return env * (tone * 0.35 + hiss * 0.45)
	)

	# Explosion: Heavy sub-bass crunch and low rumble
	sound_cache["explosion"] = synth_wav(0.50, func(t: float, dur: float) -> float:
		var env: float = (1.0 - t / dur) ** 1.8
		var bass: float = sin(t * 52.0 * TAU) * 0.4
		var crunch: float = randf_range(-0.7, 0.7) * 0.4
		return env * (bass + crunch)
	)

	# Oil Slick Deploy: Pressurized liquid squirt
	sound_cache["oil_slick_deploy"] = synth_wav(0.20, func(t: float, dur: float) -> float:
		var env: float = (1.0 - t / dur) ** 1.6
		var freq: float = lerp(540.0, 110.0, t / dur)
		var squirt: float = sin(t * freq * TAU)
		return env * squirt * 0.5
	)

	# Overheat Warning: Dual-tone urgent alert beep
	sound_cache["overheat_warning"] = synth_wav(0.16, func(t: float, dur: float) -> float:
		var freq: float = 920.0 if fmod(t, 0.08) < 0.04 else 620.0
		var tone: float = sin(t * freq * TAU)
		return 0.4 * tone
	)

	# Target Locked: High-tech lock-on confirmation chime
	sound_cache["target_locked"] = synth_wav(0.10, func(t: float, dur: float) -> float:
		var env: float = 1.0 - (t / dur * 0.4)
		var tone: float = sin(t * 1760.0 * TAU)
		return env * tone * 0.4
	)

	# Target Acquiring: Subtle radar blip
	sound_cache["target_acquiring"] = synth_wav(0.05, func(t: float, dur: float) -> float:
		var env: float = 1.0 - (t / dur)
		var tone: float = sin(t * 880.0 * TAU)
		return env * tone * 0.25
	)

	# Weapon Dry: Mechanical hollow click
	sound_cache["weapon_dry"] = synth_wav(0.035, func(t: float, dur: float) -> float:
		var env: float = (1.0 - t / dur) ** 3.0
		return env * randf_range(-0.5, 0.5) * 0.3
	)

	# Turbo Surge: Sci-fi rising turbo spool
	sound_cache["turbo_surge"] = synth_wav(0.35, func(t: float, dur: float) -> float:
		var env: float = sin((t / dur) * PI)
		var freq: float = lerp(260.0, 1200.0, t / dur)
		var spool: float = sin(t * freq * TAU)
		return env * spool * 0.45
	)

	# Gear Shift: Tactile transmission click / exhaust pop
	sound_cache["gear_shift"] = synth_wav(0.06, func(t: float, dur: float) -> float:
		var env: float = (1.0 - t / dur) ** 2.2
		var click: float = sin(t * 320.0 * TAU) * 0.4
		var exhaust: float = randf_range(-0.5, 0.5) * 0.4
		return env * (click + exhaust)
	)

	# Scrap Pickup: Two-tone bright arcade chime
	sound_cache["scrap_pickup"] = synth_wav(0.12, func(t: float, dur: float) -> float:
		var env: float = (1.0 - t / dur) ** 1.8
		var freq: float = 1200.0 if t < 0.055 else 1650.0
		var tone: float = sin(t * freq * TAU)
		return env * tone * 0.4
	)

	# Missile Pickup: Punchy heavy arming tone with dual rising harmonic chime
	sound_cache["missile_pickup"] = synth_wav(0.24, func(t: float, dur: float) -> float:
		var env: float = (1.0 - t / dur) ** 1.3
		var f1: float = lerp(480.0, 960.0, clamp(t / 0.12, 0.0, 1.0))
		var f2: float = 1440.0 if t > 0.10 else 720.0
		var tone: float = sin(t * f1 * TAU) * 0.45 + sin(t * f2 * TAU) * 0.35
		return env * tone * 0.45
	)

	# Weapons Van Siren: Iconic alternating two-tone rendezvous klaxon
	sound_cache["van_siren"] = synth_wav(0.55, func(t: float, dur: float) -> float:
		var env: float = sin((t / dur) * PI)
		var freq: float = 620.0 if fmod(t, 0.28) < 0.14 else 820.0
		var tone: float = sin(t * freq * TAU)
		return env * tone * 0.55
	)

	# Weapons Van Dock: Heavy hydraulic clamp lock and pneumatic seal
	sound_cache["van_dock"] = synth_wav(0.42, func(t: float, dur: float) -> float:
		var env: float = (1.0 - t / dur) ** 2.0
		var sub: float = sin(t * 85.0 * TAU) * 0.7
		var hiss: float = randf_range(-0.5, 0.5) * (1.0 - clamp(t / 0.2, 0.0, 1.0)) * 0.4
		var clank: float = sin(t * 240.0 * TAU) * 0.5 if t < 0.08 else 0.0
		return env * (sub + hiss + clank) * 0.6
	)

	# Weapons Van Eject: High-pressure pneumatic launch burst
	sound_cache["van_eject"] = synth_wav(0.38, func(t: float, dur: float) -> float:
		var env: float = (1.0 - t / dur) ** 1.6
		var hiss: float = randf_range(-0.7, 0.7) * 0.6
		var punch: float = sin(t * 110.0 * TAU) * 0.6 if t < 0.12 else 0.0
		return env * (hiss + punch) * 0.65
	)

	# Upgrade Bought: Clean high-tech tri-tone chime
	sound_cache["upgrade_bought"] = synth_wav(0.28, func(t: float, dur: float) -> float:
		var env: float = (1.0 - t / dur) ** 1.2
		var freq: float = 660.0
		if t > 0.16:
			freq = 1320.0
		elif t > 0.08:
			freq = 990.0
		var tone: float = sin(t * freq * TAU)
		return env * tone * 0.45
	)

	# Shield Hit: Crystalline resonant electric ping
	sound_cache["shield_hit"] = synth_wav(0.18, func(t: float, dur: float) -> float:
		var env: float = (1.0 - t / dur) ** 2.2
		var tone: float = sin(t * 1850.0 * TAU) * 0.6 + sin(t * 3700.0 * TAU) * 0.3
		var buzz: float = randf_range(-0.3, 0.3) * (1.0 - clamp(t / 0.06, 0.0, 1.0))
		return env * (tone + buzz) * 0.55
	)

	# Shield Break: Shattering electric overload discharge
	sound_cache["shield_break"] = synth_wav(0.35, func(t: float, dur: float) -> float:
		var env: float = (1.0 - t / dur) ** 1.8
		var crack: float = randf_range(-0.9, 0.9) * (1.0 - clamp(t / 0.1, 0.0, 1.0))
		var low_hum: float = sin(t * 140.0 * TAU) * 0.7
		var spark: float = sin(t * lerp(2200.0, 440.0, clamp(t / dur, 0.0, 1.0)) * TAU) * 0.4
		return env * (crack + low_hum + spark) * 0.65
	)

	# Shield Recharged: Ascending harmonic recharge chime
	sound_cache["shield_recharged"] = synth_wav(0.30, func(t: float, dur: float) -> float:
		var env: float = (1.0 - t / dur) ** 1.4
		var freq: float = lerp(520.0, 1560.0, clamp(t / dur, 0.0, 1.0))
		var tone: float = sin(t * freq * TAU) * 0.5 + sin(t * (freq * 1.5) * TAU) * 0.3
		return env * tone * 0.5
	)

	# Objective Complete: Triumphant rising arcade fanfare (C5 -> E5 -> G5 -> C6)
	sound_cache["objective_complete"] = synth_wav(0.40, func(t: float, dur: float) -> float:
		var env: float = (1.0 - t / dur) ** 1.15
		var step: int = int(floor(t / 0.08))
		var freqs: Array[float] = [523.25, 659.25, 783.99, 1046.50, 1046.50]
		var freq: float = freqs[min(step, freqs.size() - 1)]
		var tone: float = sin(t * freq * TAU) * 0.5 + sin(t * freq * 2.0 * TAU) * 0.25
		return env * tone * 0.55
	)

func synth_wav(duration: float, sample_func: Callable, sample_rate: int = 22050) -> AudioStreamWAV:
	var total_samples: int = int(duration * sample_rate)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)

	# Attenuate sample scale to 0.40 to ensure ~8dB digital headroom
	for i in range(total_samples):
		var t: float = float(i) / float(sample_rate)
		var s: float = clamp(sample_func.call(t, duration), -1.0, 1.0) * 0.40
		var val_16: int = int(s * 32767.0)
		bytes.encode_s16(i * 2, val_16)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = bytes
	return wav
