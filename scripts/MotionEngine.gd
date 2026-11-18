extends RefCounted
class_name MotionEngine

# Non-destructive timeline: sampled FK pose -> per-part limits -> IK -> diagnostics.
var rig: MotionRig
var duration: float = 3.0
var fps: int = 60
var frames: Array = []
var constraints: Dictionary = {}
var play_time: float = 0.0
var warnings: Array = []
var history: Array[String] = []
var future: Array[String] = []
# Original non-baked settings and keyframes are retained for later restoration.
var bake_source: Dictionary = {}
var bake_report: Dictionary = {}
const MAX_BAKE_FRAMES := 3601
const MAX_UNDO := 50

func setup(model: MotionRig) -> void:
	rig = model
	constraints.clear()
	bake_source.clear()
	bake_report.clear()
	frames.clear()
	frames.append({"time": 0.0, "poses": rig.rest.duplicate(true)})
	frames.append({"time": duration, "poses": rig.rest.duplicate(true)})
	history.clear()
	future.clear()
	play_time = 0.0
	evaluate(0.0)

func add_sample_animation() -> void:
	if not rig.parts.has("前左上肢"):
		return
	var sample: Dictionary = rig.rest.duplicate(true)
	var lifted: Dictionary = sample["前左上肢"].duplicate(true)
	lifted["rotation"] = [0.0, 0.0, -26.0]
	sample["前左上肢"] = lifted
	frames.insert(1, {"time": 0.7, "poses": sample})
	var sample2: Dictionary = rig.rest.duplicate(true)
	var lowered: Dictionary = sample2["前左上肢"].duplicate(true)
	lowered["rotation"] = [0.0, 0.0, 15.0]
	sample2["前左上肢"] = lowered
	frames.insert(2, {"time": 1.4, "poses": sample2})
	evaluate(0.0)

# Convert Blockbench channels into editable local poses, at a fixed sampling rate.
# Keeping the source animation in rig.bb_animations allows switching without reimporting.
func load_bb_animation(index: int) -> String:
	if index < 0 or index >= rig.bb_animations.size():
		return "選択されたモーションがありません"
	var animation: Dictionary = rig.bb_animations[index]
	var animators: Dictionary = animation.get("animators", {})
	var channels: Dictionary = {}
	var latest: float = 0.0
	for uuid in animators.keys():
		var part: String = str(rig.bb_uuid_to_name.get(str(uuid), ""))
		if part == "" or not (animators[uuid] is Dictionary):
			continue
		var animator: Dictionary = animators[uuid]
		if not channels.has(part):
			channels[part] = {}
		for keyframe in animator.get("keyframes", []):
			if not (keyframe is Dictionary):
				continue
			var channel := str(keyframe.get("channel", ""))
			if not (channel in ["position", "rotation", "scale"]):
				continue
			if not channels[part].has(channel):
				channels[part][channel] = []
			channels[part][channel].append(keyframe)
			latest = maxf(latest, float(keyframe.get("time", 0.0)))
	for part in channels.keys():
		for channel in channels[part].keys():
			channels[part][channel].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return float(a.get("time", 0.0)) < float(b.get("time", 0.0)))
	duration = maxf(0.1, maxf(float(animation.get("length", 0.0)), latest))
	fps = clampi(int(animation.get("snapping", 24)), 24, 60)
	constraints.clear()
	bake_source.clear()
	bake_report.clear()
	history.clear()
	future.clear()
	frames.clear()
	var frame_total: int = mini(1800, int(ceil(duration * float(fps))) + 1)
	for i in range(frame_total):
		var t := minf(float(i) / float(fps), duration)
		if i == frame_total - 1:
			t = duration
		var poses: Dictionary = rig.rest.duplicate(true)
		for part in channels.keys():
			if not poses.has(part):
				continue
			var pose: Dictionary = poses[part].duplicate(true)
			for channel in channels[part].keys():
				var sampled := _bb_channel_value(channels[part][channel], t, channel)
				var base := MotionRig.from_array(pose[channel])
				match channel:
					"position":
						base += sampled / 16.0
					"rotation":
						base += sampled
					"scale":
						base *= sampled
				pose[channel] = MotionRig.vec3_array(base)
			poses[part] = pose
		frames.append({"time": t, "poses": poses})
	play_time = 0.0
	evaluate(0.0)
	return "「%s」を読み込みました：%dパーツ、%.2f秒" % [str(animation.get("name", "無題")), channels.size(), duration]

func _bb_channel_vector(frame: Dictionary, channel: String, pre: bool) -> Vector3:
	var points: Array = frame.get("data_points", [])
	if points.is_empty():
		return Vector3.ONE if channel == "scale" else Vector3.ZERO
	var point: Variant = points[0] if pre or points.size() == 1 else points[points.size() - 1]
	if not (point is Dictionary):
		return Vector3.ONE if channel == "scale" else Vector3.ZERO
	var values := Vector3(str(point.get("x", "0")).to_float(),
		str(point.get("y", "0")).to_float(),
		str(point.get("z", "0")).to_float())
	if rig.bb_legacy_axes:
		if channel == "position":
			values.x = -values.x
		elif channel == "rotation":
			values.x = -values.x
			values.y = -values.y
	return values

func _bb_channel_value(track: Array, at_time: float, channel: String) -> Vector3:
	if track.is_empty():
		return Vector3.ONE if channel == "scale" else Vector3.ZERO
	var left: Dictionary = track[0]
	var right: Dictionary = track[track.size() - 1]
	for keyframe in track:
		if float(keyframe.get("time", 0.0)) <= at_time:
			left = keyframe
		if float(keyframe.get("time", 0.0)) >= at_time:
			right = keyframe
			break
	if left == right:
		return _bb_channel_vector(left, channel, false)
	var a := _bb_channel_vector(left, channel, false)
	var b := _bb_channel_vector(right, channel, true)
	if str(left.get("interpolation", "linear")) == "step":
		return a
	var span := float(right.get("time", 0.0)) - float(left.get("time", 0.0))
	if span <= 0.00001:
		return a
	var weight := clampf((at_time - float(left.get("time", 0.0))) / span, 0.0, 1.0)
	if str(left.get("interpolation", "")) == "catmullrom":
		weight = weight * weight * (3.0 - 2.0 * weight)
	return a.lerp(b, weight)

func _sort_key(a: Dictionary, b: Dictionary) -> bool:
	return float(a["time"]) < float(b["time"])

func _ensure_sorted() -> void:
	frames.sort_custom(_sort_key)

func _interpolate_pose(pa: Dictionary, pb: Dictionary, weight: float) -> Dictionary:
	var output: Dictionary = {}
	for field in ["position", "rotation", "scale"]:
		var av := MotionRig.from_array(pa.get(field, [0, 0, 0]))
		var bv := MotionRig.from_array(pb.get(field, [0, 0, 0]))
		var v := av.lerp(bv, weight)
		if field == "rotation":
			v = Vector3(rad_to_deg(lerp_angle(deg_to_rad(av.x), deg_to_rad(bv.x), weight)),
				rad_to_deg(lerp_angle(deg_to_rad(av.y), deg_to_rad(bv.y), weight)),
				rad_to_deg(lerp_angle(deg_to_rad(av.z), deg_to_rad(bv.z), weight)))
		output[field] = MotionRig.vec3_array(v)
	return output

func sample(at_time: float) -> Dictionary:
	if frames.is_empty():
		return rig.rest.duplicate(true)
	_ensure_sorted()
	var t := clampf(at_time, 0.0, duration)
	var left: Dictionary = frames[0]
	var right: Dictionary = frames[frames.size() - 1]
	for frame in frames:
		if float(frame["time"]) <= t:
			left = frame
		if float(frame["time"]) >= t:
			right = frame
			break
	var span: float = float(right["time"]) - float(left["time"])
	var alpha: float = clampf((t - float(left["time"])) / span, 0.0, 1.0) if span > 0.00001 else 0.0
	var pose_map: Dictionary = {}
	for name in rig.parts.keys():
		var default_pose: Dictionary = rig.rest.get(name, {})
		var ap: Dictionary = left["poses"].get(name, default_pose)
		var bp: Dictionary = right["poses"].get(name, default_pose)
		pose_map[name] = _interpolate_pose(ap, bp, alpha)
	return pose_map

func evaluate(at_time: float) -> void:
	play_time = clampf(at_time, 0.0, duration)
	var sampled := sample(play_time)
	for name in sampled.keys():
		rig.set_pose(name, sampled[name])
	for name in constraints.keys():
		_apply_constraint(name, constraints[name])
	for chain in rig.chains:
		if chain.get("enabled", false) and play_time >= float(chain.get("start", 0.0)) and play_time <= float(chain.get("finish", duration)):
			_solve_chain(chain)
	warnings = diagnose()

# Capture every editable local joint transform after FK, constraints and IK.
# This is an explicit in-place conversion of the timeline, not merely a .tres export.
# The source is backed up, so users can restore the original animation and IK setup.
# For surfaces/obstacles this does not bake collision or physics responses.
func bake_ik_fk(target_fps: int = 60) -> Dictionary:
	if rig == null or rig.parts.is_empty() or frames.is_empty():
		return {"ok": false, "message": "モデルかキーフレームがありません"}
	if target_fps != 30 and target_fps != 60:
		return {"ok": false, "message": "ベイクは30fpsまたは60fpsを選択してください"}
	var frame_count: int = int(ceil(duration * float(target_fps))) + 1
	if frame_count > MAX_BAKE_FRAMES:
		return {"ok": false, "message": "最大3601フレームです。再生時間かfpsを減らしてください"}
	record_undo()
	var source: Dictionary = snapshot()
	source.erase("bake_source")
	source.erase("bake_report")
	# Keep the first non-baked source when re-baking existing output.
	if bake_source.is_empty():
		bake_source = source.duplicate(true)
	var return_time: float = play_time
	var generated: Array = []
	var times: Array[float] = []
	var reference_midpoints: Array = []
	var interval: int = maxi(1, int(ceil(float(frame_count - 1) / 120.0)))
	for index in range(frame_count):
		var t: float = minf(duration, float(index) / float(target_fps))
		if index == frame_count - 1:
			t = duration
		evaluate(t)
		var poses: Dictionary = {}
		for name in rig.parts.keys():
			poses[name] = MotionRig.pose_of(rig.parts[name])
		generated.append({"time": t, "poses": poses})
		times.append(t)
		# Verify points between keys, where baking approximation may diverge.
		if index > 0 and index % interval == 0:
			var midpoint: float = 0.5 * (times[index - 1] + t)
			if midpoint > times[index - 1] and midpoint < t:
				evaluate(midpoint)
				var reference: Dictionary = {}
				for name in rig.parts.keys():
					reference[name] = MotionRig.pose_of(rig.parts[name])
				reference_midpoints.append({"time": midpoint, "poses": reference})
	frames = generated
	fps = target_fps
	# Baked motion no longer requires per-frame IK or active constraints.
	for chain in rig.chains:
		chain["enabled"] = false
	for name in constraints.keys():
		constraints[name]["enabled"] = false
	var worst_position: float = 0.0
	var worst_rotation: float = 0.0
	var worst_scale: float = 0.0
	for reference in reference_midpoints:
		var time: float = float(reference["time"])
		evaluate(time)
		for name in rig.parts.keys():
			var original: Dictionary = reference["poses"][name]
			var node: Node3D = rig.parts[name]
			var source_position: Vector3 = MotionRig.from_array(original["position"])
			var source_rotation: Vector3 = MotionRig.from_array(original["rotation"])
			var source_scale: Vector3 = MotionRig.from_array(original["scale"])
			worst_position = maxf(worst_position, node.position.distance_to(source_position))
			var source_quat := Basis.from_euler(Vector3(
				deg_to_rad(source_rotation.x), deg_to_rad(source_rotation.y), deg_to_rad(source_rotation.z)), node.rotation_order).get_rotation_quaternion()
			worst_rotation = maxf(worst_rotation, rad_to_deg(node.quaternion.angle_to(source_quat)))
			worst_scale = maxf(worst_scale, node.scale.distance_to(source_scale))
	bake_report = {"fps": target_fps, "frame_count": generated.size(),
		"max_position_error_m": worst_position, "max_rotation_error_deg": worst_rotation,
		"max_scale_error": worst_scale, "checked_midpoints": reference_midpoints.size()}
	evaluate(return_time)
	return {"ok": true, "message": "ベイク完了：%dフレーム（%dfps）。IK・制約計算は停止しました" % [generated.size(), target_fps],
		"report": bake_report.duplicate(true)}

func restore_bake_source() -> bool:
	if bake_source.is_empty():
		return false
	record_undo()
	var original: Dictionary = bake_source.duplicate(true)
	restore(original)
	return true

func default_constraint() -> Dictionary:
	return {"enabled": true, "weight": 1.0, "start": 0.0, "finish": duration,
		"position_min": [-10.0, -10.0, -10.0], "position_max": [10.0, 10.0, 10.0],
		"rotation_min": [-180.0, -180.0, -180.0], "rotation_max": [180.0, 180.0, 180.0],
		"scale_min": [0.05, 0.05, 0.05], "scale_max": [5.0, 5.0, 5.0]}

func _apply_constraint(name: String, entry: Dictionary) -> void:
	if not rig.parts.has(name) or not entry.get("enabled", true):
		return
	if play_time < float(entry.get("start", 0.0)) or play_time > float(entry.get("finish", duration)):
		return
	var weight := clampf(float(entry.get("weight", 1.0)), 0.0, 1.0)
	var node: Node3D = rig.parts[name]
	for field in ["position", "rotation", "scale"]:
		var current: Vector3 = node.rotation_degrees if field == "rotation" else (node.scale if field == "scale" else node.position)
		var mini: Vector3 = MotionRig.from_array(entry[field + "_min"])
		var maxi: Vector3 = MotionRig.from_array(entry[field + "_max"])
		var corrected := Vector3(clampf(current.x, mini.x, maxi.x),
			clampf(current.y, mini.y, maxi.y), clampf(current.z, mini.z, maxi.z))
		var blended := current.lerp(corrected, weight)
		match field:
			"position": node.position = blended
			"rotation": node.rotation_degrees = blended
			"scale": node.scale = blended

func _solve_chain(chain: Dictionary) -> void:
	var root: Node3D = rig.parts.get(chain["root"])
	var mid: Node3D = rig.parts.get(chain["mid"])
	var end: Node3D = rig.parts.get(chain["end"])
	if root == null or mid == null or end == null:
		return
	var tip := MotionRig.from_array(chain["tip"])
	var target: Node3D = chain["target"]
	var weight := clampf(float(chain.get("weight", 1.0)), 0.0, 1.0)
	if weight <= 0.0:
		return
	var original_root: Quaternion = root.quaternion
	var original_mid: Quaternion = mid.quaternion
	match chain.get("method", "CCD"):
		"FABRIK": _solve_fabrik(root, mid, end, tip, target.global_position)
		"2ボーン": _solve_two_bone(root, mid, end, tip, target.global_position,
			MotionRig.from_array(chain.get("pole", [0.0, 0.0, 1.0])))
		_: _solve_ccd(root, mid, end, tip, target.global_position, 8)
	root.quaternion = original_root.slerp(root.quaternion, weight)
	mid.quaternion = original_mid.slerp(mid.quaternion, weight)
	if constraints.has(chain["root"]):
		_apply_constraint(chain["root"], constraints[chain["root"]])
	if constraints.has(chain["mid"]):
		_apply_constraint(chain["mid"], constraints[chain["mid"]])

func _rotate_toward(node: Node3D, source: Vector3, dest: Vector3, max_angle: float = PI) -> void:
	if source.length_squared() < 0.000001 or dest.length_squared() < 0.000001:
		return
	var a: Vector3 = source.normalized()
	var b: Vector3 = dest.normalized()
	var axis: Vector3 = a.cross(b)
	var alignment: float = clampf(a.dot(b), -1.0, 1.0)
	if axis.length_squared() < 0.000001:
		if alignment > 0.0:
			return
		# Antiparallel vectors still need a deterministic 180-degree rotation.
		var alternative: Vector3 = Vector3.UP if absf(a.dot(Vector3.UP)) < 0.85 else Vector3.RIGHT
		axis = a.cross(alternative).normalized()
	var turn: float = minf(acos(alignment), max_angle)
	var old := node.global_transform
	node.global_transform = Transform3D(Basis(axis.normalized(), turn) * old.basis, old.origin)

# Analytic world-space two-link IK (law of cosines), with a pole direction.
# The links are root->mid and mid->end effector; no bone lengths are modified.
# Pole represents a world-space direction from the root toward the desired knee.
func _solve_two_bone(root: Node3D, mid: Node3D, end: Node3D,
		tip: Vector3, target: Vector3, pole: Vector3) -> void:
	var p0: Vector3 = root.global_position
	var p1: Vector3 = mid.global_position
	var p2: Vector3 = end.to_global(tip)
	var upper_len: float = p0.distance_to(p1)
	var lower_len: float = p1.distance_to(p2)
	if upper_len < 0.00001 or lower_len < 0.00001:
		return
	var to_goal: Vector3 = target - p0
	var wanted_distance: float = to_goal.length()
	var direction: Vector3 = to_goal.normalized() if wanted_distance > 0.00001 else (p2 - p0).normalized()
	if direction.length_squared() < 0.00001:
		direction = Vector3.FORWARD
	# A two-link limb reaches only within |L1-L2| ... (L1+L2).
	# Keep epsilon at either singularity for a stable bend normal.
	var minimum: float = absf(upper_len - lower_len) + 0.000001
	var maximum: float = upper_len + lower_len - 0.000001
	var distance: float = clampf(wanted_distance, minimum, maximum)
	var reachable_tip: Vector3 = p0 + direction * distance
	var knee_direction: Vector3 = pole - direction * pole.dot(direction)
	if knee_direction.length_squared() < 0.000001:
		var prior: Vector3 = p1 - p0
		knee_direction = prior - direction * prior.dot(direction)
	if knee_direction.length_squared() < 0.000001:
		var reference: Vector3 = Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		knee_direction = reference - direction * reference.dot(direction)
	knee_direction = knee_direction.normalized()
	var projection: float = (distance * distance + upper_len * upper_len - lower_len * lower_len) / (2.0 * distance)
	var height: float = sqrt(maxf(0.0, upper_len * upper_len - projection * projection))
	var desired_knee: Vector3 = p0 + direction * projection + knee_direction * height
	_rotate_toward(root, p1 - p0, desired_knee - p0)
	# Root rotation moved the knee and tip; now rotate the knee's lower segment
	# to the point specified by the 2-link geometric solution.
	var current_tip: Vector3 = end.to_global(tip)
	_rotate_toward(mid, current_tip - mid.global_position, reachable_tip - mid.global_position)

func _solve_ccd(root: Node3D, mid: Node3D, end: Node3D, tip: Vector3, target: Vector3, iterations: int) -> void:
	for _iter in range(iterations):
		if end.to_global(tip).distance_to(target) < 0.008:
			break
		for joint in [mid, root]:
			var from_joint: Vector3 = end.to_global(tip) - joint.global_position
			var to_target: Vector3 = target - joint.global_position
			_rotate_toward(joint, from_joint, to_target, 0.35)

func _solve_fabrik(root: Node3D, mid: Node3D, end: Node3D, tip: Vector3, target: Vector3) -> void:
	# Two-segment FABRIK, reconstructed as joint rotations (without changing bone lengths).
	var p0 := root.global_position
	var p1 := mid.global_position
	var p2 := end.to_global(tip)
	var l0 := p0.distance_to(p1)
	var l1 := p1.distance_to(p2)
	if l0 < 0.0001 or l1 < 0.0001:
		return
	if p0.distance_to(target) >= l0 + l1:
		p1 = p0 + (target - p0).normalized() * l0
		p2 = p1 + (target - p1).normalized() * l1
	else:
		for _i in range(12):
			p2 = target
			p1 = p2 + (p1 - p2).normalized() * l1
			p0 = root.global_position
			p1 = p0 + (p1 - p0).normalized() * l0
			p2 = p1 + (p2 - p1).normalized() * l1
			if p2.distance_to(target) < 0.007:
				break
	_rotate_toward(root, mid.global_position - root.global_position, p1 - root.global_position)
	_rotate_toward(mid, end.to_global(tip) - mid.global_position, p2 - mid.global_position)

func diagnose() -> Array:
	var report: Array = []
	for chain in rig.chains:
		if not chain.get("enabled", false):
			continue
		if play_time < float(chain.get("start", 0.0)) or play_time > float(chain.get("finish", duration)):
			continue
		var end: Node3D = rig.parts.get(chain["end"])
		var target: Node3D = chain["target"]
		if end == null:
			continue
		var error := end.to_global(MotionRig.from_array(chain["tip"])).distance_to(target.global_position)
		if error > 0.08:
			report.append(str(chain["name"]) + "：IK目標との誤差 %.3fm" % error)
	return report

func record_undo() -> void:
	history.append(JSON.stringify(snapshot()))
	if history.size() > MAX_UNDO:
		history.pop_front()
	future.clear()

func undo() -> bool:
	if history.is_empty():
		return false
	future.append(JSON.stringify(snapshot()))
	var previous: Variant = JSON.parse_string(history.pop_back())
	if previous is Dictionary:
		restore(previous)
		return true
	return false

func redo() -> bool:
	if future.is_empty():
		return false
	history.append(JSON.stringify(snapshot()))
	var next: Variant = JSON.parse_string(future.pop_back())
	if next is Dictionary:
		restore(next)
		return true
	return false

func set_key_component(at_time: float, part: String, field: String, axis: int, value: float) -> void:
	if not rig.parts.has(part):
		return
	var t: float = snappedf(clampf(at_time, 0.0, duration), 0.001)
	var poses: Dictionary = sample(t)
	var entry: Dictionary = poses[part].duplicate(true)
	var vector: Array = entry[field].duplicate()
	vector[axis] = value
	entry[field] = vector
	poses[part] = entry
	_insert_frame(t, poses)
	evaluate(t)

func capture_key(at_time: float) -> void:
	var t: float = snappedf(clampf(at_time, 0.0, duration), 0.001)
	var poses: Dictionary = {}
	for name in rig.parts.keys():
		poses[name] = MotionRig.pose_of(rig.parts[name])
	_insert_frame(t, poses)
	evaluate(t)

func delete_key(at_time: float) -> bool:
	if frames.size() <= 2:
		return false
	var index := -1
	var best := 9999.0
	for i in range(frames.size()):
		var delta := absf(float(frames[i]["time"]) - at_time)
		if delta < best:
			best = delta
			index = i
	if index < 0 or best >= 0.04:
		return false
	if absf(float(frames[index]["time"])) < 0.0005 or absf(float(frames[index]["time"]) - duration) < 0.0005:
		return false
	record_undo()
	frames.remove_at(index)
	evaluate(at_time)
	return true

# Move a whole keyframe to another time. Motion Studio currently stores one
# full-body pose per time, so this intentionally moves the whole frame rather
# than pretending that each track has independent timing.
func move_keyframe(from_time: float, requested_time: float) -> bool:
	if frames.size() < 3:
		return false
	var original_index: int = -1
	for i in range(frames.size()):
		if absf(float(frames[i]["time"]) - from_time) < 0.0006:
			original_index = i
			break
	if original_index < 0 or original_index == 0 or original_index == frames.size() - 1:
		return false
	var current_time: float = float(frames[original_index]["time"])
	var new_time: float = snappedf(clampf(requested_time, 0.0, duration), 1.0 / float(maxi(1, fps)))
	if new_time < 0.0005 or new_time > duration - 0.0005:
		return false
	if absf(new_time - current_time) < 0.0005:
		return false
	for i in range(frames.size()):
		if i != original_index and absf(float(frames[i]["time"]) - new_time) < 0.0006:
			return false
	record_undo()
	var moved: Dictionary = frames[original_index].duplicate(true)
	moved["time"] = new_time
	frames.remove_at(original_index)
	frames.append(moved)
	_ensure_sorted()
	evaluate(new_time)
	return true

func _insert_frame(t: float, poses: Dictionary) -> void:
	for i in range(frames.size()):
		if absf(float(frames[i]["time"]) - t) < 0.0005:
			frames[i] = {"time": t, "poses": poses}
			return
	frames.append({"time": t, "poses": poses})
	_ensure_sorted()

func snapshot() -> Dictionary:
	var chain_info: Array = []
	for chain in rig.chains:
		var item: Dictionary = chain.duplicate(true)
		item["target"] = MotionRig.vec3_array(chain["target"].global_position)
		chain_info.append(item)
	var obstacle_info: Array = []
	for item in rig.test_objects:
		obstacle_info.append({"kind": item["kind"], "position": MotionRig.vec3_array(item["node"].position),
			"rotation": MotionRig.vec3_array(item["node"].rotation_degrees), "scale": MotionRig.vec3_array(item["node"].scale)})
	return {"format": "motion-studio-v1", "source": rig.imported_source,
		"duration": duration, "fps": fps, "time": play_time,
		"frames": frames.duplicate(true), "constraints": constraints.duplicate(true),
		"chains": chain_info, "obstacles": obstacle_info,
		"bake_source": bake_source.duplicate(true), "bake_report": bake_report.duplicate(true)}

func restore(data: Dictionary) -> void:
	duration = float(data.get("duration", 3.0))
	fps = int(data.get("fps", 60))
	frames = data.get("frames", []).duplicate(true)
	constraints = data.get("constraints", {}).duplicate(true)
	bake_source = data.get("bake_source", {}).duplicate(true)
	bake_report = data.get("bake_report", {}).duplicate(true)
	rig.clear_test_objects()
	for item in data.get("obstacles", []):
		var index: int = rig.add_test_object(str(item.get("kind", "箱")), MotionRig.from_array(item.get("position", [0, 0.5, 0])))
		var obstacle: Node3D = rig.test_objects[index]["node"]
		obstacle.rotation_degrees = MotionRig.from_array(item.get("rotation", [0, 0, 0]))
		obstacle.scale = MotionRig.from_array(item.get("scale", [1, 1, 1]))
	for old_target in rig._target_group.get_children():
		old_target.queue_free()
	rig.chains.clear()
	for chain in data.get("chains", []):
		rig.add_chain(str(chain.get("name", "IK")), str(chain.get("root", "")), str(chain.get("mid", "")),
			str(chain.get("end", "")), MotionRig.from_array(chain.get("tip", [0, 0, 0])), MotionRig.from_array(chain.get("target", [0, 0, 0])))
		if rig.chains.is_empty():
			continue
		var latest: Dictionary = rig.chains[-1]
		for key in ["enabled", "method", "weight", "start", "finish", "pole"]:
			latest[key] = chain.get(key, latest.get(key))
	evaluate(float(data.get("time", 0.0)))

func save_project(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "保存できません：" + str(FileAccess.get_open_error())
	file.store_string(JSON.stringify(snapshot(), "  "))
	file.close()
	return "保存しました：" + path

func load_project(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "読み込めません"
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not (data is Dictionary) or data.get("format", "") != "motion-studio-v1":
		return "Motion Studio形式ではありません"
	var source: String = str(data.get("source", "sample"))
	if source == "sample":
		rig.create_sample()
	elif source.to_lower().ends_with(".bbmodel"):
		var issue := rig.load_bbmodel(source)
		if issue != "":
			return issue
	else:
		var issue := rig.load_gltf(source)
		if issue != "":
			return issue
	restore(data)
	history.clear()
	future.clear()
	return "読み込みました：" + path

func export_animation_tres(path: String) -> String:
	# All evaluated local FK transforms are output once per frame.
	# With an already-baked timeline this emits keys without doing runtime IK.
	var saved_time: float = play_time
	var anim := Animation.new()
	anim.length = duration
	anim.step = 1.0 / float(fps)
	var tracks: Array = []
	for name in rig.parts.keys():
		var joint: Node3D = rig.parts[name]
		var node_path: NodePath = rig.get_path_to(joint)
		var pos_track: int = anim.add_track(Animation.TYPE_POSITION_3D)
		var rot_track: int = anim.add_track(Animation.TYPE_ROTATION_3D)
		var scale_track: int = anim.add_track(Animation.TYPE_SCALE_3D)
		for idx in [pos_track, rot_track, scale_track]:
			anim.track_set_path(idx, node_path)
		tracks.append({"joint": joint, "position": pos_track, "rotation": rot_track, "scale": scale_track})
	var frame_count: int = int(ceil(duration * float(fps))) + 1
	for frame_index in range(frame_count):
		var t: float = minf(float(frame_index) / float(fps), duration)
		if frame_index == frame_count - 1:
			t = duration
		evaluate(t)
		for item in tracks:
			var joint: Node3D = item["joint"]
			anim.position_track_insert_key(int(item["position"]), t, joint.position)
			anim.rotation_track_insert_key(int(item["rotation"]), t, joint.quaternion)
			anim.scale_track_insert_key(int(item["scale"]), t, joint.scale)
	evaluate(saved_time)
	var result: Error = ResourceSaver.save(anim, path)
	if result != OK:
		return "アニメーション出力失敗：" + str(result)
	return "Godotアニメーションを出力しました：" + path
