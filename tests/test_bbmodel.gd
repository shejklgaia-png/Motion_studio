extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var rig := MotionRig.new()
	root.add_child(rig)
	var issue := rig.load_bbmodel("res://tests/sample_blockbench5.bbmodel")
	if issue != "":
		_fail("Cannot import Blockbench 5 fixture: " + issue)
		return
	if rig.parts.size() < 3:
		_fail("Expected group and 2 editable elements, got " + str(rig.parts.size()))
		return
	if rig.bb_animations.size() != 1:
		_fail("Animation metadata not found")
		return
	var mesh_nodes := 0
	for name in rig.parts:
		var node: Node3D = rig.parts[name]
		for child in node.get_children():
			if child is MeshInstance3D:
				mesh_nodes += 1
	if mesh_nodes != 2:
		_fail("Expected 2 rendered meshes, got " + str(mesh_nodes))
		return
	var animation := MotionEngine.new()
	animation.setup(rig)
	var message := animation.load_bb_animation(0)
	animation.evaluate(0.5)
	var rotated: Node3D = rig.parts["脚"]
	if absf(rotated.rotation_degrees.z - 20.0) > 0.5:
		_fail("Animation interpolation failed: " + str(rotated.rotation_degrees.z))
		return
	print("Motion Studio BBMODEL IMPORT PASS: ", message)
	quit(0)

func _fail(detail: String) -> void:
	push_error(detail)
	quit(1)
