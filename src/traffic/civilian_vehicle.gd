class_name CivilianVehicle
extends CharacterBody3D

@export_group("Vehicle Identity & Speed")
## Name/type of the vehicle.
@export var vehicle_type_name: String = "Sedan"

## Cruising speed in km/h.
@export var cruising_speed_kph: float = 92.0

## Target lane offset (-5.5 = Left passing, -1.8 = Left mid, 1.8 = Right mid, 5.5 = Right slow).
@export var target_lane_offset: float = -1.8

## Maximum health before vehicle is wrecked/explodes.
@export var max_health: float = 45.0

## Explosion scene on destruction.
@export var explosion_scene: PackedScene = preload("res://src/weapons/projectiles/explosion_fx.tscn")

var current_lane_offset: float = -1.8
var current_forward_speed: float = 0.0
var current_health: float = 45.0
var is_spinning: bool = false
var spin_timer: float = 0.0
var lane_change_cooldown: float = 4.0
var blocked_timer: float = 0.0
var flash_timer: float = 0.0

@onready var visual_mesh: Node3D = $Visuals
@onready var body_mesh: CSGBox3D = $Visuals/Body if has_node("Visuals/Body") else null
@onready var forward_ray: RayCast3D = $ForwardRay if has_node("ForwardRay") else null

var orig_material: StandardMaterial3D = null
var flash_material: StandardMaterial3D = null

const KPH_TO_MPS: float = 1.0 / 3.6
const GRAVITY: float = 30.0

func _ready() -> void:
	add_to_group("traffic")
	add_to_group("obstacles")
	current_health = max_health
	current_forward_speed = cruising_speed_kph * KPH_TO_MPS
	current_lane_offset = target_lane_offset
	floor_snap_length = 0.8
	floor_constant_speed = true
	floor_max_angle = deg_to_rad(65.0)

	if body_mesh and body_mesh.material is StandardMaterial3D:
		orig_material = body_mesh.material.duplicate()
		flash_material = orig_material.duplicate()
		flash_material.albedo_color = Color(1.0, 0.4, 0.1, 1.0)
		flash_material.emission_enabled = true
		flash_material.emission = Color(1.0, 0.3, 0.1, 1.0)
		flash_material.emission_energy_multiplier = 2.5
		body_mesh.material = orig_material

func _physics_process(delta: float) -> void:
	# Fall safety
	if global_position.y < -12.0:
		queue_free()
		return

	if is_spinning:
		process_spin_out(delta)
		return

	process_lane_and_obstacles(delta)
	process_movement(delta)
	update_visuals(delta)

func process_lane_and_obstacles(delta: float) -> void:
	lane_change_cooldown = max(0.0, lane_change_cooldown - delta)

	# Check if another car or hazard is blocking our forward lane
	var is_blocked: bool = false
	if forward_ray and forward_ray.is_colliding():
		var collider := forward_ray.get_collider()
		if collider != self:
			is_blocked = true

	if is_blocked:
		blocked_timer += delta
		# Slow down slightly to match car ahead
		current_forward_speed = move_toward(current_forward_speed, (cruising_speed_kph * 0.7) * KPH_TO_MPS, 15.0 * delta)
		
		# If blocked for > 1.2s and cooldown elapsed, attempt lane change
		if blocked_timer > 1.2 and lane_change_cooldown <= 0.0:
			attempt_lane_change()
	else:
		blocked_timer = max(0.0, blocked_timer - delta)
		# Cruising pull
		var target_spd: float = cruising_speed_kph * KPH_TO_MPS
		current_forward_speed = move_toward(current_forward_speed, target_spd, 12.0 * delta)

	# Smoothly blend lane offset toward target
	current_lane_offset = move_toward(current_lane_offset, target_lane_offset, 3.2 * delta)

func attempt_lane_change() -> void:
	lane_change_cooldown = 5.0
	blocked_timer = 0.0
	
	# Determine adjacent lanes
	if abs(target_lane_offset - HighwayManager.LANE_LEFT_PASSING) < 0.5:
		target_lane_offset = HighwayManager.LANE_LEFT_CRUISE
	elif abs(target_lane_offset - HighwayManager.LANE_LEFT_CRUISE) < 0.5:
		target_lane_offset = HighwayManager.LANE_LEFT_PASSING if randf() < 0.6 else HighwayManager.LANE_RIGHT_CRUISE
	elif abs(target_lane_offset - HighwayManager.LANE_RIGHT_CRUISE) < 0.5:
		target_lane_offset = HighwayManager.LANE_LEFT_CRUISE if randf() < 0.5 else HighwayManager.LANE_RIGHT_SLOW
	else:
		target_lane_offset = HighwayManager.LANE_RIGHT_CRUISE

func process_movement(delta: float) -> void:
	var target_pt: Vector3 = global_position - (global_transform.basis.z * 16.0)
	var road_fwd: Vector3 = -global_transform.basis.z

	# Query lane waypoint from HighwayManager
	if HighwayManager.instance:
		var road_info: Dictionary = HighwayManager.instance.get_road_transform(global_position, 18.0, current_lane_offset)
		target_pt = road_info.get("position", target_pt)
		road_fwd = road_info.get("forward", road_fwd)

	# Steer toward target lane point (highway guard: forward component cannot be negative)
	var local_target: Vector3 = global_transform.affine_inverse() * target_pt
	var angle_to_target: float = atan2(-local_target.x, max(0.2, -local_target.z))
	var steer_yaw: float = clamp(angle_to_target * 2.5, -1.6, 1.6)

	rotate_y(steer_yaw * delta)
	global_transform.basis = global_transform.basis.orthonormalized()

	var forward_dir: Vector3 = -global_transform.basis.z
	var horizontal_vel: Vector3 = forward_dir * current_forward_speed

	var vertical_y: float = -2.5 if is_on_floor() else velocity.y - GRAVITY * delta
	velocity = Vector3(horizontal_vel.x, vertical_y, horizontal_vel.z)
	move_and_slide()

	# Collision impact with player, enemies, or guardrail
	if get_slide_collision_count() > 0:
		for i in range(get_slide_collision_count()):
			var col: KinematicCollision3D = get_slide_collision(i)
			var col_normal: Vector3 = col.get_normal()
			if col_normal.y > 0.6:
				continue # Floor

			var collider := col.get_collider()
			if collider is ArcadeVehicle:
				var player_spd: float = collider.current_forward_speed * 3.6
				if player_spd > 60.0:
					# High speed collision: bump traffic aside, damage both
					EventBus.civilian_traffic_rammed.emit(self)
					take_damage(20.0)
					collider.take_damage(4.0)
					EventBus.camera_shake_requested.emit(0.20, 0.15)
					EventBus.sfx_requested.emit("bullet_impact", global_position)
					velocity += col_normal * 10.0
			elif collider is EnemyPursuitCar:
				# Enemy rams civilian: shove traffic aside
				take_damage(15.0)
				velocity += col_normal * 12.0
			else:
				# Rail scrape
				velocity = velocity.slide(col_normal)
				velocity.y = min(velocity.y, -1.0)

func process_spin_out(delta: float) -> void:
	spin_timer -= delta
	rotate_y(12.0 * delta)
	current_forward_speed = move_toward(current_forward_speed, 0.0, 22.0 * delta)

	var forward_dir: Vector3 = -global_transform.basis.z
	velocity = forward_dir * current_forward_speed
	velocity.y = -2.5 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()

	if spin_timer <= 0.0:
		is_spinning = false

func spin_out(_slip: float) -> void:
	is_spinning = true
	spin_timer = 2.4
	EventBus.sfx_requested.emit("turbo_surge", global_position)

func take_damage(amount: float, _source: String = "") -> void:
	current_health -= amount
	if body_mesh and flash_material:
		body_mesh.material = flash_material
		flash_timer = 0.08

	if current_health <= 0.0:
		destroy()

func update_visuals(delta: float) -> void:
	if flash_timer > 0.0:
		flash_timer -= delta
		if flash_timer <= 0.0 and body_mesh and orig_material:
			body_mesh.material = orig_material

func destroy() -> void:
	if explosion_scene:
		var expl: Node3D = explosion_scene.instantiate()
		get_parent().add_child(expl)
		expl.global_position = global_position

	EventBus.sfx_requested.emit("explosion", global_position)
	EventBus.camera_shake_requested.emit(0.18, 0.15)
	queue_free()
