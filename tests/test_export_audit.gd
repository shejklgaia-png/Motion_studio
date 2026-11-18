extends SceneTree
## End-to-end regression for Motion Studio's real IK/FK bake -> .tres export.
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
	engine.evaluate(0.73)
	var preserved_time: float = engine.play_time
	var path := "user://motion_export_audit.tres"
	var message := engine.export_animation_tres(path)
	if not message.begins_with("Godotアニメーションを出力"):
		_fail("Failed to export .tres: " + message)
		return
	var summary: Dictionary = engine.last_export_report
	if not bool(summary.get("ok", false)) or not bool(summary.get("reloaded", false)):
		_fail("Saved .tres failed keyframe parity audit: " + str(summary))
		return
	if int(summary.get("key_samples", 0)) < 3 or int(summary.get("mid_samples", 0)) < 2:
		_fail("Export audit did not sample keyframes and between-key interpolation")
		return
	if absf(engine.play_time - preserved_time) > 0.00001:
		_fail("Export audit did not restore the editor's playback time")
		return
	var animation := ResourceLoader.load(path, "Animation", ResourceLoader.CACHE_MODE_IGNORE) as Animation
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
	# The whole-export audit must catch a corrupted saved position key.
	var corrupted: Animation = animation.duplicate(true) as Animation
	var position_track := -1
	for track in range(corrupted.get_track_count()):
		if corrupted.track_get_type(track) == Animation.TYPE_POSITION_3D:
			position_track = track
			break
	if position_track < 0:
		_fail("Missing position track in exported animation")
		return
	var first_key: Vector3 = corrupted.track_get_key_value(position_track, 0)
	corrupted.track_set_key_value(position_track, 0, first_key + Vector3(0.3, 0.0, 0.0))
	var bad_report: Dictionary = MotionExportAudit.audit_export(engine, corrupted)
	if bool(bad_report.get("ok", true)) or (bad_report.get("errors", []) as Array).is_empty():
		_fail("Keyframe parity audit accepted a corrupted position track")
		return
	var missing: Animation = animation.duplicate(true) as Animation
	missing.remove_track(position_track)
	var missing_report: Dictionary = MotionExportAudit.audit_export(engine, missing)
	if bool(missing_report.get("ok", true)):
		_fail("Export audit accepted an incomplete joint track set")
		return
	print("EXPORT AUDIT PASS: imported .tres, compared %d channels, detected corruption and missing tracks" % examined)
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
