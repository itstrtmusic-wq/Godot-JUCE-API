extends SceneTree

var failures := 0

func _check(condition: bool, message: String = "Engine integration check failed") -> void:
 if not condition:
  push_error(message)
  failures += 1

func _initialize() -> void:
 if not ClassDB.class_exists("JuceEngine"):
  push_error("JuceEngine did not register")
  quit(1)
  return
 var engine = ClassDB.instantiate("JuceEngine")
 _check(engine.get_track_count() == 2)
 _check(engine.get_duration() == 0.0)
 _check(not engine.is_playing())
 _check(not engine.load_wav("/missing/file.wav").is_empty())
 _check(engine.load_wav(ProjectSettings.globalize_path("res://tests/tone.wav")).is_empty())
 _check(absf(engine.get_duration() - 0.1) < 0.000001)
 _check(engine.get_position() == 0.0)
 _check(not engine.load_wav(ProjectSettings.globalize_path("res://main.gd")).is_empty())
 _check(absf(engine.get_duration() - 0.1) < 0.000001, "Failed load must preserve clip")
 engine.set_volume(-1.0)
 engine.set_volume(2.0)
 engine.set_volume(NAN)
 engine.set_volume(INF)
 engine.stop()
 _check(engine.get_position() == 0.0)
 _check(not engine.is_playing())
 _check(engine.load_track_wav(1, ProjectSettings.globalize_path("res://tests/tone.wav")).is_empty())
 _check(engine.set_track_offset(1, 0.25).is_empty())
 _check(absf(engine.get_duration() - 0.35) < 0.000001)
 _check(absf(engine.get_track_duration(0) - 0.1) < 0.000001)
 _check(absf(engine.get_track_offset(1) - 0.25) < 0.000001)
 _check(not engine.set_track_offset(1, NAN).is_empty())
 _check(not engine.set_track_offset(1, -1).is_empty())
 _check(not engine.load_track_wav(99, "/missing.wav").is_empty())
 _check(not engine.clear_track(-1).is_empty())
 engine.set_track_volume(0, 0.7)
 engine.set_track_pan(1, -0.5)
 engine.set_track_mute(0, true)
 engine.set_track_solo(1, true)
 engine.set_track_pan(1, NAN)
 engine.set_track_volume(1, INF)
 _check(engine.get_track_levels(99) == Vector2.ZERO)
 _check(engine.clear_track(1).is_empty())
 _check(absf(engine.get_duration() - 0.1) < 0.000001)
 for index in range(2, 16): _check(engine.add_track() == index)
 _check(engine.add_track() == -1)
 _check(engine.get_track_count() == 16)
 engine.shutdown()
 engine.shutdown()
 engine = null
 for i in range(3):
  var another = ClassDB.instantiate("JuceEngine")
  another.shutdown()
  another = null
 if failures == 0: print("PASS: multitrack API, WAV recovery, validation, track limit and lifetime integration")
 quit(0 if failures == 0 else 1)
