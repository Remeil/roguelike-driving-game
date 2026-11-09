class_name HighwayChunk
extends Node3D

@export var heading_delta_deg: float = 0.0
@export var chunk_length: float = 120.0

var local_end_transform: Transform3D = Transform3D(Basis(), Vector3(0, 0, -120.0))

func get_end_transform() -> Transform3D:
	# Pure matrix multiplication - 100% immune to scene tree cache latency
	return global_transform * local_end_transform

func get_heading_delta_deg() -> float:
	return heading_delta_deg
