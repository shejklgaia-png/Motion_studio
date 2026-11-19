extends Control

const MODES := ["階層", "モーション", "IK", "制約", "接触", "診断", "ベイク"]
const ADVANCED_MODES := ["制約", "接触", "診断", "ベイク"]
var rig: MotionRig
var motion: MotionEngine
var stage: Node3D
var viewport: SubViewport
var preview_container: SubViewportContainer
var preview_frame: Control
var preview_tools_panel: PanelContainer
var timeline_panel: VBoxContainer
var timeline_title: Label
var timeline_toggle: Button
var timeline_expanded: bool = true
var timeline_transport: HBoxContainer
var editor_panel: VBoxContainer
var mode_action_bar: HBoxContainer
var part_selector_label: Label
var animation_selector_label: Label
var key_list_expanded: bool = false
var file_menu: MenuButton
var more_menu: MenuButton
var part_select_popup: PopupPanel
var part_select_outliner: MotionOutliner
var active_touches: Dictionary = {}
var pinch_active: bool = false
var pinch_distance: float = 0.0
var touch_blocked_until_release: bool = false
var suppress_mouse_until_ms: int = 0
var camera: Camera3D
var floor_area: StaticBody3D
var motion_gizmo: MotionGizmo
var active_transform: String = "回転"
var tool_buttons: Dictionary = {}
var pan_view: bool = false
var pan_button: Button
var drag_axis: int = -1
var drag_start: Vector2 = Vector2.ZERO
var drag_tangent: Vector2 = Vector2.ZERO
var drag_value: float = 0.0
var drag_factor: float = 0.0
var inspector: VBoxContainer
var key_row: HBoxContainer
var timeline_view: MotionTimelineView
var outliner: MotionOutliner
var selection_badge: Label
var seek: HSlider
var time_label: Label
var message_label: Label
var part_picker: OptionButton
var mode_picker: OptionButton
var mode_buttons: Dictionary = {}
var advanced_menu: MenuButton
var editor_title: Label
var action_hint: Label
var key_scroll: ScrollContainer
var key_list_toggle: Button
var selection_bar: VBoxContainer
var editor_body: VBoxContainer
var editor_scroll: ScrollContainer
var editor_toggle: Button
var guide_step: int = 0
var animation_picker: OptionButton
var camera_focus: Vector3 = Vector3(0, 1.05, 0)
var play_button: Button
var undo_button: Button
var redo_button: Button
var fit_button: Button
var help_popup: AcceptDialog
var selected_part: String = "胴体"
var selected_chain: int = 0
var selected_test: int = -1
var selected_contact: int = -1
var contact_markers: Array[MeshInstance3D] = []
var mode: String = "モーション"
var playing: bool = false
var playback_speed: float = 1.0
var bake_target_fps: int = 60
var show_original: bool = false
var camera_yaw: float = 0.62
var camera_pitch: float = 0.42
var camera_distance: float = 7.0
var pointer_down: bool = false
var dragging_object: bool = false
var save_clock: float = 0.0
var status_clock: float = 0.0

func _ready() -> void:
	_build_interface()
	_build_stage()
	motion = MotionEngine.new()
	motion.setup(rig)
	motion.add_sample_animation()
	_refresh_part_picker()
	_populate_animation_picker(false)
	_refresh_inspector()
	_refresh_key_buttons()
	_update_timeline()
	_update_gizmo()
	_refresh_action_hint()
	_apply_mode_layout()
	_update_history_buttons()
	_note("まずは ▶ 再生 → 脚をタップ → 下の数値を変更、の順に試してください。")
	if not FileAccess.file_exists("user://motion_studio_guide_seen.txt"):
		call_deferred("_show_help")

func _make_button(label: String, callback: Callable, owner: Node) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 44)
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(callback)
	owner.add_child(button)
	return button

func _add_text(parent: Node, content: String, section: bool = false) -> Label:
	var label := Label.new()
	label.text = content
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if section:
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color("e9f5ff"))
	parent.add_child(label)
	return label

func _row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	return row

func _panel(parent: Node, bg: Color) -> VBoxContainer:
	var box := PanelContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var background := StyleBoxFlat.new()
	background.bg_color = bg
	background.set_corner_radius_all(4)
	background.set_content_margin_all(7)
	box.add_theme_stylebox_override("panel", background)
	parent.add_child(box)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	box.add_child(body)
	return body

func _style_button(button: Button, active: bool = false, important: bool = false) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("3a6795") if active else (Color("3c4d69") if important else Color("333a49"))
	normal.set_corner_radius_all(4)
	normal.border_width_bottom = 1
	normal.border_color = Color("475061")
	normal.set_content_margin_all(5)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color("4a80b0") if active else Color("455268")
	button.add_theme_stylebox_override("hover", hover)
	var press := normal.duplicate()
	press.bg_color = Color("2b5680")
	button.add_theme_stylebox_override("pressed", press)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color("ffffff"))

func _build_interface() -> void:
	var back := ColorRect.new()
	back.color = Color("171b24")
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 5)
	add_child(layout)

	# A small app header: file actions live in the next row and in "その他".
	var head := _panel(layout, Color("252b36"))
	var header := _row(head)
	var title := _add_text(header, "MOTION STUDIO", true)
	title.add_theme_font_size_override("font_size", 17)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var help_button := _make_button("？", _show_help, header)
	help_button.custom_minimum_size.x = 50
	_style_button(help_button)
	help_button.tooltip_text = "短い3ステップ操作ガイド"

	var toolbar := _row(layout)
	file_menu = MenuButton.new()
	file_menu.text = "ファイル ▾"
	file_menu.custom_minimum_size.y = 44
	file_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(file_menu)
	_style_button(file_menu, false, true)
	var file_popup: PopupMenu = file_menu.get_popup()
	file_popup.add_item("モデルを読み込む（bbmodel / glb）", 10)
	file_popup.add_separator()
	file_popup.add_item("プロジェクトを開く", 11)
	file_popup.add_item("プロジェクトを保存", 12)
	file_popup.add_item("別名で保存", 13)
	file_popup.add_separator()
	file_popup.add_item("Godotアニメーションを書き出す", 14)
	file_popup.id_pressed.connect(_on_file_menu_action)

	play_button = _make_button("▶ 再生", _toggle_playback, toolbar)
	play_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(play_button, false, true)
	undo_button = _make_button("↶", func(): _toolbar_action("undo"), toolbar)
	undo_button.custom_minimum_size.x = 44
	undo_button.tooltip_text = "編集を取り消す"
	_style_button(undo_button)
	redo_button = _make_button("↷", func(): _toolbar_action("redo"), toolbar)
	redo_button.custom_minimum_size.x = 44
	redo_button.tooltip_text = "編集をやり直す"
	_style_button(redo_button)
	more_menu = MenuButton.new()
	more_menu.text = "操作 ▾"
	more_menu.custom_minimum_size.y = 44
	more_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(more_menu)
	_style_button(more_menu)
	var popup := more_menu.get_popup()
	popup.add_item("パーツ選択（検索・階層）", 6)
	popup.add_separator()
	for item in [["取り消す", 3], ["やり直す", 4], ["使い方", 5]]:
		popup.add_item(str(item[0]), int(item[1]))
	popup.id_pressed.connect(_on_more_action)
	_build_part_select_popup()

	preview_frame = Control.new()
	preview_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_frame.custom_minimum_size = Vector2(0, 220)
	layout.add_child(preview_frame)
	preview_container = SubViewportContainer.new()
	preview_container.stretch = true
	preview_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_frame.add_child(preview_container)
	preview_container.gui_input.connect(_viewport_input)
	viewport = SubViewport.new()
	viewport.size = Vector2i(480, 520)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	preview_container.add_child(viewport)

	var viewport_title := Label.new()
	viewport_title.text = "PERSPECTIVE  |  3D VIEW"
	viewport_title.position = Vector2(10, 8)
	viewport_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_title.add_theme_font_size_override("font_size", 11)
	viewport_title.add_theme_color_override("font_color", Color("b4c5d7"))
	preview_frame.add_child(viewport_title)
	selection_badge = Label.new()
	selection_badge.position = Vector2(10, 27)
	selection_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_badge.add_theme_font_size_override("font_size", 12)
	selection_badge.add_theme_color_override("font_color", Color("6dc5ff"))
	preview_frame.add_child(selection_badge)
	fit_button = _make_button("全体表示", _fit_import_camera, preview_frame)
	fit_button.anchor_left = 1.0
	fit_button.anchor_right = 1.0
	fit_button.offset_left = -102
	fit_button.offset_right = -8
	fit_button.offset_top = 8
	fit_button.offset_bottom = 47
	fit_button.custom_minimum_size.y = 39
	fit_button.tooltip_text = "モデル全体をカメラの中心に表示"
	_style_button(fit_button)

	# Transform tool switches float at the lower-right corner of the preview.
	preview_tools_panel = PanelContainer.new()
	preview_tools_panel.anchor_left = 1.0
	preview_tools_panel.anchor_top = 1.0
	preview_tools_panel.anchor_right = 1.0
	preview_tools_panel.anchor_bottom = 1.0
	preview_tools_panel.offset_left = -103.0
	preview_tools_panel.offset_top = -169.0
	preview_tools_panel.offset_right = -8.0
	preview_tools_panel.offset_bottom = -8.0
	var overlay_style := StyleBoxFlat.new()
	overlay_style.bg_color = Color(0.10, 0.12, 0.17, 0.89)
	overlay_style.set_corner_radius_all(5)
	overlay_style.set_content_margin_all(5)
	preview_tools_panel.add_theme_stylebox_override("panel", overlay_style)
	preview_frame.add_child(preview_tools_panel)
	var tools := VBoxContainer.new()
	tools.add_theme_constant_override("separation", 4)
	preview_tools_panel.add_child(tools)
	for tool_name in ["回転", "移動"]:
		var tool_id: String = tool_name
		var tool_button := _make_button(tool_name, func(): _choose_transform(tool_id), tools)
		tool_button.custom_minimum_size = Vector2(79, 44)
		tool_buttons[tool_id] = tool_button
		_style_button(tool_button, tool_id == active_transform)
	pan_button = _make_button("視点移動", _toggle_view_pan, tools)
	pan_button.custom_minimum_size = Vector2(79, 44)
	_style_button(pan_button)

	action_hint = _add_text(layout, "① ファイルから読み込む　② 動きを選ぶ　③ 部位を選んで編集")
	action_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	action_hint.clip_text = true
	action_hint.add_theme_font_size_override("font_size", 13)
	action_hint.add_theme_color_override("font_color", Color("b6d6f4"))
	selection_bar = _panel(layout, Color("292f3b"))

	timeline_panel = _panel(layout, Color("232936"))
	var timeline := timeline_panel
	var controls := _row(timeline)
	timeline_title = _add_text(controls, "動きの時間")
	timeline_title.add_theme_font_size_override("font_size", 15)
	time_label = _add_text(controls, "0.00秒")
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_label.add_theme_color_override("font_color", Color("62dcd1"))
	time_label.add_theme_font_size_override("font_size", 15)
	timeline_toggle = _make_button("閉じる ▲", _toggle_timeline, controls)
	timeline_toggle.custom_minimum_size.x = 90
	timeline_toggle.tooltip_text = "キーフレームのタイムラインを開閉します"
	_style_button(timeline_toggle)
	seek = HSlider.new()
	seek.min_value = 0.0
	seek.max_value = 3.0
	seek.step = 0.001
	seek.custom_minimum_size.y = 23
	seek.value_changed.connect(_on_user_seek)
	timeline.add_child(seek)
	timeline_view = MotionTimelineView.new()
	timeline_view.seek_requested.connect(_on_user_seek)
	timeline_view.key_move_requested.connect(_on_key_move_requested)
	timeline_view.ik_range_requested.connect(_on_ik_range_requested)
	timeline.add_child(timeline_view)
	timeline_transport = _row(timeline)
	var transport := timeline_transport
	for item in [["◀", -1.0], ["▶|", 1.0]]:
		var step_sign: float = float(item[1])
		var step_button := _make_button(str(item[0]), func(): _seek_by(step_sign / float(motion.fps)), transport)
		step_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(step_button)
	var add_key := _make_button("＋ キー", _insert_key, transport)
	add_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(add_key, false, true)
	var remove_key := _make_button("－ キー", _remove_key, transport)
	remove_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(remove_key)
	key_list_toggle = _make_button("全キー ▼", _toggle_key_list, transport)
	key_list_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(key_list_toggle)
	key_list_toggle.custom_minimum_size.y = 36
	key_scroll = ScrollContainer.new()
	key_scroll.visible = false
	key_scroll.custom_minimum_size.y = 34
	key_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	key_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	timeline.add_child(key_scroll)
	key_row = _row(key_scroll)

	# The mode tabs remain visible; the large inspector is collapsible.
	editor_panel = _panel(layout, Color("272d3a"))
	var editor := editor_panel
	editor_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor_panel.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	var editor_head := _row(editor)
	editor_title = _add_text(editor_head, "編集：モーション", true)
	editor_title.add_theme_font_size_override("font_size", 15)
	editor_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_toggle = _make_button("閉じる ▲", _toggle_editor, editor_head)
	editor_toggle.custom_minimum_size.x = 92
	_style_button(editor_toggle)
	mode_action_bar = _row(editor)
	mode_action_bar.add_theme_constant_override("separation", 5)
	var tabs_scroll := ScrollContainer.new()
	tabs_scroll.custom_minimum_size.y = 44
	tabs_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tabs_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(tabs_scroll)
	# Blockbench places mode selection immediately above the 3D viewport.
	layout.move_child(tabs_scroll, 2)
	var tabs := _row(tabs_scroll)
	for item in ["階層", "モーション", "IK"]:
		var current_mode: String = item
		var caption: String = {"階層":"部位・階層", "モーション":"動きを編集", "IK":"IK設定"}[item]
		var tab := _make_button(caption, func(): _change_mode(current_mode), tabs)
		tab.custom_minimum_size.x = 90 if item != "モーション" else 116
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mode_buttons[item] = tab
		_style_button(tab, item == mode)
	advanced_menu = MenuButton.new()
	advanced_menu.text = "詳細機能 ▾"
	advanced_menu.custom_minimum_size = Vector2(113, 44)
	advanced_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(advanced_menu)
	_style_button(advanced_menu)
	var tools_popup: PopupMenu = advanced_menu.get_popup()
	for index in range(ADVANCED_MODES.size()):
		var tool_name: String = ADVANCED_MODES[index]
		var display_name: String = {
			"制約":"関節の可動域（制約）",
			"接触":"床・物体への接触",
			"診断":"動きのチェック",
			"ベイク":"IK/FKをキーフレーム化"
		}[tool_name]
		tools_popup.add_item(display_name, index)
		mode_buttons[tool_name] = advanced_menu
	tools_popup.id_pressed.connect(func(id: int):
		if id >= 0 and id < ADVANCED_MODES.size():
			_change_mode(ADVANCED_MODES[id]))
	editor_body = VBoxContainer.new()
	editor_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor_body.add_theme_constant_override("separation", 5)
	editor.add_child(editor_body)
	var selectors := _row(selection_bar)
	var part_col := VBoxContainer.new()
	part_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selectors.add_child(part_col)
	part_selector_label = _add_text(part_col, "② 動かす部位")
	part_selector_label.add_theme_font_size_override("font_size", 13)
	part_picker = OptionButton.new()
	part_picker.fit_to_longest_item = false
	part_picker.clip_text = true
	part_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	part_picker.custom_minimum_size.y = 40
	part_picker.item_selected.connect(func(index: int):
		selected_part = part_picker.get_item_text(index)
		_refresh_timeline_view()
		_refresh_inspector()
		_update_gizmo()
		_update_selection_badge())
	part_col.add_child(part_picker)
	var anim_col := VBoxContainer.new()
	anim_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selectors.add_child(anim_col)
	animation_selector_label = _add_text(anim_col, "① モーション選択")
	animation_selector_label.add_theme_font_size_override("font_size", 13)
	animation_picker = OptionButton.new()
	animation_picker.fit_to_longest_item = false
	animation_picker.clip_text = true
	animation_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	animation_picker.custom_minimum_size.y = 40
	animation_picker.disabled = true
	animation_picker.add_item("モデル読込後に選択")
	animation_picker.item_selected.connect(func(index: int):
		if index == 0:
			motion.setup(rig)
			_after_model_change("基本姿勢を表示しています。")
		else:
			var result: String = motion.load_bb_animation(index - 1)
			_after_model_change(result))
	anim_col.add_child(animation_picker)
	selectors.move_child(anim_col, 0)
	editor_scroll = ScrollContainer.new()
	editor_scroll.custom_minimum_size.y = 130
	editor_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	editor_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	editor_scroll.follow_focus = true
	editor_body.add_child(editor_scroll)
	inspector = VBoxContainer.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector.add_theme_constant_override("separation", 10)
	editor_scroll.add_child(inspector)

	message_label = _add_text(layout, "準備中")
	message_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	message_label.clip_text = true
	message_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	message_label.add_theme_font_size_override("font_size", 13)
	message_label.add_theme_color_override("font_color", Color("a8b8c9"))
	message_label.custom_minimum_size.y = 19

func _build_part_select_popup() -> void:
	# The outliner lives outside the 3D viewport, so overlay buttons cannot cover parts.
	part_select_popup = PopupPanel.new()
	part_select_popup.title = "パーツ選択"
	part_select_popup.min_size = Vector2i(300, 320)
	add_child(part_select_popup)
	var body := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		body.add_theme_constant_override("margin_" + side, 10)
	part_select_popup.add_child(body)
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	body.add_child(content)
	var heading := _row(content)
	var title := _add_text(heading, "パーツ選択", true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close_button := _make_button("閉じる", func(): part_select_popup.hide(), heading)
	close_button.custom_minimum_size.x = 80
	_style_button(close_button)
	part_select_outliner = MotionOutliner.new()
	part_select_outliner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(part_select_outliner)
	part_select_outliner.part_selected.connect(_select_part_from_actions)

func _open_part_selector() -> void:
	if rig == null or part_select_popup == null:
		return
	part_select_outliner.set_model(rig, selected_part)
	part_select_popup.popup_centered_clamped(Vector2i(350, 440), 0.85)
	part_select_outliner.filter_box.grab_focus()

func _select_part_from_actions(name: String) -> void:
	if rig == null or not rig.parts.has(name):
		return
	part_select_popup.hide()
	selected_part = name
	_refresh_part_picker()
	_refresh_inspector()
	_update_gizmo()
	_note("パーツ選択：%s" % name)

func _on_file_menu_action(id: int) -> void:
	match id:
		10: _toolbar_action("import")
		11: _toolbar_action("open")
		12: _toolbar_action("save")
		13: _file_dialog("save_as")
		14: _file_dialog("export")

func _on_more_action(id: int) -> void:
	match id:
		6: _open_part_selector()
		3: _toolbar_action("undo")
		4: _toolbar_action("redo")
		5: _show_help()

func _update_history_buttons() -> void:
	if undo_button != null and motion != null:
		undo_button.disabled = motion.history.is_empty()
	if redo_button != null and motion != null:
		redo_button.disabled = motion.future.is_empty()

func _on_user_seek(value: float) -> void:
	if playing:
		playing = false
		play_button.text = "▶ 再生"
	_seek_to(value)

func _on_key_move_requested(from_time: float, to_time: float) -> void:
	playing = false
	play_button.text = "▶ 再生"
	if motion.move_keyframe(from_time, to_time):
		_refresh_key_buttons()
		_seek_to(motion.play_time)
		_note("◆ %.2f秒 → %.2f秒へ移動（全身フレーム）。↶で取り消せます" % [from_time, motion.play_time])
	else:
		_seek_to(from_time)
		_note("キー移動不可：先頭・末尾、または既存キーと重複しています")
	_update_history_buttons()

# A single undo snapshot covers a whole touch gesture, not every drag frame.
func _on_ik_range_requested(chain_index: int, start_time: float, finish_time: float) -> void:
	if chain_index < 0 or chain_index >= rig.chains.size():
		return
	var start_value: float = clampf(start_time, 0.0, motion.duration)
	var finish_value: float = clampf(finish_time, start_value, motion.duration)
	var chain: Dictionary = rig.chains[chain_index]
	if absf(float(chain.get("start", 0.0)) - start_value) < 0.0005 and absf(float(chain.get("finish", 0.0)) - finish_value) < 0.0005:
		return
	motion.record_undo()
	selected_chain = chain_index
	chain["start"] = start_value
	chain["finish"] = finish_value
	motion.evaluate(motion.play_time)
	_refresh_timeline_view()
	_refresh_inspector()
	_update_history_buttons()
	_note("IK適用：%.2f〜%.2f秒（↶で元に戻せます）" % [start_value, finish_value])

func _choose_transform(kind: String) -> void:
	active_transform = kind
	pan_view = false
	_style_button(pan_button, false)
	for name in tool_buttons:
		_style_button(tool_buttons[name], name == kind)
	_update_gizmo()
	_note("操作：「%s」 3D画面の色付きハンドルをドラッグしてください" % kind)

func _toggle_view_pan() -> void:
	pan_view = not pan_view
	_style_button(pan_button, pan_view)
	_update_gizmo()
	_note("視点移動：背景をドラッグして画面を平行移動" if pan_view else "視点回転：背景をドラッグしてください")

func _zoom(multiplier: float) -> void:
	camera_distance = clampf(camera_distance * multiplier, 0.5, 90.0)
	_update_camera()

func _update_gizmo() -> void:
	if motion_gizmo == null or rig == null or camera == null:
		return
	if mode == "IK" and selected_chain >= 0 and selected_chain < rig.chains.size():
		var target: Node3D = rig.chains[selected_chain]["target"]
		motion_gizmo.set_state(target, camera, "移動", drag_axis, not pan_view and not playing)
		return
	var show_handles: bool = mode in ["モーション", "階層"] and not pan_view and not playing and rig.parts.has(selected_part)
	var selected_node: Node3D = rig.parts[selected_part] if rig.parts.has(selected_part) else null
	motion_gizmo.set_state(selected_node, camera, active_transform, drag_axis, show_handles)

func _change_mode(new_mode: String) -> void:
	if mode == new_mode and editor_body.visible:
		return
	mode = new_mode
	editor_body.show()
	editor_toggle.text = "閉じる ▲"
	_apply_mode_layout()
	_refresh_timeline_view()
	for name in ["階層", "モーション", "IK"]:
		_style_button(mode_buttons[name], name == mode)
	_style_button(advanced_menu, mode in ADVANCED_MODES)
	advanced_menu.text = "詳細：%s ▾" % mode if mode in ADVANCED_MODES else "詳細機能 ▾"
	editor_title.text = "編集：%s" % mode
	_refresh_inspector()
	_refresh_action_hint()
	_update_gizmo()
	editor_scroll.scroll_vertical = 0
	_refresh_contact_markers()

func _toggle_timeline() -> void:
	timeline_expanded = not timeline_expanded
	_apply_mode_layout()

func _toggle_key_list() -> void:
	key_list_expanded = not key_list_expanded
	key_scroll.visible = key_list_expanded and mode == "モーション"
	key_list_toggle.text = "全キー ▲" if key_list_expanded else "全キー ▼"

func _mode_shortcut(action: String) -> void:
	match action:
		"parts": _open_part_selector()
		"motion": _change_mode("モーション")
		"ik": _change_mode("IK")
		"contact": _change_mode("接触")
		"diagnose": _refresh_inspector()
		"add_ik": _add_ik_chain()
		"add_key": _insert_key()
		"remove_key": _remove_key()
		"bake": _run_ik_fk_bake()
		"export": _file_dialog("export")

func _rebuild_mode_actions() -> void:
	if mode_action_bar == null:
		return
	for child in mode_action_bar.get_children():
		mode_action_bar.remove_child(child)
		child.queue_free()
	var actions: Array = []
	match mode:
		"階層": actions = [["パーツ検索", "parts"], ["選択した部位を編集", "motion"]]
		"モーション": actions = [["パーツ検索", "parts"], ["＋キー", "add_key"], ["－キー", "remove_key"]]
		"IK": actions = [["IKを追加", "add_ik"], ["パーツ検索", "parts"], ["足先の固定へ", "contact"]]
		"制約": actions = [["パーツ検索", "parts"], ["モーション編集", "motion"]]
		"接触": actions = [["IK設定", "ik"], ["パーツ検索", "parts"]]
		"診断": actions = [["もう一度診断", "diagnose"], ["IK設定", "ik"]]
		"ベイク": actions = [["▶ ベイク実行", "bake"], ["Godotに書き出す", "export"]]
	for spec in actions:
		var action_id: String = str(spec[1])
		var button := _make_button(str(spec[0]), func(): _mode_shortcut(action_id), mode_action_bar)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(button, action_id in ["add_key", "add_ik", "bake"])

func _apply_mode_layout() -> void:
	if preview_frame == null or editor_panel == null or timeline_panel == null or editor_body == null:
		return
	# Keep the 3D view usable, while letting the mode-specific inspector fill the rest.
	# Motion mode displays the original FK diamonds plus the selected IK lane.
	# IK mode displays only the IK lane, keeping the portrait 3D preview usable.
	var timeline_full: bool = mode == "モーション"
	var time_scrub: bool = mode in ["モーション", "IK", "接触", "診断", "ベイク"]
	timeline_panel.get_parent().visible = time_scrub
	var show_timeline: bool = mode in ["モーション", "IK"] and timeline_expanded
	var show_keyframes: bool = timeline_full and timeline_expanded
	timeline_title.text = "キーフレーム・IK" if timeline_full else ("IK適用時間" if mode == "IK" else "動きの時間")
	timeline_toggle.visible = mode in ["モーション", "IK"]
	timeline_toggle.text = "閉じる ▲" if timeline_expanded else "開く ▼"
	seek.visible = not show_timeline
	timeline_view.visible = show_timeline
	timeline_transport.visible = show_keyframes
	key_list_toggle.visible = show_keyframes
	key_scroll.visible = show_keyframes and key_list_expanded
	var show_transform_tools: bool = mode in ["階層", "モーション"]
	for name in tool_buttons:
		tool_buttons[name].visible = show_transform_tools
	preview_tools_panel.offset_top = -169.0 if show_transform_tools else -65.0
	var editor_container: Control = editor_panel.get_parent()
	var expanded: bool = editor_body.visible
	editor_container.size_flags_vertical = Control.SIZE_EXPAND_FILL if expanded else Control.SIZE_FILL
	editor_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL if expanded else Control.SIZE_FILL
	mode_action_bar.visible = expanded
	preview_frame.size_flags_stretch_ratio = float({
		"階層": 1.0, "モーション": 1.1, "IK": 1.0,
		"制約": 0.9, "接触": 1.0, "診断": 1.0, "ベイク": 1.0
	}.get(mode, 1.0))
	editor_container.size_flags_stretch_ratio = float({
		"階層": 1.7, "モーション": 1.3, "IK": 1.6,
		"制約": 1.9, "接触": 1.7, "診断": 1.7, "ベイク": 1.6
	}.get(mode, 1.5))
	part_selector_label.text = "対象パーツ" if mode not in ["モーション", "階層"] else "② 動かす部位"
	animation_selector_label.text = "確認する動き" if mode not in ["モーション", "階層"] else "① モーション選択"
	_rebuild_mode_actions()

func _refresh_action_hint() -> void:
	if action_hint == null:
		return
	var descriptions: Dictionary = {
		"階層": "部位をタップして選択 →「動き編集」で回転を変更",
		"モーション": "黄色い◆で時間選択／ドラッグでキー移動 → 関節を回転",
		"IK": "青いTLバーでIK・接触回避の適用時間を指定。目標点は3Dハンドルで調整",
		"制約": "関節を選び、動かせる角度や範囲を設定",
		"接触": "足先の床固定・滑走・物体追従を設定",
		"診断": "エラーと接地状態を確認",
		"ベイク": "IKを計算した動きを普通のキーに変換"
	}
	if rig == null or rig.imported_source == "sample":
		action_hint.text = "ファイル ▾ でbbmodelを読込（サンプルでも試せます）"
	else:
		action_hint.text = str(descriptions.get(mode, "時間と部位を選んで編集"))

func _toggle_editor() -> void:
	editor_body.visible = not editor_body.visible
	editor_toggle.text = "閉じる ▲" if editor_body.visible else "開く ▼"
	_apply_mode_layout()

func _show_help() -> void:
	guide_step = 0
	if help_popup == null:
		help_popup = AcceptDialog.new()
		help_popup.title = "Motion Studio 操作ガイド"
		help_popup.min_size = Vector2i(300, 170)
		help_popup.confirmed.connect(_advance_help)
		add_child(help_popup)
	_display_help_step()
	var file := FileAccess.open("user://motion_studio_guide_seen.txt", FileAccess.WRITE)
	if file != null:
		file.store_string("seen")

func _display_help_step() -> void:
	var pages := [
		"1 / 3  モデルを読み込む\n\n上の「ファイル」→「モデルを読み込む」で .bbmodel を選びます。\nサンプルモデルのままでも操作を試せます。",
		"2 / 3  部位とモーションを選ぶ\n\n上の「階層」で関節の親子関係を確認。\n「モーション」で部位やアニメーションを選びます。",
		"3 / 3  タイムラインで編集\n\n黄色い◆をタップして時間を選択。\nドラッグしてキーを移動でき、↶で取り消せます。"
	]
	help_popup.dialog_text = pages[guide_step]
	help_popup.ok_button_text = "完了" if guide_step == 2 else "次へ"
	help_popup.popup_centered(Vector2i(400, 220))

func _advance_help() -> void:
	if guide_step < 2:
		guide_step += 1
		call_deferred("_display_help_step")

func _build_stage() -> void:
	stage = Node3D.new()
	viewport.add_child(stage)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-58, 34, 0)
	light.light_energy = 1.5
	stage.add_child(light)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("2a3542")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8395aa")
	environment.ambient_light_energy = 0.72
	env.environment = environment
	stage.add_child(env)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 48.0
	stage.add_child(camera)
	_update_camera()
	floor_area = StaticBody3D.new()
	floor_area.name = "床"
	floor_area.collision_layer = 1
	floor_area.collision_mask = 0
	var floor_visual := MeshInstance3D.new()
	var ground := PlaneMesh.new()
	ground.size = Vector2(35, 35)
	floor_visual.mesh = ground
	var surface := StandardMaterial3D.new()
	surface.albedo_color = Color("394a56")
	surface.roughness = 0.95
	floor_visual.material_override = surface
	floor_area.add_child(floor_visual)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(35, 0.1, 35)
	cs.position.y = -0.055
	cs.shape = box
	floor_area.add_child(cs)
	stage.add_child(floor_area)
	var grid := MeshInstance3D.new()
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-12, 13):
		lines.surface_add_vertex(Vector3(i, 0.005, -12))
		lines.surface_add_vertex(Vector3(i, 0.005, 12))
		lines.surface_add_vertex(Vector3(-12, 0.005, i))
		lines.surface_add_vertex(Vector3(12, 0.005, i))
	lines.surface_end()
	grid.mesh = lines
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("60717f")
	grid.material_override = mat
	stage.add_child(grid)
	rig = MotionRig.new()
	stage.add_child(rig)
	rig.create_sample()
	motion_gizmo = MotionGizmo.new()
	stage.add_child(motion_gizmo)

func _update_camera() -> void:
	var center := camera_focus
	camera.position = center + Vector3(
		sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch)) * camera_distance
	camera.look_at(center, Vector3.UP)
	_update_gizmo()

func _note(message: String) -> void:
	message_label.text = message

func _export_animation(path: String) -> void:
	_note(motion.export_animation_tres(path))
	# The report belongs to the exported file, not to a live preview state.
	if mode == "ベイク":
		_refresh_inspector()

func _toolbar_action(action: String) -> void:
	match action:
		"import": _file_dialog("import")
		"save": _note(motion.save_project("user://motion_studio.motion.json"))
		"open": _file_dialog("open")
		"export": _export_animation("user://motion_animation.tres")
		"undo":
			if motion.undo():
				_after_model_change("操作を取り消しました")
			else:
				_note("取り消せる操作はありません")
		"redo":
			if motion.redo():
				_after_model_change("操作をやり直しました")
			else:
				_note("やり直せる操作はありません")

func _file_dialog(kind: String) -> void:
	var picker := FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.use_native_dialog = OS.has_feature("mobile")
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE if kind != "export" and kind != "save_as" else FileDialog.FILE_MODE_SAVE_FILE
	if kind == "import":
		picker.add_filter("*.bbmodel,*.json", "Blockbenchモデル")
		picker.add_filter("*.*", "すべてのファイル")
		picker.add_filter("*.glb,*.gltf", "glTFモデル")
	elif kind == "open":
		picker.add_filter("*.json", "Motion Studio保存データ")
	elif kind == "save_as":
		picker.add_filter("*.json", "Motion Studio保存データ")
	else:
		picker.add_filter("*.tres", "Godotアニメーション")
	picker.file_selected.connect(func(path: String):
		match kind:
			"import": _import_model(path)
			"open":
				var result := motion.load_project(path)
				_populate_animation_picker(false)
				_fit_import_camera()
				_after_model_change(result)
			"save_as": _note(motion.save_project(path))
			"export": _export_animation(path)
		picker.queue_free())
	picker.canceled.connect(func(): picker.queue_free())
	add_child(picker)
	picker.popup_centered_ratio(0.92)

func _import_model(path: String) -> void:
	var lower := path.to_lower().uri_decode()
	var issue := ""
	if lower.contains(".glb") or lower.contains(".gltf"):
		issue = rig.load_gltf(path)
	else:
		# Android SAF may return content:// URIs without a visible extension.
		issue = rig.load_bbmodel(path)
	if issue != "":
		_note("読み込みに失敗：" + issue)
		return
	motion.setup(rig)
	_populate_animation_picker(true)
	selected_part = rig.parts.keys()[0] if not rig.parts.is_empty() else ""
	selected_chain = 0
	_fit_import_camera()
	var summary := "%d部位、%dモーション" % [rig.parts.size(), rig.bb_animations.size()]
	if not rig.bb_import_warnings.is_empty():
		summary += "（テクスチャ等の注意 %d件）" % rig.bb_import_warnings.size()
	_after_model_change("Blockbenchモデルを読み込みました：" + summary)

func _populate_animation_picker(auto_apply: bool) -> void:
	if animation_picker == null:
		return
	animation_picker.clear()
	animation_picker.add_item("基本姿勢（モーションなし）")
	for animation in rig.bb_animations:
		animation_picker.add_item(str(animation.get("name", "名前なし")))
	animation_picker.disabled = rig.bb_animations.is_empty()
	var selected := 0
	if auto_apply and not rig.bb_animations.is_empty():
		selected = 1
		for i in range(rig.bb_animations.size()):
			if float(rig.bb_animations[i].get("length", 0.0)) > 0.01:
				selected = i + 1
				break
		motion.load_bb_animation(selected - 1)
	animation_picker.select(selected)

func _fit_import_camera() -> void:
	if rig.model_root == null:
		return
	var stack: Array = [rig.model_root]
	var box := AABB()
	var found := false
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and node.mesh != null:
			var bound: AABB = node.get_aabb()
			for dx in [0.0, 1.0]:
				for dy in [0.0, 1.0]:
					for dz in [0.0, 1.0]:
						var point: Vector3 = node.to_global(bound.position + bound.size * Vector3(dx, dy, dz))
						if not found:
							box = AABB(point, Vector3.ZERO)
							found = true
						else:
							box = box.expand(point)
		for child in node.get_children():
			stack.append(child)
	if found:
		camera_focus = box.get_center()
		camera_distance = clampf(box.size.length() * 1.6, 3.0, 35.0)
		_update_camera()

func _after_model_change(note: String) -> void:
	playing = false
	play_button.text = "▶ 再生"
	_refresh_part_picker()
	_refresh_inspector()
	_refresh_key_buttons()
	_update_timeline()
	_update_gizmo()
	_refresh_action_hint()
	_refresh_contact_markers()
	_note(note)

func _refresh_part_picker() -> void:
	part_picker.clear()
	var index := 0
	var selected_index := 0
	for name in rig.parts.keys():
		part_picker.add_item(name)
		if name == selected_part:
			selected_index = index
		index += 1
	if not rig.parts.is_empty():
		part_picker.select(selected_index)
		selected_part = part_picker.get_item_text(selected_index)
	_update_gizmo()
	_update_selection_badge()
	_refresh_timeline_view()
	_refresh_action_hint()

func _update_selection_badge() -> void:
	if selection_badge != null:
		selection_badge.text = "◇  " + selected_part if rig != null and rig.parts.has(selected_part) else "選択なし"

func _refresh_timeline_view() -> void:
	if timeline_view != null and motion != null:
		timeline_view.set_timeline(motion.frames, selected_part, motion.duration, motion.play_time, motion.fps)
		timeline_view.set_ik_track(rig.chains, selected_chain, mode == "モーション")

func _on_outliner_selected(name: String) -> void:
	selected_part = name
	_refresh_part_picker()
	_update_gizmo()
	_refresh_timeline_view()
	_note("選択：%s" % name)

func _inspector_outliner() -> void:
	outliner = MotionOutliner.new()
	outliner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector.add_child(outliner)
	outliner.part_selected.connect(_on_outliner_selected)
	outliner.set_model(rig, selected_part)
	var go_to_edit := _make_button("選択した部位のモーションを編集", func(): _change_mode("モーション"), inspector)
	_style_button(go_to_edit, false, true)

func _refresh_key_buttons() -> void:
	_refresh_timeline_view()
	for child in key_row.get_children():
		child.queue_free()
	# A baked timeline may have thousands of keys. Only show sampled shortcuts;
	# all frames remain accessible from the scrubber and by frame stepping.
	var count: int = motion.frames.size()
	if count > 40:
		var summary := _add_text(key_row, "%dキー　時間バーで移動　" % count)
		summary.custom_minimum_size.x = 185
	var step_size: int = maxi(1, int(ceil(float(count) / 28.0)))
	for index in range(0, count, step_size):
		var t: float = float(motion.frames[index]["time"])
		_make_button("◆ %.2f" % t, func(): _seek_to(t), key_row)
	if count > 1 and (count - 1) % step_size != 0:
		var last_t: float = float(motion.frames[count - 1]["time"])
		_make_button("◆ %.2f" % last_t, func(): _seek_to(last_t), key_row)

func _update_timeline() -> void:
	seek.set_value_no_signal(motion.play_time)
	seek.max_value = motion.duration
	time_label.text = "%.2f秒  /  %.2f" % [motion.play_time, motion.duration]
	if timeline_view != null:
		timeline_view.set_playhead(motion.play_time)

func _seek_to(value: float) -> void:
	motion.evaluate(value)
	_update_timeline()
	_update_gizmo()
	_refresh_contact_markers()
	if show_original:
		_show_raw_pose()

func _seek_by(seconds: float) -> void:
	playing = false
	play_button.text = "▶ 再生"
	_seek_to(motion.play_time + seconds)

func _toggle_playback() -> void:
	playing = not playing
	play_button.text = "Ⅱ 停止" if playing else "▶ 再生"
	_update_gizmo()

func _insert_key() -> void:
	motion.record_undo()
	motion.capture_key(motion.play_time)
	_refresh_key_buttons()
	_update_history_buttons()
	_note("現在の姿勢をキーフレームに保存しました")

func _remove_key() -> void:
	if motion.delete_key(motion.play_time):
		_refresh_key_buttons()
		_update_history_buttons()
		_note("現在のキーを削除しました（元に戻すには↶）")
	else:
		_note("ここに削除できるキーはありません。◆をタップして選択してください")

func _process(delta: float) -> void:
	if motion == null:
		return
	if playing:
		var next_time := motion.play_time + delta * playback_speed
		if next_time > motion.duration:
			next_time = fmod(next_time, motion.duration)
		_seek_to(next_time)
	save_clock += delta
	status_clock += delta
	if status_clock >= 0.25:
		status_clock = 0.0
		_update_history_buttons()
		if mode == "診断":
			_refresh_inspector()
	if save_clock >= 60.0:
		save_clock = 0.0
		motion.save_project("user://autosave.motion.json")

func _clear_inspector() -> void:
	for child in inspector.get_children():
		inspector.remove_child(child)
		child.queue_free()

func _refresh_inspector() -> void:
	if inspector == null or motion == null:
		return
	_clear_inspector()
	var hints := {
		"階層": "パーツの親子関係を確認して部位を選択",
		"モーション": "部位を選び、位置・回転を変更",
		"IK": "IK目標と時間指定の接触回避を設定",
		"制約": "動かせる範囲を設定",
		"接触": "箱や球を置いて接触をテスト",
		"診断": "動作の問題を確認",
		"ベイク": "IK/FKの結果をキーフレーム化"
	}
	var hint := _add_text(inspector, str(hints.get(mode, "")))
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("90b9cc"))
	match mode:
		"階層": _inspector_outliner()
		"モーション": _inspector_motion()
		"IK": _inspector_ik()
		"制約": _inspector_constraints()
		"接触": _inspector_contacts()
		"診断": _inspector_diagnostics()
		"ベイク": _inspector_export()

func _vector_fields(title: String, value: Vector3, low: float, high: float, step: float, changed: Callable) -> void:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 3)
	inspector.add_child(group)
	var title_label := _add_text(group, title)
	title_label.add_theme_color_override("font_color", Color("cfe3f5"))
	var axes := _row(group)
	for axis in range(3):
		var axis_index: int = axis
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		axes.add_child(column)
		var name_label := _add_text(column, ["X", "Y", "Z"][axis])
		name_label.add_theme_font_size_override("font_size", 13)
		var spin := SpinBox.new()
		spin.min_value = low
		spin.max_value = high
		spin.step = step
		spin.value = value[axis]
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.custom_minimum_size = Vector2(0, 42)
		spin.value_changed.connect(func(v: float): changed.call(axis_index, v))
		column.add_child(spin)

func _number_field(label: String, initial: float, low: float, high: float, step: float, changed: Callable) -> void:
	var line := _row(inspector)
	var text_label := _add_text(line, label)
	text_label.add_theme_font_size_override("font_size", 14)
	var number := SpinBox.new()
	number.custom_minimum_size = Vector2(140, 42)
	number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	number.min_value = low
	number.max_value = high
	number.step = step
	number.value = initial
	line.add_child(number)
	number.value_changed.connect(changed)

func _check(label: String, checked: bool, changed: Callable) -> void:
	var check := CheckBox.new()
	check.text = label
	check.button_pressed = checked
	check.custom_minimum_size.y = 44
	check.toggled.connect(changed)
	inspector.add_child(check)

func _run_ik_fk_bake() -> void:
	playing = false
	play_button.text = "▶ 再生"
	var result: Dictionary = motion.bake_ik_fk(bake_target_fps)
	if not bool(result.get("ok", false)):
		_note(str(result.get("message", "ベイクできませんでした")))
		return
	_after_model_change(str(result["message"]))
	_refresh_inspector()

func _restore_before_bake() -> void:
	playing = false
	play_button.text = "▶ 再生"
	if not motion.restore_bake_source():
		_note("ベイク前のモーションは保存されていません")
		return
	_after_model_change("ベイク前のモーションとIK・制約を復元しました")

func _bake_controls() -> void:
	var title := _add_text(inspector, "IK/FKベイク", true)
	title.add_theme_color_override("font_color", Color("5ce3d5"))
	_add_text(inspector, "IK・制約を計算した完成姿勢をキー化します。変換後はIK不要で再生できます。")
	var fps_row := _row(inspector)
	_add_text(fps_row, "記録精度")
	var rate := OptionButton.new()
	rate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for value in [30, 60]:
		rate.add_item("%dfps" % value, value)
		if value == bake_target_fps:
			rate.select(rate.item_count - 1)
	rate.item_selected.connect(func(index: int):
		bake_target_fps = rate.get_item_id(index))
	fps_row.add_child(rate)
	var run_button := _make_button("▶ IK/FKをキーフレーム化", _run_ik_fk_bake, inspector)
	run_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(run_button, false, true)
	if not motion.bake_report.is_empty():
		var info: Dictionary = motion.bake_report
		_add_text(inspector, "ベイク済み：%dキー / %dfps（IK停止）" % [
			int(info.get("frame_count", 0)), int(info.get("fps", 0))])
		_add_text(inspector, "中間フレームの最大誤差：位置 %.3fm / 回転 %.2f°" % [
			float(info.get("max_position_error_m", 0.0)),
			float(info.get("max_rotation_error_deg", 0.0))])
	if not motion.bake_source.is_empty():
		var restore_button := _make_button("↶ ベイク前に戻す", _restore_before_bake, inspector)
		_style_button(restore_button)

func _inspector_motion() -> void:
	_add_text(inspector, "キーフレーム姿勢編集", true)
	_add_text(inspector, "時間 %.3f秒 / 選択中：%s" % [motion.play_time, selected_part])
	if not rig.parts.has(selected_part):
		return
	var sampled: Dictionary = motion.sample(motion.play_time)
	if not sampled.has(selected_part):
		return
	var pose: Dictionary = sampled[selected_part]
	for field in ["position", "rotation", "scale"]:
		var lower: float = -10.0 if field == "position" else (-360.0 if field == "rotation" else 0.01)
		var upper: float = 10.0 if field == "position" else (360.0 if field == "rotation" else 8.0)
		var step: float = 0.01 if field != "rotation" else 1.0
		var label: String = {"position": "位置 (m)", "rotation": "回転 (度)", "scale": "拡大縮小"}[field]
		_vector_fields(label, MotionRig.from_array(pose[field]), lower, upper, step,
			func(axis: int, value: float):
				motion.record_undo()
				motion.set_key_component(motion.play_time, selected_part, field, axis, value)
				_refresh_key_buttons())
	_add_text(inspector, "現在の時間で回転・位置・拡縮を変更すると、キーが追加されます。")
	_number_field("再生速度", playback_speed, 0.1, 3.0, 0.1, func(v: float): playback_speed = v)
	_number_field("長さ (秒)", motion.duration, 0.5, 60.0, 0.5, func(v: float):
		motion.duration = v
		_update_timeline())
	_add_text(inspector, "追加・削除は上の「＋キー」「－キー」から操作します。")
	_add_text(inspector, "IK/FKベイクは上の「詳細機能 ▾」から開けます。")

func _set_chain_prop(key: String, value: Variant) -> void:
	if selected_chain < 0 or selected_chain >= rig.chains.size():
		return
	motion.record_undo()
	if key == "start":
		value = clampf(float(value), 0.0, float(rig.chains[selected_chain]["finish"]))
	elif key == "finish":
		value = clampf(float(value), float(rig.chains[selected_chain]["start"]), motion.duration)
	rig.chains[selected_chain][key] = value
	motion.evaluate(motion.play_time)
	_refresh_timeline_view()
	_update_history_buttons()

func _set_collision_avoid(enabled: bool) -> void:
	if selected_chain < 0 or selected_chain >= rig.chains.size():
		return
	motion.record_undo()
	var chain: Dictionary = rig.chains[selected_chain]
	chain["collision_avoid"] = enabled
	if enabled:
		chain["enabled"] = true
	motion.evaluate(motion.play_time)
	_refresh_timeline_view()
	_refresh_inspector()
	_update_history_buttons()

func _inspector_ik() -> void:
	_add_text(inspector, "IKチェーンと目標点", true)
	var row := _row(inspector)
	var chain_select := OptionButton.new()
	chain_select.fit_to_longest_item = false
	chain_select.clip_text = true
	
	chain_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for chain in rig.chains:
		chain_select.add_item(str(chain["name"]))
	if not rig.chains.is_empty():
		selected_chain = clampi(selected_chain, 0, rig.chains.size() - 1)
		chain_select.select(selected_chain)
	chain_select.item_selected.connect(func(i: int):
		selected_chain = i
		_refresh_inspector()
		_refresh_timeline_view()
		_update_gizmo())
	row.add_child(chain_select)
	_make_button("IKを追加", _add_ik_chain, row)
	if rig.chains.is_empty():
		_add_text(inspector, "モデルの関節を選んでIKチェーンを追加してください。")
		return
	var chain: Dictionary = rig.chains[selected_chain]
	_check("IKを有効にする", chain["enabled"], func(on: bool): _set_chain_prop("enabled", on))
	var calculation := _row(inspector)
	_add_text(calculation, "計算方法")
	var method_select := OptionButton.new()
	method_select.fit_to_longest_item = false
	method_select.clip_text = true
	
	_add_text(inspector, "「2ボーン」は関節長を維持する解析IKです。膝の曲がる向きは下の「膝方向」で調整できます。")
	for method_name in ["CCD", "FABRIK", "2ボーン"]:
		method_select.add_item(method_name)
		if method_name == chain["method"]:
			method_select.select(method_select.item_count - 1)
	method_select.item_selected.connect(func(i: int): _set_chain_prop("method", method_select.get_item_text(i)))
	calculation.add_child(method_select)
	for item in [["root", "始点"], ["mid", "中間"], ["end", "末端"]]:
		var field: String = item[0]
		var line := _row(inspector)
		_add_text(line, item[1])
		var picker := OptionButton.new()
		picker.fit_to_longest_item = false
		picker.clip_text = true
		
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for joint_name in rig.parts.keys():
			picker.add_item(joint_name)
			if joint_name == str(chain[field]): picker.select(picker.item_count - 1)
		picker.item_selected.connect(func(i: int): _set_chain_prop(field, picker.get_item_text(i)))
		line.add_child(picker)
	var goal: Node3D = chain["target"]
	_vector_fields("目標位置（ワールド座標・m）", goal.global_position, -30, 30, 0.01,
		func(axis: int, value: float):
			motion.record_undo()
			var pos := goal.global_position
			pos[axis] = value
			goal.global_position = pos
			motion.evaluate(motion.play_time))
	_vector_fields("膝方向（ワールド方向）", MotionRig.from_array(chain.get("pole", [0.0, 0.0, 1.0])), -1.0, 1.0, 0.05,
		func(axis: int, value: float):
			var pole: Array = chain.get("pole", [0.0, 0.0, 1.0]).duplicate()
			pole[axis] = value
			_set_chain_prop("pole", pole))
	_number_field("IK強度", chain["weight"], 0.0, 1.0, 0.05, func(v: float): _set_chain_prop("weight", v))
	_add_text(inspector, "接触回避IK（時間指定）", true)
	_check("接触した時だけIKで避ける", bool(chain.get("collision_avoid", false)),
		func(on: bool): _set_collision_avoid(on))
	if bool(chain.get("collision_avoid", false)):
		_add_text(inspector, "モーションの元の軌道を残し、指定時間内に対象へめり込む時だけ関節を補正します。離れている時は姿勢を変更しません。")
		_check("地面との接触を回避", bool(chain.get("collision_floor", true)),
			func(on: bool): _set_chain_prop("collision_floor", on))
		_check("物体との接触を回避", bool(chain.get("collision_objects", false)),
			func(on: bool): _set_chain_prop("collision_objects", on))
		if bool(chain.get("collision_objects", false)):
			_add_text(inspector, "接触モードで配置した箱・球・カプセルを対象にします。")
			var selector_row := _row(inspector)
			_add_text(selector_row, "回避する物体")
			var object_picker := OptionButton.new()
			object_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			object_picker.clip_text = true
			object_picker.add_item("すべてのテスト物体")
			for test_object in rig.test_objects:
				object_picker.add_item(str(test_object["node"].name))
			var object_index: int = int(chain.get("collision_object_index", -1))
			object_picker.select(clampi(object_index + 1, 0, rig.test_objects.size()))
			object_picker.item_selected.connect(func(i: int): _set_chain_prop("collision_object_index", i - 1))
			selector_row.add_child(object_picker)
			if rig.test_objects.is_empty():
				_add_text(inspector, "テスト物体がありません。「詳細機能 ▾」→「接触」で物体を配置してください。")
		_check("中間関節側のメッシュも判定", bool(chain.get("collision_include_mid", true)),
			func(on: bool): _set_chain_prop("collision_include_mid", on))
		_number_field("地面の高さ（m）", float(chain.get("collision_height", 0.0)), -10.0, 10.0, 0.01,
			func(v: float): _set_chain_prop("collision_height", v))
		_number_field("接触回避の余裕（m）", float(chain.get("collision_margin", 0.005)), 0.0, 0.25, 0.005,
			func(v: float): _set_chain_prop("collision_margin", v))
		_add_text(inspector, "青い「接触回避」バーの両端で有効時間を指定します。床固定と違い、接触がなければ元のモーションを維持します。回避できない場合は診断に残差を表示します。")
	_add_text(inspector, "上の青いバー：両端をドラッグで時間変更／中央で区間移動（1フレーム単位）")
	_number_field("開始 (秒)", chain["start"], 0.0, motion.duration, 0.05, func(v: float): _set_chain_prop("start", v))
	_number_field("終了 (秒)", chain["finish"], 0.0, motion.duration, 0.05, func(v: float): _set_chain_prop("finish", v))
	_add_text(inspector, "目標の赤・緑・青の矢印を指でドラッグすると、X・Y・Z軸を個別に動かせます。")
	var lock_button := _make_button("足先固定・滑走の設定へ", func(): _change_mode("接触"), inspector)
	_style_button(lock_button, false, true)

func _add_ik_chain() -> void:
	var names: Array = rig.parts.keys()
	if names.size() < 3:
		_note("IK設定には3部位以上必要です")
		return
	motion.record_undo()
	# Prefer the selected joint as an end effector when it has two registered ancestors.
	var tip_name: String = selected_part if rig.parts.has(selected_part) else str(names[2])
	var tip_node: Node3D = rig.parts[tip_name]
	var parent: Node = tip_node.get_parent()
	var grandparent: Node = parent.get_parent() if parent != null else null
	var middle: String = str(parent.get_meta("part_name")) if parent != null and parent.has_meta("part_name") else str(names[1])
	var parent_name: String = str(grandparent.get_meta("part_name")) if grandparent != null and grandparent.has_meta("part_name") else str(names[0])
	rig.add_chain("新規IK" + str(rig.chains.size() + 1), parent_name, middle, tip_name,
		Vector3.ZERO, tip_node.global_position)
	selected_chain = rig.chains.size() - 1
	_refresh_timeline_view()
	_refresh_inspector()

func _set_limit(label: String, field: String, axis: int, value: float) -> void:
	motion.record_undo()
	if not motion.constraints.has(label):
		motion.constraints[label] = motion.default_constraint()
	var arr: Array = motion.constraints[label][field]
	arr[axis] = value
	motion.evaluate(motion.play_time)

func _inspector_constraints() -> void:
	_add_text(inspector, "位置・回転・伸縮の制限", true)
	if not rig.parts.has(selected_part):
		return
	if not motion.constraints.has(selected_part):
		motion.constraints[selected_part] = motion.default_constraint()
	var item: Dictionary = motion.constraints[selected_part]
	_check("この部位の制約を有効化", item.get("enabled", true), func(active: bool):
		motion.record_undo()
		item["enabled"] = active
		motion.evaluate(motion.play_time))
	for field in ["position", "rotation", "scale"]:
		var title: String = {"position": "位置 (m)", "rotation": "回転 (度)", "scale": "伸縮"}[field]
		var low: float = -30.0 if field == "position" else (-360.0 if field == "rotation" else 0.0)
		var high: float = 30.0 if field == "position" else (360.0 if field == "rotation" else 10.0)
		for limit_kind in ["min", "max"]:
			var slot: String = field + "_" + limit_kind
			_vector_fields(title + (" 下限" if limit_kind == "min" else " 上限"),
				MotionRig.from_array(item[slot]), low, high, 0.1,
				func(axis: int, value: float): _set_limit(selected_part, slot, axis, value))
	_number_field("制約の強度", item["weight"], 0, 1, 0.05, func(v: float):
		motion.record_undo()
		item["weight"] = v
		motion.evaluate(motion.play_time))
	_number_field("制約開始", item["start"], 0, 60, 0.05, func(v: float):
		motion.record_undo()
		item["start"] = v
		motion.evaluate(motion.play_time))
	_number_field("制約終了", item["finish"], 0, 60, 0.05, func(v: float):
		motion.record_undo()
		item["finish"] = v
		motion.evaluate(motion.play_time))
	_add_text(inspector, "※ 同じ軸の下限が上限を超える設定は避けてください。")

func _new_contact(mode_name: String) -> void:
	var object_idx: int = selected_test if mode_name == "obstacle" else -1
	if not motion.add_contact(selected_chain, mode_name, object_idx):
		_note("固定できません：IKまたは参照物体を選択してください")
		return
	selected_contact = motion.contact_constraints.size() - 1
	_after_model_change("足先固定を作成しました。黄色い球が固定位置です")

func _edit_contact(index: int, key: String, value: Variant) -> void:
	if index < 0 or index >= motion.contact_constraints.size():
		return
	motion.record_undo()
	motion.contact_constraints[index][key] = value
	motion.evaluate(motion.play_time)
	_refresh_contact_markers()
	_update_history_buttons()

func _delete_contact() -> void:
	if selected_contact < 0 or selected_contact >= motion.contact_constraints.size():
		return
	motion.record_undo()
	motion.contact_constraints.remove_at(selected_contact)
	selected_contact = mini(selected_contact, motion.contact_constraints.size() - 1)
	motion.evaluate(motion.play_time)
	_refresh_contact_markers()
	_refresh_inspector()

func _refresh_contact_markers() -> void:
	if stage == null or motion == null:
		return
	while contact_markers.size() < motion.contact_constraints.size():
		var marker := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.09
		sphere.height = 0.18
		marker.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color("ffe184")
		mat.no_depth_test = true
		marker.material_override = mat
		stage.add_child(marker)
		contact_markers.append(marker)
	for i in range(contact_markers.size()):
		var marker: MeshInstance3D = contact_markers[i]
		marker.visible = false
		if i >= motion.contact_constraints.size():
			continue
		var contact: Dictionary = motion.contact_constraints[i]
		var result: Dictionary = motion.get_contact_goal(int(contact.get("chain_index", -1)), motion.play_time)
		if mode in ["接触", "IK", "診断"] and bool(result.get("active", false)) and int(result.get("contact_index", -1)) == i:
			marker.visible = true
			marker.global_position = result["position"]

func _inspector_contact_locks() -> void:
	_add_text(inspector, "足先固定・滑走（IK/FKベイク対応）", true)
	_add_text(inspector, "床・空間・物体に足先を固定し、摩擦と移動速度を設定します。")
	if rig.chains.is_empty():
		_add_text(inspector, "先に「IK設定」でチェーンを作成してください。")
		return
	var chain_row := _row(inspector)
	_add_text(chain_row, "IKの足先")
	var chains := OptionButton.new()
	chains.fit_to_longest_item = false
	chains.clip_text = true
	chains.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for chain in rig.chains:
		chains.add_item(str(chain["name"]))
	selected_chain = clampi(selected_chain, 0, rig.chains.size() - 1)
	chains.select(selected_chain)
	chains.item_selected.connect(func(i: int): selected_chain = i)
	chain_row.add_child(chains)
	var actions := _row(inspector)
	for item in [["床に固定", "floor"], ["空間に固定", "world"], ["物体に固定", "obstacle"]]:
		var kind: String = str(item[1])
		var btn := _make_button(str(item[0]), func(): _new_contact(kind), actions)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.disabled = kind == "obstacle" and rig.test_objects.is_empty()
		_style_button(btn, kind == "floor")
	if motion.contact_constraints.is_empty():
		_add_text(inspector, "固定点はありません。足先を選んで固定方法を押してください。")
		return
	var control_row := _row(inspector)
	var options := OptionButton.new()
	options.fit_to_longest_item = false
	options.clip_text = true
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range(motion.contact_constraints.size()):
		var item: Dictionary = motion.contact_constraints[i]
		var k: int = int(item.get("chain_index", -1))
		var name: String = str(rig.chains[k]["name"]) if k >= 0 and k < rig.chains.size() else "不明"
		options.add_item("%d: %s" % [i + 1, name])
	selected_contact = clampi(selected_contact, 0, motion.contact_constraints.size() - 1)
	options.select(selected_contact)
	options.item_selected.connect(func(i: int):
		selected_contact = i
		_refresh_inspector())
	control_row.add_child(options)
	var remove := _make_button("削除", _delete_contact, control_row)
	_style_button(remove)
	var idx: int = selected_contact
	var entry: Dictionary = motion.contact_constraints[idx]
	_check("固定を有効にする", bool(entry.get("enabled", true)), func(v: bool): _edit_contact(idx, "enabled", v))
	for spec in [["weight", "固定強度", 0.0, 1.0], ["friction", "摩擦（1=固定）", 0.0, 1.0],
		["start", "開始 秒", 0.0, motion.duration], ["finish", "終了 秒", 0.0, motion.duration]]:
		var key: String = str(spec[0])
		_number_field(str(spec[1]), float(entry.get(key, 1.0)), float(spec[2]), float(spec[3]), 0.05,
			func(v: float): _edit_contact(idx, key, v))
	_vector_fields("滑走速度 X/Y/Z （m/秒）", MotionRig.from_array(entry.get("slide", [0.0, 0.0, 0.0])),
		-5.0, 5.0, 0.05, func(axis: int, v: float):
			var value: Array = entry.get("slide", [0.0, 0.0, 0.0]).duplicate()
			value[axis] = v
			_edit_contact(idx, "slide", value))
	_add_text(inspector, "黄色の球＝実際の固定目標。物体固定は参照物体の移動に追従します。")

func _inspector_contacts() -> void:
	_inspector_contact_locks()
	_add_text(inspector, "接触・障害物テスト", true)
	var top := _row(inspector)
	for kind in ["箱", "球", "カプセル"]:
		_make_button("＋" + kind, func():
			motion.record_undo()
			selected_test = rig.add_test_object(kind, Vector3(0, 0.55, -1.5))
			_refresh_inspector(), top)
	_make_button("全削除", func():
		motion.record_undo()
		rig.clear_test_objects()
		selected_test = -1
		motion.evaluate(motion.play_time)
		_refresh_contact_markers()
		_refresh_inspector(), top)
	if not rig.test_objects.is_empty():
		var choices := OptionButton.new()
		choices.fit_to_longest_item = false
		choices.clip_text = true
	
		for test in rig.test_objects:
			choices.add_item(str(test["node"].name))
		selected_test = clampi(selected_test, 0, rig.test_objects.size() - 1)
		choices.select(selected_test)
		choices.item_selected.connect(func(index: int):
			selected_test = index
			_refresh_inspector())
		inspector.add_child(choices)
		var test_node: Node3D = rig.test_objects[selected_test]["node"]
		for field in ["position", "rotation", "scale"]:
			var vector: Vector3 = test_node.position if field == "position" else (test_node.rotation_degrees if field == "rotation" else test_node.scale)
			_vector_fields({"position":"位置", "rotation":"回転", "scale":"大きさ"}[field], vector,
				-20.0 if field != "scale" else 0.1, 20.0, 0.05,
				func(axis: int, value: float):
					motion.record_undo()
					var v: Vector3 = test_node.position if field == "position" else (test_node.rotation_degrees if field == "rotation" else test_node.scale)
					v[axis] = value
					_apply_test_transform(test_node, field, axis, value))
	_add_text(inspector, "足先の接触センサーは床と障害物の接触を物理判定します。")
	_add_text(inspector, "※ 現段階では四脚サンプルのみ接触センサーを装備しています。")

func _show_raw_pose() -> void:
	var fk_pose: Dictionary = motion.sample(motion.play_time)
	for name in fk_pose.keys():
		rig.set_pose(name, fk_pose[name])

func _inspector_diagnostics() -> void:
	_add_text(inspector, "リアルタイム診断", true)
	_add_text(inspector, "IK目標・接触回避の残差・関節共有の競合を検査します。")
	_check("IKと制約を除いた原本姿勢を表示", show_original, func(on: bool):
		show_original = on
		motion.evaluate(motion.play_time)
		if on: _show_raw_pose())
	var report: Array = motion.warnings.duplicate()
	report.append_array(rig.get_contact_report())
	if report.is_empty():
		_add_text(inspector, "現時点で検出された問題はありません。")
	else:
		for entry in report:
			_add_text(inspector, "⚠ " + str(entry))
	_add_text(inspector, "※ IK目標残差・足先の床距離・物理センサーを表示。全身の高精度干渉解析は今後の拡張対象です。")

func _inspector_export() -> void:
	_bake_controls()
	var header := _add_text(inspector, "ファイルの保存・読み込み", true)
	header.add_theme_color_override("font_color", Color("acc7d6"))
	_add_text(inspector, "上部の「ファイル ▾」から、モデル読み込み・保存・復元・Godot書き出しを選べます。")
	_add_text(inspector, "ベイク済みモーションは、IKの再計算なしでGodotアニメーションへ書き出せます。")
	_add_text(inspector, "書き出し時に.tresを再読込し、関節のローカル位置・回転・拡縮を照合します。")
	if motion.last_export_report.is_empty():
		_add_text(inspector, "出力精度の結果は、最初の書き出し後にここへ表示されます。")
		return
	var audit: Dictionary = motion.last_export_report
	var heading: String = "✓ 前回の書き出しを検証済み" if bool(audit.get("ok", false)) else "⚠ 前回の書き出しに検証警告"
	_add_text(inspector, heading, true)
	_add_text(inspector, "照合：キー %d点・中間 %d点・関節チャンネル %d件" % [
		int(audit.get("key_samples", 0)), int(audit.get("mid_samples", 0)), int(audit.get("tracks_checked", 0))])
	_add_text(inspector, "キー最大差：位置 %.5fm / 回転 %.3f° / 倍率 %.5f" % [
		float(audit.get("max_position_error_m", 0.0)),
		float(audit.get("max_rotation_error_deg", 0.0)), float(audit.get("max_scale_error", 0.0))])
	_add_text(inspector, "キー間最大差：位置 %.5fm / 回転 %.3f° / 倍率 %.5f" % [
		float(audit.get("mid_position_error_m", 0.0)),
		float(audit.get("mid_rotation_error_deg", 0.0)), float(audit.get("mid_scale_error", 0.0))])
	if bool(audit.get("interpolation_warning", false)):
		_add_text(inspector, "⚠ キー間の補間に差があります。FPSを上げてベイク・再出力してください。")
	for problem in audit.get("errors", []):
		_add_text(inspector, "⚠ " + str(problem))
	_add_text(inspector, "※ この検査は現在のモデル階層と出力トラックの照合です。ゲーム側の階層・ルートが違う場合の一致は保証しません。")

func _plane_position(screen_pos: Vector2, height: float) -> Vector3:
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return Vector3.ZERO
	var factor := (height - origin.y) / dir.y
	return origin + dir * factor

func _camera_screen_position(position: Vector2) -> Vector2:
	var dimensions := Vector2(maxf(preview_container.size.x, 1.0), maxf(preview_container.size.y, 1.0))
	return Vector2(position.x * float(viewport.size.x) / dimensions.x, position.y * float(viewport.size.y) / dimensions.y)

func _finish_pointer_drag() -> void:
	if drag_axis >= 0:
		_refresh_key_buttons()
		_refresh_inspector()
		drag_axis = -1
		_update_gizmo()
	dragging_object = false
	pointer_down = false

func _begin_pointer(position: Vector2) -> void:
	pointer_down = true
	if _start_transform_drag(position):
		return
	_pick_from_screen(position)

func _move_pointer(position: Vector2, relative: Vector2) -> void:
	if not pointer_down:
		return
	if drag_axis >= 0:
		_drag_transform(position)
	elif dragging_object and mode == "IK" and selected_chain >= 0 and selected_chain < rig.chains.size():
		var target: Node3D = rig.chains[selected_chain]["target"]
		target.global_position = _plane_position(position, target.global_position.y)
		motion.evaluate(motion.play_time)
	elif dragging_object and mode == "接触" and selected_test >= 0 and selected_test < rig.test_objects.size():
		var obstacle: Node3D = rig.test_objects[selected_test]["node"]
		obstacle.position = _plane_position(position, obstacle.position.y)
	elif pan_view:
		var units: float = camera_distance * tan(deg_to_rad(camera.fov) * 0.5) * 2.0 / maxf(1.0, float(viewport.size.y))
		camera_focus -= (camera.global_transform.basis.x * relative.x + camera.global_transform.basis.y * relative.y) * units
		_update_camera()
	else:
		camera_yaw -= relative.x * 0.008
		camera_pitch = clampf(camera_pitch + relative.y * 0.007, -0.2, 1.3)
		_update_camera()

func _pinch_separation() -> float:
	if active_touches.size() < 2:
		return 0.0
	var indices: Array = active_touches.keys()
	var first: Vector2 = active_touches[indices[0]]
	var second: Vector2 = active_touches[indices[1]]
	return first.distance_to(second)

func _on_screen_touch(event: InputEventScreenTouch) -> void:
	suppress_mouse_until_ms = Time.get_ticks_msec() + 200
	if event.pressed:
		active_touches[event.index] = _camera_screen_position(event.position)
		if active_touches.size() >= 2:
			# Pinch always changes the preview camera zoom, never the model's scale.
			# Stop any one-finger joint manipulation before beginning two-finger zoom.
			_finish_pointer_drag()
			pinch_active = true
			touch_blocked_until_release = true
			pinch_distance = _pinch_separation()
		elif not touch_blocked_until_release:
			_begin_pointer(_camera_screen_position(event.position))
	else:
		active_touches.erase(event.index)
		if active_touches.size() < 2:
			pinch_active = false
			pinch_distance = 0.0
		if active_touches.is_empty():
			_finish_pointer_drag()
			touch_blocked_until_release = false

func _on_screen_drag(event: InputEventScreenDrag) -> void:
	suppress_mouse_until_ms = Time.get_ticks_msec() + 200
	if not active_touches.has(event.index):
		return
	active_touches[event.index] = _camera_screen_position(event.position)
	if pinch_active and active_touches.size() >= 2:
		var current_gap: float = _pinch_separation()
		if pinch_distance > 8.0 and current_gap > 8.0:
			_zoom(clampf(pinch_distance / current_gap, 0.75, 1.35))
		pinch_distance = current_gap
	elif active_touches.size() == 1 and not touch_blocked_until_release:
		_move_pointer(_camera_screen_position(event.position), _camera_screen_position(event.relative))

func _viewport_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_screen_touch(event)
		return
	if event is InputEventScreenDrag:
		_on_screen_drag(event)
		return
	if event is InputEventMagnifyGesture:
		_zoom(1.0 / maxf(0.1, event.factor))
		return
	# Android may synthesize mouse events for the same touch; ignore duplicates.
	if Time.get_ticks_msec() < suppress_mouse_until_ms:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom(1.0 / 1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom(1.12)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_pointer(_camera_screen_position(event.position))
			else:
				_finish_pointer_drag()
	elif event is InputEventMouseMotion and pointer_down:
		_move_pointer(_camera_screen_position(event.position), _camera_screen_position(event.relative))

func _start_transform_drag(point: Vector2) -> bool:
	if pan_view or playing:
		return false
	var moving_ik: bool = mode == "IK" and selected_chain >= 0 and selected_chain < rig.chains.size()
	if not moving_ik and (mode not in ["モーション", "階層"] or not rig.parts.has(selected_part)):
		return false
	var hit: Dictionary = motion_gizmo.hit_test(point)
	if hit.is_empty():
		return false
	drag_axis = int(hit["axis"])
	drag_tangent = hit["tangent"]
	drag_start = point
	if moving_ik:
		var goal: Node3D = rig.chains[selected_chain]["target"]
		drag_value = goal.global_position[drag_axis]
		drag_factor = motion_gizmo.translation_per_pixel(drag_axis)
	else:
		var base: Dictionary = motion.sample(motion.play_time).get(selected_part, {})
		var field := _transform_field()
		var current: Vector3 = MotionRig.from_array(base.get(field, [0.0, 0.0, 0.0]))
		drag_value = current[drag_axis]
		if active_transform == "回転":
			drag_factor = 180.0 / (PI * maxf(1.0, float(hit["radius_pixels"])))
		elif active_transform == "移動":
			drag_factor = motion_gizmo.translation_per_pixel(drag_axis)
		else:
			drag_factor = 0.013
	playing = false
	play_button.text = "▶ 再生"
	motion.record_undo()
	_update_gizmo()
	return true

func _transform_field() -> String:
	if active_transform == "移動":
		return "position"
	if active_transform == "拡縮":
		return "scale"
	return "rotation"

func _drag_transform(point: Vector2) -> void:
	var delta: Vector2 = point - drag_start
	var raw_value: float = drag_value + delta.dot(drag_tangent) * drag_factor
	if mode == "IK" and selected_chain >= 0 and selected_chain < rig.chains.size():
		var goal: Node3D = rig.chains[selected_chain]["target"]
		var pos: Vector3 = goal.global_position
		pos[drag_axis] = clampf(raw_value, -100.0, 100.0)
		goal.global_position = pos
		motion.evaluate(motion.play_time)
		_update_gizmo()
		_note("IK目標　%s軸：%.2fm" % [["X", "Y", "Z"][drag_axis], pos[drag_axis]])
		return
	var field := _transform_field()
	if field == "scale":
		raw_value = clampf(raw_value, 0.02, 30.0)
	elif field == "position":
		raw_value = clampf(raw_value, -100.0, 100.0)
	else:
		raw_value = clampf(raw_value, -720.0, 720.0)
	motion.set_key_component(motion.play_time, selected_part, field, drag_axis, raw_value)
	_update_gizmo()
	var unit := "°" if field == "rotation" else ("m" if field == "position" else "倍")
	_note("%s　%s軸：%.2f%s（現在の時間にキーを保存）" % [active_transform, ["X", "Y", "Z"][drag_axis], raw_value, unit])

func _pick_from_screen(position: Vector2) -> void:
	if mode == "IK" and not rig.chains.is_empty():
		# Select target by projected screen-space hit radius (targets are visual gizmos).
		for i in range(rig.chains.size()):
			var target: Node3D = rig.chains[i]["target"]
			if camera.is_position_behind(target.global_position):
				continue
			var projected := camera.unproject_position(target.global_position)
			if projected.distance_to(position) < 36.0:
				selected_chain = i
				dragging_object = true
				motion.record_undo()
				_refresh_inspector()
				_update_gizmo()
				return
	var origin := camera.project_ray_origin(position)
	var direction := camera.project_ray_normal(position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 90.0, 2 | 4)
	var hit: Dictionary = stage.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider: CollisionObject3D = hit.get("collider")
	if collider == null:
		return
	if collider.has_meta("part_name"):
		selected_part = str(collider.get_meta("part_name"))
		_refresh_part_picker()
		_refresh_inspector()
		_refresh_timeline_view()
		_update_gizmo()
	elif collider.has_meta("test_index"):
		selected_test = int(collider.get_meta("test_index"))
		dragging_object = mode == "接触"
		if dragging_object: motion.record_undo()
		_refresh_inspector()
func _apply_test_transform(target: Node3D, property_name: String, axis: int, value: float) -> void:
	var transform_value: Vector3
	if property_name == "position":
		transform_value = target.position
	elif property_name == "rotation":
		transform_value = target.rotation_degrees
	else:
		transform_value = target.scale
	transform_value[axis] = value
	if property_name == "position":
		target.position = transform_value
	elif property_name == "rotation":
		target.rotation_degrees = transform_value
	else:
		target.scale = transform_value
