extends Node3D
class_name MotionRig

# This class stores editable scene joints separately from visualization and test bodies.
var parts: Dictionary = {}                 # Japanese joint name -> Node3D
var rest: Dictionary = {}                  # name -> numeric pose
var chains: Array = []                    # root/mid/end/target/method settings
var test_objects: Array = []
var imported_source: String = "sample"
var bb_legacy_axes: bool = false
var bb_animations: Array = []
var bb_uuid_to_name: Dictionary = {}
var bb_import_warnings: Array[String] = []
var _target_group: Node3D
var model_root: Node3D
var _unique_names: Dictionary = {}

func _ready() -> void:
	_target_group = Node3D.new()
	_target_group.name = "IKTargets"
	add_child(_target_group)

func _clear_model() -> void:
	for child in get_children():
		if child != _target_group:
			remove_child(child)
			child.queue_free()
	for target in _target_group.get_children():
		target.queue_free()
	parts.clear()
	rest.clear()
	chains.clear()
	test_objects.clear()
	_unique_names.clear()
	bb_legacy_axes = false
	bb_animations.clear()
	bb_uuid_to_name.clear()
	bb_import_warnings.clear()

func _color(rgb: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = rgb
	material.metallic = 0.0
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return material

func _register_part(label: String, node: Node3D) -> String:
	var safe := label if label != "" else "部位"
	var stem := safe
	var i := 2
	while parts.has(safe):
		safe = stem + "_" + str(i)
		i += 1
	node.name = safe
	parts[safe] = node
	node.set_meta("part_name", safe)
	return safe

func _box(parent: Node3D, dimensions: Vector3, offset: Vector3, color: Color, pick_name: String) -> void:
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	visual.mesh = mesh
	visual.material_override = _color(color)
	visual.position = offset
	parent.add_child(visual)
	if pick_name != "":
		var collider := StaticBody3D.new()
		collider.collision_layer = 2
		collider.collision_mask = 0
		collider.set_meta("part_name", pick_name)
		collider.position = offset
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = dimensions
		cs.shape = shape
		collider.add_child(cs)
		parent.add_child(collider)

func create_sample() -> void:
	_clear_model()
	imported_source = "sample"
	model_root = Node3D.new()
	model_root.name = "SampleModel"
	add_child(model_root)
	var body := Node3D.new()
	body.position = Vector3(0.0, 2.12, 0.0)
	model_root.add_child(body)
	_register_part("胴体", body)
	_box(body, Vector3(2.25, 0.52, 1.55), Vector3.ZERO, Color("7997b9"), "胴体")
	for side in [-1, 1]:
		for depth in [-1, 1]:
			var s: String = "左" if side < 0 else "右"
			var d: String = "前" if depth < 0 else "後"
			var prefix := d + s
			var upper := Node3D.new()
			body.add_child(upper)
			upper.position = Vector3(0.95 * float(side), -0.19, 0.56 * float(depth))
			_register_part(prefix + "上肢", upper)
			_box(upper, Vector3(0.29, 0.92, 0.30), Vector3(0, -0.46, 0), Color("c58b60"), prefix + "上肢")
			var lower := Node3D.new()
			upper.add_child(lower)
			lower.position = Vector3(0, -0.92, 0)
			_register_part(prefix + "下肢", lower)
			_box(lower, Vector3(0.21, 0.78, 0.23), Vector3(0, -0.39, 0), Color("aebfc9"), prefix + "下肢")
			var foot := Node3D.new()
			lower.add_child(foot)
			foot.position = Vector3(0, -0.78, 0)
			_register_part(prefix + "足先", foot)
			_box(foot, Vector3(0.44, 0.23, 0.49), Vector3(0, -0.13, -0.07), Color("d8b579"), prefix + "足先")
			var sensor := Area3D.new()
			sensor.name = "接触センサー"
			sensor.collision_layer = 0
			sensor.collision_mask = 1 | 4
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(0.43, 0.08, 0.48)
			cs.shape = shape
			sensor.position = Vector3(0, -0.25, -0.07)
			sensor.add_child(cs)
			foot.add_child(sensor)
			var target := foot.to_global(Vector3(0, -0.25, -0.07))
			add_chain(prefix, prefix + "上肢", prefix + "下肢", prefix + "足先", Vector3(0, -0.25, -0.07), target)
	store_rest()

func add_chain(label: String, root_name: String, mid_name: String, end_name: String, tip: Vector3 = Vector3.ZERO, at_position: Vector3 = Vector3.ZERO) -> void:
	if not parts.has(root_name) or not parts.has(mid_name) or not parts.has(end_name):
		return
	var target := Node3D.new()
	target.name = "Target_" + str(chains.size())
	_target_group.add_child(target)
	target.global_position = at_position
	var ball := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.105
	mesh.height = 0.21
	ball.mesh = mesh
	ball.material_override = _color(Color("49e2c1"))
	target.add_child(ball)
	chains.append({"name": label, "root": root_name, "mid": mid_name, "end": end_name,
		"tip": [tip.x, tip.y, tip.z], "target": target,
		"enabled": false, "weight": 1.0, "method": "CCD",
		"start": 0.0, "finish": 3.0, "pole": [0.0, 0.0, 1.0],
		# Time-gated environment avoidance. The contact target is not pinned:
		# the authored animation is kept until geometry would intersect.
		"collision_avoid": false, "collision_floor": true,
		"collision_objects": false, "collision_object_index": -1,
		"collision_height": 0.0, "collision_margin": 0.005,
		"collision_include_mid": true})

func store_rest() -> void:
	rest.clear()
	for label in parts.keys():
		rest[label] = pose_of(parts[label])

static func vec3_array(vector: Vector3) -> Array:
	return [vector.x, vector.y, vector.z]

static func from_array(a: Array) -> Vector3:
	if a.size() < 3:
		return Vector3.ZERO
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

static func pose_of(node: Node3D) -> Dictionary:
	return {"position": vec3_array(node.position), "rotation": vec3_array(node.rotation_degrees), "scale": vec3_array(node.scale)}

func set_pose(name: String, pose: Dictionary) -> void:
	if not parts.has(name):
		return
	var node: Node3D = parts[name]
	node.position = from_array(pose.get("position", [0, 0, 0]))
	node.rotation_degrees = from_array(pose.get("rotation", [0, 0, 0]))
	node.scale = from_array(pose.get("scale", [1, 1, 1]))

func add_test_object(kind: String, at_position: Vector3) -> int:
	var obstacle := StaticBody3D.new()
	obstacle.name = "テスト物体" + str(test_objects.size() + 1)
	obstacle.collision_layer = 4
	obstacle.collision_mask = 0
	obstacle.position = at_position
	obstacle.set_meta("test_index", test_objects.size())
	var mi := MeshInstance3D.new()
	var cs := CollisionShape3D.new()
	match kind:
		"球":
			var ball := SphereMesh.new()
			ball.radius = 0.45
			ball.height = 0.9
			mi.mesh = ball
			var sphere := SphereShape3D.new()
			sphere.radius = 0.45
			cs.shape = sphere
		"カプセル":
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.37
			capsule.height = 1.3
			mi.mesh = capsule
			var c_shape := CapsuleShape3D.new()
			c_shape.radius = 0.37
			c_shape.height = 1.3
			cs.shape = c_shape
		_:
			var cube := BoxMesh.new()
			cube.size = Vector3(0.9, 0.9, 0.9)
			mi.mesh = cube
			var box_shape := BoxShape3D.new()
			box_shape.size = Vector3(0.9, 0.9, 0.9)
			cs.shape = box_shape
	mi.material_override = _color(Color("49b9dd"))
	obstacle.add_child(mi)
	obstacle.add_child(cs)
	add_child(obstacle)
	test_objects.append({"kind": kind, "node": obstacle})
	return test_objects.size() - 1

func clear_test_objects() -> void:
	for entry in test_objects:
		var node: Node3D = entry["node"]
		remove_child(node)
		node.queue_free()
	test_objects.clear()

func get_contact_report() -> Array:
	var notices: Array = []
	for name in parts.keys():
		if not name.ends_with("足先"):
			continue
		var foot: Node3D = parts[name]
		var sensor: Area3D = foot.get_node_or_null("接触センサー")
		if sensor == null:
			continue
		var floor_gap: float = foot.to_global(Vector3(0, -0.27, -0.07)).y
		if floor_gap < -0.06:
			notices.append(name + "：床へ %.2fm めり込み" % absf(floor_gap))
		elif floor_gap > 0.18:
			notices.append(name + "：床から %.2fm 浮上" % floor_gap)
		for hit in sensor.get_overlapping_bodies():
			if hit is StaticBody3D:
				notices.append(name + " ↔ " + str(hit.name) + "：接触")
	return notices

# Supports free meshes and cubes, including Blockbench 5 separate group definitions.
func load_bbmodel(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "選択したファイルを開けません: " + str(FileAccess.get_open_error())
	var json := JSON.new()
	var result := json.parse(file.get_as_text())
	if result != OK or not (json.data is Dictionary):
		return "JSONの読み込みに失敗: " + json.get_error_message()
	var data: Dictionary = json.data
	if not data.has("elements"):
		return "Blockbenchの.bbmodel形式ではありません"
	var importer := BBModelImporter.new()
	return importer.import_data(self, data, path)

func load_gltf(path: String) -> String:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var result: Error = document.append_from_file(path, state)
	if result != OK:
		return "glTF読み込み失敗：" + str(result)
	var scene := document.generate_scene(state)
	if scene == null:
		return "シーン生成に失敗しました"
	_clear_model()
	imported_source = path
	model_root = Node3D.new()
	model_root.name = "ImportedModel"
	add_child(model_root)
	model_root.add_child(scene)
	_register_gltf_nodes(scene)
	store_rest()
	if parts.is_empty():
		return "編集可能なNode3Dがありません"
	return ""

func _register_gltf_nodes(node: Node) -> void:
	if node is Node3D and not (node is MeshInstance3D) and not (node is Camera3D) and not (node is Light3D):
		_register_part(str(node.name), node)
	for child in node.get_children():
		_register_gltf_nodes(child)
