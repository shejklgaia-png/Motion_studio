extends Control

const MODES := ["モーション", "IK", "制約", "接触", "診断", "書き出し"]
var rig: MotionRig
var motion: MotionEngine
var stage: Node3D
var viewport: SubViewport
var preview_container: SubViewportContainer
var camera: Camera3D
var floor_area: StaticBody3D
var inspector: VBoxContainer
var key_row: HBoxContainer
var seek: HSlider
var time_label: Label
var message_label: Label
var part_picker: OptionButton
var mode_picker: OptionButton
var animation_picker: OptionButton
var camera_focus: Vector3 = Vector3(0, 1.05, 0)
var play_button: Button
var help_popup: AcceptDialog
var selected_part: String = "胴体"
var selected_chain: int = 0
var selected_test: int = -1
var mode: String = "モーション"
var playing: bool = false
var playback_speed: float = 1.0
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
	_note("まずは ▶ 再生 → 脚をタップ → 下の数値を変更、の順に試してください。")
	if not FileAccess.file_exists("user://motion_studio_guide_seen.txt"):
		call_deferred("_show_help")

func _make_button(label: String, callback: Callable, owner: Node) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 40)
	button.pressed.connect(callback)
	owner.add_child(button)
	return button

func _add_text(parent: Node, content: String, section: bool = false) -> Label:
	var label := Label.new()
	label.text = content
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if section:
		label.add_theme_font_size_override("font_size", 19)
	parent.add_child(label)
	return label

func _row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	return row

func _build_interface() -> void:
	var back := ColorRect.new()
	back.color = Color("17212e")
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 5)
	add_child(layout)
	var header := _row(layout)
	var title := _add_text(header, "MOTION STUDIO", true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_picker = OptionButton.new()
	for item in MODES:
		mode_picker.add_item(item)
	mode_picker.item_selected.connect(func(index: int):
		mode = MODES[index]
		_refresh_inspector())
	header.add_child(mode_picker)
	var help_button := _make_button("使い方", _show_help, header)
	help_button.tooltip_text = "最初に試す操作や各モードの説明"
	var buttons := _row(layout)
	for entry in [
		["BB読込", "import"], ["保存", "save"], ["開く", "open"],
		["出力", "export"], ["取消", "undo"], ["やり直し", "redo"]]:
		var button_name: String = entry[1]
		var label: String = entry[0]
		var button := _make_button(label, func(): _toolbar_action(button_name), buttons)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_container = SubViewportContainer.new()
	preview_container.stretch = true
	preview_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_container.custom_minimum_size = Vector2(0, 250)
	layout.add_child(preview_container)
	preview_container.gui_input.connect(_viewport_input)
	viewport = SubViewport.new()
	viewport.size = Vector2i(480, 520)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	preview_container.add_child(viewport)
	var guide := _add_text(layout, "基本操作：①再生 ②モデルの脚をタップ ③下の位置・回転を調整。背景ドラッグで視点を回転")
	guide.add_theme_font_size_override("font_size", 12)
	var transport := _row(layout)
	play_button = _make_button("▶ 再生", _toggle_playback, transport)
	_make_button("◀", func(): _seek_by(-1.0 / float(motion.fps)), transport)
	_make_button("▶|", func(): _seek_by(1.0 / float(motion.fps)), transport)
	_make_button("＋キー", _insert_key, transport)
	_make_button("－キー", _remove_key, transport)
	time_label = _add_text(transport, "0.00秒")
	time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seek = HSlider.new()
	seek.min_value = 0.0
	seek.max_value = 3.0
	seek.step = 0.001
	seek.custom_minimum_size.y = 30
	seek.value_changed.connect(_seek_to)
	layout.add_child(seek)
	var key_scroll := ScrollContainer.new()
	key_scroll.custom_minimum_size.y = 38
	key_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	key_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(key_scroll)
	key_row = _row(key_scroll)
	var select_line := _row(layout)
	_add_text(select_line, "編集部位：")
	part_picker = OptionButton.new()
	part_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	part_picker.item_selected.connect(func(index: int):
		selected_part = part_picker.get_item_text(index)
		_refresh_inspector())
	select_line.add_child(part_picker)
	var animation_line := _row(layout)
	_add_text(animation_line, "読込モーション：")
	animation_picker = OptionButton.new()
	animation_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	animation_picker.disabled = true
	animation_picker.add_item("モデル読込後に選択")
	animation_picker.item_selected.connect(func(index: int):
		if index == 0:
			motion.setup(rig)
			_after_model_change("基本姿勢を表示しています。")
		else:
			var result: String = motion.load_bb_animation(index - 1)
			_after_model_change(result))
	animation_line.add_child(animation_picker)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 225
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	inspector = VBoxContainer.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.add_theme_constant_override("separation", 7)
	scroll.add_child(inspector)
	message_label = _add_text(layout, "準備中")
	message_label.add_theme_font_size_override("font_size", 13)
	message_label.custom_minimum_size.y = 20

func _show_help() -> void:
	if help_popup == null:
		help_popup = AcceptDialog.new()
		help_popup.title = "Motion Studio かんたん操作ガイド"
		help_popup.dialog_text = "最初は次の3つだけ試してください。\n\n①「BB読込」で .bbmodel を選択します（サンプルでも練習できます）。\n②「読込モーション」から動きを選び、「▶ 再生」を押します。\n③ モデルの脚などをタップして、下の値を変更します。\n\nキーフレームを増やすには、横長の時間スライダーを動かして「＋キー」を押します。\n\n右上の「モーション」をタップすると、作業モードが切り替わります。\n・モーション：部位の動きを編集\n・IK：足先などの目標位置を設定\n・制約：関節の角度・移動範囲を制限\n・接触：床や障害物との接触を確認\n・診断：不自然な動きを確認\n・書き出し：Godot向けに保存\n\n分からなくなったら右上の「使い方」を押してください。"
		help_popup.ok_button_text = "操作してみる"
		add_child(help_popup)
	help_popup.popup_centered_ratio(0.9)
	var file := FileAccess.open("user://motion_studio_guide_seen.txt", FileAccess.WRITE)
	if file:
		file.store_string("seen")

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

func _update_camera() -> void:
	var center := camera_focus
	camera.position = center + Vector3(
		sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch)) * camera_distance
	camera.look_at(center, Vector3.UP)

func _note(message: String) -> void:
	message_label.text = message

func _toolbar_action(action: String) -> void:
	match action:
		"import": _file_dialog("import")
		"save": _note(motion.save_project("user://motion_studio.motion.json"))
		"open": _file_dialog("open")
		"export": _note(motion.export_animation_tres("user://motion_animation.tres"))
		"undo":
			if motion.undo(): _after_model_change("操作を取り消しました")
		"redo":
			if motion.redo(): _after_model_change("操作をやり直しました")

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
			"export": _note(motion.export_animation_tres(path))
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

func _refresh_key_buttons() -> void:
	for child in key_row.get_children():
		child.queue_free()
	for frame in motion.frames:
		var t: float = float(frame["time"])
		_make_button("◆ %.2f" % t, func(): _seek_to(t), key_row)

func _update_timeline() -> void:
	seek.set_value_no_signal(motion.play_time)
	seek.max_value = motion.duration
	time_label.text = "%.2f秒" % motion.play_time

func _seek_to(value: float) -> void:
	motion.evaluate(value)
	_update_timeline()
	if show_original:
		_show_raw_pose()

func _seek_by(seconds: float) -> void:
	playing = false
	play_button.text = "▶ 再生"
	_seek_to(motion.play_time + seconds)

func _toggle_playback() -> void:
	playing = not playing
	play_button.text = "Ⅱ 停止" if playing else "▶ 再生"

func _insert_key() -> void:
	motion.record_undo()
	motion.capture_key(motion.play_time)
	_refresh_key_buttons()
	_note("現在の姿勢をキーフレームに保存しました")

func _remove_key() -> void:
	motion.record_undo()
	motion.delete_key(motion.play_time)
	_refresh_key_buttons()

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
		"モーション": "① 再生または時間バーを動かす → ② 脚を選ぶ → ③ 数値を変更 → ④ ＋キーで保存",
		"IK": "脚の先端を目標に合わせる機能です。目標位置や計算方法を設定します。",
		"制約": "関節の曲がる範囲や、位置・伸縮の限界を設定します。",
		"接触": "床やテスト用の箱・球を置いて、足先との接触を確認します。",
		"診断": "関節・接地・IKの異常を確認します。",
		"書き出し": "完成した動きをGodotで使うために出力します。"
	}
	_add_text(inspector, str(hints.get(mode, "")))
	match mode:
		"モーション": _inspector_motion()
		"IK": _inspector_ik()
		"制約": _inspector_constraints()
		"接触": _inspector_contacts()
		"診断": _inspector_diagnostics()
		"書き出し": _inspector_export()

func _vector_fields(title: String, value: Vector3, low: float, high: float, step: float, changed: Callable) -> void:
	_add_text(inspector, title)
	var line := _row(inspector)
	for axis in range(3):
		_add_text(line, ["X", "Y", "Z"][axis])
		var spin := SpinBox.new()
		spin.min_value = low
		spin.max_value = high
		spin.step = step
		spin.allow_greater = false
		spin.allow_lesser = false
		spin.value = value[axis]
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.value_changed.connect(func(v: float): changed.call(axis, v))
		line.add_child(spin)

func _number_field(label: String, initial: float, low: float, high: float, step: float, changed: Callable) -> void:
	var line := _row(inspector)
	var text_label := _add_text(line, label)
	text_label.custom_minimum_size.x = 120
	var number := SpinBox.new()
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
	check.toggled.connect(changed)
	inspector.add_child(check)

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
	var line := _row(inspector)
	_make_button("キーフレームを登録", _insert_key, line)
	_make_button("選択キーを削除", _remove_key, line)
	_number_field("再生速度", playback_speed, 0.1, 3.0, 0.1, func(v: float): playback_speed = v)
	_number_field("長さ (秒)", motion.duration, 0.5, 60.0, 0.5, func(v: float):
		motion.duration = v
		_update_timeline())
	_add_text(inspector, "変更した値は、現在の再生位置にキーフレームとして保存されます。")

func _set_chain_prop(key: String, value: Variant) -> void:
	if selected_chain < 0 or selected_chain >= rig.chains.size():
		return
	motion.record_undo()
	rig.chains[selected_chain][key] = value
	motion.evaluate(motion.play_time)

func _inspector_ik() -> void:
	_add_text(inspector, "IKチェーンと目標点", true)
	var row := _row(inspector)
	var chain_select := OptionButton.new()
	chain_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for chain in rig.chains:
		chain_select.add_item(str(chain["name"]))
	if not rig.chains.is_empty():
		selected_chain = clampi(selected_chain, 0, rig.chains.size() - 1)
		chain_select.select(selected_chain)
	chain_select.item_selected.connect(func(i: int):
		selected_chain = i
		_refresh_inspector())
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
	_number_field("IK強度", chain["weight"], 0.0, 1.0, 0.05, func(v: float): _set_chain_prop("weight", v))
	_number_field("開始 (秒)", chain["start"], 0.0, 60.0, 0.05, func(v: float): _set_chain_prop("start", v))
	_number_field("終了 (秒)", chain["finish"], 0.0, 60.0, 0.05, func(v: float): _set_chain_prop("finish", v))
	_add_text(inspector, "画面上の緑の球をドラッグすると、IK目標を直接動かせます。")

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

func _inspector_contacts() -> void:
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
		_refresh_inspector(), top)
	if not rig.test_objects.is_empty():
		var choices := OptionButton.new()
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
	_add_text(inspector, "保存・読み込み・Godotへ出力", true)
	_make_button("プロジェクトをアプリ内に保存", func(): _note(motion.save_project("user://motion_studio.motion.json")), inspector)
	_make_button("プロジェクトを別名で保存", func(): _file_dialog("save_as"), inspector)
	_make_button("前回の自動保存を復元", func():
		var result := motion.load_project("user://autosave.motion.json")
		_after_model_change(result), inspector)
	_make_button("Godotアニメーション(.tres)を出力", func():
		_note(motion.export_animation_tres("user://motion_animation.tres")), inspector)
	_make_button("Godotアニメーションを別名で出力", func(): _file_dialog("export"), inspector)
	_add_text(inspector, "エクスポート時には現在のIK・制約結果をフレームごとに焼き込みます。")
	_add_text(inspector, "ユーザーデータ保存場所：" + OS.get_user_data_dir())
	_add_text(inspector, "Androidでは外部ファイルへのアクセスや保存先の選択が端末・権限に依存します。")

func _plane_position(screen_pos: Vector2, height: float) -> Vector3:
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return Vector3.ZERO
	var factor := (height - origin.y) / dir.y
	return origin + dir * factor

func _viewport_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_distance = clampf(camera_distance - 0.5, 2.5, 24.0)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_distance = clampf(camera_distance + 0.5, 2.5, 24.0)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			pointer_down = event.pressed
			if pointer_down:
				_pick_from_screen(event.position)
			else:
				dragging_object = false
	elif event is InputEventMouseMotion and pointer_down:
		if dragging_object and mode == "IK" and selected_chain >= 0 and selected_chain < rig.chains.size():
			var target: Node3D = rig.chains[selected_chain]["target"]
			var p := _plane_position(event.position, target.global_position.y)
			target.global_position = p
			motion.evaluate(motion.play_time)
		elif dragging_object and mode == "接触" and selected_test >= 0 and selected_test < rig.test_objects.size():
			var obstacle: Node3D = rig.test_objects[selected_test]["node"]
			var p := _plane_position(event.position, obstacle.position.y)
			obstacle.position = p
		else:
			camera_yaw -= event.relative.x * 0.008
			camera_pitch = clampf(camera_pitch + event.relative.y * 0.007, -0.2, 1.3)
			_update_camera()
	elif event is InputEventMagnifyGesture:
		camera_distance = clampf(camera_distance / event.factor, 2.5, 24.0)
		_update_camera()

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
