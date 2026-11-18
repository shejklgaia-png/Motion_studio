extends SceneTree

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var scene: PackedScene = load("res://Main.tscn")
	if scene == null:
		_fail("Missing Main scene")
		return
	var app: Control = scene.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	app.call("_change_mode", "IK")
	await process_frame
	var gizmo: MotionGizmo = app.get("motion_gizmo")
	var rig: MotionRig = app.get("rig")
	var cam: Camera3D = app.get("camera")
	var engine: MotionEngine = app.get("motion")
	if gizmo == null or not gizmo.available or gizmo.tool != "移動":
		_fail("IK mode did not show the target translation axes")
		return
	var chain: Dictionary = rig.chains[0]
	if gizmo.joint != chain["target"]:
		_fail("IK handle was not anchored to selected goal")
		return
	chain["enabled"] = true
	chain["method"] = "2ボーン"
	engine.evaluate(engine.play_time)
	var chosen: Dictionary = {}
	var chosen_point: Vector2
	for axis in range(3):
		var p0: Vector3 = chain["target"].global_position
		var p1: Vector3 = p0 + gizmo._axes()[axis] * gizmo.radius * 0.82
		if cam.is_position_behind(p1):
			continue
		var point: Vector2 = cam.unproject_position(p1)
		var hit: Dictionary = gizmo.hit_test(point)
		if not hit.is_empty() and int(hit["axis"]) == axis:
			chosen = hit
			chosen_point = point
			break
	if chosen.is_empty():
		_fail("Could not find accessible touch target on IK gizmo")
		return
	var moving_axis: int = int(chosen["axis"])
	var old_goal: Vector3 = chain["target"].global_position
	if not bool(app.call("_start_transform_drag", chosen_point)):
		_fail("Could not initiate IK handle drag")
		return
	var tangent: Vector2 = chosen["tangent"]
	app.call("_drag_transform", chosen_point + tangent * 40.0)
	var new_goal: Vector3 = chain["target"].global_position
	if absf(new_goal[moving_axis] - old_goal[moving_axis]) < 0.02:
		_fail("Finger drag did not change IK goal")
		return
	for axis in range(3):
		if axis != moving_axis and absf(new_goal[axis] - old_goal[axis]) > 0.0001:
			_fail("Finger drag changed the wrong world-space axis")
			return
	app.call("_finish_pointer_drag")
	await process_frame
	if int(app.get("drag_axis")) != -1:
		_fail("IK target drag remained active after pointer release")
		return
	if not engine.undo():
		_fail("IK target drag cannot be undone")
		return
	if rig.chains[0]["target"].global_position.distance_to(old_goal) > 0.0001:
		_fail("Undo did not restore IK target location")
		return
	print("IK TOUCH PASS: select IK goal, axis drag, live update, undo and pointer cleanup")
	quit(0)

func _fail(msg: String) -> void:
	push_error(msg)
	quit(1)
