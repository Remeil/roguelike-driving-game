class_name WeaponSystem
extends Node3D

@export_group("Munition Prefabs")
## Bullet projectile scene instantiated by the machine guns.
@export var bullet_scene: PackedScene = preload("res://src/weapons/projectiles/machine_gun_bullet.tscn")

## Homing micro-missile projectile scene.
@export var missile_scene: PackedScene = preload("res://src/weapons/projectiles/micro_missile.tscn")

## Rear-deployed oil slick hazard scene.
@export var oil_slick_scene: PackedScene = preload("res://src/weapons/countermeasures/oil_slick.tscn")

@export_group("Machine Guns")
## Delay between machine gun rounds in seconds (e.g. 0.085 ≈ 12 rounds/sec).
@export var primary_fire_rate: float = 0.085

## Maximum heat capacity before the machine guns trigger an overheat lockout.
@export var max_heat: float = 100.0

## Heat buildup units generated per bullet fired.
@export var heat_per_shot: float = 4.8

## Passive heat cooling dissipation rate per second while not firing.
@export var cooling_rate: float = 28.0

## Target heat level that guns must cool down to before firing is unlocked after overheating.
@export var overheat_lockout_threshold: float = 25.0

@export_group("Micro-Missiles")
## Maximum missile ammo capacity carried on board.
@export var max_missiles: int = 8

## Minimum delay between missile launches in seconds.
@export var missile_cooldown: float = 1.0

## Flat damage bonus added to instantiated micro-missiles (from Roguelike upgrades).
var missile_damage_bonus: float = 0.0

@export_group("Countermeasures")
## Cooldown time in seconds between oil slick deployments.
@export var oil_cooldown: float = 5.0

# Runtime state
var current_heat: float = 0.0
var is_overheated: bool = false
var primary_cooldown_timer: float = 0.0
var missile_cooldown_timer: float = 0.0
var oil_cooldown_timer: float = 0.0
var current_missiles: int = 8
var alternate_cannon_flag: bool = false

@onready var vehicle: ArcadeVehicle = get_parent() as ArcadeVehicle
@onready var targeting_system: TargetingSystem = $TargetingSystem if has_node("TargetingSystem") else null

func _ready() -> void:
	current_missiles = max_missiles
	EventBus.weapon_heat_changed.emit(current_heat, max_heat, is_overheated)
	EventBus.missile_ammo_changed.emit(current_missiles, max_missiles)
	EventBus.countermeasure_cooldown_changed.emit(0.0, oil_cooldown)

func _physics_process(delta: float) -> void:
	handle_cooling(delta)
	handle_timers(delta)
	handle_inputs()

func handle_cooling(delta: float) -> void:
	if current_heat > 0.0:
		current_heat = max(0.0, current_heat - cooling_rate * delta)
		if is_overheated and current_heat <= overheat_lockout_threshold:
			is_overheated = false
		EventBus.weapon_heat_changed.emit(current_heat, max_heat, is_overheated)

func handle_timers(delta: float) -> void:
	if primary_cooldown_timer > 0.0:
		primary_cooldown_timer -= delta
	if missile_cooldown_timer > 0.0:
		missile_cooldown_timer -= delta
	if oil_cooldown_timer > 0.0:
		oil_cooldown_timer -= delta
		EventBus.countermeasure_cooldown_changed.emit(oil_cooldown_timer, oil_cooldown)

func handle_inputs() -> void:
	# Continuous primary fire
	if Input.is_action_pressed("fire_primary"):
		fire_machine_guns()
	elif Input.is_action_just_pressed("fire_primary") and is_overheated:
		EventBus.sfx_requested.emit("weapon_dry", vehicle.global_position if vehicle else global_position)

	# Secondary fire (Missiles)
	if Input.is_action_just_pressed("fire_secondary"):
		fire_missiles()

	# Countermeasure (Oil Slick)
	if Input.is_action_just_pressed("countermeasure"):
		deploy_oil_slick()

func fire_machine_guns() -> void:
	if is_overheated or primary_cooldown_timer > 0.0 or not vehicle:
		return

	primary_cooldown_timer = primary_fire_rate
	current_heat += heat_per_shot
	if current_heat >= max_heat:
		is_overheated = true
		EventBus.camera_shake_requested.emit(0.18, 0.2)
		EventBus.sfx_requested.emit("overheat_warning", vehicle.global_position)

	EventBus.weapon_heat_changed.emit(current_heat, max_heat, is_overheated)

	# Alternate between left and right hood cannon
	var fire_point: Marker3D = vehicle.front_fire_point_l if alternate_cannon_flag else vehicle.front_fire_point_r
	alternate_cannon_flag = not alternate_cannon_flag

	if bullet_scene and fire_point:
		var bullet: MachineGunBullet = bullet_scene.instantiate()
		_get_world().add_child(bullet)
		bullet.initialize(fire_point.global_position, -vehicle.global_transform.basis.z)
		trigger_muzzle_flash(fire_point)
		EventBus.camera_shake_requested.emit(0.04, 0.05)
		EventBus.sfx_requested.emit("machine_gun_fire", fire_point.global_position)

func trigger_muzzle_flash(point: Marker3D) -> void:
	if not point:
		return
	var flash_light: OmniLight3D = point.get_node_or_null("FlashLight")
	if not flash_light:
		flash_light = OmniLight3D.new()
		flash_light.name = "FlashLight"
		flash_light.light_color = Color(1.0, 0.85, 0.3)
		flash_light.light_energy = 4.5
		flash_light.omni_range = 6.0
		flash_light.visible = false
		point.add_child(flash_light)
	flash_light.visible = true
	get_tree().create_timer(0.04).timeout.connect(func() -> void:
		if is_instance_valid(flash_light):
			flash_light.visible = false
	)

func fire_missiles() -> void:
	if not vehicle:
		return

	if current_missiles < 2:
		EventBus.sfx_requested.emit("weapon_dry", vehicle.global_position)
		return

	if missile_cooldown_timer > 0.0:
		return

	missile_cooldown_timer = missile_cooldown
	current_missiles -= 2
	EventBus.missile_ammo_changed.emit(current_missiles, max_missiles)

	var car_trans: Transform3D = vehicle.global_transform
	var fwd: Vector3 = -car_trans.basis.z
	var up: Vector3 = car_trans.basis.y
	var right: Vector3 = car_trans.basis.x

	var is_looking_back: bool = Input.is_action_pressed("look_behind") or Input.is_key_pressed(KEY_B)
	var is_rear_fire: bool = is_looking_back

	var target_node: Node3D = null
	var target_dist: float = 60.0

	if targeting_system and is_instance_valid(targeting_system.current_target) and not targeting_system.current_target.is_queued_for_deletion() and targeting_system.current_target.get("is_destroyed") != true:
		target_node = targeting_system.current_target
		var to_target: Vector3 = target_node.global_position - car_trans.origin
		# If locked target is behind car, always fire backward toward it
		if fwd.dot(to_target) < 0.0:
			is_rear_fire = true
		target_dist = car_trans.origin.distance_to(target_node.global_position)

	var fire_dir: Vector3 = -fwd if is_rear_fire else fwd
	var target_spot: Vector3 = (target_node.global_position + (target_node.global_transform.basis.y * 0.85)) if target_node else (car_trans.origin + (fire_dir * 75.0) + (up * 0.85))

	# Adaptive lofting based on distance to target:
	# Close targets (<25m) get lower loft (0.18) so missiles strike directly without vaulting overhead.
	# Long range targets (55m+) get full Macross loft arc (0.42).
	var up_loft: float = lerp(0.18, 0.42, clamp(target_dist / 55.0, 0.0, 1.0))

	# Launch pair of spiraling micro-missiles in lofting Macross-style ejection arc
	for offset_x in [-0.75, 0.75]:
		if missile_scene:
			var missile: MicroMissile = missile_scene.instantiate()
			missile.damage += missile_damage_bonus
			_get_world().add_child(missile)
			# Spawn position: rear deck bay if firing rearward, hood bay if firing forward
			var spawn_pos: Vector3 = car_trans.origin + (right * offset_x) + (up * 1.05) + (fire_dir * 0.6)
			# Initial ejection vector: thrust in fire_dir + adaptive upward loft + slight outward splay
			var splay_dir: Vector3 = (fire_dir * 0.82 + up * up_loft + right * sign(offset_x) * 0.22).normalized()
			missile.initialize(spawn_pos, splay_dir, target_spot, target_node)

	EventBus.camera_shake_requested.emit(0.22, 0.18)
	EventBus.sfx_requested.emit("missile_launch", vehicle.global_position)

func deploy_oil_slick() -> void:
	if oil_cooldown_timer > 0.0 or not vehicle or not vehicle.rear_deploy_point:
		return

	oil_cooldown_timer = oil_cooldown
	EventBus.countermeasure_cooldown_changed.emit(oil_cooldown_timer, oil_cooldown)

	if oil_slick_scene:
		var slick: OilSlick = oil_slick_scene.instantiate()
		_get_world().add_child(slick)
		slick.global_position = vehicle.rear_deploy_point.global_position
		EventBus.camera_shake_requested.emit(0.06, 0.08)

func _get_world() -> Node:
	if get_tree().current_scene:
		return get_tree().current_scene
	return get_tree().root

func add_missiles(amount: int) -> void:
	current_missiles = min(max_missiles, current_missiles + amount)
	EventBus.missile_ammo_changed.emit(current_missiles, max_missiles)
