extends Node3D
class_name MotionGizmo

# World-space transform handles, projected to the active 3D viewport.
# Using a separate layer keeps them independent of imported mesh/collider names.
var display: MeshInstance3D
var mesh: ImmediateMesh
var material: StandardMaterial3D
var joint: Node3D
var view_camera: Camera3D
var tool: String = "回転"
var selected_axis: int = -1
var radius: float = 1.0
var radius_pixels: float = 74.0
var gizmo_center: Vector3 = Vector3.ZERO
var available: bool = false
const COLORS := [Color("f36b78"), Color("68d9a1"), Color("65a8ff")]
const HOT := Color("ffe091")

func _ready() -> void:
	mesh = ImmediateMesh.new()
	display = MeshInstance3D.new()
	display.mesh = mesh
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(display)
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = 90
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

func set_state(target: Node3D, camera: Camera3D, kind: String, highlighted: int, show_handles: bool = true) -> void:
	joint = target
	view_camera = camera
	tool = kind
	selected_axis = highlighted
	available = show_handles and is_instance_valid(joint) and is_instance_valid(view_camera)
	draw_handles()

func _axes() -> Array[Vector3]:
	if joint == null:
		return [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var base: Basis = joint.global_transform.basis.orthonormalized()
	if tool == "移動" and joint.get_parent() is Node3D:
		var parent_node: Node3D = joint.get_parent()
		base = parent_node.global_transform.basis.orthonormalized()
	return [base.x.normalized(), base.y.normalized(), base.z.normalized()]

func _plane_vectors(axis: Vector3) -> Array[Vector3]:
	var guide := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.93 else Vector3.RIGHT
	var first: Vector3 = axis.cross(guide).normalized()
	var second: Vector3 = axis.cross(first).normalized()
	return [first, second]

func _calc_radius() -> void:
	gizmo_center = joint.global_position
	var distance: float = view_camera.global_position.distance_to(gizmo_center)
	var height: float = maxf(float(view_camera.get_viewport().size.y), 1.0)
	radius = maxf(0.025, 2.0 * distance * tan(deg_to_rad(view_camera.fov) * 0.5) * radius_pixels / height)

func _draw_thick_segment(a: Vector3, b: Vector3, half_width: float) -> void:
	var direction: Vector3 = (b - a).normalized()
	var toward_eye: Vector3 = (view_camera.global_position - (a + b) * 0.5).normalized()
	var normal: Vector3 = direction.cross(toward_eye)
	if normal.length_squared() < 0.00001:
		normal = direction.cross(Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT)
	normal = normal.normalized() * half_width
	for p in [a - normal, a + normal, b + normal, a - normal, b + normal, b - normal]:
		mesh.surface_add_vertex(p)

func draw_handles() -> void:
	if mesh == null:
		return
	mesh.clear_surfaces()
	if not available:
		return
	_calc_radius()
	var axes := _axes()
	for i in range(3):
		var normal: Vector3 = axes[i]
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
		mesh.surface_set_color(HOT if selected_axis == i else COLORS[i])
		if tool == "回転":
			var dirs := _plane_vectors(normal)
			var prev: Vector3 = gizmo_center + dirs[0] * radius
			for n in range(1, 73):
				var angle: float = TAU * float(n) / 72.0
				var current: Vector3 = gizmo_center + (dirs[0] * cos(angle) + dirs[1] * sin(angle)) * radius
				_draw_thick_segment(prev, current, radius * 0.029)
				prev = current
		else:
			var tip: Vector3 = gizmo_center + normal * radius
			_draw_thick_segment(gizmo_center, tip, radius * 0.036)
			var dirs := _plane_vectors(normal)
			if tool == "移動":
				for sign in [-1.0, 1.0]:
					_draw_thick_segment(tip, tip - normal * radius * 0.22 + dirs[0] * radius * 0.12 * sign, radius * 0.031)
			else:
				for tangent in dirs:
					_draw_thick_segment(tip - tangent * radius * 0.09, tip + tangent * radius * 0.09, radius * 0.033)
		mesh.surface_end()

func _point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var span: Vector2 = b - a
	var denom: float = span.length_squared()
	if denom < 0.000001:
		return p.distance_to(a)
	var factor: float = clampf((p - a).dot(span) / denom, 0.0, 1.0)
	return p.distance_to(a + span * factor)

func hit_test(point: Vector2) -> Dictionary:
	if not available or view_camera == null:
		return {}
	_calc_radius()
	var axes := _axes()
	var best: float = 26.0
	var result: Dictionary = {}
	for i in range(3):
		var axis: Vector3 = axes[i]
		if tool == "回転":
			var directions := _plane_vectors(axis)
			var last: Vector3 = gizmo_center + directions[0] * radius
			for n in range(1, 73):
				var angle: float = TAU * float(n) / 72.0
				var current: Vector3 = gizmo_center + (directions[0] * cos(angle) + directions[1] * sin(angle)) * radius
				if not view_camera.is_position_behind(current) and not view_camera.is_position_behind(last):
					var a: Vector2 = view_camera.unproject_position(last)
					var b: Vector2 = view_camera.unproject_position(current)
					var gap: float = _point_segment_distance(point, a, b)
					if gap < best:
						best = gap
						var tangent: Vector2 = (b - a).normalized()
						result = {"axis": i, "tangent": tangent, "radius_pixels": radius_pixels}
				last = current
		else:
			var endpoint := gizmo_center + axis * radius
			if view_camera.is_position_behind(endpoint):
				continue
			var origin2d: Vector2 = view_camera.unproject_position(gizmo_center)
			var end2d: Vector2 = view_camera.unproject_position(endpoint)
			var gap: float = _point_segment_distance(point, origin2d, end2d)
			# Avoid selecting near the center where all three handles intersect.
			if gap < best and point.distance_to(origin2d) > 12.0:
				best = gap
				result = {"axis": i, "tangent": (end2d - origin2d).normalized(), "radius_pixels": maxf(1.0, origin2d.distance_to(end2d))}
	return result

func axis_local(index: int) -> Vector3:
	match index:
		0: return Vector3.RIGHT
		1: return Vector3.UP
		_: return Vector3.BACK

func translation_per_pixel(index: int) -> float:
	if not available:
		return 0.0
	var axes := _axes()
	var origin2d: Vector2 = view_camera.unproject_position(gizmo_center)
	var endpoint: Vector2 = view_camera.unproject_position(gizmo_center + axes[index])
	return 1.0 / maxf(5.0, (endpoint - origin2d).length())
