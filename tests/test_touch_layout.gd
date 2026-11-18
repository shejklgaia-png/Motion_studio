extends SceneTree

func _initialize() -> void:
	call_deferred("_test")

func _touch(index: int, pressed: bool, where: Vector2) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = where
	return event

func _drag(index: int, where: Vector2, delta: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = where
	event.relative = delta
	return event

func _test() -> void:
	var packed: PackedScene = load("res://Main.tscn")
	if packed == null:
		_fail("Missing main scene")
		return
	var ui: Control = packed.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	var preview: Control = ui.get("preview_frame")
	var overlay: PanelContainer = ui.get("preview_tools_panel")
	var menu: MenuButton = ui.get("file_menu")
	var btns: Dictionary = ui.get("tool_buttons")
	if preview == null or overlay == null or overlay.get_parent() != preview:
		_fail("Preview controls are not overlaid in the preview")
		return
	if btns.size() != 2 or not btns.has("回転") or not btns.has("移動"):
		_fail("Expected rotation and translation controls; zoom must use pinch")
		return
	if preview.size.y < 210.0 or overlay.position.x < preview.size.x - 130.0:
		_fail("Preview control cluster is not in lower-right corner")
		return
	if overlay.position.y < preview.size.y - 190.0:
		_fail("Preview control cluster is not near the bottom")
		return
	if menu == null:
		_fail("Missing file menu")
		return
	var popup: PopupMenu = menu.get_popup()
	var titles: String = ""
	for index in range(popup.item_count):
		titles += popup.get_item_text(index)
	for required in ["モデルを読み込む", "プロジェクトを開く", "プロジェクトを保存", "別名で保存", "Godotアニメーションを書き出す"]:
		if not titles.contains(required):
			_fail("File menu missing " + required)
			return
	ui.call("_on_file_menu_action", 12)
	if not FileAccess.file_exists("user://motion_studio.motion.json"):
		_fail("Save from file menu did not work")
		return
	var initial_zoom: float = float(ui.get("camera_distance"))
	var initial_yaw: float = float(ui.get("camera_yaw"))
	ui.call("_viewport_input", _touch(0, true, Vector2(70, 90)))
	ui.call("_viewport_input", _touch(1, true, Vector2(170, 90)))
	if not bool(ui.get("pinch_active")):
		_fail("Pinch was not activated on second touch")
		return
	if bool(ui.get("pointer_down")):
		_fail("Single-finger model editing not cancelled at pinch start")
		return
	ui.call("_viewport_input", _drag(1, Vector2(240, 90), Vector2(70, 0)))
	var zoom_in: float = float(ui.get("camera_distance"))
	if zoom_in >= initial_zoom - 0.01:
		_fail("Spreading two fingers did not zoom in")
		return
	if absf(float(ui.get("camera_yaw")) - initial_yaw) > 0.00001:
		_fail("Pinch incorrectly rotates preview camera")
		return
	ui.call("_viewport_input", _drag(1, Vector2(110, 90), Vector2(-130, 0)))
	var zoom_out: float = float(ui.get("camera_distance"))
	if zoom_out <= zoom_in + 0.01:
		_fail("Closing two fingers did not zoom out")
		return
	ui.call("_viewport_input", _touch(1, false, Vector2(110, 90)))
	if bool(ui.get("pinch_active")) or not bool(ui.get("touch_blocked_until_release")):
		_fail("First finger could accidentally edit after pinch")
		return
	ui.call("_viewport_input", _drag(0, Vector2(75, 90), Vector2(5, 0)))
	if bool(ui.get("pointer_down")):
		_fail("Existing finger restarted model editing after pinch")
		return
	ui.call("_viewport_input", _touch(0, false, Vector2(75, 90)))
	if bool(ui.get("touch_blocked_until_release")):
		_fail("Touch interaction did not reset when fingers lifted")
		return
	ui.call("_viewport_input", _touch(0, true, Vector2(75, 90)))
	ui.call("_viewport_input", _drag(0, Vector2(115, 92), Vector2(40, 2)))
	if absf(float(ui.get("camera_yaw")) - initial_yaw) < 0.001:
		_fail("Single finger camera rotation stopped working")
		return
	ui.call("_viewport_input", _touch(0, false, Vector2(115, 92)))
	print("MOTION TOUCH UI PASS: preview overlay, file dropdown, saved project, two-finger pinch, gesture isolation")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
