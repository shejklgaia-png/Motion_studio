extends SceneTree

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var root_scene: PackedScene = load("res://Main.tscn")
	if root_scene == null:
		_fail("No main scene")
		return
	var ui: Control = root_scene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	var gizmo: MotionGizmo = ui.get("motion_gizmo")
	var rig: MotionRig = ui.get("rig")
	var engine: MotionEngine = ui.get("motion")
	var camera: Camera3D = ui.get("camera")
	if gizmo == null or not gizmo.available:
		_fail("Rotation gizmo not visible on initial selected joint")
		return
	var part: String = str(ui.get("selected_part"))
	var joint: Node3D = rig.parts[part]
	var directions: Array[Vector3] = gizmo._plane_vectors(gizmo._axes()[0])
	var point3: Vector3 = joint.global_position + (directions[0] * cos(0.35) + directions[1] * sin(0.35)) * gizmo.radius
	var point2: Vector2 = camera.unproject_position(point3)
	var hit: Dictionary = gizmo.hit_test(point2)
	if hit.is_empty():
		_fail("Could not select circular rotation ring")
		return
	var axis: int = int(hit["axis"])
	var old: float = MotionRig.from_array(engine.sample(0.0)[part]["rotation"])[axis]
	if not bool(ui.call("_start_transform_drag", point2)):
		_fail("Failed to begin drag on ring")
		return
	var direction: Vector2 = hit["tangent"]
	ui.call("_drag_transform", point2 + direction * 45.0)
	var current: float = MotionRig.from_array(engine.sample(0.0)[part]["rotation"])[axis]
	if absf(current - old) < 2.0:
		_fail("Finger drag did not change angle: " + str(current))
		return
	ui.call("_choose_transform", "移動")
	if str(ui.get("active_transform")) != "移動":
		_fail("Cannot switch into move tool")
		return
	ui.call("_choose_transform", "拡縮")
	if str(ui.get("active_transform")) != "拡縮":
		_fail("Cannot switch into scale tool")
		return
	var original_distance: float = float(ui.get("camera_distance"))
	ui.call("_zoom", 0.8)
	if float(ui.get("camera_distance")) >= original_distance:
		_fail("Zoom in did not move camera")
		return
	ui.call("_toggle_view_pan")
	if not bool(ui.get("pan_view")) or gizmo.available:
		_fail("View pan did not disable joint handles")
		return
	var example: MotionRig = MotionRig.new()
	root.add_child(example)
	if example.load_bbmodel("res://tests/sample_blockbench5.bbmodel") != "":
		_fail("Could not read flat-shading fixture")
		return
	var face_normals: Array = []
	for name in example.parts:
		var node: Node3D = example.parts[name]
		for child in node.get_children():
			if child is MeshInstance3D and child.mesh != null:
				var mesh: Mesh = child.mesh
				for index in range(mesh.get_surface_count()):
					var normals: PackedVector3Array = mesh.surface_get_arrays(index)[Mesh.ARRAY_NORMAL]
					if normals.size() >= 3:
						if normals[0].distance_to(normals[1]) > 0.00001 or normals[0].distance_to(normals[2]) > 0.00001:
							_fail("Mesh contains smoothed polygon vertex normals")
							return
						face_normals.append(normals[0])
					var material: BaseMaterial3D = mesh.surface_get_material(index)
					if material.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
						_fail("Mesh material texture uses smoothing")
						return
	if face_normals.size() < 2:
		_fail("No polygon normals emitted for flat-shading test")
		return
	print("MOTION GIZMO PASS: ring drag, move/scale modes, camera zoom/pan, unsmoothed normals")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
