class_name ChaseCamera
extends Camera3D

## NodePath pointing to the player vehicle to follow.
@export var target_path: NodePath

## Camera position offset relative to target vehicle (X: lateral, Y: elevation height, Z: distance behind).
@export var follow_offset: Vector3 = Vector3(0.0, 3.6, 6.8)

## Look-at aim focus offset relative to target vehicle (negative Z points forward down the road).
@export var look_target_offset: Vector3 = Vector3(0.0, 0.4, -6.0)

## Camera position interpolation smoothing rate. Higher = snappier; lower = floatier tracking.
@export var follow_speed: float = 14.0

## Camera rotation interpolation smoothing rate. Higher = locks quickly to vehicle heading.
@export var rotation_speed: float = 12.0

## Camera field of view (FOV) in degrees at standstill and normal cruising speeds.
@export var base_fov: float = 74.0

## Dynamic FOV in degrees reached during Nitro Boost for high-speed tunnel vision sensation.
@export var max_fov: float = 90.0

var target: Node3D = null
var trauma: float = 0.0
var max_shake_offset: Vector3 = Vector3(0.08, 0.08, 0.04)
var noise_time: float = 0.0
var current_pos: Vector3 = Vector3.ZERO

# Live In-Game Camera Presets
var camera_presets: Array[Dictionary] = [
	{
		"name": "High Angle (Elevated - Default)",
		"follow_offset": Vector3(0.0, 3.6, 6.8),
		"look_target_offset": Vector3(0.0, 0.4, -6.0),
		"base_fov": 74.0
	},
	{
		"name": "Tactical High-Cam",
		"follow_offset": Vector3(0.0, 5.2, 8.5),
		"look_target_offset": Vector3(0.0, 0.0, -8.0),
		"base_fov": 76.0
	},
	{
		"name": "Standard Chase",
		"follow_offset": Vector3(0.0, 2.4, 5.8),
		"look_target_offset": Vector3(0.0, 0.8, -4.0),
		"base_fov": 72.0
	},
	{
		"name": "Low & Tight",
		"follow_offset": Vector3(0.0, 1.8, 4.8),
		"look_target_offset": Vector3(0.0, 1.0, -3.0),
		"base_fov": 70.0
	}
]
var current_preset_idx: int = 0

func _ready() -> void:
	if not target_path.is_empty():
		target = get_node_or_null(target_path)
	
	EventBus.camera_shake_requested.connect(_on_camera_shake_requested)
	fov = base_fov

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		# Press 'C' to cycle camera angles live
		if event.keycode == KEY_C:
			current_preset_idx = (current_preset_idx + 1) % camera_presets.size()
			apply_preset(current_preset_idx)
		# Press ']' or PageUp to raise camera height
		elif event.keycode == KEY_BRACKETRIGHT or event.keycode == KEY_PAGEUP:
			follow_offset.y += 0.3
			print("[Camera] Height raised: ", snappedf(follow_offset.y, 0.05), "m | follow_offset = Vector3", follow_offset)
		# Press '[' or PageDown to lower camera height
		elif event.keycode == KEY_BRACKETLEFT or event.keycode == KEY_PAGEDOWN:
			follow_offset.y = max(1.2, follow_offset.y - 0.3)
			print("[Camera] Height lowered: ", snappedf(follow_offset.y, 0.05), "m | follow_offset = Vector3", follow_offset)

func apply_preset(idx: int) -> void:
	var p: Dictionary = camera_presets[idx]
	follow_offset = p.follow_offset
	look_target_offset = p.look_target_offset
	base_fov = p.base_fov
	print("[Camera Preset] Switched to: ", p.name, " (Height: ", follow_offset.y, "m, Distance: ", follow_offset.z, "m)")

func _physics_process(delta: float) -> void:
	if not target:
		return

	# Check Look Behind input (Key 'B', Middle Mouse, or action 'look_behind')
	var is_look_behind: bool = Input.is_action_pressed("look_behind") or Input.is_key_pressed(KEY_B)
	var active_follow_offset: Vector3 = follow_offset
	var active_look_offset: Vector3 = look_target_offset

	if is_look_behind:
		# Mirror camera forward looking backward
		active_follow_offset = Vector3(follow_offset.x, follow_offset.y, -follow_offset.z)
		active_look_offset = Vector3(look_target_offset.x, look_target_offset.y, -look_target_offset.z)

	# Target position in world space
	var target_basis: Basis = target.global_transform.basis
	var desired_pos: Vector3 = target.global_position + (target_basis * active_follow_offset)
	
	# Smoothly interpolate base camera position
	var pos_spd: float = follow_speed * (2.0 if is_look_behind else 1.0)
	if current_pos == Vector3.ZERO:
		current_pos = desired_pos
	else:
		current_pos = current_pos.lerp(desired_pos, pos_spd * delta)

	# Calculate subtle shake offset
	var shake_offset: Vector3 = Vector3.ZERO
	if trauma > 0.0:
		noise_time += delta * 35.0
		var shake_amount: float = trauma * trauma
		shake_offset = Vector3(
			sin(noise_time * 1.1) * max_shake_offset.x * shake_amount,
			cos(noise_time * 1.3) * max_shake_offset.y * shake_amount,
			sin(noise_time * 0.9) * max_shake_offset.z * shake_amount
		)
		trauma = max(0.0, trauma - delta * 3.5)

	global_position = current_pos + shake_offset

	# Target look point ahead of or behind the car
	var look_target: Vector3 = target.global_position + (target_basis * active_look_offset)
	var desired_transform := global_transform.looking_at(look_target, Vector3.UP)
	var rot_spd: float = rotation_speed * (2.5 if is_look_behind else 1.0)
	global_transform.basis = global_transform.basis.slerp(desired_transform.basis, rot_spd * delta)

	# Dynamic FOV based on speed
	if target is ArcadeVehicle:
		var speed_kph: float = target.current_forward_speed * 3.6
		var boost_ratio: float = clamp(speed_kph / target.boost_top_speed_kph, 0.0, 1.0)
		var target_fov: float = lerp(base_fov, max_fov, boost_ratio)
		fov = lerp(fov, target_fov, 8.0 * delta)

func _on_camera_shake_requested(intensity: float, _duration: float) -> void:
	trauma = clamp(trauma + intensity, 0.0, 1.0)
