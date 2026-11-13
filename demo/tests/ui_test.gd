extends SceneTree
var failures := 0
func check(condition: bool, message: String) -> void:
 if not condition:
  failures += 1
  push_error(message)

func _initialize() -> void:
 call_deferred("run")

func run() -> void:
 var scene = load("res://main.tscn")
 if not scene:
  quit(1)
  return
 var demo = scene.instantiate()
 root.add_child(demo)
 await process_frame
 if not demo.session or demo.session.tracks.size() != 2:
  push_error("Updated engine required")
  quit(1)
  return
 check(demo.rows.size() == 2, "Demo must start with two rows")
 demo.selected_track = 0
 demo._load_file(ProjectSettings.globalize_path("res://tests/tone.wav"))
 demo.selected_track = 1
 demo._load_file(ProjectSettings.globalize_path("res://tests/tone.wav"))
 demo._move_clip(1, 0.25)
 check(absf(demo.timeline.offsets[1] - 0.25) < 0.000001, "Timeline must reflect engine offset")
 check(demo.rows[1].name.text == "tone.wav", "Track label must reflect loaded file")
 demo._add_track()
 check(demo.rows.size() == 3, "Adding track must update controls")
 check(demo.timeline.lengths.size() == 3, "Adding track must update timeline")
 await process_frame
 var timeline = demo.timeline
 var original: float = timeline.offsets[0]
 var press := InputEventMouseButton.new()
 press.button_index = MOUSE_BUTTON_LEFT
 press.pressed = true
 press.position = Vector2(timeline.x_at(0.05), 40)
 timeline._gui_input(press)
 var motion := InputEventMouseMotion.new()
 motion.position = press.position + Vector2(50, 0)
 motion.button_mask = MOUSE_BUTTON_MASK_LEFT
 timeline._gui_input(motion)
 var release := InputEventMouseButton.new()
 release.button_index = MOUSE_BUTTON_LEFT
 release.position = motion.position
 timeline._gui_input(release)
 check(demo.session.tracks[0].offset > original, "Dragging clip must commit offset to engine")
 check(absf(demo.rows[0].offset.value - demo.session.tracks[0].offset) < 0.011, "Offset control must match moved clip")
 demo.session.tracks[0].clear()
 demo._refresh_timeline()
 check(demo.timeline.lengths[0] == 0, "Cleared clip must disappear")
 var project_path := "user://ui-roundtrip.gjproject"
 demo.session.tracks[1].volume = 0.33
 demo.session.tracks[1].pan = -0.4
 demo.session.tracks[1].muted = true
 demo.session.master_volume = 0.27
 demo.session.tracks[1].eq.low_gain_db = 5.5
 demo.session.tracks[1].eq.bypassed = true
 demo._save_project(project_path)
 demo._add_track()
 demo._open_project(project_path)
 check(demo.rows.size() == 3, "Project open must rebuild track rows")
 check(demo.rows[1].name.text == "tone.wav", "Restored row must show file name")
 check(absf(demo.master_slider.value - 0.27) < 0.000001, "Master control must reflect restored gain")
 var restored_controls = demo.track_panel.get_child(1).get_child(1)
 var sliders: Array[float] = []
 var toggles: Array[bool] = []
 for control in restored_controls.get_children():
  if control is HSlider: sliders.append(control.value)
  if control is CheckButton: toggles.append(control.button_pressed)
 check(sliders.size() == 2 and absf(sliders[0] - 0.33) < 0.000001 and absf(sliders[1] + 0.4) < 0.000001, "Track faders must reflect restored values")
 check(toggles == [true, false], "Mute/solo controls must reflect restored values")
 var eq_controls = demo.track_panel.get_child(1).get_child(2)
 var eq_knobs: Array[float] = []
 var eq_bypassed := false
 for control in eq_controls.get_children():
  if control is SpinBox: eq_knobs.append(control.value)
  if control is CheckButton: eq_bypassed = control.button_pressed
 check(eq_knobs == [5.5, 0.0, 0.0] and eq_bypassed, "EQ controls restore from project")
 # Editing the first and third controls routes to separate gain properties.
 eq_controls.get_child(2).value = -4
 eq_controls.get_child(6).value = 3
 check(demo.session.tracks[1].eq.low_gain_db == -4 and demo.session.tracks[1].eq.high_gain_db == 3, "EQ controls address the correct bands")
 DirAccess.remove_absolute(ProjectSettings.globalize_path(project_path))
 demo.queue_free()
 await process_frame
 if failures == 0: print("PASS: demo track loading, controls, timeline dragging and cleanup")
 quit(0 if failures == 0 else 1)
