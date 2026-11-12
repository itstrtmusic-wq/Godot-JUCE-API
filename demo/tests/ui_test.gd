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
 if not demo.engine or not demo.engine.has_method("load_track_wav"):
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
 check(demo.engine.get_track_offset(0) > original, "Dragging clip must commit offset to engine")
 check(absf(demo.rows[0].offset.value - demo.engine.get_track_offset(0)) < 0.011, "Offset control must match moved clip")
 demo.engine.clear_track(0)
 demo._refresh_timeline()
 check(demo.timeline.lengths[0] == 0, "Cleared clip must disappear")
 demo.queue_free()
 await process_frame
 if failures == 0: print("PASS: demo track loading, controls, timeline dragging and cleanup")
 quit(0 if failures == 0 else 1)
