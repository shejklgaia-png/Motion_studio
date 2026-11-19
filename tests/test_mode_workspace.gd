extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load("res://Main.tscn")
	if scene == null:
		_fail("Missing Motion Studio scene")
		return
	var app: Control = scene.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame

	var preview: Control = app.get("preview_frame")
	var editor_panel: VBoxContainer = app.get("editor_panel")
	var editor_body: VBoxContainer = app.get("editor_body")
	var editor_scroll: ScrollContainer = app.get("editor_scroll")
	var timeline_panel: VBoxContainer = app.get("timeline_panel")
	var timeline_view: MotionTimelineView = app.get("timeline_view")
	var timeline_transport: HBoxContainer = app.get("timeline_transport")
	var mode_action_bar: HBoxContainer = app.get("mode_action_bar")
	var overlay: PanelContainer = app.get("preview_tools_panel")
	var part_label: Label = app.get("part_selector_label")
	var anim_label: Label = app.get("animation_selector_label")
	var tool_buttons: Dictionary = app.get("tool_buttons")
	if preview == null or editor_panel == null or editor_scroll == null or timeline_panel == null or mode_action_bar == null:
		_fail("Adaptive workspace nodes are missing")
		return
	if editor_panel.get_parent().size_flags_vertical != Control.SIZE_EXPAND_FILL:
		_fail("Inspector panel does not expand into available screen")
		return
	if editor_body.size_flags_vertical != Control.SIZE_EXPAND_FILL or editor_scroll.size_flags_vertical != Control.SIZE_EXPAND_FILL:
		_fail("Inspector content cannot use available vertical space")
		return
	var expected := {
		"階層": [false, false, true, "パーツ検索"],
		"モーション": [true, true, true, "＋キー"],
		"IK": [true, false, false, "IKを追加"],
		"制約": [false, false, false, "パーツ検索"],
		"接触": [true, false, false, "IK設定"],
		"診断": [true, false, false, "もう一度診断"],
		"ベイク": [true, false, false, "ベイク実行"]
	}
	for name in ["階層", "モーション", "IK", "制約", "接触", "診断", "ベイク"]:
		app.call("_change_mode", name)
		await process_frame
		await process_frame
		if not editor_body.visible or not mode_action_bar.visible:
			_fail("Mode controls are not visible: " + name)
			return
		var configuration: Array = expected[name]
		if timeline_panel.get_parent().visible != bool(configuration[0]):
			_fail("Wrong timeline panel for mode " + name)
			return
		if timeline_view.visible != bool(configuration[1]) or timeline_transport.visible != bool(configuration[1]):
			_fail("Full animation controls leaked into mode " + name)
			return
		if tool_buttons["回転"].visible != bool(configuration[2]) or tool_buttons["移動"].visible != bool(configuration[2]):
			_fail("Preview transform controls inappropriate for " + name)
			return
		var labels := ""
		for control in mode_action_bar.get_children():
			if control is Button:
				labels += control.text
		if not labels.contains(str(configuration[3])):
			_fail("Mode-specific quick actions missing for " + name)
			return
		if editor_panel.get_parent().size_flags_vertical != Control.SIZE_EXPAND_FILL:
			_fail("Editor stopped filling the screen in mode " + name)
			return
		if preview.size.y < 180 or editor_scroll.size.y < 120:
			_fail("Mode loses preview/editor area: %s (preview=%.1f editor=%.1f)" % [name, preview.size.y, editor_scroll.size.y])
			return
		if name == "階層":
			var outliner: MotionOutliner = app.get("outliner")
			if outliner == null or outliner.size_flags_vertical != Control.SIZE_EXPAND_FILL:
				_fail("Part hierarchy did not grow to use its editor panel")
				return
		if name == "IK" and (part_label.text != "対象パーツ" or anim_label.text != "確認する動き"):
			_fail("Context labels were not updated for IK editing")
			return

	app.call("_change_mode", "モーション")
	await process_frame
	app.call("_toggle_key_list")
	await process_frame
	var key_scroll: ScrollContainer = app.get("key_scroll")
	if not key_scroll.visible:
		_fail("Motion key list cannot be expanded")
		return
	# Fold the keyframe menu, leaving the compact scrubber and edit state intact.
	var seek: HSlider = app.get("seek")
	var timeline_toggle: Button = app.get("timeline_toggle")
	if timeline_toggle == null or not timeline_toggle.visible:
		_fail("Keyframe folding button is missing")
		return
	var engine: MotionEngine = app.get("motion")
	var frames_before: String = JSON.stringify(engine.frames)
	app.call("_toggle_timeline")
	await process_frame
	if timeline_view.visible or timeline_transport.visible or key_scroll.visible or not seek.visible:
		_fail("Folded keyframe menu did not expose the compact scrubber")
		return
	if not timeline_toggle.text.contains("開く") or JSON.stringify(engine.frames) != frames_before:
		_fail("Folding modified animation data or did not update the reopen label")
		return
	app.call("_change_mode", "IK")
	await process_frame
	if key_scroll.visible or timeline_toggle.visible:
		_fail("Keyframe controls remained visible in IK")
		return
	app.call("_change_mode", "モーション")
	await process_frame
	if timeline_view.visible or not seek.visible:
		_fail("Collapsed keyframe state was lost when changing modes")
		return
	app.call("_toggle_timeline")
	await process_frame
	if not timeline_view.visible or not timeline_transport.visible or not key_scroll.visible or seek.visible:
		_fail("Reopening keyframes did not restore the previous expanded key list")
		return
	if not timeline_toggle.text.contains("閉じる") or JSON.stringify(engine.frames) != frames_before:
		_fail("Restoring keyframes corrupted data or the open state")
		return
	app.call("_toggle_editor")
	await process_frame
	if editor_body.visible or mode_action_bar.visible or editor_panel.get_parent().size_flags_vertical != Control.SIZE_FILL:
		_fail("Collapsing the editor did not reclaim preview space")
		return
	app.call("_toggle_editor")
	await process_frame
	if not editor_body.visible or not mode_action_bar.visible or editor_panel.get_parent().size_flags_vertical != Control.SIZE_EXPAND_FILL:
		_fail("Expanded editor did not reclaim its full panel")
		return
	print("MOTION MODE WORKSPACE PASS: seven modes, expanding inspector, focused timeline, contextual tools, collapse and restore")
	quit(0)

func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
