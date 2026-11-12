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
 engine.shutdown()
 engine.shutdown()
 engine = null
 for i in range(3):
  var another = ClassDB.instantiate("JuceEngine")
  another.shutdown()
  another = null
 if failures == 0: print("PASS: native bridge WAV and lifetime integration")
 quit(0 if failures == 0 else 1)
