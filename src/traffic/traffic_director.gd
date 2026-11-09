class_name TrafficDirector
extends Node3D

@export_group("Traffic Prefabs")
## Civilian sedan scene.
@export var sedan_scene: PackedScene = preload("res://src/traffic/civilian_sedan.tscn")

## Civilian pickup truck scene.
@export var pickup_scene: PackedScene = preload("res://src/traffic/civilian_pickup.tscn")

## Civilian box truck scene.
@export var box_truck_scene: PackedScene = preload("res://src/traffic/civilian_box_truck.tscn")

@export_group("Spawning Config")
## Reference to player vehicle.
@export var player: ArcadeVehicle

## Maximum simultaneous civilian vehicles on the road.
@export var max_active_traffic: int = 6

## Delay between traffic spawn checks in seconds.
@export var spawn_interval: float = 3.5

## Despawn distance behind player in meters.
@export var despawn_distance_behind: float = 240.0

var active_traffic: Array[CivilianVehicle] = []
var spawn_timer: float = 1.0

func _ready() -> void:
	EventBus.weapons_van_docked.connect(_on_weapons_van_docked)
	if not player:
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0 and players[0] is ArcadeVehicle:
			player = players[0] as ArcadeVehicle

	# Initial traffic wave ahead of player
	call_deferred("spawn_initial_traffic")

func _on_weapons_van_docked() -> void:
	# Clear nearby traffic to give the van a clean cruising lane while docked
	if is_instance_valid(player):
		var p_pos: Vector3 = player.global_position
		for car in active_traffic:
			if is_instance_valid(car) and car.global_position.distance_to(p_pos) < 65.0:
				car.queue_free()

func spawn_initial_traffic() -> void:
	if not player:
		return
	# Spawn a few initial cars ahead on the runway
	for dist in [60.0, 95.0, 130.0]:
		spawn_traffic_at_distance(dist)

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return

	# Don't spawn traffic while player is inside the Weapons Van
	if player.is_docked:
		return

	clean_traffic()

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = spawn_interval
		if active_traffic.size() < max_active_traffic:
			spawn_traffic_at_distance(randf_range(90.0, 155.0))

func spawn_traffic_at_distance(dist_ahead: float) -> void:
	if not player or not HighwayManager.instance:
		return

	# Choose lane
	var chosen_lane: float = HighwayManager.ALL_LANES.pick_random()

	# Choose vehicle type based on lane
	var chosen_scene: PackedScene = sedan_scene
	var roll: float = randf()

	if chosen_lane == HighwayManager.LANE_RIGHT_SLOW:
		chosen_scene = box_truck_scene if roll < 0.6 else pickup_scene
	elif chosen_lane == HighwayManager.LANE_LEFT_PASSING:
		chosen_scene = sedan_scene
	else:
		if roll < 0.55:
			chosen_scene = sedan_scene
		elif roll < 0.85:
			chosen_scene = pickup_scene
		else:
			chosen_scene = box_truck_scene

	if not chosen_scene:
		return

	# Query highway surface ahead
	var player_fwd: Vector3 = -player.global_transform.basis.z
	var approx_pos: Vector3 = player.global_position + (player_fwd * dist_ahead)
	var road_info: Dictionary = HighwayManager.instance.get_road_transform(approx_pos, 0.0, chosen_lane)

	var spawn_pos: Vector3 = road_info.get("position", approx_pos)
	spawn_pos.y = player.global_position.y + 0.5

	var vehicle: CivilianVehicle = chosen_scene.instantiate()
	vehicle.target_lane_offset = chosen_lane
	vehicle.current_lane_offset = chosen_lane
	get_parent().add_child(vehicle)

	vehicle.global_position = spawn_pos
	# Align with road forward vector
	var fwd: Vector3 = road_info.get("forward", player_fwd)
	var right: Vector3 = road_info.get("right", player.global_transform.basis.x)
	vehicle.global_transform.basis = Basis(right, Vector3.UP, -fwd).orthonormalized()

	active_traffic.append(vehicle)

func clean_traffic() -> void:
	var player_pos: Vector3 = player.global_position

	var i: int = active_traffic.size() - 1
	while i >= 0:
		var car: CivilianVehicle = active_traffic[i]
		if not is_instance_valid(car) or car.is_queued_for_deletion():
			active_traffic.remove_at(i)
		else:
			var dist: float = car.global_position.distance_to(player_pos)
			if car.global_position.y < -10.0 or dist > despawn_distance_behind:
				car.queue_free()
				active_traffic.remove_at(i)
		i -= 1
