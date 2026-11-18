extends SceneTree
## End-to-end regression for Movie Studio's real IK/FK bake -> .tres export.
## A passing result validates local tracks at sampled times, not Android device UX.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var rig := MotionRig.new()
	root.add_child(rig)
	rig.create_sample()
	var engine := MotionEngine.new()
	engine.setup(rig)
	engine.add_sample_animation()
	var baked: Dictionary = engine.bake_ik_fk(30)
	if not bool(baked.get("ok", false)):
		_fail("Failed to bake sample FK: " + str(baked))
		return
	var path := "user://motion_export_audit.tres"
	var message := engine.export_animation_tres(path)
	if not message.begins_with("Godotアニメーションを出力"):
		_fail("Failed to export .tres: " + message)
		return
	var animation := ResourceLoader.load(path) as Animation
	if animation == null:
		_fail("Godot cannot re-import the exported .tres animation")
		return
	var examined := 0
	for t in [0.0, 0.5, 1.0, 1.5, 2.0, 3.0]:
		engine.evaluate(t)
		var report: Dictionary = MotionExportAudit.compare(animation, rig, t, 0.001)
		if not bool(report.get("ok", false)):
			_fail("Exported transform differs at t=%.2f: %s" % [t, str(report.get("errors", []))])
			return
		examined += int(report.get("tracks_checked", 0))
	if examined < 3:
		_fail("Not enough transform channels audited")
		return
	engine.evaluate(0.5)
	var first_name: String = str(rig.parts.keys()[0])
	var joint: Node3D = rig.parts[first_name]
	var original: Vector3 = joint.position
	joint.position += Vector3(0.3, 0, 0)
	var mismatch: Dictionary = MotionExportAudit.compare(animation, rig, 0.5)
	joint.position = original
	if bool(mismatch.get("ok", true)) or (mismatch.get("errors", []) as Array).is_empty():
		_fail("Audit failed to reject a shifted local transform")
		return
	print("EXPORT AUDIT PASS: imported .tres and compared %d baked channels, mismatch detected" % examined)
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
