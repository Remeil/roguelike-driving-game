class_name WeaponsVan
extends CharacterBody3D

## The iconic G-6155 Weapons Van: an armored semi-truck that rolls up ahead,
## lowers its rear ramp with landing lights, and docks the player's Interceptor car
## to perform field repairs, munition restocking, and roguelike upgrade drafts.

enum VanState {
	APPROACHING, # Driving steadily ahead, ramp lowered, waiting for player
	DOCKING,     # Player entered ramp, transitioning into bay
	DOCKED,      # Car clamped in bay, shop UI active
	LAUNCHING,   # Car ejected with boost
	DEPARTING    # Accelerating ahead, ramp retracting, despawning
}

## Steady cruising speed in km/h while waiting for the player to dock.
@export var cruising_speed_kph: float = 116.0

## Departure acceleration speed in km/h after upgrade selection.
@export var depart_speed_kph: float = 230.0

## Highway lane offset from centerline (meters). Default to right cruise lane (+1.8m).
@export var lane_offset: float = 1.8

const KPH_TO_MPS: float = 1.0 / 3.6
const GRAVITY: float = 28.0

var current_state: VanState = VanState.APPROACHING
var current_forward_speed: float = 116.0 * KPH_TO_MPS
var player_car: ArcadeVehicle = null
var shop_ui: WeaponsVanShop = null
var time_alive: float = 0.0
var depart_timer: float = 0.0
var initial_ramp_rot_deg: Vector3 = Vector3.ZERO

@onready var dock_anchor: Marker3D = $DockAnchor
@onready var dock_trigger: Area3D = $DockTrigger
@onready var runway_lights: Node3D = $Visuals/Trailer/Ramp/RunwayLights
@onready var ramp_node: Node3D = $Visuals/Trailer/Ramp

func _ready() -> void:
	add_to_group("weapons_van")
	if dock_trigger:
		dock_trigger.body_entered.connect(_on_dock_trigger_entered)

	current_forward_speed = cruising_speed_kph * KPH_TO_MPS
	floor_snap_length = 0.8
	floor_constant_speed = true

	# Respect the editor-tuned ramp rotation (e.g. 6 degrees)
	if ramp_node:
		initial_ramp_rot_deg = ramp_node.rotation_degrees

	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is ArcadeVehicle:
		player_car = players[0] as ArcadeVehicle

	# Locate or instantiate the WeaponsVanShop overlay
	call_deferred("_setup_shop_ui")

func _setup_shop_ui() -> void:
	if get_tree().current_scene:
		shop_ui = get_tree().current_scene.find_child("WeaponsVanShop", true, false) as WeaponsVanShop
	if not shop_ui:
		var shop_scene := preload("res://src/ui/weapons_van_shop.tscn")
		shop_ui = shop_scene.instantiate()
		var target_parent := get_tree().current_scene if get_tree().current_scene else get_tree().root
		target_parent.add_child(shop_ui)
	
	if shop_ui and not shop_ui.closed.is_connected(_on_shop_closed):
		shop_ui.closed.connect(_on_shop_closed)

func _exit_tree() -> void:
	if is_instance_valid(player_car):
		remove_collision_exception_with(player_car)
		player_car.remove_collision_exception_with(self)
	# If the van is ever removed or despawned while player is docked, safely rescue player
	if is_instance_valid(player_car) and player_car.is_docked:
		player_car.is_docked = false
		player_car.docked_van_anchor = null
		player_car._recover_from_void()
	if is_instance_valid(shop_ui) and shop_ui.visible:
		shop_ui.close_shop()

func _physics_process(delta: float) -> void:
	time_alive += delta

	match current_state:
		VanState.APPROACHING, VanState.DOCKING, VanState.DOCKED:
			process_cruising(delta)
			update_runway_lights()

		VanState.DEPARTING:
			process_departing(delta)

func process_cruising(delta: float) -> void:
	# Void safety recovery for the van: snap back to road surface if displaced
	if global_position.y < -3.0 and HighwayManager.instance:
		var rec_info: Dictionary = HighwayManager.instance.get_road_transform(global_position, 0.0, lane_offset)
		var safe_p: Vector3 = rec_info.get("position", global_position)
		var safe_f: Vector3 = rec_info.get("forward", -global_transform.basis.z)
		var safe_r: Vector3 = rec_info.get("right", global_transform.basis.x)
		global_position = Vector3(safe_p.x, safe_p.y + 0.1, safe_p.z)
		global_transform.basis = Basis(safe_r, Vector3.UP, -safe_f).orthonormalized()
		velocity = safe_f * (cruising_speed_kph * KPH_TO_MPS)

	# While DOCKING or DOCKED with the player, lock directly to the highway road spline
	# This guarantees the van NEVER leaves the asphalt, hits guardrails, or falls off curves
	if (current_state == VanState.DOCKED or current_state == VanState.DOCKING) and HighwayManager.instance:
		var step_dist: float = cruising_speed_kph * KPH_TO_MPS * delta
		var road_info: Dictionary = HighwayManager.instance.get_road_transform(global_position, step_dist, lane_offset)
		var target_pos: Vector3 = road_info.get("position", global_position)
		var target_fwd: Vector3 = road_info.get("forward", -global_transform.basis.z)
		var target_right: Vector3 = road_info.get("right", global_transform.basis.x)
		var target_basis := Basis(target_right, Vector3.UP, -target_fwd).orthonormalized()

		global_position = Vector3(target_pos.x, target_pos.y + 0.05, target_pos.z)
		global_transform.basis = target_basis
		velocity = target_fwd * (cruising_speed_kph * KPH_TO_MPS)
		return

	# APPROACHING state navigation
	var lookahead_dist: float = 24.0
	var target_pt: Vector3 = global_position - global_transform.basis.z * lookahead_dist

	if HighwayManager.instance:
		var road_info: Dictionary = HighwayManager.instance.get_road_transform(global_position, lookahead_dist, lane_offset)
		target_pt = road_info.get("position", target_pt)

	# Steer smoothly toward spline target point
	var local_target: Vector3 = global_transform.affine_inverse() * target_pt
	var angle_to_target: float = atan2(-local_target.x, max(0.2, -local_target.z))
	var max_turn_rate: float = 2.4 # Enhanced turn rate to cleanly follow 36° curves
	var steer_yaw: float = clamp(angle_to_target * 3.0, -max_turn_rate, max_turn_rate)

	rotate_y(steer_yaw * delta)
	global_transform.basis = global_transform.basis.orthonormalized()

	# Maintain cruising speed
	var target_speed_mps: float = cruising_speed_kph * KPH_TO_MPS
	current_forward_speed = move_toward(current_forward_speed, target_speed_mps, 18.0 * delta)

	var forward_dir: Vector3 = -global_transform.basis.z
	var horizontal_vel: Vector3 = forward_dir * current_forward_speed
	var vertical_y: float = -2.5 if is_on_floor() else velocity.y - GRAVITY * delta

	velocity = Vector3(horizontal_vel.x, vertical_y, horizontal_vel.z)
	move_and_slide()

	# Void safety cleanup (only when player is not docked!)
	if current_state != VanState.DOCKED and global_position.y < -15.0:
		queue_free()
		return

	# Despawn when left far behind by the player (only when player is not docked!)
	if current_state != VanState.DOCKED and is_instance_valid(player_car):
		var to_van: Vector3 = global_position - player_car.global_position
		var player_fwd: Vector3 = -player_car.global_transform.basis.z
		if to_van.dot(player_fwd) < -85.0:
			EventBus.weapons_van_missed.emit()
			queue_free()
			return

func process_departing(delta: float) -> void:
	depart_timer += delta

	# Void safety recovery for the departing van
	if global_position.y < -3.0 and HighwayManager.instance:
		var rec_info: Dictionary = HighwayManager.instance.get_road_transform(global_position, 0.0, lane_offset)
		var safe_p: Vector3 = rec_info.get("position", global_position)
		var safe_f: Vector3 = rec_info.get("forward", -global_transform.basis.z)
		var safe_r: Vector3 = rec_info.get("right", global_transform.basis.x)
		global_position = Vector3(safe_p.x, safe_p.y + 0.1, safe_p.z)
		global_transform.basis = Basis(safe_r, Vector3.UP, -safe_f).orthonormalized()

	# Accelerate forward rapidly away from player
	var target_speed_mps: float = depart_speed_kph * KPH_TO_MPS
	current_forward_speed = move_toward(current_forward_speed, target_speed_mps, 48.0 * delta)

	# Follow highway spline
	var lookahead_dist: float = 32.0
	var target_pt: Vector3 = global_position - global_transform.basis.z * lookahead_dist
	if HighwayManager.instance:
		var road_info: Dictionary = HighwayManager.instance.get_road_transform(global_position, lookahead_dist, lane_offset)
		target_pt = road_info.get("position", target_pt)

	var local_target: Vector3 = global_transform.affine_inverse() * target_pt
	var angle_to_target: float = atan2(-local_target.x, max(0.2, -local_target.z))
	rotate_y(clamp(angle_to_target * 2.8, -2.6, 2.6) * delta)
	global_transform.basis = global_transform.basis.orthonormalized()

	var forward_dir: Vector3 = -global_transform.basis.z
	var horizontal_vel: Vector3 = forward_dir * current_forward_speed
	var vertical_y: float = -2.5 if is_on_floor() else velocity.y - GRAVITY * delta

	velocity = Vector3(horizontal_vel.x, vertical_y, horizontal_vel.z)
	move_and_slide()

	# Animate ramp retraction only after departing ahead so it never clips car
	if ramp_node and depart_timer > 0.4:
		ramp_node.rotation_degrees.x = move_toward(ramp_node.rotation_degrees.x, 85.0, 130.0 * delta)

	# Despawn when far ahead of player or after 8s
	if is_instance_valid(player_car):
		var dist_ahead: float = global_position.distance_to(player_car.global_position)
		if dist_ahead > 240.0 or depart_timer > 8.0:
			queue_free()
	elif depart_timer > 8.0:
		queue_free()

func update_runway_lights() -> void:
	if not runway_lights:
		return
	# Pulsing landing guide lights for runway docking
	var pulse: bool = fmod(time_alive, 0.35) < 0.20
	runway_lights.visible = pulse

func _on_dock_trigger_entered(body: Node) -> void:
	if current_state != VanState.APPROACHING:
		return

	if body is ArcadeVehicle or body.is_in_group("player"):
		player_car = body as ArcadeVehicle
		if not is_instance_valid(player_car):
			return

		# Check that player is approaching from behind
		var to_player: Vector3 = player_car.global_position - global_position
		var van_fwd: Vector3 = -global_transform.basis.z
		if to_player.dot(van_fwd) > 0.0:
			# Player is ahead of the van, don't dock
			return

		current_state = VanState.DOCKING
		if player_car.has_method("start_docking"):
			player_car.start_docking(dock_anchor)
		else:
			player_car.velocity = Vector3.ZERO
			player_car.current_forward_speed = 0.0

		# Prevent physical collisions between van and player while docking/docked/departing
		add_collision_exception_with(player_car)
		player_car.add_collision_exception_with(self)

		EventBus.sfx_requested.emit("van_dock", global_position)
		EventBus.camera_shake_requested.emit(0.24, 0.25)

		# Cinematic magnetic winch pulls car smoothly up the ramp into the bay
		var tween := create_tween()
		if dock_anchor:
			tween.tween_property(player_car, "global_position", dock_anchor.global_position, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.parallel().tween_property(player_car, "global_basis", dock_anchor.global_basis, 0.38)
		
		tween.tween_callback(func() -> void:
			if is_instance_valid(player_car) and is_instance_valid(dock_anchor):
				player_car.dock_in_van(dock_anchor)
				current_state = VanState.DOCKED
				EventBus.weapons_van_docked.emit()
				if shop_ui:
					shop_ui.open_shop(player_car)
		)

func _on_shop_closed(_depart_now: bool) -> void:
	if current_state != VanState.DOCKED and current_state != VanState.DOCKING:
		return

	# Transition van to departure mode immediately with high forward velocity
	current_state = VanState.DEPARTING
	depart_timer = 0.0
	current_forward_speed = max(current_forward_speed, 185.0 * KPH_TO_MPS)

	# Safely deploy player vehicle onto the highway spline behind the van
	if is_instance_valid(player_car):
		player_car.is_docked = false
		player_car.docked_van_anchor = null

		# Ensure collision exception remains active so departing van never snags car
		add_collision_exception_with(player_car)
		player_car.add_collision_exception_with(self)

		# Trailer + ramp extends ~10m behind van center; sample road spline 16m back for guaranteed clear tarmac
		var exit_dist_behind: float = 16.0
		var probe_world_pos: Vector3 = global_position + (global_transform.basis.z * exit_dist_behind)
		var road_info: Dictionary = HighwayManager.instance.get_road_transform(probe_world_pos, 0.0, lane_offset) if HighwayManager.instance else {}
		var safe_pos: Vector3 = road_info.get("position", probe_world_pos)
		var road_fwd: Vector3 = road_info.get("forward", -global_transform.basis.z)
		var road_right: Vector3 = road_info.get("right", global_transform.basis.x)
		var safe_basis := Basis(road_right, Vector3.UP, -road_fwd).orthonormalized()

		var launch_speed_mps: float = 150.0 * KPH_TO_MPS
		var launch_velocity: Vector3 = road_fwd * launch_speed_mps

		# Position vehicle flush on highway surface with clear forward momentum
		player_car.global_position = Vector3(safe_pos.x, safe_pos.y + 0.35, safe_pos.z)
		player_car.global_transform.basis = safe_basis
		player_car.launch_from_van(launch_velocity)

		EventBus.sfx_requested.emit("van_eject", player_car.global_position)
		EventBus.camera_shake_requested.emit(0.28, 0.3)
