extends SceneTree

func _initialize() -> void:
	var snapshot := {"format":"motion-studio-v1","duration":1.0,"fps":30.0,"frames":[{"time":0.0,"poses":{}}]}
	assert(not MotionProjectStorage.save_snapshot("", snapshot))
	assert(not MotionProjectStorage.save_snapshot("user://guard.backup", snapshot))
	assert(not MotionProjectStorage.save_snapshot("user://guard.tmp", snapshot))
	assert(not MotionProjectStorage.save_snapshot("content://guard", snapshot))
	quit(0)
