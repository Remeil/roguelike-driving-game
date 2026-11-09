extends Node

## Global Event Bus for decoupling gameplay systems

# Vehicle / Player Telemetry Signals
signal player_speed_changed(current_speed: float, max_speed: float)
signal player_gear_changed(gear_index: int, gear_label: String)
signal player_boost_changed(current_boost: float, max_boost: float)
signal player_health_changed(current_health: float, max_health: float)
signal player_shield_changed(current_shield: float, max_shield: float)
signal player_drift_started()
signal player_drift_boost_awarded(bonus_speed: float)
signal player_drift_ended()

# Economy Signals
signal scrap_awarded(amount: int)
signal scrap_collected(amount: int, current_total: int)

# Combat & Weapons Signals
signal player_fired_primary(origin: Vector3, direction: Vector3)
signal player_fired_secondary(origin: Vector3, direction: Vector3)
signal player_deployed_countermeasure(origin: Vector3)

signal weapon_heat_changed(current_heat: float, max_heat: float, is_overheated: bool)
signal missile_ammo_changed(current_ammo: int, max_ammo: int)
signal missile_ammo_restored(amount: int, current_total: int)
signal countermeasure_cooldown_changed(time_left: float, max_cooldown: float)
signal target_acquired(target_node: Node3D, target_pos: Vector3, has_lock: bool)
signal explosion_spawned(pos: Vector3, radius: float)

# Audio & Camera Hooks
signal camera_shake_requested(intensity: float, duration: float)
signal sfx_requested(sfx_name: String, pos: Vector3)
signal volume_changed(volume_pct: int, is_muted: bool)

# Roguelike & Mission Signals
signal distance_travelled_changed(distance_meters: float)
signal player_recovered_from_void()
signal objective_updated(title: String, description: String, progress: float, completed: bool)
signal objective_progress_updated(title: String, description: String, current_val: float, target_val: float, unit: String, reward_scrap: int, is_completed: bool)
signal objective_completed(title: String, reward_scrap: int)
signal enemy_destroyed_with_source(enemy_type: String, source: String, pos: Vector3)
signal enemy_spun_out(enemy_node: Node)
signal civilian_traffic_rammed(civilian_node: Node)
signal weapons_van_approaching()
signal weapons_van_docked()
signal weapons_van_missed()
signal upgrade_selected(upgrade_data: Dictionary)
