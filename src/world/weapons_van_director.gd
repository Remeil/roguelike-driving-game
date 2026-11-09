class_name WeaponsVanDirector
extends Node3D

## Coordinates Weapons Van rendezvous events based on driving distance milestones and/or objective completion

@export_group("Spawning Config")
@export var van_scene: PackedScene = preload("res://src/world/weapons_van.tscn")
@export var player: ArcadeVehicle
## Physical placement distance ahead of the player car on the road (in meters) when the van spawns.
@export var spawn_distance_ahead: float = 400.0
@export var spawn_on_objective_complete: bool = true
@export var enable_distance_milestone: bool = false

@export_group("Milestone Distance Interval Scaling")
## Base driving distance (in meters) required between Weapons Van rendezvous spawns.
@export var milestone_distance_interval: float = 1200.0

## Distance (in meters) added to the milestone interval each time the Weapons Van spawns.
## e.g. 400.0 means Interval 1 = 1200m, Interval 2 = 1600m, Interval 3 = 2000m, etc.
@export var milestone_distance_increase_per_spawn: float = 400.0

## Optional distance (in meters) added to the milestone interval for each upgrade tier purchased.
@export var milestone_distance_increase_per_upgrade: float = 0.0

## Maximum ceiling for the driving distance milestone interval.
@export var max_milestone_distance_interval: float = 12000.0

var active_van: WeaponsVan = null
var distance_since_last_van: float = 0.0
var spawn_count: int = 0
var total_upgrades_purchased: int = 0

func _ready() -> void:
	if not player:
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0 and players[0] is ArcadeVehicle:
			player = players[0] as ArcadeVehicle

	EventBus.objective_completed.connect(_on_objective_completed)
	EventBus.upgrade_selected.connect(_on_upgrade_selected)

func _on_upgrade_selected(_upgrade_data: Dictionary) -> void:
	total_upgrades_purchased += 1

func _on_objective_completed(_title: String, _reward: int) -> void:
	if not spawn_on_objective_complete:
		return
	if not is_instance_valid(player):
		return
	if player.is_docked or player.is_docking:
		return

	# If van is already active but behind the player, despawn old van so fresh rendezvous spawns ahead
	if is_instance_valid(active_van):
		var to_van: Vector3 = active_van.global_position - player.global_position
		var player_fwd: Vector3 = -player.global_transform.basis.z
		if to_van.dot(player_fwd) < -10.0:
			active_van.queue_free()
			active_van = null
		else:
			# Van is already ahead awaiting rendezvous
			return

	spawn_weapons_van()

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0 and players[0] is ArcadeVehicle:
			player = players[0] as ArcadeVehicle
		return

	# Distance-based milestone spawning
	if enable_distance_milestone:
		var speed_mps: float = player.current_forward_speed
		distance_since_last_van += speed_mps * delta
		var required_interval: float = get_current_milestone_interval()
		if distance_since_last_van >= required_interval and not is_instance_valid(active_van):
			spawn_weapons_van()

## Computes current dynamic driving distance interval required before the next Weapons Van spawns
func get_current_milestone_interval() -> float:
	var total_interval: float = milestone_distance_interval + (spawn_count * milestone_distance_increase_per_spawn) + (total_upgrades_purchased * milestone_distance_increase_per_upgrade)
	return min(total_interval, max_milestone_distance_interval)

func spawn_weapons_van() -> void:
	if not van_scene or not is_instance_valid(player) or not HighwayManager.instance:
		return

	var lane: float = HighwayManager.LANE_RIGHT_CRUISE
	var road_info: Dictionary = HighwayManager.instance.get_road_transform(player.global_position, spawn_distance_ahead, lane)
	var spawn_pos: Vector3 = road_info.get("position", Vector3.ZERO)
	if spawn_pos == Vector3.ZERO:
		return

	var fwd: Vector3 = road_info.get("forward", -player.global_transform.basis.z)
	var right: Vector3 = road_info.get("right", player.global_transform.basis.x)
	var up: Vector3 = right.cross(fwd).normalized()

	var van: WeaponsVan = van_scene.instantiate() as WeaponsVan
	get_parent().add_child(van)
	active_van = van

	van.lane_offset = lane
	van.global_position = spawn_pos + Vector3(0, 0.45, 0)
	van.global_transform.basis = Basis(right, up, -fwd).orthonormalized()

	distance_since_last_van = 0.0
	spawn_count += 1

	EventBus.weapons_van_approaching.emit()
	EventBus.sfx_requested.emit("van_siren", player.global_position)
