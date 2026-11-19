extends SceneTree

# Collision avoidance must preserve the original curved FK sweep instead of
# replacing it with a straight, constant-speed horizontal slide.
func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var rig := MotionRig.new()
	root.add_child(rig)
	rig.create_sample()
	var engine := MotionEngine.new()
	engine.setup(rig)
	engine.duration = 1.8
	var rest: Dictionary = rig.rest.duplicate(true)
	var left: Dictionary = rest.duplicate(true)
	var right: Dictionary = rest.duplicate(true)
	# Make the FK animation visibly penetrate the floor, rather than relying
	# on the sample's near-zero clearance at its original body height.
	var left_body: Dictionary = left["胴体"].duplicate(true)
	left_body["position"] = [0.0, 1.50, 0.0]
	left["胴体"] = left_body
	var right_body: Dictionary = right["胴体"].duplicate(true)
	right_body["position"] = [0.0, 1.48, 0.0]
	right["胴体"] = right_body
	var left_arm: Dictionary = left["前左上肢"].duplicate(true)
	left_arm["rotation"] = [0.0, 0.0, -14.0]
	left["前左上肢"] = left_arm
	var right_arm: Dictionary = right["前左上肢"].duplicate(true)
	right_arm["rotation"] = [0.0, 0.0, 14.0]
	right["前左上肢"] = right_arm
	engine.frames = [
		{"time": 0.0, "poses": rest.duplicate(true)},
		{"time": 0.3, "poses": left.duplicate(true)},
		{"time": 0.8, "poses": right.duplicate(true)},
		{"time": 1.3, "poses": left.duplicate(true)},
		{"time": 1.8, "poses": rest.duplicate(true)}
	]
	var chain: Dictionary = rig.chains[0]
	chain["method"] = "2ボーン"
	chain["pole"] = [0.0, 0.0, 1.0]
	chain["weight"] = 1.0
	chain["start"] = 0.25
	chain["finish"] = 1.35
	chain["collision_avoid"] = true
	chain["collision_floor"] = true
	chain["collision_objects"] = false
	chain["collision_height"] = 0.0
	chain["collision_margin"] = 0.01
	chain["collision_include_mid"] = true
	var end: Node3D = rig.parts[chain["end"]]
	var tip: Vector3 = MotionRig.from_array(chain["tip"])
	var any_penetration: bool = false
	var baseline_y: Array[float] = []
	var seen_x: Array[float] = []
	for t in [0.35, 0.55, 0.8, 1.05, 1.25]:
		chain["enabled"] = false
		engine.evaluate(t)
		var authored: Vector3 = end.to_global(tip)
		var raw_floor: float = engine._ground_surface_min_y(chain)
		baseline_y.append(raw_floor)
		if raw_floor < -0.04:
			any_penetration = true
		chain["enabled"] = true
		engine.evaluate(t)
		var actual: Vector3 = end.to_global(tip)
		var corrected_floor: float = engine._ground_surface_min_y(chain)
		if corrected_floor < -0.045:
			_fail("Collision avoidance missed the surface at %.2fs: %.4f" % [t, corrected_floor])
			return
		if absf(actual.x - authored.x) > 0.05 or absf(actual.z - authored.z) > 0.05:
			_fail("Collision avoidance altered original FK sweep path: " + str([t, authored, actual]))
			return
		seen_x.append(actual.x)
	if not any_penetration:
		_fail("Regression animation did not exercise the penetration case: " + str(baseline_y))
		return
	var horizontal_span: float = seen_x.max() - seen_x.min()
	if horizontal_span < 0.25:
		_fail("Collision avoidance removed the lateral sweep arc")
		return
	# Outside the interval, the original FK pose must remain untouched.
	chain["enabled"] = false
	engine.evaluate(1.65)
	var expected: Vector3 = end.to_global(tip)
	chain["enabled"] = true
	engine.evaluate(1.65)
	if end.to_global(tip).distance_to(expected) > 0.0001:
		_fail("Ground following affected frames outside the IK time range")
		return
	var stored: Dictionary = engine.snapshot()
	engine.restore(stored)
	if not bool(rig.chains[0].get("collision_avoid", false)):
		_fail("Restored project lost collision avoidance")
		return
	if absf(float(rig.chains[0].get("collision_margin", 0.0)) - 0.01) > 0.00001:
		_fail("Restored project lost sweep clearance")
		return
	var bake: Dictionary = engine.bake_ik_fk(30)
	if not bool(bake.get("ok", false)):
		_fail("Could not bake collision avoidance to FK animation")
		return
	if bool(rig.chains[0]["enabled"]):
		_fail("IK remained active after baking collision avoidance")
		return
	engine.evaluate(0.8)
	if engine._ground_surface_min_y(rig.chains[0]) < -0.055:
		_fail("Baked collision avoidance changed the contact geometry")
		return
	if not engine.restore_bake_source() or not bool(rig.chains[0].get("collision_avoid", false)):
		_fail("Restoring pre-bake source lost ground-follow setup")
		return
	print("CONTACT AVOIDANCE IK PASS: underside, authored arc, time range, save/restore, 30fps bake")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
