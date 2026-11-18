extends VBoxContainer
class_name MotionOutliner

signal part_selected(name: String)

var part_tree: Tree
var filter_box: LineEdit
var counter: Label
var rig: MotionRig
var selected_part: String = ""
var item_lookup: Dictionary = {}
var children_map: Dictionary = {}
var key_to_label: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override("separation", 5)
	var head := HBoxContainer.new()
	add_child(head)
	var title := Label.new()
	title.text = "OUTLINER ・ パーツ階層"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 15)
	head.add_child(title)
	counter = Label.new()
	counter.add_theme_font_size_override("font_size", 12)
	head.add_child(counter)
	filter_box = LineEdit.new()
	filter_box.placeholder_text = "パーツ名で検索"
	filter_box.custom_minimum_size.y = 42
	filter_box.text_changed.connect(func(_s: String): _rebuild())
	add_child(filter_box)
	part_tree = Tree.new()
	part_tree.columns = 1
	part_tree.hide_root = true
	part_tree.select_mode = Tree.SELECT_SINGLE
	part_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	part_tree.custom_minimum_size.y = 186
	part_tree.item_selected.connect(_on_selection)
	add_child(part_tree)

func set_model(source: MotionRig, selection: String) -> void:
	rig = source
	selected_part = selection
	_rebuild()

func set_selected(selection: String) -> void:
	selected_part = selection
	if item_lookup.has(selection):
		var item: TreeItem = item_lookup[selection]
		item.select(0)

func _build_hierarchy() -> void:
	children_map.clear()
	key_to_label.clear()
	if rig == null:
		return
	for label in rig.parts.keys():
		var joint: Node3D = rig.parts[label]
		key_to_label[joint.get_instance_id()] = str(label)
	children_map[""] = []
	for label in rig.parts.keys():
		var joint: Node3D = rig.parts[label]
		var p: Node = joint.get_parent()
		while p != null and not key_to_label.has(p.get_instance_id()):
			p = p.get_parent()
		var parent_label: String = str(key_to_label.get(p.get_instance_id(), "")) if p != null else ""
		if not children_map.has(parent_label):
			children_map[parent_label] = []
		children_map[parent_label].append(str(label))
		if not children_map.has(str(label)):
			children_map[str(label)] = []

func _is_visible_branch(name: String, needle: String, visited: Dictionary) -> bool:
	if needle.is_empty() or name.to_lower().contains(needle):
		return true
	if visited.has(name):
		return false
	visited[name] = true
	for child in children_map.get(name, []):
		if _is_visible_branch(str(child), needle, visited):
			return true
	return false

func _append_part(name: String, parent: TreeItem, needle: String, depth: int) -> void:
	if depth > 60:
		return
	if not _is_visible_branch(name, needle, {}):
		return
	var item: TreeItem = part_tree.create_item(parent)
	item_lookup[name] = item
	item.set_metadata(0, name)
	var child_count: int = children_map.get(name, []).size()
	item.set_text(0, ("▸ " if child_count > 0 else "◇ ") + name)
	item.set_custom_color(0, Color("6bdcc7") if name == selected_part else Color("c9d6e3"))
	item.set_selectable(0, true)
	if name == selected_part:
		item.select(0)
	for child in children_map.get(name, []):
		_append_part(str(child), item, needle, depth + 1)

func _rebuild() -> void:
	if part_tree == null or rig == null:
		return
	_build_hierarchy()
	part_tree.clear()
	item_lookup.clear()
	var root_item := part_tree.create_item()
	var needle := filter_box.text.strip_edges().to_lower()
	for label in children_map.get("", []):
		_append_part(str(label), root_item, needle, 0)
	counter.text = str(rig.parts.size()) + "部位"

func _on_selection() -> void:
	var item: TreeItem = part_tree.get_selected()
	if item == null:
		return
	var label: String = str(item.get_metadata(0))
	if label == "":
		return
	selected_part = label
	part_selected.emit(label)
