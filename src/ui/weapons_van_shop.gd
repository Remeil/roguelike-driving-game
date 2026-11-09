class_name WeaponsVanShop
extends CanvasLayer

## Tactical Roguelike Upgrade Shop presented when docked inside the Weapons Van

signal closed(depart_now: bool)

var player_car: ArcadeVehicle = null
var current_draft: Array[Dictionary] = []

@onready var panel_root: Control = $ShopRoot
@onready var scrap_label: Label = $ShopRoot/MainPanel/HeaderMargin/HBox/ScrapLabel
@onready var card_container: HBoxContainer = $ShopRoot/MainPanel/CardMargin/CardsHBox
@onready var specs_hbox: HBoxContainer = $ShopRoot/MainPanel/SpecsMargin/Panel/Margin/SpecsHBox
@onready var reroll_btn: Button = $ShopRoot/MainPanel/FooterMargin/HBox/RerollButton
@onready var launch_btn: Button = $ShopRoot/MainPanel/FooterMargin/HBox/LaunchButton
@onready var toast_label: Label = $ShopRoot/MainPanel/ToastLabel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if reroll_btn:
		reroll_btn.pressed.connect(_on_reroll_pressed)
	if launch_btn:
		launch_btn.pressed.connect(_on_launch_pressed)

func open_shop(player: ArcadeVehicle) -> void:
	player_car = player
	visible = true
	toast_label.visible = false
	refresh_draft()
	update_scrap_display()
	update_specs_display()

func refresh_draft() -> void:
	current_draft = UpgradeManager.get_random_draft(3)
	render_cards()
	update_specs_display()

func update_scrap_display() -> void:
	if not player_car:
		return
	scrap_label.text = "SCRAP: %d" % player_car.current_scrap

func render_cards() -> void:
	# Clear existing children in container
	for child in card_container.get_children():
		child.queue_free()

	if current_draft.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "ALL UPGRADES AT MAXIMUM LEVEL"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_container.add_child(empty_lbl)
		return

	for i in range(current_draft.size()):
		var item: Dictionary = current_draft[i]
		var card: PanelContainer = create_upgrade_card(item, i)
		card_container.add_child(card)

func create_upgrade_card(item: Dictionary, card_idx: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(280, 360)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.12, 0.95)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = item.get("color", Color(0.3, 0.8, 1.0, 1.0))
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", sb)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# Hotkey / Category Header
	var cat_lbl := Label.new()
	cat_lbl.text = "[%d] %s" % [card_idx + 1, item.get("category", "SYSTEM")]
	cat_lbl.modulate = item.get("color", Color(0.3, 0.8, 1.0))
	cat_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(cat_lbl)

	# Title
	var title_lbl := Label.new()
	title_lbl.text = item.get("name", "Unknown Upgrade")
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title_lbl)

	# Level pill
	var lvl_lbl := Label.new()
	lvl_lbl.text = "LEVEL %d / %d" % [item.get("level", 0), item.get("max_level", 1)]
	lvl_lbl.modulate = Color(0.7, 0.75, 0.8)
	lvl_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(lvl_lbl)

	# Separator line
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Description (dynamically formatted with live player stats)
	var desc_lbl := Label.new()
	desc_lbl.text = UpgradeManager.get_dynamic_description(item.get("id", ""), player_car)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(desc_lbl)

	# Buy Button
	var buy_btn := Button.new()
	var cost: int = item.get("cost", 50)
	var can_afford: bool = player_car and player_car.current_scrap >= cost
	buy_btn.text = "INSTALL [%d SCRAP]" % cost
	buy_btn.disabled = not can_afford
	buy_btn.custom_minimum_size = Vector2(0, 44)
	buy_btn.pressed.connect(func() -> void:
		_on_buy_upgrade(item)
	)
	vbox.add_child(buy_btn)

	# Hover & Focus signals for dynamic stat diff preview
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.mouse_entered.connect(func() -> void:
		_on_card_hovered(item, panel)
	)
	panel.mouse_exited.connect(func() -> void:
		_on_card_unhovered(panel, item.get("color", Color(0.3, 0.8, 1.0, 1.0)))
	)
	buy_btn.mouse_entered.connect(func() -> void:
		_on_card_hovered(item, panel)
	)
	buy_btn.focus_entered.connect(func() -> void:
		_on_card_hovered(item, panel)
	)
	buy_btn.focus_exited.connect(func() -> void:
		_on_card_unhovered(panel, item.get("color", Color(0.3, 0.8, 1.0, 1.0)))
	)

	return panel

func _on_card_hovered(item: Dictionary, panel: PanelContainer) -> void:
	if not player_car:
		return
	# Highlight card outline
	var sb := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sb:
		sb.border_width_left = 3
		sb.border_width_top = 3
		sb.border_width_right = 3
		sb.border_width_bottom = 3
		sb.border_color = Color(1.0, 1.0, 1.0, 1.0)

	var diffs: Dictionary = UpgradeManager.get_stat_diffs(item.get("id", ""), player_car)
	update_specs_display(diffs)

func _on_card_unhovered(panel: PanelContainer, default_color: Color) -> void:
	# Restore card outline
	var sb := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sb:
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.border_color = default_color

	update_specs_display()

func update_specs_display(diffs: Dictionary = {}) -> void:
	if not specs_hbox or not player_car:
		return

	# Clear existing stat boxes
	for child in specs_hbox.get_children():
		child.queue_free()

	var wsys: WeaponSystem = player_car.get_node_or_null("WeaponSystem") as WeaponSystem
	if not wsys:
		wsys = player_car.find_child("WeaponSystem", true, false) as WeaponSystem

	var spec_defs: Array[Dictionary] = [
		{
			"key": "speed",
			"title": "CRUISE SPEED",
			"base_val": "%d km/h" % int(player_car.top_speed_kph),
			"unit": "km/h"
		},
		{
			"key": "torque",
			"title": "ENGINE TORQUE",
			"base_val": "%d m/s²" % int(player_car.acceleration),
			"unit": "m/s²"
		},
		{
			"key": "armor",
			"title": "MAX ARMOR",
			"base_val": "%d HP" % int(player_car.max_health),
			"unit": "HP"
		},
		{
			"key": "shield",
			"title": "DEFLECTOR SHIELD",
			"base_val": "%d HP" % int(player_car.max_shield),
			"unit": "HP"
		},
		{
			"key": "missiles",
			"title": "MISSILE RACK",
			"base_val": "%d CAP" % (wsys.max_missiles if wsys else 8),
			"unit": "CAP"
		},
		{
			"key": "nitro",
			"title": "NITRO BOOST",
			"base_val": "%d km/h" % int(player_car.boost_top_speed_kph),
			"unit": "km/h"
		}
	]

	for spec in spec_defs:
		var block := VBoxContainer.new()
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		block.alignment = BoxContainer.ALIGNMENT_CENTER

		var title_lbl := Label.new()
		title_lbl.text = spec["title"]
		title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_lbl.add_theme_font_size_override("font_size", 11)

		var val_lbl := Label.new()
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val_lbl.add_theme_font_size_override("font_size", 14)

		if diffs.has(spec["key"]):
			var d: Dictionary = diffs[spec["key"]]
			title_lbl.modulate = Color(0.3, 0.9, 1.0)
			val_lbl.text = "%s → %s %s" % [d["current"], d["next"], d["unit"]]
			val_lbl.modulate = Color(0.25, 1.0, 0.55) # Bright green diff indicator!
		else:
			title_lbl.modulate = Color(0.55, 0.62, 0.7)
			val_lbl.text = spec["base_val"]
			val_lbl.modulate = Color(0.85, 0.9, 0.95)

		block.add_child(title_lbl)
		block.add_child(val_lbl)
		specs_hbox.add_child(block)

func _on_buy_upgrade(item: Dictionary) -> void:
	if not player_car:
		return

	var cost: int = item.get("cost", 50)
	if not player_car.spend_scrap(cost):
		show_toast("INSUFFICIENT SCRAP", Color(1.0, 0.3, 0.3))
		return

	UpgradeManager.apply_upgrade(item.get("id", ""), player_car)
	EventBus.sfx_requested.emit("upgrade_bought", player_car.global_position)
	show_toast("%s INSTALLED!" % item.get("name", "UPGRADE"), Color(0.3, 0.95, 0.5))
	update_scrap_display()
	refresh_draft()

func _on_reroll_pressed() -> void:
	if not player_car:
		return
	const REROLL_COST: int = 25
	if not player_car.spend_scrap(REROLL_COST):
		show_toast("REROLL REQUIRES 25 SCRAP", Color(1.0, 0.3, 0.3))
		return

	EventBus.sfx_requested.emit("gear_shift", player_car.global_position)
	update_scrap_display()
	refresh_draft()

func _on_launch_pressed() -> void:
	close_shop()

func close_shop() -> void:
	visible = false
	closed.emit(true)

func show_toast(msg: String, col: Color) -> void:
	toast_label.text = msg
	toast_label.modulate = col
	toast_label.visible = true
	var tween := create_tween().bind_node(self)
	tween.tween_interval(1.8)
	tween.tween_callback(func() -> void:
		if is_instance_valid(toast_label):
			toast_label.visible = false
	)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1 and current_draft.size() > 0:
			_on_buy_upgrade(current_draft[0])
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_2 and current_draft.size() > 1:
			_on_buy_upgrade(current_draft[1])
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_3 and current_draft.size() > 2:
			_on_buy_upgrade(current_draft[2])
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R:
			_on_reroll_pressed()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_W:
			_on_launch_pressed()
			get_viewport().set_input_as_handled()
