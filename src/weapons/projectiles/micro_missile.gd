class_name MicroMissile
extends Area3D

## High-speed homing micro-missile with Macross-style lofted ejection and proportional navigation guidance

@export var start_speed: float = 46.0
@export var max_speed: float = 148.0
@export var acceleration: float = 165.0
@export var damage: float = 65.0
@export var spiral_radius: float = 0.35
@export var spiral_frequency: float = 16.0

var is_detonated: bool = false
var current_speed: float = 46.0
var target_point: Vector3 = Vector3.ZERO
var target_node: Node3D = null
var direction: Vector3 = Vector3.FORWARD
var time_alive: float = 0.0
var spiral_phase: float = 0.0
var explosion_scene: PackedScene = preload("res://src/weapons/projectiles/explosion_fx.tscn")

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	spiral_phase = randf() * TAU

func initialize(start_pos: Vector3, shoot_dir: Vector3, target_pos: Vector3, target: Node3D = null) -> void:
	global_position = start_pos
	direction = shoot_dir.normalized()
	target_point = target_pos
	target_node = target
	current_speed = start_speed
	look_at(global_position + direction, Vector3.UP)

func _physics_process(delta: float) -> void:
	if is_detonated:
		return

	time_alive += delta
	current_speed = move_toward(current_speed, max_speed, acceleration * delta)

	# Update target point dynamically to vehicle center-of-mass (above wheels)
	if is_instance_valid(target_node):
		var center_offset: Vector3 = target_node.global_transform.basis.y * 0.85
		target_point = target_node.global_position + center_offset

	var dist_to_target: float = 100.0

	# Lofted Ejection vs Proportional Navigation Homing:
	# 0.00s - 0.16s: Upward loft pop out of vehicle bay (clears hood and road floor)
	# 0.16s onward: High-authority proportional navigation homing
	if target_point != Vector3.ZERO:
		var to_target_vec: Vector3 = target_point - global_position
		dist_to_target = to_target_vec.length()
		var to_target: Vector3 = to_target_vec.normalized()
		var dot_heading: float = to_target.dot(direction)

		# Anti-orbiting and proximity detection:
		# If the missile has flown past the target (target is behind missile heading) after initial launch
		if time_alive > 0.20 and dot_heading < -0.05:
			if dist_to_target < 3.5:
				# Proximity fuse detonation on near-miss / fly-by
				if is_instance_valid(target_node) and target_node.has_method("take_damage"):
					if target_node is EnemyPursuitCar or target_node is TestTarget:
						target_node.take_damage(damage, "missile")
					else:
						target_node.take_damage(damage)
				detonate()
				return
			else:
				# Clean break-away: missile overshot target widely. Lose lock and dive toward road
				target_node = null
				target_point = Vector3.ZERO
				# Pitch down towards ground to impact road naturally instead of looping
				direction = (direction + Vector3.DOWN * 0.45).normalized()
		else:
			var homing_rate: float
			if time_alive < 0.16:
				homing_rate = lerp(1.5, 6.0, time_alive / 0.16)
			else:
				# Dynamic homing rate: tightens as missile closes in for lethal accuracy
				homing_rate = lerp(15.0, 10.5, clamp(dist_to_target / 55.0, 0.0, 1.0))

			direction = direction.lerp(to_target, homing_rate * delta).normalized()

	# Spiraling corkscrew motion (modulates with distance: narrows near target to avoid missing or hitting ground)
	var active_spiral_radius: float = spiral_radius
	if time_alive < 0.14:
		active_spiral_radius = lerp(0.04, spiral_radius, time_alive / 0.14)
	elif dist_to_target < 16.0:
		# Tighten spiral down to 0 right before impact for pinpoint strike
		active_spiral_radius = lerp(0.0, spiral_radius, dist_to_target / 16.0)

	var right: Vector3 = direction.cross(Vector3.UP).normalized()
	if right.is_zero_approx():
		right = Vector3.RIGHT
	var up: Vector3 = right.cross(direction).normalized()
	var spiral_angle: float = time_alive * spiral_frequency + spiral_phase
	var spiral_offset: Vector3 = (right * cos(spiral_angle) + up * sin(spiral_angle)) * active_spiral_radius

	var move_step: Vector3 = (direction * current_speed * delta) + (spiral_offset * delta * 4.0)
	global_position += move_step

	if not direction.is_zero_approx():
		look_at(global_position + direction, Vector3.UP)

	# Lifetime timeout
	if time_alive > 2.8:
		detonate()

func _on_body_entered(body: Node3D) -> void:
	if is_detonated:
		return

	# Ignore player car
	if body is ArcadeVehicle:
		return

	# Ground/road collision (Layer 2) after arming delay
	if body.collision_layer == 2:
		if time_alive < 0.15:
			return
		detonate()
		return

	if body.has_method("take_damage"):
		if body is EnemyPursuitCar or body is TestTarget:
			body.take_damage(damage, "missile")
		else:
			body.take_damage(damage)
	detonate()

func _on_area_entered(area: Area3D) -> void:
	if is_detonated:
		return

	# Ignore friendly munition and pickup triggers
	if area is MachineGunBullet or area is MicroMissile or area is OilSlick or area is MissilePickup:
		return

	if area.has_method("take_damage"):
		area.take_damage(damage)
	detonate()

func detonate() -> void:
	if is_detonated:
		return
	is_detonated = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

	if explosion_scene:
		var expl: Node3D = explosion_scene.instantiate()
		var parent: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
		parent.add_child(expl)
		expl.global_position = global_position
	EventBus.explosion_spawned.emit(global_position, 4.0)
	queue_free()
