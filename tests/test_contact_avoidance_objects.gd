extends SceneTree

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var rig := MotionRig.new()
	root.add_child(rig)
	rig.create_sample()
	var motion := MotionEngine.new()
	motion.setup(rig)
	motion.duration = 1.0
	var chain: Dictionary = rig.chains[0]
	chain["enabled"] = true
	chain["method"] = "2ボーン"
	chain["weight"] = 1.0
	chain["start"] = 0.2
	chain["finish"] = 0.8
	chain["collision_avoid"] = true
	chain["collision_floor"] = false
	chain["collision_objects"] = true
	chain["collision_margin"] = 0.005
	chain["collision_object_index"] = -1
	chain["collision_include_mid"] = false
	var foot: Node3D = rig.parts[str(chain["end"])]
	var tip_offset: Vector3 = MotionRig.from_array(chain["tip"])
	motion.evaluate(0.1)
	var baseline: Vector3 = foot.to_global(tip_offset)
	motion.evaluate(0.5)
	if foot.to_global(tip_offset).distance_to(baseline) > 0.0001:
		_fail("No collision should never change FK pose")
		return
	# All three kinds are checked in the obstacle's own coordinate system.
	var obstacle_pos: Vector3 = foot.to_global(Vector3(0.0, -0.13, -0.07))
	for kind in ["箱", "球", "カプセル"]:
		var index: int = rig.add_test_object(kind, obstacle_pos)
		var object_node: Node3D = rig.test_objects[index]["node"]
		object_node.scale = Vector3(0.55, 0.6, 0.55)
		object_node.rotation_degrees = Vector3(10, 20, 15)
		motion.evaluate(0.1)
		var original_position: Vector3 = foot.to_global(tip_offset)
		var escape: Vector3 = motion._collision_escape(chain)
		if escape.length_squared() < 0.001:
			_fail("Missing %s intersection with transformed test object" % kind)
			return
		# Interval and object selection are independent from the IK goal.
		chain["collision_object_index"] = index
		motion.evaluate(0.5)
		var displaced_position: Vector3 = foot.to_global(tip_offset)
		if displaced_position.distance_to(original_position) < 0.005:
			_fail("IK did not react to %s contact" % kind)
			return
		motion.evaluate(0.9)
		if foot.to_global(tip_offset).distance_to(original_position) > 0.0002:
			_fail("%s avoidance was active outside requested time" % kind)
			return
		object_node.position += Vector3(15.0, 0, 0)
		motion.evaluate(0.5)
		if foot.to_global(tip_offset).distance_to(original_position) > 0.0002:
			_fail("Avoidance still modifies FK after %s moved away" % kind)
			return
		chain["collision_object_index"] = -1
		rig.clear_test_objects()
		motion.evaluate(0.5)
	# Ground avoidance only pushes up when below the floor; no snapping down.
	chain["collision_objects"] = false
	chain["collision_floor"] = true
	chain["collision_height"] = -0.3
	motion.evaluate(0.5)
	if foot.to_global(tip_offset).distance_to(baseline) > 0.0002:
		_fail("Ground avoidance pulled an above-ground part onto the floor")
		return
	chain["collision_height"] = 0.1
	motion.evaluate(0.5)
	if motion._collision_escape(chain).length() > 0.05:
		_fail("Floor avoidance did not resolve penetration")
		return
	# New keys persist through undo/redo and saved animation projects.
	var saved: Dictionary = motion.snapshot()
	motion.restore(saved)
	chain = rig.chains[0]
	if not bool(chain.get("collision_avoid", false)) or not bool(chain.get("collision_floor", false)):
		_fail("Collision avoidance settings lost after project restore")
		return
	# Legacy projects migrate without silently discarding their old settings.
	var legacy: Dictionary = saved.duplicate(true)
	var old_chain: Dictionary = legacy["chains"][0]
	old_chain.erase("collision_avoid")
	old_chain.erase("collision_floor")
	old_chain.erase("collision_objects")
	old_chain.erase("collision_height")
	old_chain.erase("collision_margin")
	old_chain.erase("collision_include_mid")
	old_chain["ground_follow"] = true
	old_chain["ground_height"] = -0.03
	old_chain["ground_clearance"] = 0.02
	old_chain["ground_include_lower"] = false
	motion.restore(legacy)
	if not bool(rig.chains[0].get("collision_avoid", false)) or bool(rig.chains[0].get("collision_objects", true)):
		_fail("Legacy ground follow did not migrate to floor-only avoidance")
		return
	if absf(float(rig.chains[0].get("collision_margin", 0.0)) - 0.02) > 0.0001:
		_fail("Legacy contact clearance was lost")
		return
	print("CONTACT OBJECT AVOIDANCE PASS: rotated/scaled box, sphere, capsule, timeline, no-snapping, legacy migration")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
