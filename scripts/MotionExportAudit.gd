extends RefCounted
class_name MotionExportAudit

## Check the saved Godot Animation against the same evaluated rig, not only
## the in-memory export. Paths are relative to the MotionRig animation root.
## This checks sampled local transforms; a different game rig/root still needs
## a runtime hierarchy check in the target game.
const MAX_REPORTED_ERRORS := 8

static func compare(animation: Animation, rig: Node3D, time_seconds: float, tolerance: float = 0.0001) -> Dictionary:
	var errors: Array[String] = []
	if animation == null or rig == null:
		return {"ok": false, "tracks_checked": 0, "errors": ["アニメーションまたはリグがありません"]}
	var t: float = clampf(time_seconds, 0.0, animation.length)
	var checked := 0
	var seen: Dictionary = {}
	var max_position := 0.0
	var max_rotation := 0.0
	var max_scale := 0.0
	for track in range(animation.get_track_count()):
		var kind: Animation.TrackType = animation.track_get_type(track)
		if kind not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			continue
		var path: NodePath = animation.track_get_path(track)
		var channel_key: String = "%d:%s" % [int(kind), str(path)]
		if seen.has(channel_key):
			errors.append("重複トラック: " + str(path))
			continue
		seen[channel_key] = true
		var node: Node = rig.get_node_or_null(path)
		if not (node is Node3D):
			errors.append("対象ノードがありません: " + str(path))
			continue
		if animation.track_get_key_count(track) == 0:
			errors.append("キーフレームがありません: " + str(path))
			continue
		var joint: Node3D = node as Node3D
		match kind:
			Animation.TYPE_POSITION_3D:
				var offset: float = animation.position_track_interpolate(track, t).distance_to(joint.position)
				max_position = maxf(max_position, offset)
				if offset > tolerance:
					errors.append("位置差 %.5fm: %s" % [offset, str(path)])
			Animation.TYPE_ROTATION_3D:
				var exported: Quaternion = animation.rotation_track_interpolate(track, t).normalized()
				var expected: Quaternion = joint.quaternion.normalized()
				var dot: float = clampf(absf(exported.dot(expected)), 0.0, 1.0)
				var angle: float = rad_to_deg(2.0 * acos(dot))
				max_rotation = maxf(max_rotation, angle)
				if angle > 0.1:
					errors.append("回転差 %.3f°: %s" % [angle, str(path)])
			Animation.TYPE_SCALE_3D:
				var scale_offset: float = animation.scale_track_interpolate(track, t).distance_to(joint.scale)
				max_scale = maxf(max_scale, scale_offset)
				if scale_offset > tolerance:
					errors.append("倍率差 %.5f: %s" % [scale_offset, str(path)])
		checked += 1
	if rig is MotionRig:
		var expected_tracks: int = (rig as MotionRig).parts.size() * 3
		if checked != expected_tracks:
			errors.append("関節トラック数が不一致: %d / %d" % [checked, expected_tracks])
	return {"ok": errors.is_empty() and checked > 0, "tracks_checked": checked,
		"max_position_error_m": max_position, "max_rotation_error_deg": max_rotation,
		"max_scale_error": max_scale, "errors": errors}

## Key samples are strict. Between-key interpolation is measured separately:
## it may legitimately differ from the evaluated IK/constraint curve at finite
## export FPS, so report it as a warning rather than silently guaranteeing it.
static func audit_export(engine: MotionEngine, animation: Animation, max_key_checks: int = 32, max_mid_checks: int = 16) -> Dictionary:
	var report: Dictionary = {"ok": false, "key_samples": 0, "mid_samples": 0,
		"tracks_checked": 0, "max_position_error_m": 0.0,
		"max_rotation_error_deg": 0.0, "max_scale_error": 0.0,
		"mid_position_error_m": 0.0, "mid_rotation_error_deg": 0.0,
		"mid_scale_error": 0.0, "interpolation_warning": false, "errors": []}
	if engine == null or engine.rig == null or animation == null:
		report["errors"] = ["エンジン、モデル、または出力済みアニメーションがありません"]
		return report
	if engine.rig.parts.is_empty() or animation.length + 0.0001 < engine.duration:
		report["errors"] = ["モデルが空、または出力された再生時間が不足しています"]
		return report
	var old_time: float = engine.play_time
	var frame_rate: int = maxi(engine.fps, 1)
	var frame_count: int = int(ceil(engine.duration * float(frame_rate))) + 1
	var key_stride: int = maxi(1, int(ceil(float(frame_count - 1) / float(maxi(max_key_checks - 1, 1)))))
	var key_times: Array[float] = []
	for index in range(0, frame_count, key_stride):
		key_times.append(minf(float(index) / float(frame_rate), engine.duration))
	if key_times.is_empty() or absf(key_times[-1] - engine.duration) > 0.00001:
		key_times.append(engine.duration)
	for t in key_times:
		engine.evaluate(t)
		var comparison: Dictionary = compare(animation, engine.rig, t, 0.001)
		report["key_samples"] = int(report["key_samples"]) + 1
		report["tracks_checked"] = int(report["tracks_checked"]) + int(comparison.get("tracks_checked", 0))
		report["max_position_error_m"] = maxf(float(report["max_position_error_m"]), float(comparison.get("max_position_error_m", 0.0)))
		report["max_rotation_error_deg"] = maxf(float(report["max_rotation_error_deg"]), float(comparison.get("max_rotation_error_deg", 0.0)))
		report["max_scale_error"] = maxf(float(report["max_scale_error"]), float(comparison.get("max_scale_error", 0.0)))
		if not bool(comparison.get("ok", false)):
			for problem in comparison.get("errors", []):
				if (report["errors"] as Array).size() < MAX_REPORTED_ERRORS:
					(report["errors"] as Array).append("%.3f秒: %s" % [t, str(problem)])
	var mid_stride: int = maxi(1, int(ceil(float(frame_count - 1) / float(maxi(max_mid_checks, 1)))))
	for index in range(0, frame_count - 1, mid_stride):
		var t: float = (float(index) + 0.5) / float(frame_rate)
		if t >= engine.duration:
			continue
		engine.evaluate(t)
		var comparison: Dictionary = compare(animation, engine.rig, t, 0.001)
		report["mid_samples"] = int(report["mid_samples"]) + 1
		report["mid_position_error_m"] = maxf(float(report["mid_position_error_m"]), float(comparison.get("max_position_error_m", 0.0)))
		report["mid_rotation_error_deg"] = maxf(float(report["mid_rotation_error_deg"]), float(comparison.get("max_rotation_error_deg", 0.0)))
		report["mid_scale_error"] = maxf(float(report["mid_scale_error"]), float(comparison.get("max_scale_error", 0.0)))
	engine.evaluate(old_time)
	report["interpolation_warning"] = float(report["mid_position_error_m"]) > 0.01 or float(report["mid_rotation_error_deg"]) > 0.5 or float(report["mid_scale_error"]) > 0.01
	report["ok"] = (report["errors"] as Array).is_empty() and int(report["tracks_checked"]) > 0
	return report
