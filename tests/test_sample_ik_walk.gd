extends SceneTree

func _initialize() -> void:
	call_deferred("_verify")

func _tip(rig: MotionRig, chain: Dictionary) -> Vector3:
	var foot: Node3D = rig.parts[str(chain["end"])]
	return foot.to_global(MotionRig.from_array(chain["tip"]))

func _verify() -> void:
	var rig := MotionRig.new()
	root.add_child(rig)
	rig.create_sample()
	var engine := MotionEngine.new()
	engine.setup(rig)
	engine.add_sample_walk_animation()
	if not engine.sample_walk or rig.chains.size() != 4:
		_fail("Four-legged walk demonstration was not initialized")
		return
	if engine.frames.size() < 5 or absf(engine.duration - 3.4) > 0.01:
		_fail("Walk motion has no animated torso / duration")
		return
	for chain in rig.chains:
		if not bool(chain.get("enabled", false)) or not bool(chain.get("walk_enabled", false)):
			_fail("All four sample legs must use active IK")
			return
		if str(chain.get("method", "")) != "2ボーン":
			_fail("Walking requires the actual analytic IK solver")
			return
	var lead: Dictionary = rig.chains[0] # front left
	var support: Dictionary = rig.chains[1] # rear left
	var support_anchor: Vector3 = MotionRig.from_array(support["walk_base"])
	for t in [0.0, 0.35, 0.7, 1.0, 1.15]:
		engine.evaluate(t)
		var planted: Vector3 = _tip(rig, support)
		if planted.distance_to(support_anchor) > 0.085:
			_fail("Planted support foot slid off its world-space anchor at %s: %s" % [str(t), str(planted)])
			return
	var lead_base: Vector3 = MotionRig.from_array(lead["walk_base"])
	engine.evaluate(0.7)
	var lifted: Vector3 = _tip(rig, lead)
	if lifted.y < 0.13 or lifted.z > lead_base.z - 0.15:
		_fail("Swing foot must lift and advance using IK: " + str(lifted))
		return
	engine.evaluate(1.12)
	var landed: Vector3 = _tip(rig, lead)
	if absf(landed.y) > 0.065 or absf(landed.z - (lead_base.z - 0.62)) > 0.09:
		_fail("First swing did not land on the ground: " + str(landed))
		return
	engine.evaluate(1.7)
	var back_foot: Vector3 = _tip(rig, support)
	if back_foot.y < 0.12:
		_fail("Other diagonal pair did not lift later")
		return
	# Scrubbing must not accumulate offsets: footsteps are pure functions of time.
	engine.evaluate(2.75)
	var reference: Vector3 = _tip(rig, lead)
	engine.evaluate(0.3)
	engine.evaluate(2.75)
	if _tip(rig, lead).distance_to(reference) > 0.0002:
		_fail("Time scrubbing changed IK gait")
		return
	if MotionRig.from_array(engine.sample(3.4)["胴体"]["position"]).z > -0.5:
		_fail("Body did not travel forward")
		return
	var previous: Dictionary = engine.snapshot()
	engine.restore(previous)
	if not engine.sample_walk or not bool(rig.chains[0].get("walk_enabled", false)):
		_fail("Walk state did not survive project restore")
		return
	var baked: Dictionary = engine.bake_ik_fk(30)
	if not bool(baked.get("ok", false)) or engine.sample_walk:
		_fail("Sample gait failed IK/FK baking")
		return
	engine.evaluate(0.7)
	var baked_lift: Vector3 = _tip(rig, rig.chains[0])
	if absf(baked_lift.y - lifted.y) > 0.055:
		_fail("Baking changed the lifted foot height")
		return
	if not engine.restore_bake_source() or not engine.sample_walk:
		_fail("Original IK walk cannot be restored after baking")
		return
	var scene: PackedScene = load("res://Main.tscn")
	var app: Control = scene.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	if not bool(app.get("motion").sample_walk):
		_fail("Main did not open on the IK walking sample")
		return
	var picker: OptionButton = app.get("animation_picker")
	if not picker.get_item_text(0).contains("IK歩行"):
		_fail("Sample picker does not describe the walking motion")
		return
	app.call("_seek_to", float(app.get("motion").duration))
	app.call("_toggle_playback")
	if float(app.get("motion").play_time) > 0.01:
		_fail("Walk replay did not restart at frame zero")
		return
	print("SAMPLE IK WALK PASS: planted feet, diagonal steps, lift/landing, time scrub, save, bake and tutorial-free startup")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
