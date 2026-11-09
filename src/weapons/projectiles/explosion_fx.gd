class_name ExplosionFX
extends Node3D

@onready var light: OmniLight3D = $Light
@onready var fireball: MeshInstance3D = $Fireball

var timer: float = 0.0
const DURATION: float = 0.6

func _ready() -> void:
	EventBus.camera_shake_requested.emit(0.32, 0.22)
	EventBus.sfx_requested.emit("explosion", global_position)

func _process(delta: float) -> void:
	timer += delta
	var t: float = clamp(timer / DURATION, 0.0, 1.0)

	# Expand fireball
	var scale_factor: float = lerp(0.8, 4.2, sqrt(t))
	fireball.scale = Vector3.ONE * scale_factor

	# Fade light and material
	if light:
		light.light_energy = lerp(5.0, 0.0, t)

	if timer >= DURATION:
		queue_free()
