class_name ObjectiveManager
extends Node

## Manages data-driven mission objectives, real-time tracking, scrap payouts, and endless cycling

@export var player: ArcadeVehicle
@export var street_racer_scene: PackedScene = preload("res://src/enemies/street_racer.tscn")

const CATALOG: Array[Dictionary] = [
	{
		"id": "street_race",
		"title": "STREET RACE",
		"desc": "Beat rival racer to 1,200m or destroy them before they escape",
		"type": "street_race",
		"target_val": 1200.0,
		"unit": "m",
		"reward_scrap": 130,
		"reward_scrap_destroy": 60
	},
	{
		"id": "destroy_pursuers",
		"title": "PURSUIT INTERCEPTION",
		"desc": "Eliminate 8 hostile syndicate pursuit interceptors",
		"type": "kill_enemies",
		"target_val": 8.0,
		"unit": "Kills",
		"reward_scrap": 60,
		"source_filter": ""
	},
	{
		"id": "ordnance_strike",
		"title": "TACTICAL ORDNANCE STRIKE",
		"desc": "Score 5 confirmed kills with Lock-On Micro-Missiles",
		"type": "kill_enemies",
		"target_val": 5.0,
		"unit": "Kills",
		"reward_scrap": 70,
		"source_filter": "missile"
	},
	{
		"id": "kinetic_pit",
		"title": "KINETIC PIT MANEUVER",
		"desc": "Ram and obliterate 1 enemy vehicle at high speed",
		"type": "kill_enemies",
		"target_val": 1.0,
		"unit": "Ram Kill",
		"reward_scrap": 75,
		"source_filter": "ram"
	},
	{
		"id": "countermeasure_ambush",
		"title": "COUNTERMEASURE AMBUSH",
		"desc": "Spin out 2 pursuers using deployed Oil Slicks",
		"type": "enemy_spin",
		"target_val": 2.0,
		"unit": "Spun",
		"reward_scrap": 55
	},
	{
		"id": "supersonic_sprint",
		"title": "SUPERSONIC SPRINT",
		"desc": "Maintain top cruising speed (150 km/h) for 6 seconds",
		"type": "high_speed",
		"target_val": 6.0,
		"unit": "s",
		"min_speed_kph": 150.0,
		"reward_scrap": 50
	},
	{
		"id": "ghost_protocol",
		"title": "GHOST PROTOCOL",
		"desc": "Travel 1,200m without colliding with civilian traffic",
		"type": "clean_distance",
		"target_val": 1200.0,
		"unit": "m",
		"reward_scrap": 80
	},
	{
		"id": "highway_advance",
		"title": "HIGHWAY ADVANCE",
		"desc": "Survive hostile pursuit and advance 3,000m",
		"type": "distance",
		"target_val": 3000.0,
		"unit": "m",
		"reward_scrap": 70
	}
]

var active_objective: Dictionary = {}
var current_progress: float = 0.0
var is_completed: bool = false
var completion_cooldown: float = 0.0
var objectives_completed_count: int = 0
var last_emitted_progress: float = -999.0
var previous_objective_id: String = ""
var last_player_z: float = 0.0
var active_racer: StreetRacer = null
var racer_crossed_finish: bool = false
var race_player_distance: float = 0.0

func _ready() -> void:
	if not player:
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0 and players[0] is ArcadeVehicle:
			player = players[0] as ArcadeVehicle

	EventBus.enemy_destroyed_with_source.connect(_on_enemy_destroyed)
	EventBus.enemy_spun_out.connect(_on_enemy_spun_out)
	EventBus.civilian_traffic_rammed.connect(_on_civilian_rammed)
	EventBus.weapons_van_docked.connect(_on_weapons_van_docked)
	EventBus.player_recovered_from_void.connect(_on_player_recovered)

	# Start initial mission
	start_objective_by_id("destroy_pursuers")

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0 and players[0] is ArcadeVehicle:
			player = players[0] as ArcadeVehicle
			last_player_z = player.global_position.z
		return

	# Handle celebration transition timer
	if is_completed:
		completion_cooldown -= delta
		if completion_cooldown <= 0.0:
			pick_next_objective()
		return

	if active_objective.is_empty():
		return

	# Continuous metrics tracking
	var obj_type: String = active_objective.get("type", "")
	var target_val: float = float(active_objective.get("target_val", 1.0))
	var speed_kph: float = player.current_forward_speed * 3.6

	# Calculate distance traveled this frame along forward Z
	var z_delta: float = abs(player.global_position.z - last_player_z)
	last_player_z = player.global_position.z

	match obj_type:
		"high_speed":
			var min_kph: float = float(active_objective.get("min_speed_kph", 150.0))
			if is_instance_valid(player):
				min_kph = player.top_speed_kph
			if speed_kph >= (min_kph - 1.5):
				current_progress += delta
			else:
				# Graceful decay when speed drops below threshold
				current_progress = max(0.0, current_progress - delta * 0.45)
			_maybe_emit_progress(false)

		"drift_time":
			if player.is_drifting and speed_kph > 50.0:
				current_progress += delta
				_maybe_emit_progress(false)

		"distance", "clean_distance":
			if z_delta > 0.0 and z_delta < 50.0: # Filter out respawn teleports
				current_progress += z_delta
				_maybe_emit_progress(false)

		"street_race":
			_process_street_race(delta, z_delta)

	# Check completion threshold
	if obj_type != "street_race" and current_progress >= target_val and not is_completed:
		complete_objective()

func start_objective_by_id(id: String) -> void:
	for item in CATALOG:
		if item["id"] == id:
			_activate_objective(item.duplicate(true))
			return
	if CATALOG.size() > 0:
		_activate_objective(CATALOG[0].duplicate(true))

func pick_next_objective() -> void:
	var pool: Array[Dictionary] = []
	for item in CATALOG:
		if item["id"] != previous_objective_id:
			pool.append(item)

	if pool.is_empty():
		pool = CATALOG

	var chosen: Dictionary = pool.pick_random().duplicate(true)
	_activate_objective(chosen)

func _activate_objective(obj: Dictionary) -> void:
	if is_instance_valid(active_racer):
		active_racer.queue_free()
		active_racer = null

	active_objective = obj
	previous_objective_id = obj.get("id", "")
	current_progress = 0.0
	is_completed = false
	completion_cooldown = 0.0
	last_emitted_progress = -999.0
	racer_crossed_finish = false
	race_player_distance = 0.0

	if is_instance_valid(player):
		last_player_z = player.global_position.z

	if obj.get("type", "") == "high_speed":
		var target_kph: float = 150.0
		if is_instance_valid(player):
			target_kph = round(player.top_speed_kph)
		obj["min_speed_kph"] = target_kph
		obj["desc"] = "Maintain top cruising speed (%d km/h) for 6 seconds" % int(target_kph)

	if obj.get("type", "") == "street_race":
		_spawn_street_racer()

	_emit_objective_update(false)

func complete_objective() -> void:
	if is_completed:
		return
	is_completed = true
	completion_cooldown = 2.8
	objectives_completed_count += 1
	var reward: int = int(active_objective.get("reward_scrap", 60))
	var title: String = active_objective.get("title", "OBJECTIVE")

	# Payout bulk scrap
	EventBus.scrap_awarded.emit(reward)
	EventBus.objective_completed.emit(title, reward)

	var sound_pos: Vector3 = player.global_position if is_instance_valid(player) else Vector3.ZERO
	EventBus.sfx_requested.emit("objective_complete", sound_pos)
	EventBus.camera_shake_requested.emit(0.22, 0.20)

	_emit_objective_update(true)

func _maybe_emit_progress(force: bool) -> void:
	var delta_prog: float = abs(current_progress - last_emitted_progress)
	var target_val: float = float(active_objective.get("target_val", 1.0))
	# Throttle emission to avoid spamming signals every frame
	if force or delta_prog >= (target_val * 0.02) or current_progress >= target_val:
		_emit_objective_update(false)

func _emit_objective_update(completed: bool) -> void:
	if active_objective.is_empty():
		return
	var title: String = active_objective.get("title", "")
	var desc: String = active_objective.get("desc", "")
	var target_val: float = float(active_objective.get("target_val", 1.0))
	var unit: String = active_objective.get("unit", "")
	var reward: int = int(active_objective.get("reward_scrap", 60))
	var ratio: float = clamp(current_progress / max(0.001, target_val), 0.0, 1.0)

	last_emitted_progress = current_progress

	# Broadcast to tactical HUD
	EventBus.objective_progress_updated.emit(
		title,
		desc,
		current_progress,
		target_val,
		unit,
		reward,
		completed
	)

	var hud_desc := desc
	if completed:
		hud_desc = "✔ OBJECTIVE COMPLETED! +%d SCRAP AWARDED" % reward
	else:
		if unit == "s":
			hud_desc = "%s (%.1fs / %.1fs) • [+%d SCRAP]" % [desc, current_progress, target_val, reward]
		elif unit == "m":
			hud_desc = "%s (%dm / %dm) • [+%d SCRAP]" % [desc, int(current_progress), int(target_val), reward]
		else:
			hud_desc = "%s (%d / %d %s) • [+%d SCRAP]" % [desc, int(current_progress), int(target_val), unit, reward]

	EventBus.objective_updated.emit(title, hud_desc, ratio, completed)

func _on_enemy_destroyed(enemy_type: String, source: String, _pos: Vector3) -> void:
	if is_completed or active_objective.is_empty():
		return

	if active_objective.get("type", "") == "street_race":
		if enemy_type == "street_racer" or (is_instance_valid(active_racer) and active_racer.is_destroyed):
			var kill_reward: int = int(active_objective.get("reward_scrap_destroy", 60))
			complete_custom_objective("STREET RACE (TAKEDOWN)", kill_reward, "✔ RIVAL ELIMINATED! TAKEDOWN (+%d SCRAP)" % kill_reward)
			return

	if active_objective.get("type", "") == "kill_enemies":
		var filter: String = active_objective.get("source_filter", "")
		if filter == "" or filter == source:
			current_progress += 1.0
			_emit_objective_update(false)
			if current_progress >= float(active_objective.get("target_val", 1.0)):
				complete_objective()

func _on_enemy_spun_out(_enemy_node: Node) -> void:
	if is_completed or active_objective.is_empty():
		return

	if active_objective.get("type", "") == "enemy_spin":
		current_progress += 1.0
		_emit_objective_update(false)
		if current_progress >= float(active_objective.get("target_val", 1.0)):
			complete_objective()

func _on_civilian_rammed(_civilian_node: Node) -> void:
	if is_completed or active_objective.is_empty():
		return

	if active_objective.get("type", "") == "clean_distance":
		# Civilian traffic collided: penalty resets streak!
		if current_progress > 15.0:
			current_progress = 0.0
			EventBus.sfx_requested.emit("weapon_dry", player.global_position if is_instance_valid(player) else Vector3.ZERO)
			_emit_objective_update(false)

func _on_weapons_van_docked() -> void:
	if is_instance_valid(active_racer):
		active_racer.queue_free()
		active_racer = null

	if is_completed or active_objective.is_empty():
		return

	if active_objective.get("type", "") == "van_dock":
		current_progress += 1.0
		_emit_objective_update(false)
		if current_progress >= float(active_objective.get("target_val", 1.0)):
			complete_objective()

func _on_player_recovered() -> void:
	if is_instance_valid(player):
		last_player_z = player.global_position.z
	if is_completed or active_objective.is_empty():
		return
	if active_objective.get("type", "") == "clean_distance":
		current_progress = 0.0
	_emit_objective_update(false)

# =========================================================================
# STREET RACE MECHANICS
# =========================================================================

func _spawn_street_racer() -> void:
	if not street_racer_scene or not is_instance_valid(player) or not HighwayManager.instance:
		return

	var player_x: float = player.global_position.x
	var target_lane: float = HighwayManager.LANE_LEFT_CRUISE if player_x >= 0.0 else HighwayManager.LANE_RIGHT_CRUISE
	var spawn_dist: float = 14.0

	var road_info: Dictionary = HighwayManager.instance.get_road_transform(player.global_position, spawn_dist, target_lane)
	var spawn_pos: Vector3 = road_info.get("position", Vector3.ZERO)
	if spawn_pos == Vector3.ZERO:
		spawn_pos = player.global_position - player.global_transform.basis.z * spawn_dist

	# Crucial: elevate by +0.5m so vehicle collision starts cleanly above asphalt
	spawn_pos.y = player.global_position.y + 0.5

	var fwd: Vector3 = road_info.get("forward", -player.global_transform.basis.z)
	var right: Vector3 = road_info.get("right", player.global_transform.basis.x)

	var racer: StreetRacer = street_racer_scene.instantiate() as StreetRacer
	if not racer:
		return

	racer.current_lane_offset = target_lane
	racer.target_lane_offset = target_lane
	racer.current_forward_speed = max(player.current_forward_speed + 1.0, 32.0)

	player.get_parent().add_child(racer)
	racer.global_transform = Transform3D(Basis(right, Vector3.UP, -fwd).orthonormalized(), spawn_pos)

	active_racer = racer
	EventBus.sfx_requested.emit("turbo_surge", racer.global_position)

func _process_street_race(_delta: float, z_delta: float) -> void:
	if not is_instance_valid(active_racer) or active_racer.is_queued_for_deletion():
		if not is_completed:
			# Racer eliminated or knocked off highway: complete with takedown reward!
			var kill_reward: int = int(active_objective.get("reward_scrap_destroy", 60))
			complete_custom_objective("STREET RACE (TAKEDOWN)", kill_reward, "✔ RIVAL ELIMINATED! (+%d SCRAP)" % kill_reward)
		return

	if active_racer.is_destroyed:
		return

	if z_delta > 0.0 and z_delta < 50.0:
		race_player_distance += z_delta
		current_progress = race_player_distance

	var target_val: float = float(active_objective.get("target_val", 1200.0))
	var to_racer: Vector3 = active_racer.global_position - player.global_position
	var forward_lead: float = (-player.global_transform.basis.z).dot(to_racer)
	var gap: float = to_racer.length()

	# Check if rival crossed finish line first
	if active_racer.race_distance_traveled >= target_val and not racer_crossed_finish:
		racer_crossed_finish = true
		EventBus.sfx_requested.emit("overheat_warning", player.global_position)

	# Win Condition: Player crosses 1,200m first (or while ahead)
	if race_player_distance >= target_val and not is_completed:
		if not racer_crossed_finish or forward_lead <= 0.0:
			var win_reward: int = int(active_objective.get("reward_scrap", 130))
			complete_custom_objective("STREET RACE (1ST PLACE)", win_reward, "✔ RACE WON! 1ST PLACE (+%d SCRAP)" % win_reward)
			if is_instance_valid(active_racer):
				active_racer.retire()
			return

	# Escape threshold: if rival pulls >300m away ahead of player, race is lost!
	if not is_completed and forward_lead > 0.0 and gap >= 300.0:
		_fail_street_race()
		return

	_emit_street_race_update(forward_lead, target_val)

func _emit_street_race_update(forward_lead: float, target_val: float) -> void:
	if active_objective.is_empty():
		return

	var title: String = active_objective.get("title", "STREET RACE")
	var win_reward: int = int(active_objective.get("reward_scrap", 130))
	var kill_reward: int = int(active_objective.get("reward_scrap_destroy", 60))
	var ratio: float = clamp(current_progress / max(0.001, target_val), 0.0, 1.0)

	var hud_desc: String = ""
	if racer_crossed_finish:
		var gap: int = int(player.global_position.distance_to(active_racer.global_position)) if is_instance_valid(active_racer) else 0
		hud_desc = "⚠ RACER ESCAPING! DESTROY BEFORE 300m GAP (%dm / 300m) • [+%d SCRAP]" % [gap, kill_reward]
		ratio = clamp(float(gap) / 300.0, 0.0, 1.0)
	elif forward_lead <= 0.0:
		var lead_m: int = int(-forward_lead)
		hud_desc = "1ST PLACE (LEAD +%dm) • SPRINT: %dm / %dm • [+%d SCRAP]" % [lead_m, int(current_progress), int(target_val), win_reward]
	else:
		var gap_m: int = int(forward_lead)
		hud_desc = "2ND PLACE (GAP -%dm) • SPRINT: %dm / %dm • [WIN: +%d / KILL: +%d]" % [gap_m, int(current_progress), int(target_val), win_reward, kill_reward]

	EventBus.objective_progress_updated.emit(
		title,
		hud_desc,
		current_progress,
		target_val,
		"m",
		kill_reward if racer_crossed_finish else win_reward,
		false
	)
	EventBus.objective_updated.emit(title, hud_desc, ratio, false)

func complete_custom_objective(title_override: String, scrap_amount: int, celebration_msg: String) -> void:
	if is_completed:
		return
	is_completed = true
	completion_cooldown = 3.2
	objectives_completed_count += 1

	EventBus.scrap_awarded.emit(scrap_amount)
	EventBus.objective_completed.emit(title_override, scrap_amount)

	var sound_pos: Vector3 = player.global_position if is_instance_valid(player) else Vector3.ZERO
	EventBus.sfx_requested.emit("objective_complete", sound_pos)
	EventBus.camera_shake_requested.emit(0.26, 0.22)

	EventBus.objective_progress_updated.emit(
		title_override,
		celebration_msg,
		float(active_objective.get("target_val", 1200.0)),
		float(active_objective.get("target_val", 1200.0)),
		"m",
		scrap_amount,
		true
	)
	EventBus.objective_updated.emit(title_override, celebration_msg, 1.0, true)

func _fail_street_race() -> void:
	if is_completed:
		return
	is_completed = true
	completion_cooldown = 2.6
	if is_instance_valid(active_racer):
		active_racer.queue_free()
		active_racer = null

	EventBus.sfx_requested.emit("weapon_dry", player.global_position if is_instance_valid(player) else Vector3.ZERO)

	var fail_msg: String = "✖ RIVAL ESCAPED (>300m)! RACE LOST"
	EventBus.objective_progress_updated.emit(
		"STREET RACE (FAILED)",
		fail_msg,
		0.0,
		float(active_objective.get("target_val", 1200.0)),
		"m",
		0,
		false
	)
	EventBus.objective_updated.emit("STREET RACE (FAILED)", fail_msg, 0.0, false)
