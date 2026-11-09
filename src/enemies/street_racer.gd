class_name StreetRacer
extends CharacterBody3D

## High-speed syndicate street racer for the "Street Race" mission objective.
## Outpaces standard pursuit cars, surges with Nitro bursts, and scales dynamically with player speed upgrades.

@export_group("Durability & Economy")
@export var max_health: float = 95.0
@export var scrap_reward: int = 15

@export_group("Visual Effects")
@export var explosion_scene: PackedScene = preload("res://src/weapons/projectiles/explosion_fx.tscn")
@export var ammo_pickup_scene: PackedScene = preload("res://src/weapons/pickups/missile_pickup.tscn")

var current_health: float = 95.0
var current_forward_speed: float = 0.0
var target_player: ArcadeVehicle = null
var current_lane_offset: float = 1.8
var target_lane_offset: float = 1.8
var is_destroyed: bool = false
var is_retired: bool = false
var last_damage_source: String = "bullet"
var flash_timer: float = 0.0
var spin_timer: float = 0.0
var is_spinning: bool = false

# Nitrous burst system
var nitro_active: bool = false
var nitro_timer: float = 0.0
var nitro_cooldown: float = 4.5

# Race distance metrics
var race_distance_traveled: float = 0.0
var last_position_z: float = 0.0
var lane_change_cooldown: float = 1.5

@onready var visual_mesh: Node3D = $Visuals
@onready var chassis_mesh: CSGBox3D = $Visuals/Chassis
@onready var nitro_flame_l: CSGCylinder3D = $Visuals/Chassis/NitroFlame_L
@onready var nitro_flame_r: CSGCylinder3D = $Visuals/Chassis/NitroFlame_R
@onready var underglow_light: OmniLight3D = $Visuals/Underglow
@onready var ground_ray: RayCast3D = $GroundRay

var orig_material: StandardMaterial3D = null
var flash_material: StandardMaterial3D = null

const KPH_TO_MPS: float = 1.0 / 3.6
const GRAVITY: float = 30.0

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("street_racer")
	current_health = max_health
	floor_snap_length = 1.5
	floor_constant_speed = true
	floor_max_angle = deg_to_rad(65.0)

	find_player()
	last_position_z = global_position.z

	# Calculate initial speed based on player
	var p_top: float = target_player.top_speed_kph if is_instance_valid(target_player) else 140.0
	current_forward_speed = (p_top * 0.95) * KPH_TO_MPS

	if chassis_mesh and chassis_mesh.material is StandardMaterial3D:
		orig_material = chassis_mesh.material.duplicate()
		flash_material = orig_material.duplicate()
		flash_material.albedo_color = Color(1.0, 0.3, 0.2, 1.0)
		flash_material.emission_enabled = true
		flash_material.emission = Color(1.0, 0.4, 0.2, 1.0)
		flash_material.emission_energy_multiplier = 3.5
		chassis_mesh.material = orig_material

	# Initial opening launch burst: blast forward at race start to speed off into the distance!
	nitro_active = true
	nitro_timer = 2.4
	set_nitro_visuals(true)
	nitro_cooldown = 10.0

func find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is ArcadeVehicle:
		target_player = players[0] as ArcadeVehicle

## Dynamically scales base cruising speed from player's upgraded top speed
func get_target_cruising_speed_kph() -> float:
	var p_top: float = target_player.top_speed_kph if is_instance_valid(target_player) else 140.0
	
	# Rubberbanding:
	if is_instance_valid(target_player):
		var to_racer: Vector3 = global_position - target_player.global_position
		var lead_dist: float = (-target_player.global_transform.basis.z).dot(to_racer)
		if lead_dist > 65.0:
			# If pulling far ahead (>65m), ease off slightly so player can reel them in with Nitro
			return p_top * 0.98
		elif lead_dist < -4.0:
			# Player is ahead in 1st place: rival aggressively drafts right behind at 102%
			return p_top * 1.02

	# Cruising speed is 102% of player's top cruise speed (e.g. 143 km/h default),
	# so rival gradually pulls away unless player drives well and uses Nitro!
	return p_top * 1.02

## Dynamically scales nitro burst speed from player's upgraded stats
func get_target_nitro_speed_kph() -> float:
	var p_top: float = target_player.boost_top_speed_kph if is_instance_valid(target_player) else 200.0
	# Nitro burst surges ~18 km/h over player cruise speed (e.g. 158 km/h default),
	# aggressive and exciting, but still well below player's 200 km/h Nitro boost!
	return p_top * 0.9

func _physics_process(delta: float) -> void:
	if is_destroyed:
		return

	# Fall safety: if knocked off highway or fell into void, award takedown elimination!
	if global_position.y < -7.0:
		destroy()
		return

	if not is_instance_valid(target_player):
		find_player()

	# Track distance traveled forward
	var z_step: float = abs(global_position.z - last_position_z)
	if z_step > 0.0 and z_step < 50.0:
		race_distance_traveled += z_step
	last_position_z = global_position.z

	if is_spinning:
		process_spin_out(delta)
		return

	process_nitro(delta)
	process_traffic_avoidance(delta)
	process_movement(delta)
	update_visuals(delta)

func process_nitro(delta: float) -> void:
	if is_retired:
		if nitro_active:
			set_nitro_visuals(false)
		return

	if nitro_active:
		nitro_timer -= delta
		if nitro_timer <= 0.0:
			nitro_active = false
			set_nitro_visuals(false)
			nitro_cooldown = randf_range(6.5, 9.5)
	else:
		# Don't boost if already far ahead (>60m)
		var is_far_ahead: bool = false
		if is_instance_valid(target_player):
			var to_racer: Vector3 = global_position - target_player.global_position
			var lead_dist: float = (-target_player.global_transform.basis.z).dot(to_racer)
			if lead_dist > 60.0:
				is_far_ahead = true

		if not is_far_ahead:
			nitro_cooldown -= delta
			if nitro_cooldown <= 0.0:
				nitro_active = true
				nitro_timer = randf_range(1.8, 2.4)
				set_nitro_visuals(true)
				EventBus.sfx_requested.emit("turbo_surge", global_position)

func set_nitro_visuals(active: bool) -> void:
	if nitro_flame_l:
		nitro_flame_l.visible = active
	if nitro_flame_r:
		nitro_flame_r.visible = active
	if underglow_light:
		underglow_light.light_energy = 3.5 if active else 1.8

func process_traffic_avoidance(delta: float) -> void:
	lane_change_cooldown -= delta
	if lane_change_cooldown > 0.0:
		return

	# Check for civilian traffic AND stationary target drones / enemy obstacles ahead
	var candidate_obstacles: Array[Node] = []
	candidate_obstacles.append_array(get_tree().get_nodes_in_group("traffic"))
	candidate_obstacles.append_array(get_tree().get_nodes_in_group("enemies"))

	var obstacle_in_front: bool = false

	for obs in candidate_obstacles:
		if not is_instance_valid(obs) or not (obs is Node3D) or obs == self or obs == target_player:
			continue
		var to_obs: Vector3 = (obs as Node3D).global_position - global_position
		# If obstacle is 3m to 38m directly ahead in approximately our lane
		var forward_dist: float = (-global_transform.basis.z).dot(to_obs)
		var lateral_dist: float = abs(global_transform.basis.x.dot(to_obs))

		if forward_dist > 3.0 and forward_dist < 38.0 and lateral_dist < 2.5:
			obstacle_in_front = true
			break

	if obstacle_in_front:
		# Shift to best open lane to weave smoothly through traffic and around targets
		var lanes := HighwayManager.ALL_LANES
		var best_lane: float = target_lane_offset
		var max_lane_score: float = -999.0

		for lane in lanes:
			if abs(lane - target_lane_offset) < 0.5:
				continue
			var lane_min_dist: float = 999.0
			for obs in candidate_obstacles:
				if not is_instance_valid(obs) or not (obs is Node3D) or obs == self or obs == target_player:
					continue
				var to_obs: Vector3 = (obs as Node3D).global_position - global_position
				var f_dist: float = (-global_transform.basis.z).dot(to_obs)
				if f_dist > 2.0 and f_dist < 50.0:
					var l_offset: float = (global_transform.basis.x).dot(to_obs)
					var lane_diff: float = lane - current_lane_offset
					if abs(l_offset - lane_diff) < 2.2:
						if f_dist < lane_min_dist:
							lane_min_dist = f_dist

			var shift_cost: float = abs(lane - target_lane_offset) * 2.0
			var score: float = lane_min_dist - shift_cost
			if score > max_lane_score:
				max_lane_score = score
				best_lane = lane

		target_lane_offset = best_lane
		lane_change_cooldown = 1.0

func process_movement(delta: float) -> void:
	# Calculate target speed
	var target_speed_kph: float = 0.0
	if is_retired:
		# Race already finished: coast down to slow speed
		target_speed_kph = 90.0
	elif nitro_active:
		target_speed_kph = get_target_nitro_speed_kph()
	else:
		target_speed_kph = get_target_cruising_speed_kph()

	# Blend lane offset toward target lane
	current_lane_offset = move_toward(current_lane_offset, target_lane_offset, 5.5 * delta)

	# Spline lookahead target point
	var target_pt: Vector3 = global_position - global_transform.basis.z * 22.0
	if HighwayManager.instance:
		var road_info: Dictionary = HighwayManager.instance.get_road_transform(global_position, 22.0, current_lane_offset)
		target_pt = road_info.get("position", target_pt)

	# Steer toward highway spline lookahead
	var local_target: Vector3 = global_transform.affine_inverse() * target_pt
	var angle_to_target: float = atan2(-local_target.x, max(0.2, -local_target.z))

	# Tight high-speed cornering physics
	var steer_yaw: float = clamp(angle_to_target * 3.2, -1.9, 1.9)
	rotate_y(steer_yaw * delta)
	global_transform.basis = global_transform.basis.orthonormalized()

	# Smooth acceleration
	var target_mps: float = target_speed_kph * KPH_TO_MPS
	var accel_rate: float = 40.0 if nitro_active else 28.0
	current_forward_speed = move_toward(current_forward_speed, target_mps, accel_rate * delta)

	# Forward velocity & lateral grip
	var forward_dir: Vector3 = -global_transform.basis.z
	var right_dir: Vector3 = global_transform.basis.x
	var forward_vel: Vector3 = forward_dir * current_forward_speed
	var current_lateral: Vector3 = velocity.project(right_dir)
	var damped_lateral: Vector3 = current_lateral * 0.06

	var horizontal_vel: Vector3 = forward_vel + damped_lateral

	# Road surface snapping & banking alignment
	var on_ground: bool = is_on_floor()
	if ground_ray and ground_ray.is_colliding():
		var hit_pt: Vector3 = ground_ray.get_collision_point()
		var hit_norm: Vector3 = ground_ray.get_collision_normal()

		# Snap down/up if slight displacement over chunk seams
		if not on_ground and global_position.y < hit_pt.y + 0.6 and global_position.y > hit_pt.y - 1.2:
			global_position.y = hit_pt.y + 0.45
			velocity.y = 0.0
			on_ground = true

		# Slope & banking alignment
		if hit_norm.y > 0.4 and hit_norm.y < 0.999:
			var cur_fwd: Vector3 = -global_transform.basis.z
			var right_vec: Vector3 = cur_fwd.cross(hit_norm).normalized()
			var back_vec: Vector3 = right_vec.cross(hit_norm).normalized()
			var target_basis: Basis = Basis(right_vec, hit_norm, back_vec).orthonormalized()
			global_transform.basis = global_transform.basis.slerp(target_basis, 10.0 * delta).orthonormalized()

	var vertical_y: float = -3.5 if on_ground else velocity.y - GRAVITY * delta
	velocity = Vector3(horizontal_vel.x, vertical_y, horizontal_vel.z)
	move_and_slide()

	# Collision impact with player and obstacles
	if get_slide_collision_count() > 0:
		for i in range(get_slide_collision_count()):
			var col: KinematicCollision3D = get_slide_collision(i)
			var col_normal: Vector3 = col.get_normal()
			if col_normal.y > 0.6:
				continue
			var collider := col.get_collider()
			if collider is ArcadeVehicle:
				collider.take_damage(5.0 * collider.ram_recoil_multiplier)
				var ram_dmg: float = 15.0 * collider.ram_multiplier
				take_damage(ram_dmg, "ram")
				EventBus.camera_shake_requested.emit(0.22, 0.2)
				EventBus.sfx_requested.emit("bullet_impact", global_position)
				velocity += col_normal * 10.0
			elif collider and collider.has_method("take_damage") and not (collider is ArcadeVehicle):
				# Smash through stationary target drone or enemy obstacle with high-speed ram!
				collider.take_damage(100.0, "ram")
				EventBus.sfx_requested.emit("explosion", col.get_position())
				target_lane_offset = HighwayManager.LANE_LEFT_PASSING if current_lane_offset > 0.0 else HighwayManager.LANE_RIGHT_SLOW
				lane_change_cooldown = 0.5
			else:
				velocity = velocity.slide(col_normal)
				velocity.y = min(velocity.y, -1.0)

	# Anti-stuck watchdog: if racer gets wedged below 15 km/h while active, push to open lane
	if not is_retired and current_forward_speed < 15.0:
		target_lane_offset = HighwayManager.LANE_LEFT_CRUISE if current_lane_offset > 0.0 else HighwayManager.LANE_RIGHT_CRUISE
		current_forward_speed = max(current_forward_speed, 35.0)

func update_visuals(delta: float) -> void:
	if flash_timer > 0.0:
		flash_timer -= delta
		if flash_timer <= 0.0 and chassis_mesh and orig_material:
			chassis_mesh.material = orig_material

func take_damage(amount: float, source: String = "") -> void:
	if is_destroyed:
		return
	if source != "":
		last_damage_source = source
	current_health -= amount

	if chassis_mesh and flash_material:
		chassis_mesh.material = flash_material
		flash_timer = 0.09

	if current_health <= 0.0 and not is_destroyed:
		destroy()

func spin_out(_slip: float) -> void:
	if is_spinning or is_destroyed:
		return
	is_spinning = true
	spin_timer = 1.8
	nitro_active = false
	set_nitro_visuals(false)
	EventBus.sfx_requested.emit("bullet_impact", global_position)

func process_spin_out(delta: float) -> void:
	spin_timer -= delta
	rotate_y(14.0 * delta)
	current_forward_speed = move_toward(current_forward_speed, 0.0, 30.0 * delta)

	var forward_dir: Vector3 = -global_transform.basis.z
	velocity = forward_dir * current_forward_speed
	velocity.y = -2.5 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()

	if spin_timer <= 0.0 or current_forward_speed < 4.0:
		# Recovers from spin if alive, otherwise explodes if critical
		if current_health < 35.0:
			destroy()
		else:
			is_spinning = false
			# Resume race
			current_forward_speed = 30.0

func retire() -> void:
	is_retired = true
	set_nitro_visuals(false)
	target_lane_offset = HighwayManager.LANE_RIGHT_SLOW

func destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	remove_from_group("enemies")
	remove_from_group("street_racer")
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0

	if explosion_scene:
		var expl: Node3D = explosion_scene.instantiate()
		get_parent().add_child(expl)
		expl.global_position = global_position

	EventBus.scrap_awarded.emit(scrap_reward)
	EventBus.sfx_requested.emit("explosion", global_position)
	EventBus.camera_shake_requested.emit(0.32, 0.28)
	EventBus.enemy_destroyed_with_source.emit("street_racer", last_damage_source, global_position)

	if ammo_pickup_scene and get_parent() and randf() <= 0.65:
		var pickup: Node3D = ammo_pickup_scene.instantiate() as Node3D
		if pickup:
			get_parent().add_child(pickup)
			pickup.global_position = global_position + Vector3(0, 0.75, 0)

	queue_free()
