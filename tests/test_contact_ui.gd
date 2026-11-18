extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://Main.tscn")
	if packed == null:
		_fail("Main scene unavailable")
		return
	var app: Control = packed.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	app.call("_change_mode", "接触")
	await process_frame
	var motion: MotionEngine = app.get("motion")
	var inspector: VBoxContainer = app.get("inspector")
	var labels: Array[String] = []
	for element in inspector.get_children():
		if element is Label:
			labels.append(str(element.text))
	if not labels.any(func(t: String): return t.contains("足先固定")):
		_fail("Touch inspector did not expose contact tools")
		return
	app.call("_new_contact", "floor")
	await process_frame
	if motion.contact_constraints.size() != 1:
		_fail("Contact creation button did not create a pin")
		return
	var markers: Array = app.get("contact_markers")
	if markers.is_empty() or not markers[0].visible:
		_fail("Yellow contact anchor preview was not visible")
		return
	if absf(float(markers[0].global_position.y)) > 0.0001:
		_fail("Floor contact anchor marker not grounded")
		return
	var count: int = motion.history.size()
	app.call("_edit_contact", 0, "friction", 0.25)
	if absf(float(motion.contact_constraints[0]["friction"]) - 0.25) > 0.001:
		_fail("Friction control did not update live contact")
		return
	if motion.history.size() <= count:
		_fail("Friction edit is not undoable")
		return
	app.call("_toolbar_action", "undo")
	if absf(float(motion.contact_constraints[0]["friction"]) - 1.0) > 0.001:
		_fail("Undo did not restore contact friction")
		return
	app.call("_change_mode", "モーション")
	await process_frame
	markers = app.get("contact_markers")
	if not markers.is_empty() and markers[0].visible:
		_fail("Contact overlay should hide outside IK/contact/diagnostics")
		return
	app.call("_change_mode", "診断")
	await process_frame
	markers = app.get("contact_markers")
	if markers.is_empty() or not markers[0].visible:
		_fail("Diagnostic mode should show active pin")
		return
	app.call("_change_mode", "接触")
	await process_frame
	app.call("_delete_contact")
	await process_frame
	if not motion.contact_constraints.is_empty():
		_fail("Deleting a pin from UI failed")
		return
	markers = app.get("contact_markers")
	if not markers.is_empty() and markers[0].visible:
		_fail("Deleted contact's marker remained visible")
		return
	print("CONTACT TOUCH UI PASS: anchor creation, yellow marker, friction, undo, visibility and deletion")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
