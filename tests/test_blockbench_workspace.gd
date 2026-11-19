extends SceneTree

func _initialize() -> void:
	call_deferred("_verify_blockbench_workspace")

func _verify_blockbench_workspace() -> void:
	var source: PackedScene = load("res://Main.tscn")
	if source == null:
		_fail("Main scene is missing")
		return
	var app: Control = source.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	var preview: Control = app.get("preview_frame")
	var timeline: MotionTimelineView = app.get("timeline_view")
	var rig: MotionRig = app.get("rig")
	var motion: MotionEngine = app.get("motion")
	var tabs: Dictionary = app.get("mode_buttons")
	var file_menu: MenuButton = app.get("file_menu")
	if preview == null or timeline == null or rig == null or motion == null:
		_fail("Workspace lost preview, timeline, or model engine")
		return
	for name in ["階層", "モーション", "IK", "制約", "接触", "診断", "ベイク"]:
		if not tabs.has(name):
			_fail("Editor functionality missing: " + name)
			return
	var viewport: SubViewportContainer = app.get("preview_container")
	if preview.size.y < 180.0 or viewport.size.y < 180.0:
		_fail("3D viewer shrunk too much")
		return
	if timeline.size.y < 115.0 or timeline.get_parent() == null:
		_fail("Multi-channel timeline not visible")
		return
	var tab_button: Button = tabs["モーション"]
	var top_of_preview: float = preview.global_position.y
	if tab_button.global_position.y >= top_of_preview:
		_fail("Mode tabs are not above the viewport")
		return
	var picker: OptionButton = app.get("part_picker")
	if picker == null:
		_fail("Part selector was removed")
		return
	# Torso uses explicit FK rotation keys; legs now use animated IK targets.
	var chosen := "胴体"
	if not rig.parts.has(chosen):
		_fail("Sample rig lost an animated joint")
		return
	app.set("selected_part", chosen)
	app.call("_refresh_part_picker")
	if timeline.selected_part != chosen:
		_fail("Timeline did not follow selected joint")
		return
	var rotation_keys: Array = timeline.keys.get("rotation", [])
	if rotation_keys.size() < 2:
		_fail("Rotation track has no diamond keys")
		return
	var marker_x: float = timeline._time_to_x(0.7)
	timeline._jump_to_position(Vector2(marker_x, 27.0 + 15.0))
	if absf(motion.play_time - 0.7) > 0.01:
		_fail("Diamond keyframe scrub did not reach selected time")
		return
	app.call("_change_mode", "階層")
	await process_frame
	var outliner: MotionOutliner = app.get("outliner")
	if outliner == null or outliner.part_tree == null:
		_fail("Outliner tab did not create hierarchy tree")
		return
	if outliner.item_lookup.size() != rig.parts.size():
		_fail("Outliner omitted parts")
		return
	if outliner.children_map.get("胴体", []).is_empty():
		_fail("Outliner has no nested bones")
		return
	var branch: String = "前右上肢"
	if not outliner.item_lookup.has(branch):
		_fail("Outliner missing expected branch")
		return
	outliner.item_lookup[branch].select(0)
	await process_frame
	if str(app.get("selected_part")) != branch:
		_fail("Outliner click did not choose joint")
		return
	# Existing features must remain accessible after switching new workspace tabs.
	for name in ["モーション", "IK", "制約", "接触", "診断", "ベイク"]:
		app.call("_change_mode", name)
		await process_frame
		if str(app.get("mode")) != name:
			_fail("Mode switch failed: " + name)
			return
	if file_menu == null or file_menu.get_popup().item_count < 6:
		_fail("Unified file menu is missing actions")
		return
	var report: Dictionary = motion.bake_ik_fk(30)
	if not bool(report.get("ok", false)):
		_fail("IK/FK bake broken by UI changes")
		return
	app.call("_refresh_key_buttons")
	await process_frame
	if timeline.keys.is_empty() or timeline.clip_duration < 2.9:
		_fail("Timeline broke with baked motion")
		return
	print("BLOCKBENCH WORKSPACE PASS: top mode tabs, outliner hierarchy, selected tracks, diamond scrub, all editor modes and IK bake")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
