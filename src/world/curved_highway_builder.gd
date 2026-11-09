class_name CurvedHighwayBuilder
extends HighwayChunk

enum CurveMode {
	ARC,
	S_CURVE
}

@export var curve_mode: CurveMode = CurveMode.ARC
@export var curve_angle_deg: float = 0.0
@export var s_curve_amplitude_deg: float = 34.0
@export var subdivisions: int = 40
@export var road_width: float = 18.4

var samples: Array[Dictionary] = []

# Shared materials
var mat_asphalt: StandardMaterial3D
var mat_yellow: StandardMaterial3D
var mat_white: StandardMaterial3D
var mat_guardrail: StandardMaterial3D
var mat_terrain: StandardMaterial3D

func _ready() -> void:
	if curve_mode == CurveMode.ARC:
		heading_delta_deg = curve_angle_deg
	else:
		heading_delta_deg = 0.0 # S-curves have net zero heading change

	setup_materials()
	generate_arc_samples()
	build_highway_geometry()

func setup_materials() -> void:
	mat_asphalt = StandardMaterial3D.new()
	mat_asphalt.albedo_color = Color(0.12, 0.13, 0.15, 1.0)
	mat_asphalt.roughness = 0.88
	mat_asphalt.cull_mode = BaseMaterial3D.CULL_DISABLED

	mat_yellow = StandardMaterial3D.new()
	mat_yellow.albedo_color = Color(1.0, 0.82, 0.12, 1.0)
	mat_yellow.roughness = 0.3
	mat_yellow.emission_enabled = true
	mat_yellow.emission = Color(1.0, 0.8, 0.1, 1.0)
	mat_yellow.emission_energy_multiplier = 0.5
	mat_yellow.cull_mode = BaseMaterial3D.CULL_DISABLED

	mat_white = StandardMaterial3D.new()
	mat_white.albedo_color = Color(0.95, 0.96, 0.98, 1.0)
	mat_white.roughness = 0.3
	mat_white.emission_enabled = true
	mat_white.emission = Color(0.9, 0.92, 0.95, 1.0)
	mat_white.emission_energy_multiplier = 0.35
	mat_white.cull_mode = BaseMaterial3D.CULL_DISABLED

	mat_guardrail = StandardMaterial3D.new()
	mat_guardrail.albedo_color = Color(0.72, 0.74, 0.78, 1.0)
	mat_guardrail.metallic = 0.85
	mat_guardrail.roughness = 0.3
	mat_guardrail.cull_mode = BaseMaterial3D.CULL_DISABLED

	mat_terrain = StandardMaterial3D.new()
	mat_terrain.albedo_color = Color(0.20, 0.38, 0.17, 1.0)
	mat_terrain.roughness = 0.95
	mat_terrain.cull_mode = BaseMaterial3D.CULL_DISABLED

func get_heading_at_t(t: float) -> float:
	if curve_mode == CurveMode.S_CURVE:
		# S-Curve: oscillates left then right (or vice versa), zero net change
		return deg_to_rad(s_curve_amplitude_deg) * sin(2.0 * PI * t)
	else:
		# Standard Arc: constant curvature
		return deg_to_rad(curve_angle_deg) * t

func generate_arc_samples() -> void:
	samples.clear()
	var current_pos := Vector3.ZERO
	var ds: float = chunk_length / float(subdivisions)

	# Sample 0
	samples.append({
		"pos": current_pos,
		"forward": Vector3(0, 0, -1),
		"normal": Vector3(1, 0, 0)
	})

	for i in range(subdivisions):
		var t_mid: float = (float(i) + 0.5) / float(subdivisions)
		var heading: float = get_heading_at_t(t_mid)
		var fwd := Vector3(-sin(heading), 0.0, -cos(heading)).normalized()
		var norm := Vector3(cos(heading), 0.0, -sin(heading)).normalized()
		current_pos += fwd * ds
		samples.append({
			"pos": current_pos,
			"forward": fwd,
			"normal": norm
		})

func build_highway_geometry() -> void:
	var st_road := SurfaceTool.new()
	var st_yellow := SurfaceTool.new()
	var st_white := SurfaceTool.new()
	var st_rails := SurfaceTool.new()
	var st_terrain := SurfaceTool.new()

	st_road.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_yellow.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_white.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_rails.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_terrain.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_w := road_width * 0.5

	# 1. Build Smooth Continuous Geometry
	for i in range(subdivisions):
		var prev_sample: Dictionary = samples[i]
		var next_sample: Dictionary = samples[i + 1]

		var c0: Vector3 = prev_sample.pos
		var n0: Vector3 = prev_sample.normal
		var c1: Vector3 = next_sample.pos
		var n1: Vector3 = next_sample.normal

		# --- Road Surface Quad ---
		var r_l0: Vector3 = c0 - n0 * half_w
		var r_r0: Vector3 = c0 + n0 * half_w
		var r_l1: Vector3 = c1 - n1 * half_w
		var r_r1: Vector3 = c1 + n1 * half_w
		add_quad(st_road, r_l0, r_r0, r_l1, r_r1, Vector3.UP)

		# --- Yellow Double Centerline Quad ---
		var y_w := 0.22
		var y_elev := Vector3(0, 0.035, 0)
		var y_l0: Vector3 = c0 - n0 * y_w + y_elev
		var y_r0: Vector3 = c0 + n0 * y_w + y_elev
		var y_l1: Vector3 = c1 - n1 * y_w + y_elev
		var y_r1: Vector3 = c1 + n1 * y_w + y_elev
		add_quad(st_yellow, y_l0, y_r0, y_l1, y_r1, Vector3.UP)

		# --- White Shoulder Lines ---
		var w_w := 0.16
		var w_elev := Vector3(0, 0.035, 0)
		for side in [-8.2, 8.2]:
			var wl0: Vector3 = c0 + n0 * (side - w_w) + w_elev
			var wr0: Vector3 = c0 + n0 * (side + w_w) + w_elev
			var wl1: Vector3 = c1 + n1 * (side - w_w) + w_elev
			var wr1: Vector3 = c1 + n1 * (side + w_w) + w_elev
			add_quad(st_white, wl0, wr0, wl1, wr1, Vector3.UP)

		# --- Dashed Lane Lines ---
		var dist_along := (float(i) / float(subdivisions)) * chunk_length
		if fmod(dist_along, 16.0) < 9.5:
			var d_w := 0.12
			for side in [-4.1, 4.1]:
				var dl0: Vector3 = c0 + n0 * (side - d_w) + w_elev
				var dr0: Vector3 = c0 + n0 * (side + d_w) + w_elev
				var dl1: Vector3 = c1 + n1 * (side - d_w) + w_elev
				var dr1: Vector3 = c1 + n1 * (side + d_w) + w_elev
				add_quad(st_white, dl0, dr0, dl1, dr1, Vector3.UP)

		# --- Guardrails (Left & Right) ---
		var rail_h_bottom := 0.15
		var rail_h_top := 0.85
		var rail_offset := half_w + 0.15

		var l_bot0: Vector3 = c0 - n0 * rail_offset + Vector3(0, rail_h_bottom, 0)
		var l_top0: Vector3 = c0 - n0 * rail_offset + Vector3(0, rail_h_top, 0)
		var l_bot1: Vector3 = c1 - n1 * rail_offset + Vector3(0, rail_h_bottom, 0)
		var l_top1: Vector3 = c1 - n1 * rail_offset + Vector3(0, rail_h_top, 0)
		add_quad(st_rails, l_bot0, l_top0, l_bot1, l_top1, n0)

		var r_bot0: Vector3 = c0 + n0 * rail_offset + Vector3(0, rail_h_bottom, 0)
		var r_top0: Vector3 = c0 + n0 * rail_offset + Vector3(0, rail_h_top, 0)
		var r_bot1: Vector3 = c1 + n1 * rail_offset + Vector3(0, rail_h_bottom, 0)
		var r_top1: Vector3 = c1 + n1 * rail_offset + Vector3(0, rail_h_top, 0)
		add_quad(st_rails, r_top0, r_bot0, r_top1, r_bot1, -n0)

		# --- Terrain Skirts & Rolling Hills ---
		var d_meadow := 42.0
		var d_crest := 125.0
		var d_outer := 230.0

		var y_road_edge := -0.15
		var y_meadow := -0.45
		var y_crest0: float = 3.8 + 2.4 * sin(c0.z * 0.035)
		var y_crest1: float = 3.8 + 2.4 * sin(c1.z * 0.035)
		var y_outer := 0.8

		# Left side points (c - n * d)
		var l_road0: Vector3 = r_l0 + Vector3(0, y_road_edge, 0)
		var l_road1: Vector3 = r_l1 + Vector3(0, y_road_edge, 0)
		var l_mead0: Vector3 = c0 - n0 * d_meadow + Vector3(0, y_meadow, 0)
		var l_mead1: Vector3 = c1 - n1 * d_meadow + Vector3(0, y_meadow, 0)
		var l_crest0: Vector3 = c0 - n0 * d_crest + Vector3(0, y_crest0, 0)
		var l_crest1: Vector3 = c1 - n1 * d_crest + Vector3(0, y_crest1, 0)
		var l_out0: Vector3 = c0 - n0 * d_outer + Vector3(0, y_outer, 0)
		var l_out1: Vector3 = c1 - n1 * d_outer + Vector3(0, y_outer, 0)

		# Right side points (c + n * d)
		var r_road0: Vector3 = r_r0 + Vector3(0, y_road_edge, 0)
		var r_road1: Vector3 = r_r1 + Vector3(0, y_road_edge, 0)
		var r_mead0: Vector3 = c0 + n0 * d_meadow + Vector3(0, y_meadow, 0)
		var r_mead1: Vector3 = c1 + n1 * d_meadow + Vector3(0, y_meadow, 0)
		var r_crest0: Vector3 = c0 + n0 * d_crest + Vector3(0, y_crest0, 0)
		var r_crest1: Vector3 = c1 + n1 * d_crest + Vector3(0, y_crest1, 0)
		var r_out0: Vector3 = c0 + n0 * d_outer + Vector3(0, y_outer, 0)
		var r_out1: Vector3 = c1 + n1 * d_outer + Vector3(0, y_outer, 0)

		# Left quads (outer to inner)
		add_quad(st_terrain, l_mead0, l_road0, l_mead1, l_road1, Vector3.UP)
		add_quad(st_terrain, l_crest0, l_mead0, l_crest1, l_mead1, Vector3.UP)
		add_quad(st_terrain, l_out0, l_crest0, l_out1, l_crest1, Vector3.UP)

		# Right quads (inner to outer)
		add_quad(st_terrain, r_road0, r_mead0, r_road1, r_mead1, Vector3.UP)
		add_quad(st_terrain, r_mead0, r_crest0, r_mead1, r_crest1, Vector3.UP)
		add_quad(st_terrain, r_crest0, r_out0, r_crest1, r_out1, Vector3.UP)

	# Commit visual meshes
	attach_mesh_instance("RoadMesh", st_road.commit(), mat_asphalt)
	attach_mesh_instance("YellowLineMesh", st_yellow.commit(), mat_yellow)
	attach_mesh_instance("WhiteLineMesh", st_white.commit(), mat_white)
	attach_mesh_instance("GuardrailMesh", st_rails.commit(), mat_guardrail)
	attach_mesh_instance("TerrainMesh", st_terrain.commit(), mat_terrain)

	# Populate roadside low-poly trees along skirts & rolling hills
	build_roadside_trees()

	# 2. Build Solid BoxShape3D Collisions with seamless overlap
	var road_body := StaticBody3D.new()
	road_body.name = "RoadBody"
	road_body.collision_layer = 2 # Ground layer
	road_body.collision_mask = 5

	var rail_body := StaticBody3D.new()
	rail_body.name = "RailBody"
	rail_body.collision_layer = 4 # Obstacle / Wall layer
	rail_body.collision_mask = 5

	var num_coll_boxes: int = 16
	var box_len: float = (chunk_length / float(num_coll_boxes)) + 1.2 # 1.2m overlap prevents any cracks

	for b in range(num_coll_boxes):
		var t_mid: float = (float(b) + 0.5) / float(num_coll_boxes)
		var sample_idx: int = int(round(t_mid * float(subdivisions)))
		sample_idx = clamp(sample_idx, 0, samples.size() - 1)
		var samp: Dictionary = samples[sample_idx]
		var mid_pos: Vector3 = samp.pos
		var mid_fwd: Vector3 = samp.forward
		var mid_norm: Vector3 = samp.normal
		var box_basis := Basis(mid_norm, Vector3.UP, -mid_fwd).orthonormalized()

		# Road Box Collision (1.2m thick solid slab)
		var road_cs := CollisionShape3D.new()
		var road_box := BoxShape3D.new()
		road_box.size = Vector3(road_width + 1.0, 1.2, box_len)
		road_cs.shape = road_box
		road_cs.transform = Transform3D(box_basis, mid_pos + Vector3(0, -0.6, 0))
		road_body.add_child(road_cs)

		# Left Rail Collision Box
		var l_rail_cs := CollisionShape3D.new()
		var l_rail_box := BoxShape3D.new()
		l_rail_box.size = Vector3(0.5, 1.4, box_len)
		l_rail_cs.shape = l_rail_box
		var l_rail_pos: Vector3 = mid_pos - mid_norm * (half_w + 0.25) + Vector3(0, 0.55, 0)
		l_rail_cs.transform = Transform3D(box_basis, l_rail_pos)
		rail_body.add_child(l_rail_cs)

		# Right Rail Collision Box
		var r_rail_cs := CollisionShape3D.new()
		var r_rail_box := BoxShape3D.new()
		r_rail_box.size = Vector3(0.5, 1.4, box_len)
		r_rail_cs.shape = r_rail_box
		var r_rail_pos: Vector3 = mid_pos + mid_norm * (half_w + 0.25) + Vector3(0, 0.55, 0)
		r_rail_cs.transform = Transform3D(box_basis, r_rail_pos)
		rail_body.add_child(r_rail_cs)

	add_child(road_body)
	add_child(rail_body)

	# 3. Setup Local End Transform
	var final_sample: Dictionary = samples.back()
	var fwd: Vector3 = final_sample.forward
	var norm: Vector3 = final_sample.normal
	var end_basis := Basis(norm, Vector3.UP, -fwd).orthonormalized()
	local_end_transform = Transform3D(end_basis, final_sample.pos)

	var end_conn: Marker3D = get_node_or_null("EndConnector")
	if not end_conn:
		end_conn = Marker3D.new()
		end_conn.name = "EndConnector"
		add_child(end_conn)
	end_conn.transform = local_end_transform

func add_quad(st: SurfaceTool, p00: Vector3, p10: Vector3, p01: Vector3, p11: Vector3, norm: Vector3) -> void:
	# Triangle 1 (CCW)
	st.set_normal(norm)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(p00)

	st.set_normal(norm)
	st.set_uv(Vector2(0, 1))
	st.add_vertex(p01)

	st.set_normal(norm)
	st.set_uv(Vector2(1, 0))
	st.add_vertex(p10)

	# Triangle 2 (CCW)
	st.set_normal(norm)
	st.set_uv(Vector2(1, 0))
	st.add_vertex(p10)

	st.set_normal(norm)
	st.set_uv(Vector2(0, 1))
	st.add_vertex(p01)

	st.set_normal(norm)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(p11)

func attach_mesh_instance(node_name: String, mesh: Mesh, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)

## Computes minimum squared distance from world_pos to this chunk's curved centerline spline
func get_distance_to_spline_sq(world_pos: Vector3) -> float:
	if samples.is_empty():
		return global_position.distance_squared_to(world_pos)
	var local_pos: Vector3 = global_transform.affine_inverse() * world_pos
	var min_dist_sq: float = 999999.0
	for s in samples:
		var d_sq: float = s.pos.distance_squared_to(local_pos)
		if d_sq < min_dist_sq:
			min_dist_sq = d_sq
	return min_dist_sq

## Returns road center, forward, right vectors and lane target point
func get_road_info_at_world_pos(world_pos: Vector3, lookahead_m: float = 0.0, lane_offset: float = 0.0) -> Dictionary:
	if samples.is_empty():
		return {
			"position": world_pos,
			"road_center": world_pos,
			"forward": -global_transform.basis.z,
			"right": global_transform.basis.x,
			"sample_index": 0,
			"is_at_end": false
		}

	var local_pos: Vector3 = global_transform.affine_inverse() * world_pos
	var ds: float = chunk_length / float(subdivisions)

	# Find closest sample index
	var closest_idx: int = 0
	var min_dist_sq: float = 999999.0
	for i in range(samples.size()):
		var d_sq: float = samples[i].pos.distance_squared_to(local_pos)
		if d_sq < min_dist_sq:
			min_dist_sq = d_sq
			closest_idx = i

	# Advance by lookahead distance
	var advance_samples: int = int(round(lookahead_m / max(0.1, ds)))
	var target_idx: int = clamp(closest_idx + advance_samples, 0, samples.size() - 1)

	var s: Dictionary = samples[target_idx]
	var world_center: Vector3 = global_transform * s.pos
	var world_fwd: Vector3 = (global_transform.basis * s.forward).normalized()
	var world_right: Vector3 = (global_transform.basis * s.normal).normalized()
	var lane_pt: Vector3 = world_center + (world_right * lane_offset)

	return {
		"position": lane_pt,
		"road_center": world_center,
		"forward": world_fwd,
		"right": world_right,
		"sample_index": target_idx,
		"closest_index": closest_idx,
		"is_at_end": (closest_idx + advance_samples) >= (samples.size() - 1) and advance_samples > 0
	}

static var _shared_tree_mesh: ArrayMesh = null

static func get_or_create_tree_mesh() -> ArrayMesh:
	if _shared_tree_mesh != null:
		return _shared_tree_mesh

	var mat_trunk := StandardMaterial3D.new()
	mat_trunk.albedo_color = Color(0.30, 0.18, 0.11, 1.0)
	mat_trunk.roughness = 0.9

	var mat_foliage := StandardMaterial3D.new()
	mat_foliage.albedo_color = Color(0.13, 0.33, 0.15, 1.0)
	mat_foliage.roughness = 0.85

	# 1. Trunk (Surface 0)
	var st_trunk := SurfaceTool.new()
	st_trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_trunk.set_material(mat_trunk)
	_build_frustum(st_trunk, 0.0, 0.35, 2.8, 0.22, 6, false)
	_shared_tree_mesh = st_trunk.commit()

	# 2. Foliage (Surface 1)
	var st_foliage := SurfaceTool.new()
	st_foliage.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_foliage.set_material(mat_foliage)
	# Tier 1 (lowest)
	_build_frustum(st_foliage, 2.0, 2.2, 4.4, 0.6, 6, true)
	# Tier 2 (middle)
	_build_frustum(st_foliage, 3.8, 1.7, 6.2, 0.4, 6, true)
	# Tier 3 (top cone)
	_build_frustum(st_foliage, 5.4, 1.2, 7.8, 0.0, 6, true)
	st_foliage.commit(_shared_tree_mesh)

	return _shared_tree_mesh

static func _build_frustum(st: SurfaceTool, y_bot: float, r_bot: float, y_top: float, r_top: float, sides: int, add_bottom_cap: bool) -> void:
	for s in range(sides):
		var a0: float = float(s) * TAU / float(sides)
		var a1: float = float(s + 1) * TAU / float(sides)
		var v0 := Vector3(cos(a0) * r_bot, y_bot, sin(a0) * r_bot)
		var v1 := Vector3(cos(a1) * r_bot, y_bot, sin(a1) * r_bot)
		var v2 := Vector3(cos(a1) * r_top, y_top, sin(a1) * r_top)
		var v3 := Vector3(cos(a0) * r_top, y_top, sin(a0) * r_top)

		if r_top <= 0.001:
			var n := (v1 - v0).cross(v2 - v0).normalized()
			st.set_normal(n)
			st.add_vertex(v0)
			st.add_vertex(v1)
			st.add_vertex(v2)
		else:
			var n := (v1 - v0).cross(v3 - v0).normalized()
			st.set_normal(n)
			st.add_vertex(v0)
			st.add_vertex(v1)
			st.add_vertex(v2)

			st.set_normal(n)
			st.add_vertex(v0)
			st.add_vertex(v2)
			st.add_vertex(v3)

		if add_bottom_cap:
			st.set_normal(Vector3.DOWN)
			st.add_vertex(v1)
			st.add_vertex(v0)
			st.add_vertex(Vector3(0, y_bot, 0))

func build_roadside_trees() -> void:
	var tree_transforms: Array[Transform3D] = []
	var half_w := road_width * 0.5

	# Seeded deterministic RNG per chunk
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(int(round(global_position.x)), int(round(global_position.y)), int(round(global_position.z))))

	# Sample along the chunk: every 2 subdivisions
	for i in range(0, samples.size() - 1, 2):
		var samp: Dictionary = samples[i]
		var c: Vector3 = samp.pos
		var n: Vector3 = samp.normal
		var f: Vector3 = samp.forward

		# Left side: near roadside, mid meadow, hillcrest
		_spawn_tree_candidate(rng, tree_transforms, c, n, f, -1.0, rng.randf_range(16.0, 28.0), 0.65, half_w)
		_spawn_tree_candidate(rng, tree_transforms, c, n, f, -1.0, rng.randf_range(32.0, 65.0), 0.70, half_w)
		_spawn_tree_candidate(rng, tree_transforms, c, n, f, -1.0, rng.randf_range(75.0, 125.0), 0.55, half_w)

		# Right side: near roadside, mid meadow, hillcrest
		_spawn_tree_candidate(rng, tree_transforms, c, n, f, 1.0, rng.randf_range(16.0, 28.0), 0.65, half_w)
		_spawn_tree_candidate(rng, tree_transforms, c, n, f, 1.0, rng.randf_range(32.0, 65.0), 0.70, half_w)
		_spawn_tree_candidate(rng, tree_transforms, c, n, f, 1.0, rng.randf_range(75.0, 125.0), 0.55, half_w)

	if tree_transforms.is_empty():
		return

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = get_or_create_tree_mesh()
	multimesh.instance_count = tree_transforms.size()

	for i in range(tree_transforms.size()):
		multimesh.set_instance_transform(i, tree_transforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "TreeMultiMesh"
	mmi.multimesh = multimesh
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)

func _spawn_tree_candidate(rng: RandomNumberGenerator, out_transforms: Array[Transform3D], c: Vector3, n: Vector3, f: Vector3, side: float, dist: float, chance: float, half_w: float) -> void:
	if rng.randf() > chance:
		return

	var fwd_jitter := rng.randf_range(-2.5, 2.5)
	var pos := c + n * (side * dist) + f * fwd_jitter
	pos.y = _get_terrain_y(c.z, dist, half_w)

	var scale_xz := rng.randf_range(0.85, 1.35)
	var scale_y := rng.randf_range(0.9, 1.45) * scale_xz
	var rot_y := rng.randf_range(0.0, TAU)

	var basis := Basis().rotated(Vector3.UP, rot_y).scaled(Vector3(scale_xz, scale_y, scale_xz))
	out_transforms.append(Transform3D(basis, pos))

func _get_terrain_y(cz: float, dist: float, half_w: float) -> float:
	if dist <= 42.0:
		return lerp(-0.15, -0.45, (dist - half_w) / (42.0 - half_w))
	elif dist <= 125.0:
		var crest := 3.8 + 2.4 * sin(cz * 0.035)
		var t := (dist - 42.0) / (125.0 - 42.0)
		return lerp(-0.45, crest, t)
	else:
		var crest := 3.8 + 2.4 * sin(cz * 0.035)
		var t := clampf((dist - 125.0) / (230.0 - 125.0), 0.0, 1.0)
		return lerp(crest, 0.8, t)
