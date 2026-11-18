extends SceneTree

func _initialize() -> void:
	call_deferred("_verify")

func _has_time(frames: Array, wanted: float) -> bool:
	for frame in frames:
		if absf(float(frame["time"]) - wanted) < 0.0006:
			return true
	return false

func _verify() -> void:
	var scene: PackedScene = load("res://Main.tscn")
	if scene == null:
		_fail("Missing Main")
		return
	var app: Control = scene.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	var engine: MotionEngine = app.get("motion")
	var timeline: MotionTimelineView = app.get("timeline_view")
	var undo_btn: Button = app.get("undo_button")
	var redo_btn: Button = app.get("redo_button")
	var fit_btn: Button = app.get("fit_button")
	var camera_distance: float = float(app.get("camera_distance"))
	var gizmo: MotionGizmo = app.get("motion_gizmo")
	if undo_btn == null or redo_btn == null or fit_btn == null or gizmo == null:
		_fail("Basic editing/navigation buttons missing")
		return
	if not undo_btn.visible or not redo_btn.visible or fit_btn.get_parent() != app.get("preview_frame"):
		_fail("Undo/redo or preview fit button incorrectly placed")
		return
	if gizmo.radius_pixels < 70.0:
		_fail("Finger manipulation handles are too small")
		return
	app.call("_zoom", 1.65)
	app.call("_fit_import_camera")
	if absf(float(app.get("camera_distance")) - camera_distance) > 0.005:
		_fail("One-tap reset did not fit original model")
		return
	app.set("selected_part", "前左上肢")
	app.call("_refresh_part_picker")
	await process_frame
	var original_rotation: Array = engine.frames[1]["poses"]["前左上肢"]["rotation"].duplicate()
	var original_count: int = engine.frames.size()
	var start: float = 0.7
	var destination: float = 1.0
	var y: float = MotionTimelineView.HEADER_H + MotionTimelineView.ROW_H * 0.5
	timeline._press(Vector2(timeline._time_to_x(start), y))
	timeline._move(Vector2(timeline._time_to_x(destination), y))
	if not timeline.dragging_key:
		_fail("Diamond did not enter move mode")
		return
	timeline._release()
	await process_frame
	if not _has_time(engine.frames, destination) or _has_time(engine.frames, start):
		_fail("Timeline drag did not shift the keyframe")
		return
	if engine.frames.size() != original_count:
		_fail("Moving key added or removed frames")
		return
	if absf(float(engine.frames[1]["poses"]["前左上肢"]["rotation"][2]) - float(original_rotation[2])) > 0.0001:
		_fail("Moving a key modified its animation pose")
		return
	app.call("_update_history_buttons")
	if undo_btn.disabled or not redo_btn.disabled:
		_fail("Undo/redo enabled states not updated after editing")
		return
	var before_conflict: String = JSON.stringify(engine.frames)
	if engine.move_keyframe(destination, 1.4):
		_fail("Overlapping destination key should be rejected")
		return
	if JSON.stringify(engine.frames) != before_conflict:
		_fail("Rejected move unexpectedly changed timeline")
		return
	app.call("_toolbar_action", "undo")
	if not _has_time(engine.frames, start) or _has_time(engine.frames, destination):
		_fail("Visible undo did not restore key time")
		return
	app.call("_update_history_buttons")
	if redo_btn.disabled:
		_fail("Redo remained disabled after undo")
		return
	app.call("_toolbar_action", "redo")
	if not _has_time(engine.frames, destination) or _has_time(engine.frames, start):
		_fail("Visible redo did not restore the key move")
		return
	var end_time: float = engine.duration
	if engine.move_keyframe(0.0, 1.0) or engine.move_keyframe(end_time, 2.7):
		_fail("Keyframe endpoint protection broken")
		return
	print("MOTION UX PASS: camera fit, larger gizmo, draggable diamond retiming, collision guard and undo/redo")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
