class_name UpgradeManager
extends RefCounted

## Manages the data-driven roguelike boon & upgrade catalog for the Weapons Van
## All upgrades, stats, formulas, and instant actions are 100% defined in the catalog below.
## Any changes to effect values, properties, or targets are automatically reflected in:
## 1. Actual vehicle & weapon stats
## 2. In-game card descriptions (e.g. 150 -> 170 km/h)
## 3. Telemetry bar live diff previews

static var catalog: Array[Dictionary] = [
	{
		"id": "twin_turbo",
		"name": "Overbored Twin-Turbo V8",
		"category": "PROPULSION",
		"cost": 30,
		"level": 0,
		"max_level": 6,
		"color": Color(1.0, 0.45, 0.1, 1.0),
		"effects": [
			{
				"target": "player",
				"property": "top_speed_kph",
				"op": "add",
				"value": 10.0,
				"label": "Base Cruising Speed",
				"unit": "km/h",
				"spec_key": "speed"
			},
			{
				"target": "player",
				"property": "boost_top_speed_kph",
				"op": "add",
				"value": 10.0,
				"label": "Boost Top Speed",
				"unit": "km/h",
				"spec_key": "speed"
			},
		],
		"actions": []
	},
	{
		"id": "dogbox_transmission",
		"name": "Sequential Dog-Box Transmission",
		"category": "DRIVETRAIN",
		"cost": 30,
		"level": 0,
		"max_level": 5,
		"color": Color(0.2, 0.75, 1.0, 1.0),
		"effects": [
			{
				"target": "player",
				"property": "acceleration",
				"op": "add",
				"value": 2.0,
				"label": "Engine Torque",
				"unit": "m/s²",
				"spec_key": "torque"
			},
			{
				"target": "player",
				"property": "drift_speed_bleed",
				"op": "multiply",
				"value": 0.9,
				"min_value": 2.0,
				"label": "Drift Speed Bleed",
				"unit": "m/s²",
				"format_float": true
			}
		],
		"actions": []
	},
	{
		"id": "aegis_shield",
		"name": "Aegis Deflector Grid",
		"category": "DEFENSE",
		"cost": 60,
		"level": 0,
		"max_level": 3,
		"color": Color(0.15, 0.9, 1.0, 1.0),
		"effects": [
			{
				"target": "player",
				"property": "max_shield",
				"op": "add",
				"value": 10.0,
				"label": "Energy Shield",
				"unit": "HP",
				"spec_key": "shield"
			},
			{
				"target": "player",
				"property": "shield_regen_rate",
				"op": "add",
				"value": 2.0,
				"label": "Shield Recharge",
				"unit": "/s"
			}
		],
		"actions": [
			{
				"target": "player",
				"method": "recharge_shield",
				"args": [9999.0],
				"label": "Instant 100% Shield Recharge"
			}
		]
	},
	{
		"id": "chobham_armor",
		"name": "Chobham Composite Plating",
		"category": "SURVIVABILITY",
		"cost": 40,
		"level": 0,
		"max_level": 5,
		"color": Color(0.3, 0.95, 0.5, 1.0),
		"effects": [
			{
				"target": "player",
				"property": "max_health",
				"op": "add",
				"value": 20.0,
				"label": "Max Armor",
				"unit": "HP",
				"spec_key": "armor"
			}
		],
		"actions": [
			{
				"target": "player",
				"method": "repair_health",
				"args": [9999.0],
				"label": "Instant 100% Armor Field Repair"
			}
		]
	},
	{
		"id": "supercharger",
		"name": "Nitro Supercharger",
		"category": "PROPULSION",
		"cost": 55,
		"level": 0,
		"max_level": 5,
		"color": Color(0.2, 0.85, 1.0, 1.0),
		"effects": [
			{
				"target": "player",
				"property": "boost_top_speed_kph",
				"op": "add",
				"value": 15.0,
				"label": "Top Nitro Speed",
				"unit": "km/h",
				"spec_key": "nitro"
			},
			{
				"target": "player",
				"property": "boost_regen_rate",
				"op": "add",
				"value": 1.0,
				"label": "Nitro Fuel Regen",
				"unit": "/s"
			}
		],
		"actions": []
	},
	{
		"id": "expanded_mag",
		"name": "Expanded Ordnance Rack",
		"category": "ORDNANCE",
		"cost": 30,
		"level": 0,
		"max_level": 4,
		"color": Color(1.0, 0.75, 0.2, 1.0),
		"effects": [
			{
				"target": "weapon_system",
				"property": "max_missiles",
				"op": "add",
				"value": 4,
				"label": "Max Missile Capacity",
				"unit": "Missiles",
				"spec_key": "missiles"
			}
		],
		"actions": [
			{
				"target": "weapon_system",
				"method": "add_missiles",
				"args": [4],
				"label": "Instant +4 Missiles Loaded"
			}
		]
	},
	{
		"id": "thermobaric_missiles",
		"name": "Thermobaric Micro-Missiles",
		"category": "ORDNANCE",
		"cost": 65,
		"level": 0,
		"max_level": 3,
		"color": Color(1.0, 0.3, 0.25, 1.0),
		"effects": [
			{
				"target": "weapon_system",
				"property": "missile_damage_bonus",
				"op": "add",
				"value": 30.0,
				"label": "Missile Impact Damage",
				"unit": "DMG",
				"spec_key": "missiles",
				"base_display_offset": 65.0
			}
		],
		"actions": [],
		"extra_text": "+50% Blast Wave Concussion"
	},
	{
		"id": "quad_cannons",
		"name": "Quad Hood Cannons",
		"category": "PRIMARY WEAPONS",
		"cost": 30,
		"level": 0,
		"max_level": 6,
		"color": Color(0.95, 0.45, 0.15, 1.0),
		"effects": [
			{
				"target": "weapon_system",
				"property": "primary_fire_rate",
				"op": "multiply",
				"value": 0.85,
				"min_value": 0.045,
				"label": "Fire Rate",
				"unit": "RPM"
			},
			{
				"target": "weapon_system",
				"property": "cooling_rate",
				"op": "add",
				"value": 6.0,
				"label": "Heat Dissipation",
				"unit": "/s"
			}
		],
		"actions": []
	},
	{
		"id": "kinetic_ram",
		"name": "Heavy Kinetic Ramming Prow",
		"category": "CHASSIS",
		"cost": 40,
		"level": 0,
		"max_level": 4,
		"color": Color(0.85, 0.5, 0.9, 1.0),
		"effects": [
			{
				"target": "player",
				"property": "ram_multiplier",
				"op": "add",
				"value": 0.5,
				"label": "Ramming Power",
				"unit": "x",
				"format_multiplier": true
			},
			{
				"target": "player",
				"property": "ram_recoil_multiplier",
				"op": "multiply",
				"value": 0.80,
				"min_value": 0.2,
				"label": "Self Recoil Damage",
				"unit": "x",
				"format_multiplier": true
			}
		],
		"actions": []
	},
	{
		"id": "slick_spreader",
		"name": "High-Viscosity Oil Spreader",
		"category": "COUNTERMEASURES",
		"cost": 45,
		"level": 0,
		"max_level": 2,
		"color": Color(0.65, 0.65, 0.75, 1.0),
		"effects": [
			{
				"target": "weapon_system",
				"property": "oil_cooldown",
				"op": "add",
				"value": -1.2,
				"min_value": 2.5,
				"label": "Oil Cooldown",
				"unit": "s",
				"format_float": true
			}
		],
		"actions": [],
		"extra_text": "+100% Oil Slick Road Friction Loss"
	},
	{
		"id": "racing_aero",
		"name": "Ground-Effect Aerodynamics",
		"category": "HANDLING",
		"cost": 40,
		"level": 0,
		"max_level": 2,
		"color": Color(0.4, 0.7, 1.0, 1.0),
		"effects": [
			{
				"target": "player",
				"property": "drift_turn_multiplier",
				"op": "add",
				"value": 0.35,
				"label": "Drift Turn Authority",
				"unit": "x",
				"format_multiplier": true
			},
			{
				"target": "player",
				"property": "time_until_normal_grip",
				"op": "multiply",
				"value": 0.70,
				"min_value": 0.25,
				"label": "Grip Recovery Delay",
				"unit": "s",
				"format_float": true
			}
		],
		"actions": []
	},
	{
		"id": "scrap_salvage",
		"name": "Electromagnetic Salvager",
		"category": "ECONOMY",
		"cost": 35,
		"level": 0,
		"max_level": 5,
		"color": Color(1.0, 0.85, 0.3, 1.0),
		"effects": [
			{
				"target": "player",
				"property": "scrap_multiplier",
				"op": "add",
				"value": 0.1,
				"label": "Harvested Scrap",
				"unit": "x",
				"format_multiplier": true
			}
		]
	},
	{
		"id": "aerodynamic_wing",
		"name": "Aerodynamic Wing",
		"category": "AERODYNAMICS",
		"cost": 30,
		"level": 0,
		"max_level": 5,
		"color": Color(0.2, 0.92, 0.82, 1.0),
		"effects": [
			{
				"target": "player",
				"property": "coasting_drag",
				"op": "subtract",
				"value": 4.0,
				"min_value": 2.0,
				"label": "Coasting Drag",
				"unit": "m/s²",
				"format_float": true
			}
		],
		"actions": []
	},
]

static func reset_catalog() -> void:
	for item in catalog:
		item["level"] = 0

static func get_random_draft(count: int = 3) -> Array[Dictionary]:
	var eligible: Array[Dictionary] = []
	for item in catalog:
		if item["level"] < item["max_level"]:
			eligible.append(item.duplicate(true))

	eligible.shuffle()
	var result: Array[Dictionary] = []
	for i in range(min(count, eligible.size())):
		result.append(eligible[i])
	return result

## 100% data-driven upgrade application
static func apply_upgrade(upgrade_id: String, player: ArcadeVehicle) -> bool:
	if not player:
		return false

	var target_item: Dictionary = {}
	for item in catalog:
		if item["id"] == upgrade_id:
			target_item = item
			break

	if target_item.is_empty():
		return false

	target_item["level"] += 1

	var wsys: WeaponSystem = player.get_node_or_null("WeaponSystem") as WeaponSystem
	if not wsys:
		wsys = player.find_child("WeaponSystem", true, false) as WeaponSystem

	# Apply all configured property effects
	var effects: Array = target_item.get("effects", [])
	for eff in effects:
		var target_obj: Object = player if eff.get("target") == "player" else wsys
		if not target_obj:
			continue

		var prop: String = eff.get("property", "")
		var op: String = eff.get("op", "add")
		var val = eff.get("value", 0.0)
		var min_val = eff.get("min_value", null)

		var cur_val = target_obj.get(prop)
		if cur_val != null:
			var new_val = cur_val
			if op == "add":
				new_val = cur_val + val
			elif op == "subtract":
				new_val = cur_val - val
			elif op == "multiply":
				new_val = cur_val * val

			if min_val != null:
				new_val = max(min_val, new_val)

			target_obj.set(prop, new_val)

	# Execute instant actions (field repair, reload, scrap bonuses)
	var actions: Array = target_item.get("actions", [])
	for act in actions:
		var target_obj: Object = player if act.get("target") == "player" else wsys
		if not target_obj:
			continue
		var method_name: String = act.get("method", "")
		var args: Array = act.get("args", [])
		if target_obj.has_method(method_name):
			target_obj.callv(method_name, args)

	EventBus.upgrade_selected.emit(target_item)
	return true

## 100% data-driven dynamic description generator
static func get_dynamic_description(upgrade_id: String, player: ArcadeVehicle) -> String:
	var target_item: Dictionary = {}
	for item in catalog:
		if item["id"] == upgrade_id:
			target_item = item
			break

	if target_item.is_empty():
		return ""

	if not player:
		return target_item.get("name", "")

	var wsys: WeaponSystem = player.get_node_or_null("WeaponSystem") as WeaponSystem
	if not wsys:
		wsys = player.find_child("WeaponSystem", true, false) as WeaponSystem

	var lines: Array[String] = []

	var effects: Array = target_item.get("effects", [])
	for eff in effects:
		var target_obj: Object = player if eff.get("target") == "player" else wsys
		if not target_obj:
			continue

		var prop: String = eff.get("property", "")
		var op: String = eff.get("op", "add")
		var val: float = float(eff.get("value", 0.0))
		var min_val = eff.get("min_value", null)
		var label: String = eff.get("label", prop.capitalize())
		var unit: String = eff.get("unit", "")
		var base_offset: float = float(eff.get("base_display_offset", 0.0))
		var raw_cur: float = float(target_obj.get(prop))

		# Compute next value
		var raw_next: float = raw_cur
		if op == "add":
			raw_next = raw_cur + val
		elif op == "subtract":
			raw_next = raw_cur - val
		elif op == "multiply":
			raw_next = raw_cur * val

		if min_val != null:
			raw_next = max(float(min_val), raw_next)

		# Special display for machine gun RPM:
		if prop == "primary_fire_rate":
			var cur_rpm: int = int(round(60.0 / max(0.001, raw_cur)))
			var next_rpm: int = int(round(60.0 / max(0.001, raw_next)))
			lines.append("+%d%% Fire Rate (%d -> %d RPM)" % [int(round((1.0 - val) * 100.0)), cur_rpm, next_rpm])
		elif eff.get("format_multiplier", false):
			var sign_str: String = "+" if val > 0 else ""
			lines.append("%s%s %s (%.2fx -> %.2fx)" % [sign_str, str(val) if op == "add" else ("%d%%" % int(round((1.0 - val) * 100.0))), label, raw_cur, raw_next])
		elif eff.get("format_float", false):
			var sign_str: String = "+" if (raw_next - raw_cur) > 0 else ""
			var delta_str: String = "%s%.1f %s" % [sign_str, (raw_next - raw_cur), unit]
			lines.append("%s %s (%.1f -> %.1f %s)" % [delta_str, label, raw_cur, raw_next, unit])
		else:
			var disp_cur: int = int(round(raw_cur + base_offset))
			var disp_next: int = int(round(raw_next + base_offset))
			var diff_val: int = disp_next - disp_cur
			var sign_str: String = "+" if diff_val > 0 else ""
			var u_suffix: String = (" " + unit) if unit != "" else ""
			lines.append("%s%d%s %s (%d -> %d%s)" % [sign_str, diff_val, u_suffix, label, disp_cur, disp_next, u_suffix])

	# Add instant actions descriptions
	var actions: Array = target_item.get("actions", [])
	for act in actions:
		var act_label: String = act.get("label", "")
		if act_label != "":
			lines.append(act_label)

	# Extra static notes if any
	var extra: String = target_item.get("extra_text", "")
	if extra != "":
		lines.append(extra)

	return "\n".join(lines)

## 100% data-driven stat diff extractor for HUD telemetry bar
static func get_stat_diffs(upgrade_id: String, player: ArcadeVehicle) -> Dictionary:
	if not player:
		return {}

	var target_item: Dictionary = {}
	for item in catalog:
		if item["id"] == upgrade_id:
			target_item = item
			break

	if target_item.is_empty():
		return {}

	var wsys: WeaponSystem = player.get_node_or_null("WeaponSystem") as WeaponSystem
	if not wsys:
		wsys = player.find_child("WeaponSystem", true, false) as WeaponSystem

	var diffs: Dictionary = {}

	var effects: Array = target_item.get("effects", [])
	for eff in effects:
		var spec_key: String = eff.get("spec_key", "")
		if spec_key == "":
			continue

		var target_obj: Object = player if eff.get("target") == "player" else wsys
		if not target_obj:
			continue

		var prop: String = eff.get("property", "")
		var op: String = eff.get("op", "add")
		var val: float = float(eff.get("value", 0.0))
		var min_val = eff.get("min_value", null)
		var unit: String = eff.get("unit", "")
		var base_offset: float = float(eff.get("base_display_offset", 0.0))
		var cur_val: float = float(target_obj.get(prop))

		var next_val: float = cur_val
		if op == "add":
			next_val = cur_val + val
		elif op == "subtract":
			next_val = cur_val - val
		elif op == "multiply":
			next_val = cur_val * val

		if min_val != null:
			next_val = max(float(min_val), next_val)

		var disp_cur: float = cur_val + base_offset
		var disp_next: float = next_val + base_offset
		var delta_val: float = disp_next - disp_cur
		var sign_str: String = "+" if delta_val > 0 else ""

		var cur_fmt: String = "%.1f" if eff.get("format_float", false) else "%d"
		var delta_fmt: String = "%.1f" if eff.get("format_float", false) else "%d"

		diffs[spec_key] = {
			"current": cur_fmt % disp_cur,
			"next": cur_fmt % disp_next,
			"unit": unit,
			"delta": ("%s" + delta_fmt) % [sign_str, delta_val]
		}

	return diffs
