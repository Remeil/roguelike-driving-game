class_name TacticalHUD
extends CanvasLayer

@onready var speed_label: Label = $Margin/BottomLeft/VBox/HBoxSpeed/SpeedLabel
@onready var gear_label: Label = $Margin/BottomLeft/VBox/HBoxSpeed/GearLabel
@onready var speed_bar: ProgressBar = $Margin/BottomLeft/VBox/SpeedBar
@onready var boost_bar: ProgressBar = $Margin/BottomLeft/VBox/BoostBar
@onready var boost_label: Label = $Margin/BottomLeft/VBox/HBoxBoost/BoostLabel

@onready var heat_bar: ProgressBar = $Margin/BottomRight/VBox/HeatBar
@onready var heat_label: Label = $Margin/BottomRight/VBox/HBoxGuns/HeatLabel
@onready var missile_bar: ProgressBar = $Margin/BottomRight/VBox/MissileBar
@onready var missile_label: Label = $Margin/BottomRight/VBox/HBoxMissiles/MissileLabel
@onready var oil_bar: ProgressBar = $Margin/BottomRight/VBox/OilBar
@onready var oil_label: Label = $Margin/BottomRight/VBox/HBoxOil/OilLabel

@onready var shield_box: VBoxContainer = $Margin/TopLeft/VBox/ShieldBox
@onready var shield_bar: ProgressBar = $Margin/TopLeft/VBox/ShieldBox/ShieldBar
@onready var shield_label: Label = $Margin/TopLeft/VBox/ShieldBox/ShieldLabel
@onready var health_bar: ProgressBar = $Margin/TopLeft/VBox/HealthBar
@onready var health_label: Label = $Margin/TopLeft/VBox/HealthLabel
@onready var scrap_label: Label = $Margin/TopRight/ScrapLabel
@onready var drift_banner: Label = $Margin/Center/DriftBanner
@onready var objective_box: PanelContainer = $Margin/TopCenter/ObjectiveBox
@onready var objective_title: Label = $Margin/TopCenter/ObjectiveBox/Margin/VBox/HeaderHBox/Title
@onready var objective_reward: Label = $Margin/TopCenter/ObjectiveBox/Margin/VBox/HeaderHBox/RewardTag
@onready var objective_desc: Label = $Margin/TopCenter/ObjectiveBox/Margin/VBox/Desc
@onready var objective_bar: ProgressBar = $Margin/TopCenter/ObjectiveBox/Margin/VBox/ProgressHBox/ProgressBar
@onready var objective_counter: Label = $Margin/TopCenter/ObjectiveBox/Margin/VBox/ProgressHBox/CounterLabel
@onready var mirror_viewport: SubViewport = $Margin/TopCenter/MirrorPanel/VBox/ViewportContainer/SubViewport
@onready var rear_camera: Camera3D = $Margin/TopCenter/MirrorPanel/VBox/ViewportContainer/SubViewport/RearCamera
@onready var threat_status_label: Label = $Margin/TopCenter/MirrorPanel/VBox/ThreatHeader/ThreatStatus

@onready var reticle: Control = $Margin/Reticle
@onready var reticle_box: ReferenceRect = $Margin/Reticle/BoxOutline
@onready var reticle_status: Label = $Margin/Reticle/LockStatus
@onready var volume_toast: Label = $Margin/VolumeToast
@onready var gun_crosshair: Control = $Margin/GunCrosshair

var drift_flash_timer: float = 0.0
var volume_toast_timer: float = 0.0
var threat_warning_beep_timer: float = 0.0
var target_world_pos: Vector3 = Vector3.ZERO
var target_has_lock: bool = false
var has_active_target: bool = false
var active_target_node: Node3D = null
var player_car: ArcadeVehicle = null

func _ready() -> void:
	if mirror_viewport:
		mirror_viewport.world_3d = get_viewport().find_world_3d()

	EventBus.player_speed_changed.connect(_on_speed_changed)
	EventBus.player_gear_changed.connect(_on_gear_changed)
	EventBus.player_boost_changed.connect(_on_boost_changed)
	EventBus.player_health_changed.connect(_on_health_changed)
	EventBus.player_shield_changed.connect(_on_shield_changed)
	EventBus.player_drift_started.connect(_on_drift_started)
	EventBus.player_drift_boost_awarded.connect(_on_drift_boost_awarded)
	EventBus.player_drift_ended.connect(_on_drift_ended)
	EventBus.scrap_collected.connect(_on_scrap_collected)
	EventBus.objective_progress_updated.connect(_on_objective_progress_updated)
	EventBus.player_recovered_from_void.connect(_on_player_recovered_from_void)

	# Milestone 2 Combat signals
	EventBus.weapon_heat_changed.connect(_on_heat_changed)
	EventBus.missile_ammo_changed.connect(_on_missile_ammo_changed)
	EventBus.missile_ammo_restored.connect(_on_missile_ammo_restored)
	EventBus.countermeasure_cooldown_changed.connect(_on_oil_cooldown_changed)
	EventBus.target_acquired.connect(_on_target_acquired)
	EventBus.volume_changed.connect(_on_volume_changed)
	EventBus.weapons_van_approaching.connect(_on_weapons_van_approaching)
	EventBus.weapons_van_docked.connect(_on_weapons_van_docked)
	EventBus.weapons_van_missed.connect(_on_weapons_van_missed)

	drift_banner.visible = false
	reticle.visible = false
	if volume_toast:
		volume_toast.visible = false

	# Initial mission objective
	objective_title.text = "MISSION: PURSUIT & RECON"
	objective_desc.text = "Infiltrate Sector 1 • Collect Scrap • Prepare for Weapons Van"

func _process(delta: float) -> void:
	if drift_flash_timer > 0.0:
		drift_flash_timer -= delta
		if drift_flash_timer <= 0.0:
			drift_banner.visible = false

	if volume_toast_timer > 0.0:
		volume_toast_timer -= delta
		if volume_toast_timer <= 0.0 and volume_toast:
			volume_toast.visible = false

	update_reticle_position()
	update_gun_crosshair()
	update_rear_camera_and_threats(delta)

func update_rear_camera_and_threats(delta: float) -> void:
	if not player_car:
		player_car = get_tree().get_first_node_in_group("player") as ArcadeVehicle
		if not player_car and get_tree().current_scene:
			var car_node := get_tree().current_scene.find_child("PlayerCar", true, false)
			if car_node is ArcadeVehicle:
				player_car = car_node
	if not player_car:
		return

	# 1. Update Rear Camera position & heading
	if rear_camera:
		var car_trans: Transform3D = player_car.global_transform
		rear_camera.global_position = car_trans.origin + (car_trans.basis * Vector3(0.0, 1.45, 0.3))
		# Look 180 degrees backward
		rear_camera.global_transform.basis = car_trans.basis.rotated(Vector3.UP, PI)

	# 2. Threat Radar Scan (find closest pursuer behind player)
	if not threat_status_label:
		return

	var enemies := get_tree().get_nodes_in_group("enemies")
	var closest_dist: float = 999.0
	var closest_enemy: Node3D = null
	var player_fwd: Vector3 = -player_car.global_transform.basis.z
	var player_right: Vector3 = player_car.global_transform.basis.x

	for enemy in enemies:
		if not is_instance_valid(enemy) or not (enemy is Node3D):
			continue
		var to_enemy: Vector3 = enemy.global_position - player_car.global_position
		# Behind check: negative projection along forward vector
		var fwd_dist: float = player_fwd.dot(to_enemy)
		if fwd_dist < 0.0 and fwd_dist > -85.0:
			var dist: float = to_enemy.length()
			if dist < closest_dist:
				closest_dist = dist
				closest_enemy = enemy

	if closest_enemy != null:
		var to_enemy: Vector3 = closest_enemy.global_position - player_car.global_position
		var lateral_dot: float = player_right.dot(to_enemy.normalized())
		var dir_str: String = "▼▼ TAIL"
		if lateral_dot < -0.2:
			dir_str = "◄◄ LEFT"
		elif lateral_dot > 0.2:
			dir_str = "RIGHT ►►"

		var dist_meters: int = int(closest_dist)
		if closest_dist < 22.0:
			# Critical danger: in firing / ramming range
			threat_status_label.text = "⚠ IMMINENT THREAT %s %dM ⚠" % [dir_str, dist_meters]
			var flash: bool = fmod(Time.get_ticks_msec() / 180.0, 2.0) < 1.0
			threat_status_label.modulate = Color(1.0, 0.2, 0.15, 1.0) if flash else Color(1.0, 0.85, 0.2, 1.0)
			
			threat_warning_beep_timer -= delta
			if threat_warning_beep_timer <= 0.0:
				threat_warning_beep_timer = 2.4
				EventBus.sfx_requested.emit("target_acquiring", player_car.global_position)
		else:
			threat_status_label.text = "PURSUIT DETECTED %s %dM" % [dir_str, dist_meters]
			threat_status_label.modulate = Color(1.0, 0.82, 0.2, 1.0)
	else:
		threat_status_label.text = "REAR RADAR // CLEAR"
		threat_status_label.modulate = Color(0.35, 0.85, 0.95, 0.85)

func update_gun_crosshair() -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera or not gun_crosshair:
		return

	if not player_car:
		player_car = get_tree().get_first_node_in_group("player") as ArcadeVehicle
		if not player_car and get_tree().current_scene:
			var car_node := get_tree().current_scene.find_child("PlayerCar", true, false)
			if car_node is ArcadeVehicle:
				player_car = car_node

	if player_car:
		var aim_pos: Vector3 = player_car.global_position + (-player_car.global_transform.basis.z * 48.0) + Vector3(0, 0.5, 0)
		if not camera.is_position_behind(aim_pos):
			var screen_pt: Vector2 = camera.unproject_position(aim_pos)
			gun_crosshair.position = screen_pt - (gun_crosshair.size * 0.5)
			gun_crosshair.visible = true
		else:
			gun_crosshair.visible = false

func update_reticle_position() -> void:
	if not has_active_target or not is_instance_valid(active_target_node) or active_target_node.is_queued_for_deletion() or active_target_node.get("is_destroyed") == true:
		reticle.visible = false
		has_active_target = false
		active_target_node = null
		return

	target_world_pos = active_target_node.global_position + Vector3(0.0, 0.85, 0.0)

	var camera := get_viewport().get_camera_3d()
	if not camera:
		reticle.visible = false
		return

	# Only project if target is in front of camera
	if camera.is_position_behind(target_world_pos):
		reticle.visible = false
		return

	var screen_pos := camera.unproject_position(target_world_pos)
	reticle.position = screen_pos - (reticle.size * 0.5)
	reticle.visible = true

	var is_rival: bool = is_instance_valid(active_target_node) and active_target_node.is_in_group("street_racer")

	if target_has_lock:
		reticle_box.border_color = Color(1.0, 0.2, 0.2, 1.0) # Red locked
		reticle_status.text = "LOCKED: RIVAL" if is_rival else "LOCKED"
		reticle_status.modulate = Color(1.0, 0.25, 0.25, 1.0)
	else:
		reticle_box.border_color = Color(0.2, 0.85, 1.0, 0.85) # Cyan tracking
		reticle_status.text = "TRACKING: RIVAL" if is_rival else "TRACKING"
		reticle_status.modulate = Color(0.3, 0.9, 1.0, 1.0)

func _on_heat_changed(current_heat: float, max_heat: float, is_overheated: bool) -> void:
	heat_bar.max_value = max_heat
	heat_bar.value = current_heat
	
	if is_overheated:
		heat_label.text = "OVERHEAT LOCKOUT!"
		heat_label.modulate = Color(1.0, 0.2, 0.2, 1.0)
	else:
		var pct := int((current_heat / max_heat) * 100.0)
		heat_label.text = "HEAT %d%%" % pct
		if pct > 75:
			heat_label.modulate = Color(1.0, 0.6, 0.2, 1.0)
		else:
			heat_label.modulate = Color(0.3, 0.9, 1.0, 1.0)

func _on_missile_ammo_changed(current_ammo: int, max_ammo: int) -> void:
	missile_bar.max_value = max_ammo
	missile_bar.value = current_ammo
	missile_label.text = "%d / %d" % [current_ammo, max_ammo]
	if current_ammo == 0:
		missile_label.modulate = Color(0.9, 0.3, 0.3, 1.0)
	elif current_ammo < 3:
		missile_label.modulate = Color(1.0, 0.65, 0.2, 1.0)
	else:
		missile_label.modulate = Color(1.0, 0.8, 0.3, 1.0)

func _on_missile_ammo_restored(amount: int, current_total: int) -> void:
	if volume_toast:
		volume_toast.text = "ORDNANCE RESTOCKED // +%d MISSILES" % amount
		volume_toast.modulate = Color(1.0, 0.85, 0.25, 1.0)
		volume_toast.visible = true
		volume_toast_timer = 2.0
	missile_label.modulate = Color(1.0, 0.95, 0.35, 1.0)

func _on_oil_cooldown_changed(time_left: float, max_cooldown: float) -> void:
	oil_bar.max_value = max_cooldown
	# Invert so 0 time left = full bar
	oil_bar.value = max_cooldown - time_left
	if time_left <= 0.01:
		oil_label.text = "READY"
		oil_label.modulate = Color(0.3, 0.95, 0.5, 1.0)
	else:
		oil_label.text = "%.1fs" % time_left
		oil_label.modulate = Color(0.7, 0.75, 0.8, 1.0)

func _on_target_acquired(target_node: Node3D, target_pos: Vector3, has_lock: bool) -> void:
	if not is_instance_valid(target_node) or target_pos == Vector3.ZERO or target_node.is_queued_for_deletion() or target_node.get("is_destroyed") == true:
		has_active_target = false
		active_target_node = null
		reticle.visible = false
	else:
		has_active_target = true
		active_target_node = target_node
		target_world_pos = target_pos + Vector3(0.0, 0.85, 0.0)
		target_has_lock = has_lock

func _on_speed_changed(current_kph: float, max_kph: float) -> void:
	var rounded_speed: int = int(round(current_kph))
	speed_label.text = "%d KPH" % max(0, rounded_speed)
	speed_bar.max_value = max_kph
	speed_bar.value = current_kph

func _on_gear_changed(_gear_idx: int, gear_str: String) -> void:
	if gear_label:
		gear_label.text = " [GEAR %s]" % gear_str
		if gear_str == "R":
			gear_label.modulate = Color(1.0, 0.4, 0.4, 1.0)
		elif gear_str == "N":
			gear_label.modulate = Color(0.7, 0.75, 0.8, 1.0)
		else:
			gear_label.modulate = Color(1.0, 0.85, 0.25, 1.0)

func _on_boost_changed(current_boost: float, max_boost: float) -> void:
	boost_bar.max_value = max_boost
	boost_bar.value = current_boost
	var pct: int = int((current_boost / max_boost) * 100.0)
	boost_label.text = "NITRO %d%%" % pct

func _on_shield_changed(current_shield: float, max_shield: float) -> void:
	if not shield_box:
		return
	if max_shield <= 0.0:
		shield_box.visible = false
		return

	shield_box.visible = true
	shield_bar.max_value = max_shield
	shield_bar.value = current_shield
	var pct: int = int((current_shield / max_shield) * 100.0)
	if pct <= 0:
		shield_label.text = "SHIELD OFFLINE"
		shield_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35, 1.0))
	else:
		shield_label.text = "SHIELD %d%%" % pct
		shield_label.add_theme_color_override("font_color", Color(0.2, 0.85, 1.0, 1.0))

func _on_health_changed(current_hp: float, max_hp: float) -> void:
	health_bar.max_value = max_hp
	health_bar.value = current_hp
	var pct: int = int((current_hp / max_hp) * 100.0)
	health_label.text = "ARMOR %d%%" % pct

func _on_scrap_collected(_amount: int, current_total: int) -> void:
	scrap_label.text = "SCRAP: %d" % current_total

func _on_drift_started() -> void:
	drift_banner.text = "DRIFT"
	drift_banner.modulate = Color(1.0, 0.8, 0.2, 1.0)
	drift_banner.visible = true

func _on_drift_boost_awarded(_bonus_speed: float) -> void:
	pass

func _on_drift_ended() -> void:
	drift_banner.visible = false

func _on_weapons_van_approaching() -> void:
	if volume_toast:
		volume_toast.text = "⚠ WEAPONS VAN RENDEZVOUS // DOCK IN REAR BAY ⚠"
		volume_toast.modulate = Color(0.2, 0.95, 1.0, 1.0)
		volume_toast.visible = true
		volume_toast_timer = 4.0

func _on_weapons_van_docked() -> void:
	if volume_toast:
		volume_toast.text = "✔ DOCKED IN WEAPONS VAN // FIELD SERVICE ENGAGED"
		volume_toast.modulate = Color(0.3, 1.0, 0.5, 1.0)
		volume_toast.visible = true
		volume_toast_timer = 2.5

func _on_weapons_van_missed() -> void:
	if volume_toast:
		volume_toast.text = "WEAPONS VAN MISSED • COMPLETE NEXT OBJECTIVE"
		volume_toast.modulate = Color(1.0, 0.65, 0.25, 1.0)
		volume_toast.visible = true
		volume_toast_timer = 3.0

func _on_player_recovered_from_void() -> void:
	if volume_toast:
		volume_toast.text = "⚠ HIGHWAY RECOVERY // VEHICLE RESET TO ROADWAY ⚠"
		volume_toast.modulate = Color(1.0, 0.45, 0.2, 1.0)
		volume_toast.visible = true
		volume_toast_timer = 3.0

func _on_objective_progress_updated(title: String, desc: String, cur_val: float, target_val: float, unit: String, reward_scrap: int, is_completed: bool) -> void:
	if not objective_title:
		return
	objective_title.text = title
	objective_desc.text = desc
	if objective_reward:
		objective_reward.text = "+%d SCRAP" % reward_scrap
	var ratio: float = clamp(cur_val / max(0.001, target_val), 0.0, 1.0)
	if objective_bar:
		objective_bar.value = ratio

	if not objective_counter:
		return

	if is_completed:
		objective_counter.text = "✔ COMPLETE"
		objective_counter.modulate = Color(0.3, 1.0, 0.5, 1.0)
		if objective_reward:
			objective_reward.modulate = Color(0.3, 1.0, 0.5, 1.0)
		_flash_objective_box(Color(0.25, 1.0, 0.5, 1.0))
	else:
		objective_counter.modulate = Color(0.3, 0.9, 1.0, 1.0)
		if objective_reward:
			objective_reward.modulate = Color(1.0, 0.85, 0.25, 1.0)
		if unit == "s":
			objective_counter.text = "[%.1fs / %.1fs]" % [cur_val, target_val]
		elif unit == "m":
			objective_counter.text = "[%dm / %dm]" % [int(cur_val), int(target_val)]
		else:
			objective_counter.text = "[%d / %d]" % [int(cur_val), int(target_val)]

func _flash_objective_box(flash_color: Color) -> void:
	if not objective_box:
		return
	objective_box.modulate = flash_color
	var tween := create_tween()
	tween.tween_property(objective_box, "modulate", Color(1.0, 1.0, 1.0, 1.0), 1.4)

func _on_volume_changed(volume_pct: int, is_muted: bool) -> void:
	if not volume_toast:
		return
	if is_muted:
		volume_toast.text = "MUTED [M to Unmute]"
		volume_toast.modulate = Color(1.0, 0.35, 0.35, 1.0)
	else:
		volume_toast.text = "VOLUME: %d%% [- / +]" % volume_pct
		volume_toast.modulate = Color(0.3, 0.9, 1.0, 1.0)
	volume_toast.visible = true
	volume_toast_timer = 1.6
