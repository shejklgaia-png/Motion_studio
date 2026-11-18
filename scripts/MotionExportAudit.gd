extends RefCounted
class_name MotionExportAudit

## Compare baked local transforms with the exported Animation resource.
## The animation's track root must be the same rig node used for export.
static func compare(animation: Animation, rig: Node3D, time_seconds: float, tolerance: float = 0.0001) -> Dictionary:
	var errors: Array[String] = []
	if animation == null or rig == null:
		return {"ok": false, "errors": ["アニメーションまたはリグがありません"]}
	var t := clampf(time_seconds, 0.0, animation.length)
	var checked := 0
	for track in range(animation.get_track_count()):
		var kind := animation.track_get_type(track)
		if kind not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			continue
		var path := animation.track_get_path(track)
		var node := rig.get_node_or_null(NodePath(str(path)))
		if not (node is Node3D):
			errors.append("対象ノードがありません: " + str(path))
			continue
		if animation.track_get_key_count(track) == 0:
			errors.append("キーフレームがありません: " + str(path))
			continue
		var sampled: Variant = animation.value_track_interpolate(track, t) if kind == Animation.TYPE_VALUE else null
		match kind:
			Animation.TYPE_POSITION_3D:
				sampled = animation.position_track_interpolate(track, t)
				if sampled.distance_to(node.position) > tolerance:
					errors.append("位置差: " + str(path))
			Animation.TYPE_ROTATION_3D:
				sampled = animation.rotation_track_interpolate(track, t)
				if absf(sampled.normalized().dot(node.quaternion.normalized())) < 1.0 - tolerance:
					errors.append("回転差: " + str(path))
			Animation.TYPE_SCALE_3D:
				sampled = animation.scale_track_interpolate(track, t)
				if sampled.distance_to(node.scale) > tolerance:
					errors.append("倍率差: " + str(path))
		checked += 1
	return {"ok": errors.is_empty() and checked > 0, "tracks_checked": checked, "errors": errors}
