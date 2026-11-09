class_name TestTarget
extends CharacterBody3D

@export var max_health: float = 60.0
@export var scrap_reward: int = 5
var current_health: float = 60.0
var is_spinning: bool = false
var spin_timer: float = 0.0
var last_damage_source: String = "bullet"
var is_destroyed: bool = false

@onready var mesh: CSGBox3D = $VisualMesh
var explosion_scene: PackedScene = preload("res://src/weapons/projectiles/explosion_fx.tscn")
var ammo_pickup_scene: PackedScene = preload("res://src/weapons/pickups/missile_pickup.tscn")

func _ready() -> void:
	add_to_group("enemies")
	current_health = max_health

func _physics_process(delta: float) -> void:
	if is_spinning:
		spin_timer -= delta
		rotate_y(14.0 * delta)
		velocity = velocity.lerp(Vector3.ZERO, 3.0 * delta)
		move_and_slide()
		if spin_timer <= 0.0:
			is_spinning = false

func take_damage(amount: float, source: String = "") -> void:
	if is_destroyed:
		return
	if source != "":
		last_damage_source = source
	current_health -= amount
	# Flash mesh white/red
	if mesh and mesh.material is StandardMaterial3D:
		var orig_mat := mesh.material as StandardMaterial3D
		orig_mat.albedo_color = Color(1.0, 0.2, 0.2)
		get_tree().create_timer(0.08).timeout.connect(func() -> void:
			if is_instance_valid(orig_mat):
				orig_mat.albedo_color = Color(0.85, 0.25, 0.2)
		)

	if current_health <= 0.0 and not is_destroyed:
		destroy()

func spin_out(_slip: float) -> void:
	is_spinning = true
	spin_timer = 2.0
	EventBus.sfx_requested.emit("turbo_surge", global_position)
	EventBus.enemy_spun_out.emit(self)

func destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	remove_from_group("enemies")
	collision_layer = 0
	collision_mask = 0

	if explosion_scene:
		var expl: Node3D = explosion_scene.instantiate()
		get_parent().add_child(expl)
		expl.global_position = global_position

	EventBus.scrap_awarded.emit(scrap_reward)
	EventBus.enemy_destroyed_with_source.emit("test_target", last_damage_source, global_position)
	if ammo_pickup_scene and randf() < 0.35 and get_parent():
		var pickup: Node3D = ammo_pickup_scene.instantiate()
		get_parent().add_child(pickup)
		pickup.global_position = global_position + Vector3(0, 0.75, 0)
	queue_free()
