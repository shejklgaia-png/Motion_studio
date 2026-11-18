extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var rig := MotionRig.new()
	root.add_child(rig)
	rig.create_sample()
	var engine := MotionEngine.new()
	engine.setup(rig)
	engine.add_sample_animation()
	var original_count: int = engine.frames.size()
	if rig.chains.is_empty():
		_fail("Missing sample IK chain")
		return
	var chain: Dictionary = rig.chains[0]
	var first_root: String = str(chain["root"])
	var mid: String = str(chain["mid"])
	var goal: Node3D = chain["target"]
	goal.global_position += Vector3(0.28, 0.26, -0.12)
	chain["enabled"] = true
	chain["weight"] = 1.0
	chain["start"] = 0.0
	chain["finish"] = 3.0
	var bounds: Dictionary = engine.default_constraint()
	bounds["rotation_min"] = [-180.0, -180.0, -75.0]
	bounds["rotation_max"] = [180.0, 180.0, 75.0]
	engine.constraints[first_root] = bounds
	engine.evaluate(0.5)
	var source_rotation: Quaternion = rig.parts[first_root].quaternion
	var source_mid_rotation: Quaternion = rig.parts[mid].quaternion
	var source_position: Vector3 = rig.parts[first_root].position
	var source_time: float = engine.play_time

	var result: Dictionary = engine.bake_ik_fk(30)
	if not bool(result.get("ok", false)):
		_fail("Baking failed: " + str(result.get("message", "")))
		return
	if engine.frames.size() != 91 or engine.fps != 30:
		_fail("Wrong 30fps full timeline: " + str(engine.frames.size()))
		return
	if bool(rig.chains[0]["enabled"]) or bool(engine.constraints[first_root]["enabled"]):
		_fail("Runtime IK or constraints still active after baking")
		return
	if engine.bake_source.is_empty() or engine.bake_report.is_empty():
		_fail("Backup or verification report was not generated")
		return
	if int(engine.bake_report.get("checked_midpoints", 0)) <= 0:
		_fail("No intermediate frame verification")
		return
	engine.evaluate(source_time)
	if rig.parts[first_root].quaternion.angle_to(source_rotation) > deg_to_rad(0.15):
		_fail("Baked FK differs from original IK rotation at exact sample")
		return
	if rig.parts[mid].quaternion.angle_to(source_mid_rotation) > deg_to_rad(0.15):
		_fail("Baked FK differs from original IK mid-joint rotation")
		return
	if rig.parts[first_root].position.distance_to(source_position) > 0.0001:
		_fail("Baked FK position differs from original")
		return
	var stable_baked: Quaternion = rig.parts[mid].quaternion
	var target: Node3D = rig.chains[0]["target"]
	target.global_position += Vector3(1.0, 0.5, 0.0)
	engine.evaluate(source_time)
	if rig.parts[mid].quaternion.angle_to(stable_baked) > 0.0001:
		_fail("Baked animation still depends on IK target")
		return

	var snapshot: Dictionary = engine.snapshot()
	if not snapshot.has("bake_source") or not snapshot.has("bake_report"):
		_fail("Baked backup missing from project snapshot")
		return
	if snapshot["bake_source"].has("bake_source"):
		_fail("Recursive backup nesting detected")
		return
	var saved: String = engine.save_project("user://motion_bake_test.motion.json")
	if not saved.begins_with("保存しました"):
		_fail("Baked project cannot be saved: " + saved)
		return
	engine.load_project("user://motion_bake_test.motion.json")
	if engine.frames.size() != 91 or bool(rig.chains[0]["enabled"]) or engine.bake_source.is_empty():
		_fail("Save/load did not keep baked FK and original backup")
		return

	var export_message := engine.export_animation_tres("user://motion_bake_test.tres")
	if not export_message.begins_with("Godotアニメーションを出力") or not FileAccess.file_exists("user://motion_bake_test.tres"):
		_fail("Failed to export baked Godot animation: " + export_message)
		return

	if not engine.restore_bake_source():
		_fail("Could not restore the source of the bake")
		return
	if engine.frames.size() != original_count or not bool(rig.chains[0]["enabled"]):
		_fail("Source frame count or IK configuration not restored")
		return
	if engine.bake_source.size() != 0 or engine.bake_report.size() != 0:
		_fail("Baked state still active after restoring source")
		return
	engine.evaluate(source_time)
	if rig.parts[first_root].quaternion.angle_to(source_rotation) > deg_to_rad(0.15):
		_fail("Source IK motion was not restored")
		return
	var bad_fps := engine.bake_ik_fk(17)
	if bool(bad_fps.get("ok", false)):
		_fail("Unsupported fps was not rejected")
		return
	var sixty: Dictionary = engine.bake_ik_fk(60)
	if not bool(sixty.get("ok", false)) or engine.frames.size() != 181 or engine.fps != 60:
		_fail("60fps IK/FK baking failed")
		return
	if bool(rig.chains[0]["enabled"]):
		_fail("60fps baking left IK active")
		return
	if not engine.undo():
		_fail("Undo after 60fps bake failed")
		return
	if engine.frames.size() != original_count or not bool(rig.chains[0]["enabled"]):
		_fail("Undo did not restore original IK animation")
		return
	print("MOTION BAKE PASS: 30/60fps FK keys, source backup, runtime IK off, stable targets, export, restore, undo")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
