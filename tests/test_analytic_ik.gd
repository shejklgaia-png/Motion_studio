extends SceneTree

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var rig := MotionRig.new()
	root.add_child(rig)
	rig.create_sample()
	var engine := MotionEngine.new()
	engine.setup(rig)
	engine.add_sample_animation()
	var chain: Dictionary = rig.chains[0]
	var upper: Node3D = rig.parts[chain["root"]]
	var knee: Node3D = rig.parts[chain["mid"]]
	var end: Node3D = rig.parts[chain["end"]]
	var tip := MotionRig.from_array(chain["tip"])
	var goal: Node3D = chain["target"]
	engine.evaluate(0.4)
	var upper_len: float = upper.global_position.distance_to(knee.global_position)
	var lower_len: float = knee.global_position.distance_to(end.to_global(tip))
	var origin: Vector3 = upper.global_position
	var desired: Vector3 = origin + Vector3(0.17, -1.52, 0.0)
	goal.global_position = desired
	chain["enabled"] = true
	chain["weight"] = 1.0
	chain["method"] = "2ボーン"
	chain["pole"] = [0.0, 0.0, 1.0]
	engine.evaluate(0.4)
	var reached: Vector3 = end.to_global(tip)
	if reached.distance_to(desired) > 0.02:
		_fail("Analytic 2-bone failed reachable target: " + str(reached.distance_to(desired)))
		return
	if absf(upper.global_position.distance_to(knee.global_position) - upper_len) > 0.0001:
		_fail("Analytic solver changed upper bone length")
		return
	if absf(knee.global_position.distance_to(end.to_global(tip)) - lower_len) > 0.0001:
		_fail("Analytic solver changed lower bone length")
		return
	var positive_knee: float = knee.global_position.z - origin.z
	chain["pole"] = [0.0, 0.0, -1.0]
	engine.evaluate(0.4)
	var negative_knee: float = knee.global_position.z - origin.z
	if positive_knee < 0.12 or negative_knee > -0.12:
		_fail("Pole direction did not control knee bend: " + str([positive_knee, negative_knee]))
		return
	if end.to_global(tip).distance_to(desired) > 0.02:
		_fail("Reversing pole changed end effector target")
		return

	var maximum: float = upper_len + lower_len
	goal.global_position = origin + Vector3(0, -8.0, 0)
	engine.evaluate(0.4)
	var reached_distance: float = end.to_global(tip).distance_to(origin)
	if absf(reached_distance - maximum) > 0.018:
		_fail("Unreachable target should clamp at maximum reach: " + str(reached_distance))
		return
	# No IK when disabled: changing the target must not influence FK pose.
	chain["enabled"] = false
	engine.evaluate(0.4)
	var fk_pose: Quaternion = upper.quaternion
	goal.global_position += Vector3(1.2, 0.4, -1.3)
	engine.evaluate(0.4)
	if fk_pose.angle_to(upper.quaternion) > 0.0001:
		_fail("Disabled IK still modifies FK pose")
		return
	chain["enabled"] = true
	chain["pole"] = [0.0, 1.0, 1.0]
	chain["method"] = "2ボーン"
	var saved: Dictionary = engine.snapshot()
	if not engine.save_project("user://analytic_ik.motion.json").begins_with("保存しました"):
		_fail("Could not save analytic IK project")
		return
	engine.load_project("user://analytic_ik.motion.json")
	if rig.chains.is_empty() or str(rig.chains[0]["method"]) != "2ボーン":
		_fail("Restored project lost true two-bone solver selection")
		return
	if MotionRig.from_array(rig.chains[0]["pole"]).distance_to(Vector3(0, 1, 1)) > 0.0001:
		_fail("Pole direction was not restored")
		return
	# A baked motion must become independent of the IK target.
	var bake: Dictionary = engine.bake_ik_fk(30)
	if not bool(bake.get("ok", false)):
		_fail("Cannot bake analytic IK to FK")
		return
	if bool(rig.chains[0]["enabled"]):
		_fail("IK still enabled after baking")
		return
	engine.evaluate(0.5)
	var stored_quat: Quaternion = rig.parts[chain["root"]].quaternion
	rig.chains[0]["target"].global_position += Vector3(0.9, 0.0, 0.9)
	engine.evaluate(0.5)
	if stored_quat.angle_to(rig.parts[chain["root"]].quaternion) > 0.0001:
		_fail("Baked 2-bone FK still depends on target")
		return
	if not engine.restore_bake_source():
		_fail("Cannot restore pre-bake 2-bone IK motion")
		return
	if str(rig.chains[0]["method"]) != "2ボーン" or not bool(rig.chains[0]["enabled"]):
		_fail("Pre-bake IK settings not restored")
		return
	print("ANALYTIC IK PASS: reachable/unreachable targets, length, pole bending, saving, 30fps bake and restore")
	quit(0)

func _fail(msg: String) -> void:
	push_error(msg)
	quit(1)
