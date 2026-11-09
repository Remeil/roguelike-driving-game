class_name EnemyPursuitCar
extends CharacterBody3D

@export_group("Durability & Economy")
## Maximum health hit points.
@export var max_health: float = 70.0

## Scrap currency rewarded to player upon destruction (bulk scrap shifted to mission objectives).
@export var scrap_reward: int = 8

@export_group("Performance & Combat")
## Base cruising speed in km/h.
@export var cruising_speed_kph: float = 138.0

## Catch-up sprint speed in km/h when pursuing player from behind.
@export var catchup_speed_kph: float = 165.0

## Machine gun firing range in meters.
@export var shoot_range: float = 58.0

## Minimum delay in seconds between burst shots.
@export var burst_delay: float = 2.6

## Projectile scene fired by hood cannons.
@export var bullet_scene: PackedScene = preload("res://src/enemies/enemy_bullet.tscn")

## Explosion visual effect on destruction.
@export var explosion_scene: PackedScene = preload("res://src/weapons/projectiles/explosion_fx.tscn")

## Tactical ammo pickup dropped on destruction.
@export var ammo_pickup_scene: PackedScene = preload("res://src/weapons/pickups/missile_pickup.tscn")

enum AIState {
	PURSUIT,
	ENGAGE_ATTACK,
	RAM_PASS,
	LEAD_BLOCK,
	SPINNING_OUT
}

var current_state: AIState = AIState.PURSUIT
var current_health: float = 70.0
var current_forward_speed: float = 0.0
var target_player: ArcadeVehicle = null
var target_lane_offset: float = 0.0
var current_lane_offset: float = 0.0
var burst_timer: float = 1.0
var shots_in_burst_remaining: int = 0
var shot_interval_timer: float = 0.0
var alternate_cannon: bool = false
var spin_timer: float = 0.0
var flash_timer: float = 0.0
var last_damage_source: String = "bullet"
var is_destroyed: bool = false
var brake_check_cooldown: float = 3.5
var is_brake_checking: bool = false
var brake_check_duration: float = 0.0

@onready var visual_mesh: Node3D = $Visuals
@onready var body_mesh: CSGBox3D = $Visuals/Chassis
@onready var ground_ray: RayCast3D = $GroundRay
@onready var gun_point_l: Marker3D = $GunPoint_L
@onready var gun_point_r: Marker3D = $GunPoint_R

var orig_material: StandardMaterial3D = null
var flash_material: StandardMaterial3D = null

const KPH_TO_MPS: float = 1.0 / 3.6
const GRAVITY: float = 30.0

func _ready() -> void:
	add_to_group("enemies")
	current_health = max_health
	current_forward_speed = cruising_speed_kph * KPH_TO_MPS
	floor_snap_length = 0.8
	floor_constant_speed = true
	floor_max_angle = deg_to_rad(65.0)

	# Find player car in scene tree
	find_player()

	if body_mesh and body_mesh.material is StandardMaterial3D:
		orig_material = body_mesh.material.duplicate()
		flash_material = orig_material.duplicate()
		flash_material.albedo_color = Color(1.0, 0.2, 0.15, 1.0)
		flash_material.emission_enabled = true
		flash_material.emission = Color(1.0, 0.3, 0.1, 1.0)
		flash_material.emission_energy_multiplier = 3.0
		body_mesh.material = orig_material

func find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is ArcadeVehicle:
		target_player = players[0] as ArcadeVehicle

func _physics_process(delta: float) -> void:
	# Fall safety: if knocked or fallen off road, despawn cleanly
	if global_position.y < -12.0:
		queue_free()
		return

	if not is_instance_valid(target_player):
		find_player()

	if current_state == AIState.SPINNING_OUT:
		process_spin_out(delta)
		return

	process_ai_decision(delta)
	process_movement(delta)
	process_weapons(delta)
	update_visuals(delta)

func process_ai_decision(delta: float) -> void:
	if not target_player:
		return

	var to_player: Vector3 = target_player.global_position - global_position
	var dist: float = to_player.length()
	var forward_dir: Vector3 = -global_transform.basis.z
	var dot_fwd: float = forward_dir.dot(to_player.normalized())

	# Determine if behind or ahead of player
	var player_fwd: Vector3 = -target_player.global_transform.basis.z
	var behind_player: bool = player_fwd.dot(global_position - target_player.global_position) < 0.0

	if behind_player:
		if dist > 45.0:
			current_state = AIState.PURSUIT
		elif dist > 14.0:
			current_state = AIState.ENGAGE_ATTACK
		else:
			# Close range aggressive push
			current_state = AIState.RAM_PASS
	else:
		# In front of player: lead roadblock or sideswipe if alongside
		if dist < 12.0:
			current_state = AIState.RAM_PASS
		else:
			current_state = AIState.LEAD_BLOCK

	# Determine target lane offset relative to road center
	if HighwayManager.instance:
		var p_info: Dictionary = HighwayManager.instance.get_road_transform(target_player.global_position, 0.0, 0.0)
		var road_right: Vector3 = p_info.get("right", target_player.global_transform.basis.x)
		var player_to_center: Vector3 = target_player.global_position - p_info.get("road_center", target_player.global_position)
		var player_lane: float = clamp(road_right.dot(player_to_center), -6.0, 6.0)

		match current_state:
			AIState.PURSUIT:
				target_lane_offset = player_lane
			AIState.ENGAGE_ATTACK:
				# Shift slightly to side for an open cannon firing line
				target_lane_offset = clamp(player_lane + (1.8 if player_lane < 0.0 else -1.8), -5.8, 5.8)
			AIState.RAM_PASS:
				# Cut directly into player's line for ramming impact
				target_lane_offset = player_lane
			AIState.LEAD_BLOCK:
				# Swerve directly in front of player to block passing lanes!
				target_lane_offset = player_lane

func process_movement(delta: float) -> void:
	var target_speed_kph: float = cruising_speed_kph

	if target_player:
		var dist: float = global_position.distance_to(target_player.global_position)
		var player_speed: float = target_player.current_forward_speed * 3.6

		match current_state:
			AIState.PURSUIT:
				# Catch-up: sprint toward player, strictly capped at enemy top speed
				target_speed_kph = clamp(player_speed + 14.0, cruising_speed_kph, catchup_speed_kph)
			AIState.ENGAGE_ATTACK:
				# Tail match: match player velocity while maintaining firing distance, capped at enemy top speed
				target_speed_kph = clamp(player_speed, cruising_speed_kph, catchup_speed_kph)
			AIState.RAM_PASS:
				# Burst of surge to sideswipe, capped at enemy top speed
				target_speed_kph = clamp(player_speed + 8.0, cruising_speed_kph, catchup_speed_kph)
			AIState.LEAD_BLOCK:
				# Roadblock player: stay in front, decelerate so player catches up to engage
				var block_spd: float = max(80.0, player_speed - 14.0)
				target_speed_kph = clamp(block_spd, 80.0, 128.0)

		# Brake-check hazard in LEAD_BLOCK when player tailgates closely
		if current_state == AIState.LEAD_BLOCK and dist < 22.0 and dist > 5.0:
			brake_check_cooldown -= delta
			if brake_check_cooldown <= 0.0:
				brake_check_cooldown = randf_range(5.0, 8.5)
				is_brake_checking = true
				brake_check_duration = 0.85

		if is_brake_checking:
			brake_check_duration -= delta
			target_speed_kph = max(55.0, target_speed_kph * 0.6)
			if brake_check_duration <= 0.0:
				is_brake_checking = false

	# Smoothly blend lane offset toward target
	current_lane_offset = move_toward(current_lane_offset, target_lane_offset, 4.5 * delta)

	# Highway spline lookahead target point
	var target_pt: Vector3 = target_player.global_position if target_player else (global_position - global_transform.basis.z * 18.0)
	if HighwayManager.instance:
		var road_info: Dictionary = HighwayManager.instance.get_road_transform(global_position, 18.0, current_lane_offset)
		target_pt = road_info.get("position", target_pt)

	# Steer toward target lane point (highway guard: forward component cannot be negative)
	var local_target: Vector3 = global_transform.affine_inverse() * target_pt
	var angle_to_target: float = atan2(-local_target.x, max(0.2, -local_target.z))
	
	# Speed-governed turning rate: tighter turning authority at high speeds for realistic physics
	var speed_ratio: float = clamp(current_forward_speed / (catchup_speed_kph * KPH_TO_MPS), 0.25, 1.0)
	var max_turn_rate: float = lerp(2.2, 1.45, speed_ratio)
	var steer_yaw: float = clamp(angle_to_target * 2.8, -max_turn_rate, max_turn_rate)

	rotate_y(steer_yaw * delta)
	global_transform.basis = global_transform.basis.orthonormalized()

	# Accelerate forward
	var target_speed_mps: float = target_speed_kph * KPH_TO_MPS
	current_forward_speed = move_toward(current_forward_speed, target_speed_mps, 26.0 * delta)

	# Lateral momentum & tire grip physics
	var forward_dir: Vector3 = -global_transform.basis.z
	var right_dir: Vector3 = global_transform.basis.x
	var forward_vel: Vector3 = forward_dir * current_forward_speed
	var current_lateral_vel: Vector3 = velocity.project(right_dir)
	var damped_lateral: Vector3 = current_lateral_vel * 0.08 # 92% normal grip with realistic tire slip

	var horizontal_vel: Vector3 = forward_vel + damped_lateral

	# Ground snapping
	var vertical_y: float = -2.5 if is_on_floor() else velocity.y - GRAVITY * delta
	velocity = Vector3(horizontal_vel.x, vertical_y, horizontal_vel.z)
	move_and_slide()

	# Collision impact with player and rails
	if get_slide_collision_count() > 0:
		for i in range(get_slide_collision_count()):
			var col: KinematicCollision3D = get_slide_collision(i)
			var col_normal: Vector3 = col.get_normal()
			if col_normal.y > 0.6:
				continue # Road floor contact
			var collider := col.get_collider()
			if collider is ArcadeVehicle:
				# Deal ramming damage to player
				collider.take_damage(6.0 * collider.ram_recoil_multiplier)
				var ram_dmg: float = 14.0 * collider.ram_multiplier
				take_damage(ram_dmg, "ram") # Ramming impact damage
				EventBus.camera_shake_requested.emit(0.24, 0.2)
				EventBus.sfx_requested.emit("bullet_impact", global_position)
				# Deflect slightly sideways
				velocity += col_normal * 12.0
			else:
				# Scrape along guardrail: glide along rail, prevent popping over
				velocity = velocity.slide(col_normal)
				velocity.y = min(velocity.y, -1.0)

func process_weapons(delta: float) -> void:
	if not target_player:
		return

	var dist: float = global_position.distance_to(target_player.global_position)
	var forward_dir: Vector3 = -global_transform.basis.z
	var to_player: Vector3 = (target_player.global_position - global_position).normalized()
	var angle_deg: float = rad_to_deg(forward_dir.angle_to(to_player))

	# Can only shoot if player is in front of the enemy within firing arc
	var can_aim: bool = angle_deg < 24.0 and dist < shoot_range and dist > 8.0

	burst_timer -= delta
	if burst_timer <= 0.0 and can_aim:
		burst_timer = burst_delay
		shots_in_burst_remaining = 3
		shot_interval_timer = 0.0

	if shots_in_burst_remaining > 0:
		shot_interval_timer -= delta
		if shot_interval_timer <= 0.0:
			shot_interval_timer = 0.18
			shots_in_burst_remaining -= 1
			fire_cannons()

func fire_cannons() -> void:
	if not bullet_scene:
		return

	var spawn_marker: Marker3D = gun_point_r if alternate_cannon else gun_point_l
	alternate_cannon = not alternate_cannon

	var spawn_pos: Vector3 = spawn_marker.global_position if spawn_marker else global_position
	var shoot_dir: Vector3 = -global_transform.basis.z

	# Add slight spread
	shoot_dir.x += randf_range(-0.03, 0.03)

	var bullet: Node3D = bullet_scene.instantiate()
	get_parent().add_child(bullet)
	if bullet.has_method("initialize"):
		bullet.initialize(spawn_pos, shoot_dir)

	EventBus.sfx_requested.emit("machine_gun_shot", global_position)

func process_spin_out(delta: float) -> void:
	spin_timer -= delta
	rotate_y(15.0 * delta) # Rapid uncontrollable spin
	current_forward_speed = move_toward(current_forward_speed, 0.0, 32.0 * delta)

	var forward_dir: Vector3 = -global_transform.basis.z
	velocity = forward_dir * current_forward_speed
	velocity.y = -2.5 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()

	if spin_timer <= 0.0 or current_forward_speed < 4.0:
		# After dramatic spin-out, explode!
		destroy()

func spin_out(_slip: float) -> void:
	if current_state == AIState.SPINNING_OUT:
		return
	current_state = AIState.SPINNING_OUT
	spin_timer = 2.2
	EventBus.sfx_requested.emit("turbo_surge", global_position)
	EventBus.camera_shake_requested.emit(0.18, 0.15)
	EventBus.enemy_spun_out.emit(self)

func take_damage(amount: float, source: String = "") -> void:
	if is_destroyed:
		return
	if source != "":
		last_damage_source = source
	current_health -= amount

	# Mesh hit flash
	if body_mesh and flash_material:
		body_mesh.material = flash_material
		flash_timer = 0.09

	if current_health <= 0.0 and not is_destroyed:
		destroy()

func update_visuals(delta: float) -> void:
	if flash_timer > 0.0:
		flash_timer -= delta
		if flash_timer <= 0.0 and body_mesh and orig_material:
			body_mesh.material = orig_material

func destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	remove_from_group("enemies")
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0

	if explosion_scene:
		var expl: Node3D = explosion_scene.instantiate()
		get_parent().add_child(expl)
		expl.global_position = global_position

	EventBus.scrap_awarded.emit(scrap_reward)
	EventBus.sfx_requested.emit("explosion", global_position)
	EventBus.camera_shake_requested.emit(0.28, 0.25)
	EventBus.enemy_destroyed_with_source.emit("pursuit_car", last_damage_source, global_position)

	_maybe_drop_ammo()

	queue_free()

func _maybe_drop_ammo() -> void:
	if not ammo_pickup_scene or not get_parent():
		return

	# Dynamic drop balance: higher drop probability when player is critically low on missiles
	var drop_chance: float = 0.40
	if is_instance_valid(target_player):
		var wsys: WeaponSystem = target_player.get_node_or_null("WeaponSystem") as WeaponSystem
		if not wsys:
			wsys = target_player.find_child("WeaponSystem", true, false) as WeaponSystem
		if wsys:
			if wsys.current_missiles == 0:
				drop_chance = 0.90 # Lifeline when completely dry
			elif wsys.current_missiles <= 2:
				drop_chance = 0.70 # High chance when low

	if randf() <= drop_chance:
		var pickup: Node3D = ammo_pickup_scene.instantiate() as Node3D
		if pickup:
			get_parent().add_child(pickup)
			pickup.global_position = global_position + Vector3(0, 0.75, 0)
