extends Control
class_name MotionTimelineView

signal seek_requested(time: float)

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

var clip_duration: float = 3.0
var play_time: float = 0.0
var selected_part: String = ""
var keys: Dictionary = {}
var scrubbing: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(0, HEADER_H + ROW_H * 3.0 + 7.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

func set_timeline(frames: Array, part: String, duration: float, at_time: float) -> void:
	selected_part = part
	clip_duration = maxf(0.01, duration)
	play_time = clampf(at_time, 0.0, clip_duration)
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
			var diamond := PackedVector2Array([
				center + Vector2(0, -5), center + Vector2(5, 0),
				center + Vector2(0, 5), center + Vector2(-5, 0)])
			draw_colored_polygon(diamond, KEY)
	var head: float = _time_to_x(play_time)
	draw_line(Vector2(head, 0), Vector2(head, size.y - 2), BLUE, 2.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(head - 6, 1), Vector2(head + 6, 1), Vector2(head, 10)]), BLUE)

func _jump_to_position(position: Vector2) -> void:
	if position.x < LABEL_WIDTH:
		return
	var requested: float = _x_to_time(position.x)
	# Similar to Blockbench: touching close to a keyframe seeks that exact key.
	if position.y >= HEADER_H:
		var row: int = clampi(int((position.y - HEADER_H) / ROW_H), 0, ROWS.size() - 1)
		for value in keys.get(ROWS[row], []):
			if absf(_time_to_x(float(value)) - position.x) < 9.0:
				requested = float(value)
				break
	seek_requested.emit(requested)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		scrubbing = event.pressed
		if event.pressed:
			_jump_to_position(event.position)
		accept_event()
	elif event is InputEventScreenDrag and scrubbing:
		_jump_to_position(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		scrubbing = event.pressed
		if event.pressed:
			_jump_to_position(event.position)
		accept_event()
	elif event is InputEventMouseMotion and scrubbing:
		_jump_to_position(event.position)
		accept_event()
