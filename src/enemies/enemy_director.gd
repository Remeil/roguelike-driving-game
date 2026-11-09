class_name EnemyDirector
extends Node3D

@export_group("Spawning Config")
## Enemy pursuit interceptor scene to spawn.
@export var enemy_car_scene: PackedScene = preload("res://src/enemies/enemy_pursuit_car.tscn")

## Target reference to the player vehicle.
@export var player: ArcadeVehicle

## Maximum number of simultaneous active enemies allowed on the highway.
@export var max_active_enemies: int = 2

## Time in seconds between enemy spawn waves.
@export var spawn_interval: float = 12.0

## Initial delay in seconds before the first enemy spawns.
@export var initial_delay: float = 4.0

## Despawn distance behind player in meters.
@export var despawn_distance_behind: float = 240.0

var active_enemies: Array[EnemyPursuitCar] = []
var spawn_timer: float = 0.0

func _ready() -> void:
	spawn_timer = initial_delay
	EventBus.weapons_van_docked.connect(_on_weapons_van_docked)
	if not player:
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0 and players[0] is ArcadeVehicle:
			player = players[0] as ArcadeVehicle

func _on_weapons_van_docked() -> void:
	# Immediately clear active enemies and bullets when docking into the Weapons Van
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	active_enemies.clear()
	get_tree().call_group("enemy_bullets", "queue_free")
	# Grace period before new enemies spawn after leaving the van
	spawn_timer = spawn_interval + 6.0

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return

	# Never spawn or process enemies while player is safely inside the Weapons Van
	if player.is_docked:
		spawn_timer = spawn_interval + 6.0
		return

	# Clean up dead or distant enemies
	clean_enemies()

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = spawn_interval
		if active_enemies.size() < max_active_enemies:
			spawn_enemy()

func find_road_surface(candidate_pos: Vector3) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	# Cast ray downward through road collision layer 2
	var from_pt: Vector3 = candidate_pos + Vector3(0.0, 15.0, 0.0)
	var to_pt: Vector3 = candidate_pos + Vector3(0.0, -25.0, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from_pt, to_pt, 2)
	return space_state.intersect_ray(query)

func spawn_enemy() -> void:
	if not enemy_car_scene or not player:
		return

	var player_fwd: Vector3 = -player.global_transform.basis.z
	var player_right: Vector3 = player.global_transform.basis.x
	var lane_offset: float = [-3.8, 3.8].pick_random()

	# Try candidate spawn distances (prefer behind, fallback to ahead if road curves away)
	var candidate_distances: Array[float] = [-38.0, -24.0, 75.0, -18.0]
	var found_pos: Vector3 = Vector3.ZERO
	var is_behind: bool = true

	for dist in candidate_distances:
		var test_pos: Vector3 = player.global_position + (player_fwd * dist) + (player_right * lane_offset)
		var hit: Dictionary = find_road_surface(test_pos)
		if not hit.is_empty():
			found_pos = hit.position + Vector3(0.0, 0.45, 0.0)
			is_behind = dist < 0.0
			break

	# Fallback if rays missed road: spawn closely behind player
	if found_pos == Vector3.ZERO:
		found_pos = player.global_position - (player_fwd * 20.0) + (player_right * lane_offset)
		found_pos.y = player.global_position.y + 0.45

	var enemy: EnemyPursuitCar = enemy_car_scene.instantiate()
	get_parent().add_child(enemy)
	enemy.global_position = found_pos

	# Align enemy heading with player heading
	enemy.global_transform.basis = player.global_transform.basis

	# Initial speed (strictly capped at enemy top speed)
	if is_behind:
		var max_spawn_spd: float = enemy.catchup_speed_kph * (1.0 / 3.6)
		enemy.current_forward_speed = clamp(player.current_forward_speed + 6.0, 36.0, max_spawn_spd)
	else:
		enemy.current_forward_speed = clamp(player.current_forward_speed * 0.75, 26.0, 38.0)

	active_enemies.append(enemy)

func clean_enemies() -> void:
	var player_pos: Vector3 = player.global_position

	var i: int = active_enemies.size() - 1
	while i >= 0:
		var enemy: EnemyPursuitCar = active_enemies[i]
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			active_enemies.remove_at(i)
		else:
			# Despawn if fallen below road level or left far behind
			var dist: float = enemy.global_position.distance_to(player_pos)
			if enemy.global_position.y < -10.0 or dist > despawn_distance_behind:
				enemy.queue_free()
				active_enemies.remove_at(i)
		i -= 1
