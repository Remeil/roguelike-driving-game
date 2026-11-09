class_name MissilePickup
extends Area3D

## Infrequent tactical ammo crate that restores 2 homing micro-missiles to the player

## Number of micro-missiles restored upon driving through this pickup.
@export var missiles_granted: int = 2

## Hover height above highway asphalt in meters.
@export var float_height: float = 0.75

## Yaw rotation speed in radians per second.
@export var rotation_speed: float = 2.4

## Bobbing vertical oscillation amplitude in meters.
@export var bob_amplitude: float = 0.12

## Bobbing frequency in cycles per second.
@export var bob_frequency: float = 3.2

## Distance behind the player (in meters) before this pickup despawns.
@export var despawn_distance_behind: float = 120.0

var base_y: float = 0.0
var time_alive: float = 0.0
var is_collected: bool = false
var player_ref: Node3D = null

@onready var visual_root: Node3D = $Visuals
@onready var beacon_light: OmniLight3D = $Visuals/BeaconLight
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	base_y = position.y if position.y != 0.0 else float_height
	
	# Cache player reference
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player_ref = players[0] as Node3D

func _process(delta: float) -> void:
	if is_collected:
		return

	time_alive += delta

	# Continuous hovering and spinning animation
	if visual_root:
		visual_root.rotate_y(rotation_speed * delta)
		visual_root.position.y = base_y + sin(time_alive * bob_frequency) * bob_amplitude

	# Pulsing amber light effect
	if beacon_light:
		beacon_light.light_energy = 2.4 + sin(time_alive * 4.5) * 0.9

	# Periodic check for player ref if not cached yet
	if not is_instance_valid(player_ref):
		var players: Array[Node] = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player_ref = players[0] as Node3D

	# Despawn when left behind by the player
	if is_instance_valid(player_ref):
		var to_pickup: Vector3 = global_position - player_ref.global_position
		var player_fwd: Vector3 = -player_ref.global_transform.basis.z
		# Dot product < 0 means behind the player
		if to_pickup.dot(player_fwd) < -despawn_distance_behind:
			queue_free()

func _on_body_entered(body: Node) -> void:
	if is_collected:
		return

	# Check if the colliding body is the player vehicle
	if body is ArcadeVehicle or body.is_in_group("player"):
		var weapon_sys: WeaponSystem = body.get_node_or_null("WeaponSystem") as WeaponSystem
		if not weapon_sys:
			weapon_sys = body.find_child("WeaponSystem", true, false) as WeaponSystem

		if weapon_sys:
			# If player is already full on missiles, leave the crate on the highway for when needed
			if weapon_sys.current_missiles >= weapon_sys.max_missiles:
				return

			is_collected = true
			if collision_shape:
				collision_shape.set_deferred("disabled", true)

			# Restore missiles
			weapon_sys.add_missiles(missiles_granted)
			EventBus.missile_ammo_restored.emit(missiles_granted, weapon_sys.current_missiles)
			EventBus.sfx_requested.emit("missile_pickup", global_position)

			# Energetic collection burst effect
			var tween := create_tween()
			if visual_root:
				tween.tween_property(visual_root, "scale", Vector3(1.8, 1.8, 1.8), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			if beacon_light:
				tween.parallel().tween_property(beacon_light, "light_energy", 8.0, 0.14)
			tween.tween_callback(queue_free)
