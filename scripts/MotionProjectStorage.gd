extends RefCounted
class_name MotionProjectStorage

## Store complete projects via verified staging, retaining the last valid backup.
## A damaged primary never replaces an intact .backup.

const MAX_PROJECT_BYTES := 64000000

static func valid_source(source: String) -> bool:
	if source.to_utf8_buffer().size() > MAX_PROJECT_BYTES:
		return false
	var parsed: Variant = JSON.parse_string(source)
	if not (parsed is Dictionary):
		return false
	if str(parsed.get("format", "")) != "motion-studio-v1":
		return false
	var raw_duration: Variant = parsed.get("duration", null)
	var raw_fps: Variant = parsed.get("fps", null)
	if not (raw_duration is float or raw_duration is int) or not (raw_fps is float or raw_fps is int):
		return false
	var seconds := float(raw_duration)
	var rate := float(raw_fps)
	if not is_finite(seconds) or seconds <= 0.0 or seconds > 3600.0 or not is_finite(rate) or rate < 1.0 or rate > 240.0:
		return false
	var frames: Variant = parsed.get("frames", null)
	if not (frames is Array) or frames.is_empty():
		return false
	for entry in frames:
		if not (entry is Dictionary):
			return false
		var at: Variant = entry.get("time", null)
		if not (at is int or at is float) or not is_finite(float(at)):
			return false
		if float(at) < -0.001 or float(at) > seconds + 0.001:
			return false
		var poses: Variant = entry.get("poses", null)
		if not (poses is Dictionary):
			return false
		for pose in poses.values():
			if not (pose is Dictionary):
				return false
			for field in ["position", "rotation", "scale"]:
				var components: Variant = pose.get(field, null)
				if not (components is Array) or components.size() != 3:
					return false
				for component in components:
					if not (component is int or component is float) or not is_finite(float(component)):
						return false
	for expected in ["constraints", "chains", "contacts", "obstacles"]:
		var fallback: Variant = {} if expected == "constraints" else []
		var value: Variant = parsed.get(expected, fallback)
		if expected == "constraints" and not (value is Dictionary):
			return false
		if expected != "constraints" and not (value is Array):
			return false
	return true

static func read_valid(path: String) -> Dictionary:
	if path.begins_with("content://"):
		return {"ok": false}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false}
	if file.get_length() > MAX_PROJECT_BYTES:
		file.close()
		return {"ok": false}
	var source := file.get_as_text()
	file.close()
	if not valid_source(source):
		return {"ok": false}
	return {"ok": true, "text": source, "data": JSON.parse_string(source)}

static func read_with_backup(path: String) -> Dictionary:
	var primary := read_valid(path)
	if bool(primary.get("ok", false)):
		primary["recovered"] = false
		return primary
	var backup := read_valid(path + ".backup")
	if bool(backup.get("ok", false)):
		backup["recovered"] = true
		return backup
	return {"ok": false, "recovered": false}

static func save_snapshot(path: String, snapshot: Dictionary) -> bool:
	var source := JSON.stringify(snapshot, "  ")
	if source.to_utf8_buffer().size() > MAX_PROJECT_BYTES or not valid_source(source):
		return false
	# Content URIs cannot be safely renamed or copied using filesystem APIs.
	if path.begins_with("content://"):
		return false
	var temp_path := path + ".tmp"
	var staging := FileAccess.open(temp_path, FileAccess.WRITE)
	if staging == null:
		return false
	staging.store_string(source)
	staging.flush()
	staging.close()
	var staged := read_valid(temp_path)
	if not bool(staged.get("ok", false)) or str(staged.get("text", "")) != source:
		return false
	if bool(read_valid(path).get("ok", false)):
		if DirAccess.copy_absolute(path, path + ".backup") != OK:
			return false
	var error := DirAccess.rename_absolute(temp_path, path)
	if error != OK:
		error = DirAccess.copy_absolute(temp_path, path)
		if error == OK:
			DirAccess.remove_absolute(temp_path)
	return error == OK and bool(read_valid(path).get("ok", false))
