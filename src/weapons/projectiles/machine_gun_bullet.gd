class_name MachineGunBullet
extends Area3D

@export var speed: float = 190.0
@export var damage: float = 12.0
@export var max_lifetime: float = 1.4

var direction: Vector3 = Vector3.FORWARD
var lifetime: float = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func initialize(start_pos: Vector3, shoot_dir: Vector3) -> void:
	global_position = start_pos
	direction = shoot_dir.normalized()
	# Point bullet in direction of travel
	look_at(global_position + direction, Vector3.UP)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	lifetime += delta
	if lifetime >= max_lifetime:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	# Ignore player car
	if body is ArcadeVehicle:
		return
	
	if body.has_method("take_damage"):
		if body is EnemyPursuitCar or body is TestTarget:
			body.take_damage(damage, "bullet")
		else:
			body.take_damage(damage)
	
	spawn_impact_fx()
	queue_free()

func _on_area_entered(area: Area3D) -> void:
	if area.has_method("take_damage"):
		area.take_damage(damage)
	spawn_impact_fx()
	queue_free()

func spawn_impact_fx() -> void:
	EventBus.sfx_requested.emit("bullet_impact", global_position)
	# Trigger slight screen vibration on heavy hit
	EventBus.camera_shake_requested.emit(0.04, 0.05)
