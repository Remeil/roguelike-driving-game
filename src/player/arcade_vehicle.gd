class_name ArcadeVehicle
extends CharacterBody3D

@export_group("Speed & Power")
## Maximum cruising speed in km/h under normal engine throttle.
@export var top_speed_kph: float = 150.0

## Maximum speed ceiling in km/h when engaging Nitro Boost.
@export var boost_top_speed_kph: float = 250.0

## Maximum reverse speed in km/h when reversing.
@export var reverse_speed_kph: float = 60.0

## Base engine forward acceleration (m/s²). Multiplied by the current gear's torque multiplier.
@export var acceleration: float = 32.0

## Braking deceleration power (m/s²) applied when holding reverse/brake while moving forward.
@export var brake_power: float = 75.0

## Natural rolling friction deceleration (m/s²) when coasting with no throttle input.
@export var coasting_drag: float = 14.0

## Property alias for upgrade manager compatibility
var coast_drag: float:
	get:
		return coasting_drag
	set(v):
		coasting_drag = v

## Overdrive acceleration thrust (m/s²) applied while burning Nitro Boost.
@export var boost_acceleration: float = 85.0

## Deceleration rate (m/s²) when above top speed after Nitro ends while holding throttle.
## Lower values (e.g. 2.5 - 5.0) produce a long, smooth speed glide.
## Higher values (e.g. 10.0+) drop the overspeed quickly.
@export var boost_bleed_rate: float = 4.0

@export_group("Gearing System")
## Percentage-based gear curve: [Min Speed % of Top Speed, Acceleration Multiplier %]
## Automatically scales with Top Speed and Acceleration upgrades.
## Accepts Vector2(speed_pct, accel_mult) or [speed_pct, accel_mult]
## e.g. Vector2(0.0, 1.50) = Gear 1 (0% top speed, 150% base acceleration launch torque)
@export var gears: Array = [
	Vector2(0.00, 1.50), # Gear 1: 0% - 24% top speed (150% accel launch torque)
	Vector2(0.24, 1.15), # Gear 2: 24% - 48% top speed (115% accel mid pull)
	Vector2(0.48, 0.85), # Gear 3: 48% - 70% top speed (85% accel)
	Vector2(0.70, 0.60), # Gear 4: 70% - 88% top speed (60% accel)
	Vector2(0.88, 0.35)  # Gear 5: 88%+ top speed (35% cruising pull toward top speed)
]

@export_group("Speed-Based Steering Curve")
## Speed-based turn rate multiplier: [Speed % of Top Speed, Turn Rate Multiplier]
## Automatically lerps between steps for smooth high-speed stability and low-speed agility.
## Accepts Vector2(speed_pct, turn_mult) or [speed_pct, turn_mult]
@export var speed_turn_rate_modifiers: Array = [
	Vector2(0.00, 1.15), # 0% top speed: nimble low-speed maneuvering
	Vector2(0.30, 1.00), # 30% top speed: standard turn rate
	Vector2(0.65, 0.82), # 65% top speed: tightened high-speed curve stability
	Vector2(1.00, 0.65)  # 100%+ top speed: straight-line highway stability
]

@export_group("Arcade Steering & Drifting (Option A)")
## Master yaw turn rate (radians/sec). Lower = heavier/more planted feel; higher = sharper/twitchier steering.
@export var max_turn_rate: float = 1.55

## Speed at which front wheels steer toward lock (radians/sec). Lower = heavier steering feel.
@export var steer_speed: float = 2.0

## Speed at which front wheels return to center when steering input is released (radians/sec).
@export var steer_return_speed: float = 5.0

## Lateral tire grip during normal road driving (0.90 - 0.98). Eliminates unwanted sideways slipping.
@export var normal_lateral_grip: float = 0.95

## Lateral tire grip while handbrake drifting (0.15 - 0.35). Lower = looser/tail-out slide; higher = tighter track slide.
@export var drift_lateral_grip: float = 0.22

## Speed scrubbed per second (m/s²) during drift. Set to 0.0 for pure speed preservation through corners.
@export var drift_speed_bleed: float = 0.0

## Maximum speed ceiling ratio while drifting. Accepts decimals (0.60 - 0.90) or whole percentages (60.0 - 90.0). E.g. 0.80 or 80.0 = 80% of top speed.
@export var drift_max_speed_ratio: float = 1.0

## Transition time in seconds to smoothly blend from drift slide grip back to normal tire grip upon releasing drift.
@export var time_until_normal_grip: float = 0.45

## Extra yaw turn rate multiplier unlocked while drifting, allowing the nose to pitch aggressively into corners.
@export var drift_turn_multiplier: float = 1.45

## Turn rate multiplier while Nitro boosting. Lower values stiffen steering for high-speed highway stability.
@export var boost_turn_multiplier: float = 0.75

## Visual chassis body roll tilt angle strength during steering.
@export var body_roll_strength: float = 0.08

## Visual chassis pitch squat/dive angle strength during acceleration and braking.
@export var body_pitch_strength: float = 0.05

@export_group("Boost (Nitro)")
## Total capacity of the Nitro boost tank.
@export var max_boost: float = 100.0

## Minimum Nitro tank fuel required to initiate a boost burn (prevents micro-stuttering when tank is nearly empty).
@export var min_boost_to_activate: float = 25.0

## Rate at which Nitro fuel is consumed per second while holding boost.
@export var boost_drain_rate: float = 35.0

## Passive recharge rate of Nitro fuel per second while driving normally.
@export var boost_regen_rate: float = 15.0

@export_group("Durability & Economy")
## Maximum vehicle armor hit points before critical destruction.
@export var max_health: float = 100.0

@export_group("Shield System")
## Maximum energy shield capacity. Defaults to 0 until unlocked via Aegis Deflector perk.
@export var max_shield: float = 0.0
## Energy shield recharge rate in HP per second.
@export var shield_regen_rate: float = 12.0
## Delay in seconds after taking damage before shields start recharging.
@export var shield_regen_delay: float = 3.5

## Initial scrap currency available to the player at the start of a run.
@export var starting_scrap: int = 50

# Node References
@onready var visual_mesh: Node3D = $Visuals
@onready var wheel_fl: Node3D = $Visuals/Wheels/Wheel_FL
@onready var wheel_fr: Node3D = $Visuals/Wheels/Wheel_FR
@onready var wheel_rl: Node3D = $Visuals/Wheels/Wheel_RL
@onready var wheel_rr: Node3D = $Visuals/Wheels/Wheel_RR
@onready var wheel_fl_hub: Node3D = $Visuals/Wheels/Wheel_FL/RollHub
@onready var wheel_fr_hub: Node3D = $Visuals/Wheels/Wheel_FR/RollHub
@onready var wheel_rl_hub: Node3D = $Visuals/Wheels/Wheel_RL/RollHub
@onready var wheel_rr_hub: Node3D = $Visuals/Wheels/Wheel_RR/RollHub
@onready var ground_ray: RayCast3D = $GroundRay
@onready var front_fire_point_l: Marker3D = $WeaponPoints/Front_L
@onready var front_fire_point_r: Marker3D = $WeaponPoints/Front_R
@onready var rear_deploy_point: Marker3D = $WeaponPoints/Rear

# Runtime state
var current_health: float = 100.0
var current_shield: float = 0.0
var shield_regen_timer: float = 0.0
var shield_mesh: MeshInstance3D = null
var shield_mat: StandardMaterial3D = null
var current_boost: float = 100.0
var current_scrap: int = 50
var is_drifting: bool = false
var is_boosting: bool = false
var steer_angle: float = 0.0
var current_forward_speed: float = 0.0
var drift_duration: float = 0.0
var drift_recovery_timer: float = 0.0
var drift_direction: float = 0.0
var wheel_spin_angle: float = 0.0
var current_gear_idx: int = 1
var current_gear_label: String = "1"
var prev_gear_idx: int = 1

# Weapons Van Docking & Roguelike Modifiers
var is_docking: bool = false
var is_docked: bool = false
var docked_van_anchor: Node3D = null
var launch_grace_timer: float = 0.0
var ram_multiplier: float = 1.0
var ram_recoil_multiplier: float = 1.0
var scrap_multiplier: float = 1.0

# Constants
const KPH_TO_MPS: float = 1.0 / 3.6
const GRAVITY: float = 30.0

func _ready() -> void:
	add_to_group("player")
	EventBus.scrap_awarded.connect(add_scrap)
	current_health = max_health
	current_shield = max_shield
	current_boost = max_boost
	current_scrap = starting_scrap
	floor_snap_length = 0.6
	floor_constant_speed = true
	floor_max_angle = deg_to_rad(65.0)
	_setup_shield_mesh()
	EventBus.scrap_collected.emit(0, current_scrap)
	EventBus.player_shield_changed.emit(current_shield, max_shield)

func _physics_process(delta: float) -> void:
	# Absolute void safety net: NEVER get stuck below road, whether docked or free
	if global_position.y < -7.0:
		_recover_from_void()
		return

	if is_docking:
		velocity = Vector3.ZERO
		return

	if is_docked:
		if is_instance_valid(docked_van_anchor):
			global_transform = docked_van_anchor.global_transform
			return
		else:
			# Van was destroyed or missing; release car and recover safely
			_recover_from_void()
			return

	if launch_grace_timer > 0.0:
		launch_grace_timer -= delta

	# Energy Shield recharge logic
	if max_shield > 0.0 and current_shield < max_shield:
		shield_regen_timer += delta
		if shield_regen_timer >= shield_regen_delay:
			var old_shield: float = current_shield
			current_shield = min(max_shield, current_shield + shield_regen_rate * delta)
			if current_shield >= max_shield and old_shield < max_shield:
				EventBus.sfx_requested.emit("shield_recharged", global_position)
			EventBus.player_shield_changed.emit(current_shield, max_shield)

	handle_inputs(delta)
	apply_movement(delta)
	update_visuals(delta)
	emit_telemetry()

func handle_inputs(delta: float) -> void:
	var throttle_input: float = Input.get_action_strength("throttle") - Input.get_action_strength("brake_reverse")
	var raw_steer: float = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	var handbrake_pressed: bool = Input.is_action_pressed("handbrake")
	var handbrake_just_pressed: bool = Input.is_action_just_pressed("handbrake")
	var boost_pressed: bool = Input.is_action_pressed("boost")
	var boost_just_pressed: bool = Input.is_action_just_pressed("boost")

	var current_kph: float = current_forward_speed * 3.6

	# Boost Logic (requires min_boost_to_activate to initiate burn, preventing stutter-boosting on empty)
	var was_boosting: bool = is_boosting
	if is_boosting:
		is_boosting = boost_pressed and current_boost > 0.0 and throttle_input > 0.05
	else:
		is_boosting = boost_pressed and current_boost >= min_boost_to_activate and throttle_input > 0.05

	if is_boosting:
		current_boost = max(0.0, current_boost - boost_drain_rate * delta)
		if not was_boosting or boost_just_pressed:
			EventBus.camera_shake_requested.emit(0.12, 0.1)
			EventBus.sfx_requested.emit("turbo_surge", global_position)
	else:
		current_boost = min(max_boost, current_boost + boost_regen_rate * delta)

	# Drift Engagement: activates immediately whenever handbrake is held at speed
	var was_drifting: bool = is_drifting
	if handbrake_pressed and current_kph > 20.0:
		is_drifting = true
		if abs(raw_steer) > 0.05:
			drift_direction = sign(raw_steer)
	elif not handbrake_pressed or current_kph < 15.0:
		is_drifting = false

	if is_drifting:
		drift_duration += delta
		drift_recovery_timer = time_until_normal_grip
		if not was_drifting:
			EventBus.player_drift_started.emit()
			EventBus.camera_shake_requested.emit(0.12, 0.1)
	else:
		if was_drifting:
			EventBus.player_drift_ended.emit()
			drift_duration = 0.0
			drift_recovery_timer = time_until_normal_grip
		elif drift_recovery_timer > 0.0:
			drift_recovery_timer = max(0.0, drift_recovery_timer - delta)

	# Gearing logic
	var gear_accel: float = acceleration
	if current_forward_speed < -0.8:
		current_gear_idx = -1
		current_gear_label = "R"
		gear_accel = acceleration * 0.75
	elif abs(current_forward_speed) < 0.2 and abs(throttle_input) < 0.05:
		current_gear_idx = 0
		current_gear_label = "N"
		gear_accel = 0.0
	else:
		var gear_info: Dictionary = get_current_gear(current_kph)
		current_gear_idx = int(gear_info["index"])
		current_gear_label = str(gear_info["label"])
		gear_accel = float(gear_info["acceleration"])

	if current_gear_idx != prev_gear_idx:
		if current_gear_idx > prev_gear_idx and prev_gear_idx > 0 and throttle_input > 0.4:
			EventBus.sfx_requested.emit("gear_shift", global_position)
		prev_gear_idx = current_gear_idx
		EventBus.player_gear_changed.emit(current_gear_idx, current_gear_label)

	# Target forward speed
	var max_fwd: float = (boost_top_speed_kph if is_boosting else top_speed_kph) * KPH_TO_MPS
	var max_rev: float = reverse_speed_kph * KPH_TO_MPS
	var accel_rate: float = boost_acceleration if is_boosting else gear_accel

	if throttle_input > 0.0:
		if is_drifting and not is_boosting and drift_speed_bleed > 0.0:
			# Normalize percentage (e.g. 90.0 -> 0.90, or 0.90 -> 0.90)
			var ratio_norm: float = drift_max_speed_ratio
			if ratio_norm > 1.0:
				ratio_norm /= 100.0
			ratio_norm = clamp(ratio_norm, 0.1, 1.0)
			var drift_cap: float = max_fwd * ratio_norm

			if current_forward_speed > drift_cap:
				# Above drift ceiling: bleed/scrub excess speed down to cap
				current_forward_speed = move_toward(current_forward_speed, drift_cap * throttle_input, drift_speed_bleed * delta)
			else:
				# Below drift ceiling: accelerate with engine power up to cap
				current_forward_speed = move_toward(current_forward_speed, drift_cap * throttle_input, accel_rate * delta)
		else:
			# Normal driving or pure speed preservation
			if not is_boosting and current_forward_speed > max_fwd:
				# Post-boost overspeed bleed: smoothly glide speed back down to top speed
				current_forward_speed = move_toward(current_forward_speed, max_fwd * throttle_input, boost_bleed_rate * delta)
			else:
				# Below top speed: accelerate up to top speed using current gear torque
				current_forward_speed = move_toward(current_forward_speed, max_fwd * throttle_input, accel_rate * delta)
	elif throttle_input < 0.0:
		if current_forward_speed > 0.5:
			current_forward_speed = move_toward(current_forward_speed, 0.0, brake_power * delta)
		else:
			current_forward_speed = move_toward(current_forward_speed, -max_rev * abs(throttle_input), acceleration * 0.7 * delta)
	else:
		var effective_drag: float = max(coasting_drag, drift_speed_bleed) if (is_drifting and drift_speed_bleed > 0.0) else coasting_drag
		current_forward_speed = move_toward(current_forward_speed, 0.0, effective_drag * delta)

	# Arcade Steering Angle
	var target_steer: float = raw_steer
	var steer_rate: float = steer_speed * (drift_turn_multiplier if is_drifting else 1.0)

	if abs(target_steer) > 0.01:
		steer_angle = move_toward(steer_angle, target_steer, steer_rate * delta)
	else:
		steer_angle = move_toward(steer_angle, 0.0, steer_return_speed * delta)

func apply_movement(delta: float) -> void:
	var speed_ratio: float = clamp(current_forward_speed / (top_speed_kph * KPH_TO_MPS), -0.6, 1.0)
	
	# Turn modifier: speed curve + drifts + boost
	var speed_turn_mult: float = get_speed_turn_multiplier(abs(current_forward_speed) * 3.6)
	var turn_mult: float = speed_turn_mult
	if is_drifting:
		turn_mult *= drift_turn_multiplier
	elif drift_recovery_timer > 0.0 and time_until_normal_grip > 0.001:
		var recovery_ratio: float = 1.0 - (drift_recovery_timer / time_until_normal_grip)
		turn_mult *= lerp(drift_turn_multiplier, 1.0, recovery_ratio)
	elif is_boosting:
		turn_mult *= boost_turn_multiplier

	# When drifting, allow full yaw responsiveness so the nose pivots into the slide:
	var yaw_speed_factor: float = 1.0 if is_drifting else clamp(abs(speed_ratio), 0.35, 1.0)
	var yaw_amount: float = steer_angle * (max_turn_rate * turn_mult) * yaw_speed_factor * delta
	rotate_y(yaw_amount)
	global_transform.basis = global_transform.basis.orthonormalized()

	# Ground slope alignment (pitch and roll on ramps/banking)
	if ground_ray and ground_ray.is_colliding():
		var normal: Vector3 = ground_ray.get_collision_normal()
		# Only blend if road is tilted (e.g. ramp or slope) to avoid micro-jitters on flat highway
		if normal.y < 0.995 and normal.y > 0.4:
			var current_fwd: Vector3 = -global_transform.basis.z
			var right_vec: Vector3 = current_fwd.cross(normal).normalized()
			var back_vec: Vector3 = right_vec.cross(normal).normalized()
			var target_basis: Basis = Basis(right_vec, normal, back_vec).orthonormalized()
			global_transform.basis = global_transform.basis.slerp(target_basis, 8.0 * delta).orthonormalized()

	var forward_dir: Vector3 = -global_transform.basis.z
	var right_dir: Vector3 = global_transform.basis.x

	var forward_vel: Vector3 = forward_dir * current_forward_speed
	var current_lateral_vel: Vector3 = velocity.project(right_dir)
	var grip: float = normal_lateral_grip
	if is_drifting:
		grip = drift_lateral_grip
	elif drift_recovery_timer > 0.0 and time_until_normal_grip > 0.001:
		var recovery_ratio: float = 1.0 - (drift_recovery_timer / time_until_normal_grip)
		grip = lerp(drift_lateral_grip, normal_lateral_grip, recovery_ratio)

	var damped_lateral: Vector3 = current_lateral_vel * (1.0 - grip)
	var horizontal_vel: Vector3 = forward_vel + damped_lateral

	var vertical_y: float = velocity.y
	if is_on_floor():
		vertical_y = -2.5 # Reliable downward floor snap
	else:
		vertical_y -= GRAVITY * delta

	velocity = Vector3(horizontal_vel.x, vertical_y, horizontal_vel.z)
	move_and_slide()

	# Rail and Obstacle collisions (ignore road floor)
	if get_slide_collision_count() > 0:
		for i in range(get_slide_collision_count()):
			var col: KinematicCollision3D = get_slide_collision(i)
			var col_normal: Vector3 = col.get_normal()
			# Ignore road / floor contact (steep upward normal)
			if col_normal.y > 0.6:
				continue

			var collider := col.get_collider()
			if collider is EnemyPursuitCar:
				var player_spd: float = current_forward_speed * 3.6
				if player_spd > 60.0:
					collider.take_damage(28.0 * ram_multiplier, "ram")
					take_damage(4.0 * ram_recoil_multiplier)
					EventBus.camera_shake_requested.emit(0.25, 0.2)
					EventBus.sfx_requested.emit("bullet_impact", global_position)

			var impact_intensity: float = abs(col_normal.dot(forward_dir))
			if launch_grace_timer <= 0.0 and impact_intensity > 0.5 and current_forward_speed > 16.0:
				current_forward_speed *= 0.6
				EventBus.camera_shake_requested.emit(0.25, 0.2)
			elif impact_intensity <= 0.5 and current_forward_speed > 12.0:
				# Light scrape along rail
				EventBus.camera_shake_requested.emit(0.06, 0.08)

func update_visuals(delta: float) -> void:
	if not visual_mesh:
		return

	var slide_ratio: float = 1.0 if is_drifting else ((drift_recovery_timer / time_until_normal_grip) if (drift_recovery_timer > 0.0 and time_until_normal_grip > 0.001) else 0.0)
	var roll_mult: float = lerp(1.0, 1.7, slide_ratio)
	var target_roll: float = -steer_angle * body_roll_strength * roll_mult
	var target_pitch: float = (current_forward_speed / 50.0) * body_pitch_strength

	visual_mesh.rotation.z = lerp_angle(visual_mesh.rotation.z, target_roll, 12.0 * delta)
	visual_mesh.rotation.x = lerp_angle(visual_mesh.rotation.x, target_pitch, 12.0 * delta)

	var target_drift_yaw: float = (steer_angle * 0.35) * slide_ratio
	visual_mesh.rotation.y = lerp_angle(visual_mesh.rotation.y, target_drift_yaw, 10.0 * delta)

	# Front wheel steering angle (isolated to Y rotation, strictly clamped)
	var steer_visual: float = clamp(steer_angle * 0.52, -0.58, 0.58)
	if wheel_fl:
		wheel_fl.rotation.y = steer_visual
	if wheel_fr:
		wheel_fr.rotation.y = steer_visual

	# Wheel roll spin (isolated to RollHub X rotation)
	var spin: float = (current_forward_speed / 0.35) * delta
	wheel_spin_angle = wrapf(wheel_spin_angle + spin, -PI, PI)
	for hub in [wheel_fl_hub, wheel_fr_hub, wheel_rl_hub, wheel_rr_hub]:
		if hub:
			hub.rotation.x = wheel_spin_angle

func add_scrap(amount: int) -> void:
	var total_earned := int(round(amount * scrap_multiplier))
	current_scrap += total_earned
	EventBus.scrap_collected.emit(total_earned, current_scrap)
	EventBus.sfx_requested.emit("scrap_pickup", global_position)

func spend_scrap(amount: int) -> bool:
	if current_scrap < amount:
		return false
	current_scrap -= amount
	EventBus.scrap_collected.emit(-amount, current_scrap)
	return true

func start_docking(anchor: Node3D) -> void:
	is_docking = true
	is_docked = false
	docked_van_anchor = anchor
	velocity = Vector3.ZERO
	current_forward_speed = 0.0
	is_boosting = false
	is_drifting = false

func dock_in_van(anchor: Node3D) -> void:
	is_docking = false
	is_docked = true
	docked_van_anchor = anchor
	velocity = Vector3.ZERO
	current_forward_speed = 0.0
	is_boosting = false
	is_drifting = false
	repair_health(max_health)
	if max_shield > 0.0:
		current_shield = max_shield
		EventBus.player_shield_changed.emit(current_shield, max_shield)
	var wsys: WeaponSystem = get_node_or_null("WeaponSystem") as WeaponSystem
	if not wsys:
		wsys = find_child("WeaponSystem", true, false) as WeaponSystem
	if wsys:
		wsys.add_missiles(wsys.max_missiles)
		wsys.current_heat = 0.0
		wsys.is_overheated = false

func launch_from_van(launch_vel: Vector3) -> void:
	is_docking = false
	is_docked = false
	docked_van_anchor = null
	velocity = launch_vel
	current_forward_speed = launch_vel.length()
	current_boost = max_boost
	launch_grace_timer = 1.5
	EventBus.sfx_requested.emit("turbo_surge", global_position)
	EventBus.camera_shake_requested.emit(0.28, 0.3)

func take_damage(amount: float, _source: String = "") -> void:
	if is_docked:
		return # Armored Weapons Van shields the car completely while docked

	shield_regen_timer = 0.0

	# Energy shield absorbs damage first
	if current_shield > 0.0:
		if current_shield >= amount:
			current_shield -= amount
			amount = 0.0
			EventBus.sfx_requested.emit("shield_hit", global_position)
			EventBus.camera_shake_requested.emit(0.12, 0.12)
			_pulse_shield_fx()
			EventBus.player_shield_changed.emit(current_shield, max_shield)
			return
		else:
			amount -= current_shield
			current_shield = 0.0
			EventBus.sfx_requested.emit("shield_break", global_position)
			EventBus.camera_shake_requested.emit(0.24, 0.22)
			_pulse_shield_fx()
			EventBus.player_shield_changed.emit(current_shield, max_shield)

	current_health = max(0.0, current_health - amount)
	EventBus.player_health_changed.emit(current_health, max_health)
	EventBus.camera_shake_requested.emit(0.20, 0.18)
	EventBus.sfx_requested.emit("bullet_impact", global_position)

func _setup_shield_mesh() -> void:
	shield_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.35
	sphere.height = 2.7
	shield_mesh.mesh = sphere
	shield_mesh.scale = Vector3(1.18, 0.75, 1.85)
	shield_mesh.position = Vector3(0.0, 0.55, 0.0)

	shield_mat = StandardMaterial3D.new()
	shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shield_mat.albedo_color = Color(0.15, 0.85, 1.0, 0.0)
	shield_mat.emission_enabled = true
	shield_mat.emission = Color(0.2, 0.9, 1.0, 1.0)
	shield_mat.emission_energy_multiplier = 0.0
	shield_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shield_mesh.material_override = shield_mat
	shield_mesh.visible = false

	if visual_mesh:
		visual_mesh.add_child(shield_mesh)
	else:
		add_child(shield_mesh)

func _pulse_shield_fx() -> void:
	if not shield_mesh or not shield_mat:
		return
	shield_mesh.visible = true
	shield_mat.albedo_color.a = 0.38
	shield_mat.emission_energy_multiplier = 4.0
	var tween := create_tween()
	tween.tween_property(shield_mat, "albedo_color:a", 0.0, 0.22)
	tween.parallel().tween_property(shield_mat, "emission_energy_multiplier", 0.0, 0.22)
	tween.tween_callback(func() -> void:
		if is_instance_valid(shield_mesh):
			shield_mesh.visible = false
	)

func repair_health(amount: float) -> void:
	current_health = min(max_health, current_health + amount)
	EventBus.player_health_changed.emit(current_health, max_health)

func recharge_shield(amount: float) -> void:
	current_shield = min(max_shield, current_shield + amount)
	EventBus.player_shield_changed.emit(current_shield, max_shield)

## Safely recovers the player vehicle onto the highway surface if knocked off the road into the void
func _recover_from_void() -> void:
	is_docking = false
	is_docked = false
	docked_van_anchor = null

	if not HighwayManager.instance:
		global_position.y = 0.5
		velocity = Vector3.ZERO
		return

	# Retrieve closest road segment transform along the highway curve
	var road_info: Dictionary = HighwayManager.instance.get_road_transform(global_position, 0.0, 0.0)
	var safe_pos: Vector3 = road_info.get("road_center", global_position)
	var safe_fwd: Vector3 = road_info.get("forward", -global_transform.basis.z)
	var safe_right: Vector3 = road_info.get("right", global_transform.basis.x)
	var safe_basis := Basis(safe_right, Vector3.UP, -safe_fwd).orthonormalized()

	# Snap safely to road center
	global_position = Vector3(safe_pos.x, safe_pos.y + 0.35, safe_pos.z)
	global_transform.basis = safe_basis

	var recover_speed_mps: float = max(80.0 * (1.0 / 3.6), current_forward_speed)
	current_forward_speed = recover_speed_mps
	velocity = safe_fwd * recover_speed_mps

	# Deduct slight damage penalty and notify
	take_damage(15.0)
	EventBus.sfx_requested.emit("bullet_impact", global_position)
	EventBus.camera_shake_requested.emit(0.35, 0.3)
	EventBus.player_recovered_from_void.emit()

## Generic piecewise linear curve sampler for percentage-based curves
## Linearly interpolates values between adjacent breakpoints
func sample_stepped_curve(target_ratio: float, points: Array, default_val: float = 1.0) -> Dictionary:
	if points.is_empty():
		return {"value": default_val, "index": 0, "progress": 0.0}

	# Parse points into list of Vector2(ratio, value)
	var parsed: Array[Vector2] = []
	for item in points:
		var r: float = 0.0
		var v: float = default_val
		if item is Vector2:
			r = item.x
			v = item.y
		elif item is Array and item.size() >= 2:
			r = float(item[0])
			v = float(item[1])
		elif item is Dictionary:
			r = float(item.get("speed_pct", item.get("min_speed_pct", item.get("x", 0.0))))
			v = float(item.get("value", item.get("accel_mult", item.get("y", default_val))))

		# Normalize whole percentages (e.g. 20.0 -> 0.20)
		if r > 1.0:
			r /= 100.0

		parsed.append(Vector2(r, v))

	# Sort points by speed ratio
	parsed.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

	# Clamped boundaries
	if target_ratio <= parsed[0].x:
		return {"value": parsed[0].y, "index": 0, "progress": 0.0}

	var last_idx: int = parsed.size() - 1
	if target_ratio >= parsed[last_idx].x:
		return {"value": parsed[last_idx].y, "index": last_idx, "progress": 1.0}

	# Find enclosing interval and linearly interpolate
	for i in range(last_idx):
		var p_curr: Vector2 = parsed[i]
		var p_next: Vector2 = parsed[i + 1]
		if target_ratio >= p_curr.x and target_ratio <= p_next.x:
			var span: float = p_next.x - p_curr.x
			var t: float = clamp((target_ratio - p_curr.x) / span, 0.0, 1.0) if span > 0.0001 else 0.0
			var interp_val: float = lerp(p_curr.y, p_next.y, t)
			return {"value": interp_val, "index": i, "progress": t}

	return {"value": parsed[last_idx].y, "index": last_idx, "progress": 1.0}

func get_current_gear(speed_kph: float) -> Dictionary:
	var speed_ratio: float = clamp(speed_kph / max(1.0, top_speed_kph), 0.0, 2.0)
	var sample: Dictionary = sample_stepped_curve(speed_ratio, gears, 1.0)
	var accel_mult: float = sample["value"]

	# Flexible parser check if user entered 150 for 150%
	if accel_mult > 10.0:
		accel_mult /= 100.0

	var gear_num: int = int(sample["index"]) + 1
	return {
		"index": gear_num,
		"label": str(gear_num),
		"acceleration": accel_mult * acceleration
	}

func get_speed_turn_multiplier(speed_kph: float) -> float:
	var speed_ratio: float = clamp(speed_kph / max(1.0, top_speed_kph), 0.0, 2.0)
	var sample: Dictionary = sample_stepped_curve(speed_ratio, speed_turn_rate_modifiers, 1.0)
	var mult: float = sample["value"]
	if mult > 10.0:
		mult /= 100.0
	return mult

func emit_telemetry() -> void:
	var kph: float = current_forward_speed * 3.6
	EventBus.player_speed_changed.emit(kph, boost_top_speed_kph)
	EventBus.player_gear_changed.emit(current_gear_idx, current_gear_label)
	EventBus.player_boost_changed.emit(current_boost, max_boost)
	EventBus.player_health_changed.emit(current_health, max_health)
	EventBus.distance_travelled_changed.emit(-global_position.z)
