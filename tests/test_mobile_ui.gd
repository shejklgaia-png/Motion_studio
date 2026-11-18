extends SceneTree

func _initialize() -> void:
	call_deferred("_verify_layout")

func _verify_layout() -> void:
	var scene: PackedScene = load("res://Main.tscn")
	if scene == null:
		_fail("Main scene could not be opened")
		return
	var ui: Control = scene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	var part_picker: OptionButton = ui.get("part_picker")
	var anim_picker: OptionButton = ui.get("animation_picker")
	var inspector: VBoxContainer = ui.get("inspector")
	var preview: SubViewportContainer = ui.get("preview_container")
	if part_picker == null or anim_picker == null or inspector == null or preview == null:
		_fail("Missing editor UI widgets")
		return
	if part_picker.size.x > 260.0 or anim_picker.size.x > 260.0:
		_fail("Selector overflow: %.1f and %.1f" % [part_picker.size.x, anim_picker.size.x])
		return
	if preview.size.y < 180.0:
		_fail("3D viewport is too small: %.1f" % preview.size.y)
		return
	ui.call("_change_mode", "IK")
	await process_frame
	if str(ui.get("mode")) != "IK":
		_fail("Mode switching does not work")
		return
	ui.call("_toggle_editor")
	await process_frame
	var editor_body: VBoxContainer = ui.get("editor_body")
	if editor_body.visible:
		_fail("Inspector folding did not close")
		return
	ui.call("_toggle_editor")
	await process_frame
	if not editor_body.visible:
		_fail("Inspector folding did not reopen")
		return
	ui.call("_show_help")
	await process_frame
	var popup: AcceptDialog = ui.get("help_popup")
	if popup == null or popup.dialog_text.length() > 170:
		_fail("Guided tutorial is missing or too long")
		return
	print("MOTION STUDIO UI PASS: mobile selectors, viewport, modes, folding, compact help")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
