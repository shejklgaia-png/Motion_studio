extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://Main.tscn")
	if packed == null:
		_fail("Main scene missing")
		return
	var app: Control = packed.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame

	var selector_bar: VBoxContainer = app.get("selection_bar")
	var part_picker: OptionButton = app.get("part_picker")
	var animation_picker: OptionButton = app.get("animation_picker")
	var editor_body: VBoxContainer = app.get("editor_body")
	var preview: Control = app.get("preview_frame")
	var tabs: Dictionary = app.get("mode_buttons")
	var advanced: MenuButton = app.get("advanced_menu")
	var key_scroll: ScrollContainer = app.get("key_scroll")
	var key_list_toggle: Button = app.get("key_list_toggle")
	var hint: Label = app.get("action_hint")
	var editor_title: Label = app.get("editor_title")
	if selector_bar == null or part_picker == null or animation_picker == null:
		_fail("Always-visible part and animation selectors are missing")
		return
	if selector_bar.get_parent() != preview.get_parent():
		_fail("Selectors should be separate from the collapsible inspector")
		return
	if not selector_bar.visible or part_picker.size.x < 80.0 or animation_picker.size.x < 80.0:
		_fail("Selectors have insufficient width or are hidden")
		return
	if selector_bar.global_position.y <= preview.global_position.y:
		_fail("Selectors are not below the preview")
		return
	if advanced == null or advanced.get_popup().item_count < 4:
		_fail("Advanced features menu incomplete")
		return
	for label in ["階層", "モーション", "IK", "制約", "接触", "診断", "ベイク"]:
		if not tabs.has(label):
			_fail("Mode removed: " + label)
			return
	if key_list_toggle == null or key_scroll == null or key_scroll.visible:
		_fail("Key list should be available but folded by default")
		return
	app.call("_toggle_key_list")
	await process_frame
	if not key_scroll.visible:
		_fail("Key list cannot be expanded")
		return
	app.call("_toggle_key_list")
	if key_scroll.visible:
		_fail("Key list cannot be hidden")
		return
	if hint == null or not hint.text.contains("ファイル"):
		_fail("Initial workflow hint is missing")
		return
	app.call("_toggle_editor")
	await process_frame
	if editor_body.visible == true or not selector_bar.visible:
		_fail("Collapsing the inspector also hid the primary selectors")
		return
	app.call("_change_mode", "ベイク")
	await process_frame
	if not editor_body.visible or not editor_title.text.contains("ベイク"):
		_fail("Advanced menu mode not visible in the inspector")
		return
	if not advanced.text.contains("ベイク"):
		_fail("Current advanced mode is not indicated")
		return
	app.call("_change_mode", "モーション")
	await process_frame
	if advanced.text.contains("ベイク"):
		_fail("Advanced menu retains an incorrect selected label")
		return
	var rig: MotionRig = app.get("rig")
	if rig == null or rig.parts.is_empty():
		_fail("Rig was changed")
		return
	app.call("_refresh_part_picker")
	await process_frame
	if part_picker.item_count != rig.parts.size():
		_fail("Part selector no longer shows every part")
		return
	print("MOTION CLARITY UI PASS: primary selectors, compact modes, advanced tools, optional keys, contextual help")
	quit(0)

func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
