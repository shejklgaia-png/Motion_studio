extends RefCounted
class_name BBModelImporter

# Imports Blockbench 4.x inline outliners and Blockbench 5.x groups + UUID outliners.
# All geometry and pivots use Blockbench's 16-units-per-meter convention.
const UNIT := 16.0
const PALETTE := ["809db9", "c58b60", "83b3a2", "b69ab9", "b7a67f", "9db0c5"]

var rig: MotionRig
var textures: Dictionary = {}
var texture_sizes: Dictionary = {}
var all_elements: Dictionary = {}
var all_groups: Dictionary = {}
var uv_size := Vector2(16, 16)
var warnings: Array[String] = []
var mesh_count := 0

func import_data(target: MotionRig, data: Dictionary, path: String) -> String:
	if not (data.get("elements") is Array):
		return "Blockbenchモデルのelements配列がありません"
	var element_list: Array = data.get("elements", [])
	if element_list.is_empty():
		return "モデルにパーツがありません"
	rig = target
	all_elements.clear()
	all_groups.clear()
	textures.clear()
	texture_sizes.clear()
	warnings.clear()
	mesh_count = 0
	var resolution: Dictionary = data.get("resolution", {})
	uv_size = Vector2(maxf(1, float(resolution.get("width", 16))), maxf(1, float(resolution.get("height", 16))))
	for elem in element_list:
		if elem is Dictionary:
			var uid := str(elem.get("uuid", ""))
			if uid != "":
				all_elements[uid] = elem
	for group in data.get("groups", []):
		if group is Dictionary:
			all_groups[str(group.get("uuid", ""))] = group
	_read_textures(data.get("textures", []), path)
	rig._clear_model()
	rig.model_root = Node3D.new()
	rig.model_root.name = "BlockbenchModel"
	rig.add_child(rig.model_root)
	rig.imported_source = path
	var format_version := str(data.get("meta", {}).get("format_version", "4.0"))
	rig.bb_legacy_axes = format_version.split(".")[0].to_int() < 5
	rig.bb_animations = data.get("animations", []).duplicate(true)
	rig.bb_uuid_to_name.clear()
	rig.bb_import_warnings.clear()
	var outliner: Array = data.get("outliner", [])
	if outliner.is_empty():
		for element in element_list:
			if element is Dictionary:
				_element(element, rig.model_root, Vector3.ZERO)
	else:
		_children(outliner, rig.model_root, Vector3.ZERO)
	if rig.parts.is_empty():
		return "表示できるグループやメッシュがありません"
	if mesh_count == 0:
		warnings.append("表示できるメッシュがありません。cube / meshを確認してください")
	rig.bb_import_warnings = warnings.duplicate()
	rig.store_rest()
	return ""

func _read_textures(items: Array, path: String) -> void:
	for idx in range(items.size()):
		var entry: Variant = items[idx]
		if not (entry is Dictionary):
			continue
		var info: Dictionary = entry
		var tex: Texture2D = null
		var raw := str(info.get("source", ""))
		var image := Image.new()
		var err := ERR_FILE_UNRECOGNIZED
		if raw.begins_with("data:image/") and raw.contains("base64,"):
			var bytes := Marshalls.base64_to_raw(raw.split("base64,")[1])
			if raw.begins_with("data:image/png"):
				err = image.load_png_from_buffer(bytes)
			elif raw.begins_with("data:image/jpeg"):
				err = image.load_jpg_from_buffer(bytes)
			elif raw.begins_with("data:image/webp"):
				err = image.load_webp_from_buffer(bytes)
		else:
			# FileAccess can read Android SAF content:// model URIs, but not arbitrary
			# adjacent files without SAF grants. Embedded textures work offline.
			if not path.begins_with("content://"):
				var base := path.get_base_dir()
				var relative := str(info.get("relative_path", ""))
				var resolved := base.path_join(relative)
				if relative != "" and FileAccess.file_exists(resolved):
					err = image.load(resolved)
		if err == OK and not image.is_empty():
			tex = ImageTexture.create_from_image(image)
		elif raw != "" or str(info.get("relative_path", "")) != "":
			warnings.append("テクスチャ未読込: " + str(info.get("name", idx)))
		var key := str(idx)
		textures[key] = tex
		texture_sizes[key] = Vector2(maxf(1, float(info.get("uv_width", uv_size.x))),
			maxf(1, float(info.get("uv_height", uv_size.y))))
		var uuid := str(info.get("uuid", ""))
		if uuid != "":
			textures[uuid] = tex
			texture_sizes[uuid] = texture_sizes[key]

func _vec(value: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback

func _children(items: Array, parent: Node3D, parent_origin: Vector3) -> void:
	for entry in items:
		if entry is Dictionary and entry.has("children"):
			var uid := str(entry.get("uuid", ""))
			var group: Dictionary = all_groups.get(uid, entry)
			var pivot := _vec(group.get("origin", parent_origin), parent_origin)
			var joint := Node3D.new()
			joint.position = (pivot - parent_origin) / UNIT
			joint.rotation_order = 5 # Godot ZYX, matching Blockbench's Euler order.
			joint.rotation_degrees = _vec(group.get("rotation", [0, 0, 0]))
			parent.add_child(joint)
			var label := rig._register_part(str(group.get("name", "グループ")), joint)
			joint.set_meta("bb_uuid", uid)
			if uid != "":
				rig.bb_uuid_to_name[uid] = label
			_children(entry.get("children", []), joint, pivot)
		elif entry is String or entry is StringName:
			var key := str(entry)
			if all_elements.has(key):
				_element(all_elements[key], parent, parent_origin)
		elif entry is Dictionary and entry.has("vertices"):
			_element(entry, parent, parent_origin)
		elif entry is Dictionary and entry.has("from"):
			_element(entry, parent, parent_origin)

func _element(entry: Dictionary, parent: Node3D, parent_origin: Vector3) -> void:
	if not bool(entry.get("visibility", true)):
		return
	var pivot := _vec(entry.get("origin", parent_origin), parent_origin)
	var node := Node3D.new()
	node.rotation_order = 5
	node.position = (pivot - parent_origin) / UNIT
	node.rotation_degrees = _vec(entry.get("rotation", [0, 0, 0]))
	node.scale = _vec(entry.get("stretch", [1, 1, 1]), Vector3.ONE)
	parent.add_child(node)
	var label := rig._register_part(str(entry.get("name", "メッシュ")), node)
	var uid := str(entry.get("uuid", ""))
	node.set_meta("bb_uuid", uid)
	if uid != "":
		rig.bb_uuid_to_name[uid] = label
	var geometry: ArrayMesh
	if entry.has("vertices"):
		geometry = _mesh_geometry(entry)
	elif entry.has("from") and entry.has("to"):
		geometry = _cube_geometry(entry)
	else:
		return
	if geometry == null or geometry.get_surface_count() == 0:
		warnings.append("空のメッシュ: " + label)
		return
	var visual := MeshInstance3D.new()
	visual.name = "表示メッシュ"
	visual.mesh = geometry
	node.add_child(visual)
	var body := StaticBody3D.new()
	body.name = "部位選択判定"
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_meta("part_name", label)
	var shape := CollisionShape3D.new()
	shape.shape = geometry.create_trimesh_shape()
	body.add_child(shape)
	node.add_child(body)
	mesh_count += 1

func _surface(surfaces: Dictionary, key: String) -> Dictionary:
	if not surfaces.has(key):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces[key] = {"tool": tool, "count": 0}
	return surfaces[key]

func _texture_key(face: Dictionary) -> String:
	if not face.has("texture") or face["texture"] == null:
		return "-"
	var key := str(face["texture"])
	return key if textures.has(key) else "-"

func _write_face(surfaces: Dictionary, pts: Array, uv: Array, texkey: String) -> void:
	if pts.size() < 3 or uv.size() != pts.size():
		return
	var surface: Dictionary = _surface(surfaces, texkey)
	var tool: SurfaceTool = surface["tool"]
	var size: Vector2 = texture_sizes.get(texkey, uv_size)
	for i in range(1, pts.size() - 1):
		var indices := [0, i, i + 1]
		var a: Vector3 = pts[0]
		var b: Vector3 = pts[i]
		var c: Vector3 = pts[i + 1]
		var normal: Vector3 = (b - a).cross(c - a)
		if normal.length_squared() < 0.0000000001:
			continue
		normal = normal.normalized()
		for k in indices:
			var t: Vector2 = uv[k]
			tool.set_uv(Vector2(t.x / size.x, t.y / size.y))
			tool.set_normal(normal) # Unshared per-triangle normal: hard edges, no smoothing.
			tool.add_vertex(pts[k])
			surface["count"] = int(surface["count"]) + 1

func _finish(surfaces: Dictionary, palette_idx: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for key in surfaces.keys():
		var surface: Dictionary = surfaces[key]
		var tool: SurfaceTool = surface["tool"]
		if int(surface["count"]) == 0:
			continue
		tool.commit(mesh)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(PALETTE[absi(palette_idx) % PALETTE.size()])
		material.metallic = 0.0
		material.roughness = 1.0
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		if textures.has(key) and textures[key] != null:
			material.albedo_color = Color.WHITE
			material.albedo_texture = textures[key]
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh

func _mesh_geometry(entry: Dictionary) -> ArrayMesh:
	var raw_vertices: Dictionary = entry.get("vertices", {})
	var faces: Dictionary = entry.get("faces", {})
	var surfaces: Dictionary = {}
	for face_info in faces.values():
		if not (face_info is Dictionary):
			continue
		var face: Dictionary = face_info
		var verts: Array = face.get("vertices", [])
		var uv_data: Dictionary = face.get("uv", {})
		if verts.size() < 3:
			continue
		var coords: Array = []
		var coords_uv: Array = []
		var valid := true
		for v_key in verts:
			var vid := str(v_key)
			if not raw_vertices.has(vid):
				valid = false
				break
			coords.append(_vec(raw_vertices[vid]) / UNIT)
			var raw_uv: Variant = uv_data.get(vid, [0, 0])
			if raw_uv is Array and raw_uv.size() >= 2:
				coords_uv.append(Vector2(float(raw_uv[0]), float(raw_uv[1])))
			else:
				coords_uv.append(Vector2.ZERO)
		if valid:
			_write_face(surfaces, coords, coords_uv, _texture_key(face))
	return _finish(surfaces, int(entry.get("color", 0)))

func _cube_geometry(entry: Dictionary) -> ArrayMesh:
	var a := _vec(entry.get("from", [0, 0, 0]))
	var b := _vec(entry.get("to", [16, 16, 16]))
	var inflate := float(entry.get("inflate", 0.0))
	var pivot := _vec(entry.get("origin", [0, 0, 0]))
	a -= Vector3.ONE * inflate
	b += Vector3.ONE * inflate
	var x0 := minf(a.x, b.x)
	var x1 := maxf(a.x, b.x)
	var y0 := minf(a.y, b.y)
	var y1 := maxf(a.y, b.y)
	var z0 := minf(a.z, b.z)
	var z1 := maxf(a.z, b.z)
	var coords: Dictionary = {
		"north": [Vector3(x1,y1,z0),Vector3(x0,y1,z0),Vector3(x0,y0,z0),Vector3(x1,y0,z0)],
		"south": [Vector3(x0,y1,z1),Vector3(x1,y1,z1),Vector3(x1,y0,z1),Vector3(x0,y0,z1)],
		"east": [Vector3(x1,y1,z1),Vector3(x1,y1,z0),Vector3(x1,y0,z0),Vector3(x1,y0,z1)],
		"west": [Vector3(x0,y1,z0),Vector3(x0,y1,z1),Vector3(x0,y0,z1),Vector3(x0,y0,z0)],
		"up": [Vector3(x0,y1,z0),Vector3(x1,y1,z0),Vector3(x1,y1,z1),Vector3(x0,y1,z1)],
		"down": [Vector3(x0,y0,z1),Vector3(x1,y0,z1),Vector3(x1,y0,z0),Vector3(x0,y0,z0)]
	}
	var faces: Dictionary = entry.get("faces", {})
	var surfaces: Dictionary = {}
	for side in coords.keys():
		var face: Dictionary = faces.get(side, {})
		if face.has("texture") and face["texture"] == null:
			continue
		var corners: Array = []
		for vertex in coords[side]:
			corners.append((vertex - pivot) / UNIT)
		var box_uv: Variant = entry.get("uv_offset", [0, 0])
		var uv: Array = face.get("uv", [0, 0, 16, 16])
		if uv.size() != 4:
			uv = [0, 0, 16, 16]
		if not face.has("uv") and box_uv is Array and box_uv.size() >= 2:
			uv = [float(box_uv[0]), float(box_uv[1]), float(box_uv[0]) + 16.0, float(box_uv[1]) + 16.0]
		var a_uv := Vector2(float(uv[0]), float(uv[1]))
		var b_uv := Vector2(float(uv[2]), float(uv[3]))
		var uv_pts := [a_uv, Vector2(b_uv.x,a_uv.y), b_uv, Vector2(a_uv.x,b_uv.y)]
		_write_face(surfaces, corners, uv_pts, _texture_key(face))
	return _finish(surfaces, int(entry.get("color", 0)))
