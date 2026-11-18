extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _same_point(a: Vector3, b: Vector3, tolerance: float = 0.0005) -> bool:
	return a.distance_to(b) <= tolerance

func _run() -> void:
	var rig := MotionRig.new()
	root.add_child(rig)
	rig.create_sample()
	var motion := MotionEngine.new()
	motion.setup(rig)
	motion.add_sample_animation()
	var chain: Dictionary = rig.chains[0]
	chain["method"] = "2ボーン"
	motion.evaluate(0.0)
	if not motion.add_contact(0, "floor"):
		_fail("Cannot add floor contact")
		return
	if not bool(chain["enabled"]) or motion.contact_constraints.size() != 1:
		_fail("Contact did not activate IK and create an anchor")
		return
	var anchor: Dictionary = motion.get_contact_goal(0, 0.0)
	if not bool(anchor.get("active", false)) or absf(anchor["position"].y) > 0.0001:
		_fail("Floor contact should fix height to 0")
		return
	var first_position: Vector3 = anchor["position"]
	chain["target"].global_position += Vector3(0.33, 0.25, -0.15)
	motion.evaluate(0.7)
	var held: Dictionary = motion.get_contact_goal(0, 0.7)
	if not _same_point(first_position, held["position"]):
		_fail("Floor contact drifted with authored IK target")
		return
	var foot: Node3D = rig.parts[chain["end"]]
	var tip: Vector3 = foot.to_global(MotionRig.from_array(chain["tip"]))
	if tip.distance_to(first_position) > 0.12:
		_fail("Contact IK did not hold sample foot near anchor: " + str(tip.distance_to(first_position)))
		return
	motion.contact_constraints[0]["slide"] = [0.6, 0.9, 0.0]
	motion.contact_constraints[0]["friction"] = 0.0
	var at_one: Vector3 = motion.get_contact_goal(0, 1.0)["position"]
	if not _same_point(at_one, first_position + Vector3(0.6, 0, 0)):
		_fail("Floor slip must advance in X while Y remains fixed")
		return
	motion.evaluate(1.6)
	motion.evaluate(0.2)
	motion.evaluate(1.0)
	var at_one_again: Vector3 = motion.get_contact_goal(0, 1.0)["position"]
	if not _same_point(at_one, at_one_again):
		_fail("Time scrubbing changed deterministic contact position")
		return
	motion.contact_constraints[0]["friction"] = 1.0
	if not _same_point(motion.get_contact_goal(0, 1.0)["position"], first_position):
		_fail("Maximum friction did not stop slip")
		return
	motion.contact_constraints[0]["start"] = 0.4
	motion.contact_constraints[0]["finish"] = 0.8
	if bool(motion.get_contact_goal(0, 0.2).get("active", false)):
		_fail("Contact active before its start")
		return
	if bool(motion.get_contact_goal(0, 0.9).get("active", false)):
		_fail("Contact active after its finish")
		return
	var test_id: int = rig.add_test_object("箱", Vector3(0.5, 0.7, -0.8))
	motion.evaluate(0.0)
	if not motion.add_contact(1, "obstacle", test_id):
		_fail("Could not attach foot to test object")
		return
	var world_before: Vector3 = motion.get_contact_goal(1, 0.0)["position"]
	rig.test_objects[test_id]["node"].position += Vector3(0.25, 0.18, -0.14)
	var world_after: Vector3 = motion.get_contact_goal(1, 0.0)["position"]
	if not _same_point(world_after, world_before + Vector3(0.25, 0.18, -0.14)):
		_fail("Object-relative anchor did not track its obstacle")
		return
	var saved_contact: Dictionary = motion.contact_constraints[1].duplicate(true)
	var saved := motion.save_project("user://contact_anchor.motion.json")
	if not saved.begins_with("保存しました"):
		_fail("Cannot serialize contacts")
		return
	if not motion.load_project("user://contact_anchor.motion.json").begins_with("読み込みました"):
		_fail("Cannot restore contacts")
		return
	if motion.contact_constraints.size() != 2 or motion.contact_constraints[1] != saved_contact:
		_fail("Loading project lost contact constraint values")
		return
	motion.evaluate(0.5)
	var bakeres: Dictionary = motion.bake_ik_fk(30)
	if not bool(bakeres.get("ok", false)):
		_fail("Contact constrained motion could not bake")
		return
	for item in motion.contact_constraints:
		if bool(item["enabled"]):
			_fail("Baked FK still has active contact constraints")
			return
	for ch in rig.chains:
		if bool(ch.get("enabled", false)):
			_fail("Baked FK still has active IK")
			return
	if not motion.restore_bake_source():
		_fail("Cannot restore source contact motion after baking")
		return
	if motion.contact_constraints.size() != 2 or not bool(motion.contact_constraints[0]["enabled"]):
		_fail("Contact settings not restored after bake")
		return
	rig.add_chain("共有関節テスト", str(rig.chains[0]["root"]),
		str(rig.chains[0]["mid"]), str(rig.chains[0]["end"]),
		MotionRig.from_array(rig.chains[0]["tip"]), rig.chains[0]["target"].global_position)
	rig.chains[-1]["enabled"] = true
	motion.evaluate(0.5)
	if not motion._has_shared_ik_joints([0, rig.chains.size() - 1]):
		_fail("Overlapping IK joints not detected")
		return
	if not motion.warnings.any(func(line: String): return line.contains("共有")):
		_fail("Overlapping IK warning not shown in diagnostics")
		return
	print("CONTACT ROADMAP PASS: floor lock, sliding friction, local obstacle anchors, temporal stability, save/load, FK bake, shared IK")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
