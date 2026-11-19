extends SceneTree
## Two-level navigation: related modes share the same top-level page.
func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MOTION TASK TABS FAILED: " + message)
    quit(1)

func _run() -> void:
    var app: Control = load("res://Main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    await process_frame
    var pages: Dictionary = app.get("primary_page_buttons")
    var modes: Dictionary = app.get("mode_buttons")
    var groups := {
        "モデル": ["階層", "制約"],
        "動き": ["モーション"],
        "IK・接触": ["IK", "接触"],
        "仕上げ": ["診断", "ベイク"]
    }
    if pages.size() != 4 or modes.size() != 7:
        _fail("Four primary tabs must contain all seven modes")
        return
    for group in groups:
        app.call("_select_primary_page", group)
        await process_frame
        if not (pages[group] as Button).button_pressed:
            _fail("Primary page did not activate: " + group)
            return
        for name in groups[group]:
            app.call("_change_mode", name)
            await process_frame
            if str(app.get("mode")) != name:
                _fail("Nested mode cannot be selected: " + name)
                return
            if not (modes[name] as Button).button_pressed:
                _fail("Nested mode does not show active selection: " + name)
                return
            for other in modes:
                if (modes[other] as Button).visible != (other in groups[group]):
                    _fail("Unrelated nested tools mixed into " + group)
                    return
    app.call("_change_mode", "接触")
    app.call("_select_primary_page", "仕上げ")
    app.call("_select_primary_page", "IK・接触")
    if str(app.get("mode")) != "接触":
        _fail("Returning to a page lost its previous editing mode")
        return
    app.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
    app.size = Vector2(360, 800)
    await process_frame
    for group in groups:
        var button: Button = pages[group]
        var rect: Rect2 = button.get_global_rect()
        if rect.size.x < 44 or rect.size.y < 44 or rect.position.x < -1 or rect.end.x > 361:
            _fail("Primary tab clipped on narrow portrait: " + group)
            return
    print("MOTION TASK TABS PASSED: four task pages, seven nested modes, return memory, narrow portrait")
    quit(0)
