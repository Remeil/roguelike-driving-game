class_name EnemyBullet
extends Area3D

@export var speed: float = 175.0
@export var damage: float = 8.0
@export var max_lifetime: float = 1.4

var direction: Vector3 = Vector3.FORWARD
var lifetime: float = 0.0

func _ready() -> void:
	add_to_group("enemy_bullets")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func initialize(start_pos: Vector3, shoot_dir: Vector3) -> void:
	global_position = start_pos
	direction = shoot_dir.normalized()
	look_at(global_position + direction, Vector3.UP)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	lifetime += delta
	if lifetime >= max_lifetime:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	# Ignore enemies and targeting nodes
	if body.is_in_group("enemies"):
		return

	if body.has_method("take_damage"):
		body.take_damage(damage)

	spawn_impact_fx()
	queue_free()

func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group("enemies"):
		return

	if area.has_method("take_damage"):
		area.take_damage(damage)

	spawn_impact_fx()
	queue_free()

func spawn_impact_fx() -> void:
	EventBus.sfx_requested.emit("bullet_impact", global_position)
