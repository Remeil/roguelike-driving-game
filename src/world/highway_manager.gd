class_name HighwayManager
extends Node3D

@export_group("Chunk Prefabs")
## Straight highway chunk scene (0° deflection).
@export var straight_chunk_scene: PackedScene = preload("res://src/world/highway_chunk_straight.tscn")

## Gentle left-curving highway chunk scene (~18° left arc).
@export var gentle_left_scene: PackedScene = preload("res://src/world/highway_chunk_curve_left.tscn")

## Gentle right-curving highway chunk scene (~18° right arc).
@export var gentle_right_scene: PackedScene = preload("res://src/world/highway_chunk_curve_right.tscn")

## Sharp left-curving highway chunk scene (~36° left arc).
@export var sharp_left_scene: PackedScene = preload("res://src/world/highway_chunk_sharp_left.tscn")

## Sharp right-curving highway chunk scene (~36° right arc).
@export var sharp_right_scene: PackedScene = preload("res://src/world/highway_chunk_sharp_right.tscn")

## S-Curve left-first chicane highway chunk scene (deflects left then right, net 0°).
@export var s_curve_left_scene: PackedScene = preload("res://src/world/highway_chunk_s_curve_left.tscn")

## S-Curve right-first chicane highway chunk scene (deflects right then left, net 0°).
@export var s_curve_right_scene: PackedScene = preload("res://src/world/highway_chunk_s_curve_right.tscn")

## Target drone scene spawned periodically along the road for combat testing.
@export var test_target_scene: PackedScene = preload("res://src/weapons/test_target.tscn")

## Tactical ammo pickup scene placed infrequently along highway lanes.
@export var ammo_pickup_scene: PackedScene = preload("res://src/weapons/pickups/missile_pickup.tscn")

@export_group("Generation Settings")
## Reference to the player car node used for distance calculations.
@export var player: Node3D

## Initial number of consecutive highway chunks generated in advance ahead of the player.
@export var initial_chunk_count: int = 8

## Distance in meters behind the player at which past chunks are automatically recycled/freed.
@export var despawn_distance_behind: float = 520.0

## Maximum absolute corridor heading deflection in degrees from the global forward axis (prevents endless looping).
@export var max_corridor_heading_deg: float = 48.0

static var instance: HighwayManager = null

# Standard 4-lane highway offsets (meters from road centerline)
const LANE_LEFT_PASSING: float = -5.5
const LANE_LEFT_CRUISE: float = -1.8
const LANE_RIGHT_CRUISE: float = 1.8
const LANE_RIGHT_SLOW: float = 5.5
const ALL_LANES: Array[float] = [-5.5, -1.8, 1.8, 5.5]

var active_chunks: Array[HighwayChunk] = []
var next_spawn_transform: Transform3D = Transform3D.IDENTITY
var current_heading_deg: float = 0.0
var chunks_spawned_count: int = 0

func _ready() -> void:
	instance = self
	# Start slightly behind origin to ensure road exists under car at spawn
	next_spawn_transform.origin = Vector3(0, 0, 30.0)

	# Spawn initial runway
	for i in range(initial_chunk_count):
		spawn_next_chunk()

func _process(_delta: float) -> void:
	if not player:
		return

	# Maintain active chunks ahead of player (keep at least 900m of road queued ahead)
	if active_chunks.size() > 0:
		var last_chunk: HighwayChunk = active_chunks.back()
		var dist_to_end: float = player.global_position.distance_to(last_chunk.get_end_transform().origin)
		if dist_to_end < 900.0:
			spawn_next_chunk()

	# Despawn chunks left behind
	clean_old_chunks()

func spawn_next_chunk() -> void:
	var scene_to_spawn: PackedScene = choose_next_chunk_scene()
	if not scene_to_spawn:
		return

	var chunk: HighwayChunk = scene_to_spawn.instantiate()
	chunk.global_transform = next_spawn_transform
	add_child(chunk)

	current_heading_deg += chunk.get_heading_delta_deg()
	next_spawn_transform = chunk.get_end_transform()

	active_chunks.append(chunk)
	chunks_spawned_count += 1

	# Spawn test target drone along the road (35% probability per chunk after initial runway)
	if chunks_spawned_count >= 2 and test_target_scene and randf() < 0.4:
		var target: Node3D = test_target_scene.instantiate() as Node3D
		if target:
			chunk.add_child(target)
			var lane_offset: float = ALL_LANES.pick_random()
			target.position = Vector3(lane_offset, 0.4, -45.0)

	# Infrequent ambient missile ammo pickups placed along highway lanes (~20% probability per chunk)
	if chunks_spawned_count >= 2 and ammo_pickup_scene and randf() < 0.22:
		var pickup: Node3D = ammo_pickup_scene.instantiate() as Node3D
		if pickup:
			chunk.add_child(pickup)
			var lane: float = ALL_LANES.pick_random()
			pickup.position = Vector3(lane, 0.75, randf_range(-30.0, -60.0))

func choose_next_chunk_scene() -> PackedScene:
	# First 2 chunks are always straight runway
	if chunks_spawned_count < 2:
		return straight_chunk_scene

	var roll: float = randf()

	# Anti-Loop Steering Governance:
	# If road is turned strongly left (>= +22 deg), steer right or S-curve
	if current_heading_deg >= 22.0:
		if current_heading_deg >= 35.0:
			# Force sharp right turn back towards center
			return sharp_right_scene
		elif roll < 0.4:
			return sharp_right_scene
		elif roll < 0.7:
			return gentle_right_scene
		else:
			return straight_chunk_scene

	# If road is turned strongly right (<= -22 deg), steer left or S-curve
	if current_heading_deg <= -22.0:
		if current_heading_deg <= -35.0:
			# Force sharp left turn back towards center
			return sharp_left_scene
		elif roll < 0.4:
			return sharp_left_scene
		elif roll < 0.7:
			return gentle_left_scene
		else:
			return straight_chunk_scene

	# In center corridor (-22 deg to +22 deg):
	# Full variety: S-curves, 45-degree sharp bends, gentle sweepers, and straights
	if roll < 0.28:
		# High-speed S-Curve Chicane (net heading change is 0, so 100% safe anywhere)
		return s_curve_left_scene if randf() < 0.5 else s_curve_right_scene
	elif roll < 0.52:
		# Sharp 45-degree power slide bend
		return sharp_left_scene if randf() < 0.5 else sharp_right_scene
	elif roll < 0.76:
		# Gentle 15-degree sweeper
		return gentle_left_scene if randf() < 0.5 else gentle_right_scene
	else:
		# High-speed straightaway
		return straight_chunk_scene

func clean_old_chunks() -> void:
	if not player:
		return

	# Keep at least 12 chunks active at all times
	while active_chunks.size() > 12:
		var oldest: HighwayChunk = active_chunks[0]
		var dist_to_start: float = player.global_position.distance_to(oldest.global_position)
		var dist_to_end: float = player.global_position.distance_to(oldest.get_end_transform().origin)

		# Only free if BOTH start and end of chunk are far behind the player
		if dist_to_start > despawn_distance_behind and dist_to_end > despawn_distance_behind:
			active_chunks.pop_front()
			oldest.queue_free()
		else:
			break

## Find active chunk whose centerline spline is closest to given world position
func get_chunk_at(world_pos: Vector3) -> CurvedHighwayBuilder:
	var best_chunk: CurvedHighwayBuilder = null
	var best_dist_sq: float = 9999999.0

	for chunk in active_chunks:
		if chunk is CurvedHighwayBuilder:
			var d_sq: float = chunk.get_distance_to_spline_sq(world_pos)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best_chunk = chunk as CurvedHighwayBuilder

	return best_chunk

## Returns exact road and lane target transform along highway curve
func get_road_transform(world_pos: Vector3, lookahead_m: float = 16.0, lane_offset: float = 0.0) -> Dictionary:
	var cur_chunk: CurvedHighwayBuilder = get_chunk_at(world_pos)
	if not cur_chunk:
		return {
			"position": world_pos + Vector3(lane_offset, 0, -lookahead_m),
			"road_center": world_pos + Vector3(0, 0, -lookahead_m),
			"forward": Vector3(0, 0, -1),
			"right": Vector3(1, 0, 0)
		}

	var cur_pos: Vector3 = world_pos
	var remaining_dist: float = lookahead_m
	var chunk_idx: int = active_chunks.find(cur_chunk)
	var latest_info: Dictionary = {}

	# Walk along connected highway chunks until the full lookahead distance is traversed
	while cur_chunk and chunk_idx >= 0 and chunk_idx < active_chunks.size():
		latest_info = cur_chunk.get_road_info_at_world_pos(cur_pos, remaining_dist, lane_offset)
		if not latest_info.get("is_at_end", false) or remaining_dist <= 0.0:
			return latest_info

		var ds: float = cur_chunk.chunk_length / float(max(1, cur_chunk.subdivisions))
		var samples_traveled: int = (cur_chunk.samples.size() - 1) - int(latest_info.get("closest_index", 0))
		var dist_traveled: float = max(1.0, samples_traveled * ds)
		remaining_dist -= dist_traveled

		chunk_idx += 1
		if chunk_idx < active_chunks.size() and active_chunks[chunk_idx] is CurvedHighwayBuilder:
			cur_chunk = active_chunks[chunk_idx] as CurvedHighwayBuilder
			cur_pos = cur_chunk.global_position
		else:
			break

	if not latest_info.is_empty():
		return latest_info

	# Fallback if outside chunks
	return {
		"position": world_pos + Vector3(lane_offset, 0, -lookahead_m),
		"road_center": world_pos + Vector3(0, 0, -lookahead_m),
		"forward": Vector3(0, 0, -1),
		"right": Vector3(1, 0, 0)
	}
