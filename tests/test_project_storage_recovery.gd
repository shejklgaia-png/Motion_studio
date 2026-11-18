extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var path := "user://motion_storage_regression.motion.json"
	for suffix in ["", ".backup", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	var rig := MotionRig.new()
	root.add_child(rig)
	rig.create_sample()
	var engine := MotionEngine.new()
	engine.setup(rig)
	if not engine.save_project(path).begins_with("保存しました"):
		_fail("first save failed")
		return
	engine.duration = 4.0
	if not engine.save_project(path).begins_with("保存しました"):
		_fail("second save failed")
		return
	var backup := MotionProjectStorage.read_valid(path + ".backup")
	if not bool(backup.get("ok", false)) or absf(float(backup["data"]["duration"]) - 3.0) > 0.0001:
		_fail("valid previous project missing from backup")
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	var result := engine.load_project(path)
	if not result.contains("バックアップから復元") or absf(engine.duration - 3.0) > 0.0001:
		_fail("corrupted save did not restore the valid backup: " + result)
		return
	engine.duration = 5.0
	if not engine.save_project(path).begins_with("保存しました"):
		_fail("saving after corruption failed")
		return
	if absf(float(MotionProjectStorage.read_valid(path + ".backup")["data"]["duration"]) - 3.0) > 0.0001:
		_fail("corrupted primary overwrote backup")
		return
	if absf(float(MotionProjectStorage.read_valid(path)["data"]["duration"]) - 5.0) > 0.0001:
		_fail("repaired primary was not persisted")
		return
	if MotionProjectStorage.valid_source('{"format":"motion-studio-v1","duration":3,"fps":60,"frames":[{"time":0,"poses":{"joint":{"position":[1],"rotation":[0,0,0],"scale":[1,1,1]}}}]}'):
		_fail("malformed pose was accepted")
		return
	var original := str(MotionProjectStorage.read_valid(path).get("text", ""))
	if MotionProjectStorage.save_snapshot(path, {"format": "motion-studio-v1", "frames": []}):
		_fail("invalid snapshot accepted")
		return
	if str(MotionProjectStorage.read_valid(path).get("text", "")) != original:
		_fail("invalid snapshot changed saved data")
		return
	DirAccess.remove_absolute(path)
	if not bool(MotionProjectStorage.read_with_backup(path).get("recovered", false)):
		_fail("missing primary could not recover backup")
		return
	for suffix in ["", ".backup", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	print("MOTION STORAGE RECOVERY PASS")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
