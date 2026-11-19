extends SceneTree

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var scene: PackedScene = load("res://Main.tscn")
	if scene == null:
		_fail("Main scene missing")
		return
	var app: Control = scene.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	var engine: MotionEngine = app.get("motion")
	var rig: MotionRig = app.get("rig")
	var timeline: MotionTimelineView = app.get("timeline_view")
	if rig.chains.is_empty():
		_fail("Sample IK chain missing")
		return
	var original_frames: String = JSON.stringify(engine.frames)
	app.call("_change_mode", "IK")
	await process_frame
	if not timeline.visible or timeline.key_rows_visible or timeline.ik_index != 0:
		_fail("IK mode must display selected time span without FK rows")
		return
	var chain: Dictionary = rig.chains[0]
	chain["enabled"] = true
	chain["start"] = 0.50
	chain["finish"] = 1.90
	app.call("_refresh_timeline_view")
	await process_frame
	var y: float = timeline._ik_track_y() + 20.0
	var x_start: float = timeline._time_to_x(0.50)
	timeline._press(Vector2(x_start, y))
	timeline._move(Vector2(timeline._time_to_x(0.80), y))
	if timeline.ik_drag_mode != "start" or absf(timeline.ik_preview_start - 0.8) > 0.02:
		_fail("Dragging start handle did not preview retiming")
		return
	timeline._release()
	if absf(float(chain["start"]) - 0.8) > 0.02 or absf(float(chain["finish"]) - 1.9) > 0.01:
		_fail("Dragging IK start did not change application period")
		return
	if not engine.undo():
		_fail("IK interval drag could not be undone")
		return
	if absf(float(rig.chains[0]["start"]) - 0.50) > 0.01:
		_fail("Undo did not restore IK interval")
		return
	app.call("_refresh_timeline_view")
	if not engine.redo():
		_fail("IK interval drag could not be redone")
		return
	app.call("_refresh_timeline_view")
	chain = rig.chains[0]
	if absf(float(chain["start"]) - 0.8) > 0.02:
		_fail("Redo did not restore IK interval")
		return
	# Touch the middle of the bar to shift the whole interval, rather than a handle.
	var middle_x: float = timeline._time_to_x(1.3)
	timeline._press(Vector2(middle_x, y))
	timeline._move(Vector2(timeline._time_to_x(1.60), y))
	if timeline.ik_drag_mode != "move":
		_fail("IK body drag did not enter move mode")
		return
	timeline._release()
	if absf(float(chain["start"]) - 1.10) > 0.02 or absf(float(chain["finish"]) - 2.20) > 0.02:
		_fail("Moving IK bar did not preserve interval length")
		return
	timeline._press(Vector2(timeline._time_to_x(2.20), y))
	timeline._move(Vector2(timeline._time_to_x(2.45), y))
	timeline._release()
	if absf(float(chain["finish"]) - 2.45) > 0.02:
		_fail("Dragging IK finish did not update end time")
		return
	if JSON.stringify(engine.frames) != original_frames:
		_fail("Editing an IK range corrupted regular keyframes")
		return
	app.call("_change_mode", "モーション")
	await process_frame
	if not timeline.visible or not timeline.key_rows_visible or not timeline.ik_visible:
		_fail("Motion editor must show IK lane alongside FK keyframes")
		return
	var snap: Dictionary = engine.snapshot()
	if absf(float(snap["chains"][0]["finish"]) - 2.45) > 0.02:
		_fail("Saved project lacks updated IK time interval")
		return
	print("IK TIMELINE PASS: selected track, finger resize, whole-bar move, undo/redo, keyframe integrity and saved range")
	quit(0)

func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
