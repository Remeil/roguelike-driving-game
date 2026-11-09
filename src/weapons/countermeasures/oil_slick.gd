class_name OilSlick
extends Area3D

@export var lifetime: float = 12.0
@export var slip_factor: float = 0.15

var timer: float = 0.0
var slick_material: StandardMaterial3D = null
@onready var mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	EventBus.sfx_requested.emit("oil_slick_deploy", global_position)
	
	if mesh and mesh.mesh and mesh.mesh.material is StandardMaterial3D:
		slick_material = mesh.mesh.material.duplicate()
		mesh.material_override = slick_material

func _process(delta: float) -> void:
	timer += delta
	# Fade out during the last 2 seconds
	if timer > (lifetime - 2.0):
		var fade := (lifetime - timer) / 2.0
		if slick_material:
			slick_material.albedo_color.a = clamp(fade, 0.0, 1.0)
	
	if timer >= lifetime:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	# Ignore player car
	if body is ArcadeVehicle:
		return

	if body.has_method("spin_out"):
		body.spin_out(slip_factor)
	elif body.has_method("apply_oil_slip"):
		body.apply_oil_slip(slip_factor)
