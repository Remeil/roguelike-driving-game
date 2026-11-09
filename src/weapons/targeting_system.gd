class_name TargetingSystem
extends Node3D

@export var max_range: float = 95.0
@export var min_range: float = 4.0
@export var max_lock_angle_deg: float = 34.0
@export var time_to_lock: float = 0.35

var current_target: Node3D = null
var lock_timer: float = 0.0
var is_locked: bool = false
var is_looking_behind: bool = false

@onready var vehicle: ArcadeVehicle = get_parent().get_parent() as ArcadeVehicle if get_parent() is WeaponSystem else get_parent() as ArcadeVehicle

func _process(delta: float) -> void:
	# Check if player is currently looking behind
	is_looking_behind = Input.is_action_pressed("look_behind") or Input.is_key_pressed(KEY_B)

	# If current target was destroyed or queued for deletion, clear it immediately
	if not is_instance_valid(current_target) or current_target.is_queued_for_deletion() or current_target.get("is_destroyed") == true:
		current_target = null
		lock_timer = 0.0
		is_locked = false

	var best_target: Node3D = scan_for_targets()

	if best_target != null:
		if best_target == current_target:
			if not is_locked:
				lock_timer += delta
				if lock_timer >= time_to_lock:
					is_locked = true
					EventBus.sfx_requested.emit("target_locked", current_target.global_position)
		else:
			current_target = best_target
			lock_timer = 0.0
			is_locked = false
			EventBus.sfx_requested.emit("target_acquiring", current_target.global_position)

		EventBus.target_acquired.emit(current_target, current_target.global_position, is_locked)
	else:
		current_target = null
		lock_timer = 0.0
		is_locked = false
		EventBus.target_acquired.emit(null, Vector3.ZERO, false)

func scan_for_targets() -> Node3D:
	var car_basis: Basis = vehicle.global_transform.basis if is_instance_valid(vehicle) else global_transform.basis
	# When looking behind (holding look_behind / Key B), scan rearward arc; otherwise scan forward arc
	var aim_forward: Vector3 = car_basis.z if is_looking_behind else -car_basis.z
	var origin: Vector3 = global_position

	var candidates := get_tree().get_nodes_in_group("enemies")
	var best_candidate: Node3D = null
	var best_score: float = 99999.0 # Lower is better (closest to aim center)

	for node in candidates:
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		if node.is_queued_for_deletion() or node.get("is_destroyed") == true:
			continue

		var target_3d := node as Node3D
		var to_target := target_3d.global_position - origin
		var dist := to_target.length()

		if dist < min_range or dist > max_range:
			continue

		var dir := to_target.normalized()
		var dot := aim_forward.dot(dir)
		if dot <= 0.0:
			continue # Not in our targeted hemisphere

		var angle_deg := rad_to_deg(acos(clamp(dot, -1.0, 1.0)))
		if angle_deg > max_lock_angle_deg:
			continue

		# Score balances angle alignment and distance
		var score := (angle_deg * 2.0) + (dist * 0.4)
		if score < best_score:
			best_score = score
			best_candidate = target_3d

	return best_candidate

func has_lock() -> bool:
	return is_locked and is_instance_valid(current_target) and not current_target.is_queued_for_deletion() and current_target.get("is_destroyed") != true

func get_target_pos() -> Vector3:
	if has_lock():
		return current_target.global_position
	return Vector3.ZERO
