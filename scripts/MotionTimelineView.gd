extends Control
class_name MotionTimelineView

signal seek_requested(time: float)
signal key_move_requested(original_time: float, destination_time: float)
signal ik_range_requested(chain_index: int, start_time: float, finish_time: float)

const LABEL_WIDTH := 94.0
const HEADER_H := 27.0
const ROW_H := 30.0
const ROWS := ["rotation", "position", "scale"]
const ROW_LABELS := ["↻ 回転", "↔ 位置", "□ 拡縮"]
const BLUE := Color("55abed")
const FRAME := Color("333c4c")
const BACK := Color("191f29")
const DIVIDER := Color("3a4353")
const TEXT := Color("cbd4e1")
const KEY := Color("e2bb70")
const IK_BAR := Color("479cd8")
const IK_INACTIVE := Color("778393")
const IK_ROW_H := 43.0

var clip_duration: float = 3.0
var play_time: float = 0.0
var selected_part: String = ""
var keys: Dictionary = {}
var scrubbing: bool = false
var frame_times: Array[float] = []
var timeline_fps: int = 60
var press_position: Vector2 = Vector2.ZERO
var key_drag_start: float = -1.0
var key_drag_preview: float = -1.0
var dragging_key: bool = false
var mouse_suppression_until_ms: int = 0
var key_rows_visible: bool = true
var ik_visible: bool = false
var ik_index: int = -1
var ik_name: String = ""
var ik_enabled: bool = false
var collision_avoidance_lane: bool = false
var ik_start: float = 0.0
var ik_finish: float = 0.0
var ik_preview_start: float = 0.0
var ik_preview_finish: float = 0.0
var ik_drag_mode: String = ""
var ik_press_time: float = 0.0
var ik_original_start: float = 0.0
var ik_original_finish: float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(0, HEADER_H + ROW_H * 3.0 + 7.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

func set_timeline(frames: Array, part: String, duration: float, at_time: float, fps: int = 60) -> void:
	selected_part = part
	clip_duration = maxf(0.01, duration)
	play_time = clampf(at_time, 0.0, clip_duration)
	timeline_fps = maxi(1, fps)
	frame_times.clear()
	keys = {"rotation": [], "position": [], "scale": []}
	var last_values: Dictionary = {}
	for frame in frames:
		if not (frame is Dictionary):
			continue
		var poses: Dictionary = frame.get("poses", {})
		var pose: Dictionary = poses.get(part, {})
		if pose.is_empty():
			continue
		var t: float = float(frame.get("time", 0.0))
		frame_times.append(t)
		for channel in ROWS:
			var values: Array = pose.get(channel, [])
			if values.size() < 3:
				continue
			var changed := not last_values.has(channel)
			if not changed:
				var prior: Array = last_values[channel]
				for axis in range(3):
					if absf(float(values[axis]) - float(prior[axis])) > 0.0001:
						changed = true
						break
			if changed:
				keys[channel].append(t)
			last_values[channel] = values.duplicate()
	queue_redraw()

# Keep one selected IK lane on small portrait screens. In the IK workspace
# the large FK channel rows are hidden, leaving room for the 3D preview.
func set_ik_track(chains: Array, selected_index: int, show_keys: bool = true) -> void:
	key_rows_visible = show_keys
	ik_visible = not chains.is_empty() or not show_keys
	ik_index = clampi(selected_index, 0, chains.size() - 1) if not chains.is_empty() else -1
	ik_name = "IK未設定"
	ik_enabled = false
	collision_avoidance_lane = false
	ik_start = 0.0
	ik_finish = clip_duration
	if ik_index >= 0:
		var chain: Dictionary = chains[ik_index]
		ik_name = str(chain.get("name", "IK"))
		ik_enabled = bool(chain.get("enabled", false))
		collision_avoidance_lane = bool(chain.get("collision_avoid", chain.get("ground_follow", false)))
		ik_start = clampf(float(chain.get("start", 0.0)), 0.0, clip_duration)
		ik_finish = clampf(float(chain.get("finish", clip_duration)), ik_start, clip_duration)
	if ik_drag_mode == "":
		ik_preview_start = ik_start
		ik_preview_finish = ik_finish
	custom_minimum_size.y = HEADER_H + (float(ROWS.size()) * ROW_H if show_keys else 0.0) + (IK_ROW_H if ik_visible else 0.0) + 7.0
	queue_redraw()

func _ik_track_y() -> float:
	return HEADER_H + (float(ROWS.size()) * ROW_H if key_rows_visible else 0.0)

func _is_ik_row(point: Vector2) -> bool:
	return ik_visible and point.y >= _ik_track_y() and point.y < _ik_track_y() + IK_ROW_H

func set_playhead(value: float) -> void:
	play_time = clampf(value, 0.0, clip_duration)
	queue_redraw()

func _timeline_width() -> float:
	return maxf(24.0, size.x - LABEL_WIDTH - 12.0)

func _time_to_x(t: float) -> float:
	return LABEL_WIDTH + _timeline_width() * clampf(t / clip_duration, 0.0, 1.0)

func _x_to_time(x: float) -> float:
	return clip_duration * clampf((x - LABEL_WIDTH) / _timeline_width(), 0.0, 1.0)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACK)
	draw_rect(Rect2(Vector2(0, 0), Vector2(LABEL_WIDTH, size.y)), Color("252d3a"))
	var font: Font = get_theme_default_font()
	var font_size: int = 12
	draw_string(font, Vector2(8, 18), "タイムライン", HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH - 13, font_size, TEXT)
	var interval: float = 0.25
	if clip_duration > 7.5:
		interval = 1.0
	if clip_duration > 30.0:
		interval = 5.0
	for index in range(int(ceil(clip_duration / interval)) + 1):
		var t: float = float(index) * interval
		if t > clip_duration + 0.0001:
			break
		var x: float = _time_to_x(t)
		draw_line(Vector2(x, HEADER_H - 8), Vector2(x, size.y - 2), DIVIDER, 1.0)
		if index % 2 == 0:
			draw_string(font, Vector2(x + 2, 17), "%.1f" % t, HORIZONTAL_ALIGNMENT_LEFT, 39, 11, TEXT)
	if key_rows_visible:
		for row in range(ROWS.size()):
			var y: float = HEADER_H + float(row) * ROW_H
			var backdrop: Color = Color("202733") if row % 2 == 0 else Color("1b222d")
			draw_rect(Rect2(Vector2(LABEL_WIDTH, y), Vector2(_timeline_width(), ROW_H)), backdrop)
			draw_rect(Rect2(Vector2(0, y), Vector2(LABEL_WIDTH, ROW_H)), Color("2a3341"))
			draw_line(Vector2(0, y), Vector2(size.x, y), DIVIDER, 1.0)
			draw_string(font, Vector2(11, y + 20), ROW_LABELS[row], HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH - 16, font_size, TEXT)
			var current: Array = keys.get(ROWS[row], [])
			var prior_drawn: float = -100.0
			for t in current:
				var x: float = _time_to_x(float(t))
				if x - prior_drawn < 3.0:
					continue
				prior_drawn = x
				var center := Vector2(x, y + ROW_H * 0.5)
				var color: Color = Color("ffde88") if absf(play_time - float(t)) < 0.001 else KEY
				var diamond := PackedVector2Array([
					center + Vector2(0, -7), center + Vector2(7, 0),
					center + Vector2(0, 7), center + Vector2(-7, 0)])
				draw_colored_polygon(diamond, color)
				if absf(play_time - float(t)) < 0.001:
					draw_arc(center, 11.0, 0.0, TAU, 20, BLUE, 1.6)
	if ik_visible:
		var y: float = _ik_track_y()
		draw_rect(Rect2(Vector2(LABEL_WIDTH, y), Vector2(_timeline_width(), IK_ROW_H)), Color("182b40"))
		draw_rect(Rect2(Vector2(0, y), Vector2(LABEL_WIDTH, IK_ROW_H)), Color("273a50"))
		draw_line(Vector2(0, y), Vector2(size.x, y), DIVIDER, 1.0)
		draw_string(font, Vector2(9, y + 18), "接触回避" if collision_avoidance_lane else "IK 適用", HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH - 12, 12, Color("9acdf5"))
		if ik_index >= 0:
			var label: String = ik_name
			if label.length() > 9:
				label = label.substr(0, 8) + "…"
			draw_string(font, Vector2(9, y + 34), label, HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH - 12, 11, TEXT)
			var x0: float = _time_to_x(ik_preview_start)
			var x1: float = _time_to_x(ik_preview_finish)
			var bar_color: Color = IK_BAR if ik_enabled else IK_INACTIVE
			var bar_y: float = y + 11.0
			var bar_h: float = 25.0
			draw_rect(Rect2(Vector2(x0, bar_y), Vector2(maxf(2.0, x1 - x0), bar_h)), bar_color)
			draw_rect(Rect2(Vector2(x0, bar_y), Vector2(maxf(2.0, x1 - x0), bar_h)), Color("c1e7ff") if ik_enabled else Color("aab4bd"), false, 1.2)
			for handle_x in [x0, x1]:
				draw_rect(Rect2(Vector2(handle_x - 4.0, bar_y - 3.0), Vector2(8, bar_h + 6.0)), Color("d8edff") if ik_enabled else Color("c5cad2"))
			var time_text: String = "%.2f–%.2f秒" % [ik_preview_start, ik_preview_finish]
			draw_string(font, Vector2(clampf((x0 + x1) * 0.5 - 31.0, LABEL_WIDTH + 2.0, size.x - 85.0), y + 28.0),
				time_text, HORIZONTAL_ALIGNMENT_LEFT, 85, 11, Color("ffffff"))
			if not ik_enabled:
				draw_string(font, Vector2(size.x - 35.0, y + 10.0), "OFF", HORIZONTAL_ALIGNMENT_LEFT, 34, 10, Color("b8bfce"))
		else:
			draw_string(font, Vector2(LABEL_WIDTH + 10, y + 27), "IK設定からチェーンを追加", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT)
	if dragging_key and key_drag_start >= 0.0:
		var ghost_x: float = _time_to_x(key_drag_preview)
		draw_line(Vector2(ghost_x, 0), Vector2(ghost_x, size.y - 2), Color("ffda74", 0.85), 2.0)
		draw_string(font, Vector2(clampf(ghost_x - 20.0, LABEL_WIDTH, size.x - 48.0), 24),
			"%.2fs" % key_drag_preview, HORIZONTAL_ALIGNMENT_LEFT, 45, 12, Color("ffe3aa"))
	var head: float = _time_to_x(play_time)
	draw_line(Vector2(head, 0), Vector2(head, size.y - 2), BLUE, 2.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(head - 6, 1), Vector2(head + 6, 1), Vector2(head, 10)]), BLUE)

func _find_key_under_touch(point: Vector2) -> float:
	if not key_rows_visible or point.x < LABEL_WIDTH - 5.0 or point.y < HEADER_H or point.y >= _ik_track_y():
		return -1.0
	var row: int = clampi(int((point.y - HEADER_H) / ROW_H), 0, ROWS.size() - 1)
	var best: float = 17.0
	var found: float = -1.0
	for time in keys.get(ROWS[row], []):
		var t: float = float(time)
		if t <= 0.0005 or t >= clip_duration - 0.0005:
			continue
		var distance: float = absf(_time_to_x(t) - point.x)
		if distance < best:
			best = distance
			found = t
	return found

func _snap_time(value: float) -> float:
	return clampf(snappedf(value, 1.0 / float(timeline_fps)), 0.0, clip_duration)

func _jump_to_position(position: Vector2) -> void:
	if position.x < LABEL_WIDTH:
		return
	var requested: float = _x_to_time(position.x)
	if key_rows_visible and position.y >= HEADER_H and not _is_ik_row(position):
		var row: int = clampi(int((position.y - HEADER_H) / ROW_H), 0, ROWS.size() - 1)
		for value in keys.get(ROWS[row], []):
			if absf(_time_to_x(float(value)) - position.x) < 17.0:
				requested = float(value)
				break
	seek_requested.emit(requested)

# 22px handle hit boxes make edge retiming usable with fingers.
# Whole-bar dragging preserves the interval duration and clamps to clip bounds.
func _press(point: Vector2) -> void:
	scrubbing = true
	press_position = point
	key_drag_start = -1.0
	key_drag_preview = -1.0
	dragging_key = false
	ik_drag_mode = ""
	if _is_ik_row(point) and ik_index >= 0 and point.x >= LABEL_WIDTH:
		var x0: float = _time_to_x(ik_start)
		var x1: float = _time_to_x(ik_finish)
		var edge_distance: float = 22.0
		var d0: float = absf(point.x - x0)
		var d1: float = absf(point.x - x1)
		if d0 <= edge_distance and d0 <= d1:
			ik_drag_mode = "start"
		elif d1 <= edge_distance:
			ik_drag_mode = "finish"
		elif point.x >= x0 and point.x <= x1:
			ik_drag_mode = "move"
		ik_press_time = _x_to_time(point.x)
		ik_original_start = ik_start
		ik_original_finish = ik_finish
		ik_preview_start = ik_start
		ik_preview_finish = ik_finish
	else:
		key_drag_start = _find_key_under_touch(point)
		key_drag_preview = key_drag_start
	_jump_to_position(point)

func _move(point: Vector2) -> void:
	if not scrubbing:
		return
	if ik_drag_mode != "":
		var t: float = _snap_time(_x_to_time(point.x))
		var frame_step: float = 1.0 / float(timeline_fps)
		var span: float = ik_original_finish - ik_original_start
		match ik_drag_mode:
			"start":
				ik_preview_start = clampf(t, 0.0, maxf(0.0, ik_original_finish - frame_step))
				ik_preview_finish = ik_original_finish
			"finish":
				ik_preview_start = ik_original_start
				ik_preview_finish = clampf(t, minf(clip_duration, ik_original_start + frame_step), clip_duration)
			"move":
				var shift: float = t - _snap_time(ik_press_time)
				ik_preview_start = clampf(_snap_time(ik_original_start + shift), 0.0, maxf(0.0, clip_duration - span))
				ik_preview_finish = ik_preview_start + span
		queue_redraw()
		return
	if key_drag_start >= 0.0 and absf(point.x - press_position.x) >= 12.0:
		dragging_key = true
	if dragging_key:
		key_drag_preview = _snap_time(_x_to_time(point.x))
		seek_requested.emit(key_drag_preview)
		queue_redraw()
	else:
		_jump_to_position(point)

func _release() -> void:
	if not scrubbing:
		return
	scrubbing = false
	if ik_drag_mode != "":
		var changed: bool = absf(ik_preview_start - ik_original_start) > 0.0005 or absf(ik_preview_finish - ik_original_finish) > 0.0005
		if changed:
			ik_range_requested.emit(ik_index, ik_preview_start, ik_preview_finish)
		ik_drag_mode = ""
	elif dragging_key and key_drag_start >= 0.0 and absf(key_drag_preview - key_drag_start) > 0.0005:
		key_move_requested.emit(key_drag_start, key_drag_preview)
	dragging_key = false
	key_drag_start = -1.0
	key_drag_preview = -1.0
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		mouse_suppression_until_ms = Time.get_ticks_msec() + 180
		if event.pressed:
			_press(event.position)
		else:
			_release()
		accept_event()
	elif event is InputEventScreenDrag:
		mouse_suppression_until_ms = Time.get_ticks_msec() + 180
		_move(event.position)
		accept_event()
	elif Time.get_ticks_msec() >= mouse_suppression_until_ms:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press(event.position)
			else:
				_release()
			accept_event()
		elif event is InputEventMouseMotion and scrubbing:
			_move(event.position)
			accept_event()
