extends SceneTree
const Session = preload("res://addons/juce_bridge/api/audio_session.gd")
# Device activation is controlled separately from actual WAV decode tests.
class FakeDevice extends RefCounted:
 var init_error := ""
 var initialized := false
 func initialize() -> String:
  initialized = init_error.is_empty()
  return init_error
 func shutdown() -> void: initialized = false
 func set_volume(_value: float) -> void: pass
 func select_output_device(_name: String) -> String: return ""
class DeviceSession extends Session:
 var stage_error := ""
 func _create_project_session():
  var staged = Session.new()
  staged._engine = FakeDevice.new()
  staged._engine.init_error = stage_error
  return staged
var failures := 0
func check(condition: bool, message: String) -> void:
 if not condition:
  failures += 1
  push_error(message)
func write(path: String, data: Variant) -> void:
 var file := FileAccess.open(path, FileAccess.WRITE)
 file.store_string(data if data is String else JSON.stringify(data))
 file.close()
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var folder := "user://project-test-%d" % Time.get_ticks_usec()
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
 var audio := folder.path_join("tone.wav")
 DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tests/tone.wav"), ProjectSettings.globalize_path(audio))
 var path := folder.path_join("session.gjproject")
 var bad := folder.path_join("bad.gjproject")
 var session = Session.new()
 session.auto_initialize = false
 root.add_child(session)
 var events: Array = []
 session.project_saved.connect(func(value: String): events.append(["saved", value]))
 session.project_loaded.connect(func(value: String): events.append(["loaded", value]))
 var first: AudioTrack = session.add_track("Drums")
 check(first != null, "Native engine required")
 if first == null:
  session.free()
  quit(1)
  return
 check(first.load_wav(audio).is_empty(), "Test audio must load")
 first.volume = 0.7
 first.pan = -0.3
 first.muted = true
 first.solo = true
 first.offset = 1.25
 var empty: AudioTrack = session.add_track("Empty track")
 empty.track_name = ""
 empty.offset = 2.0
 empty.volume = 0.2
 session.master_volume = 0.35
 check(session.save_project(path).is_empty(), "Project must save")
 var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
 check(original.tracks[0].file == "tone.wav", "Audio beneath project directory uses relative path")
 check(original.tracks[1].file == "", "Empty track has no file reference")
 session.master_volume = 0.45
 check(session.save_project(path).is_empty(), "Saving must replace an existing file")
 check(events.count(["saved", path]) == 2, "Save signals correspond to successful writes")
 first.volume = 0.1
 first.offset = 0
 check(session.load_project(path).is_empty(), "Project must load")
 check(events.count(["loaded", path]) == 1, "Load emits once after commit")
 check(session.tracks.size() == 2 and session.tracks[0].track_name == "Drums", "Track order and names restored")
 var restored: AudioTrack = session.tracks[0]
 check(absf(restored.volume - 0.7) < 0.000001 and absf(restored.pan + 0.3) < 0.000001, "Mixer values restored")
 check(restored.muted and restored.solo, "Mute and solo restored")
 check(absf(restored.offset - 1.25) < 0.000001 and absf(restored.duration - 0.1) < 0.000001, "Clip offset and audio restored")
 check(session.tracks[1].track_name.is_empty(), "Explicit empty track names must round trip")
 check(session.tracks[1].duration == 0 and session.tracks[1].offset == 2, "Empty tracks retain settings")
 check(absf(session.master_volume - 0.45) < 0.000001 and session.state == &"stopped", "Master restored and transport stopped")
 check(first.duration == 0, "Replaced track handles must detach")
 first.volume = 0.9
 check(absf(restored.volume - 0.7) < 0.000001, "Old handles cannot alter new tracks")
 var native = session._engine
 var invalid: Dictionary = original.duplicate(true)
 invalid.tracks[0].file = "missing.wav"
 write(bad, invalid)
 check(not session.load_project(bad).is_empty(), "Missing WAV must reject load")
 check(session._engine == native and session.tracks[0] == restored, "Failed load preserves native engine and track identity")
 check(absf(session.master_volume - 0.45) < 0.000001, "Failed load preserves master")
 invalid = original.duplicate(true)
 invalid.tracks[0].file = "session.gjproject"
 write(bad, invalid)
 check(not session.load_project(bad).is_empty(), "Non-WAV audio reference must reject load")
 for text in ["{", "[]", '{"format":"wrong","version":1}', " ".repeat(1024 * 1024 + 1)]:
  write(bad, text)
  check(not session.load_project(bad).is_empty(), "Malformed/oversize project must fail")
 invalid = original.duplicate(true)
 invalid.version = 99
 write(bad, invalid)
 check(not session.load_project(bad).is_empty(), "Unknown version must fail")
 invalid = original.duplicate(true)
 invalid.tracks[0].volume = "loud"
 write(bad, invalid)
 check(not session.load_project(bad).is_empty(), "Invalid property type must fail")
 invalid = original.duplicate(true)
 invalid.tracks[0].pan = 5
 write(bad, invalid)
 check(not session.load_project(bad).is_empty(), "Out-of-range mixer values must fail")
 invalid = original.duplicate(true)
 for number in range(15): invalid.tracks.append(original.tracks[0].duplicate())
 write(bad, invalid)
 check(not session.load_project(bad).is_empty(), "Too many tracks must fail")
 check(session._engine == native and session.tracks[0] == restored, "All validation failures preserve current data")
 check(events.count(["loaded", path]) == 1, "Failed loads do not emit project_loaded")
 var before := FileAccess.get_file_as_string(path)
 restored.track_name = "x".repeat(1024 * 1024 + 1)
 check(not session.save_project(path).is_empty(), "Oversize save must fail")
 check(FileAccess.get_file_as_string(path) == before, "Failed save preserves existing file")
 restored.track_name = "Drums"
 check(not session.save_project(folder.path_join("absent/sub/project.gjproject")).is_empty(), "Unwritable destination returns error")
 check(not session.save_project("relative.gjproject").is_empty(), "Relative project destination must fail safely")
 # Empty sessions are valid projects.
 write(bad, {"format": "godot-juce-session", "version": 1, "master_volume": 0.5, "tracks": []})
 check(session.load_project(bad).is_empty() and session.tracks.is_empty(), "Empty session round trip")
 session.free()
 # A device error must retain the old engine, and report if reopening it fails.
 var device_session := DeviceSession.new()
 device_session.auto_initialize = false
 var old_device := FakeDevice.new()
 device_session._engine = old_device
 device_session._ready_audio = true
 device_session.stage_error = "Device busy"
 check(not device_session.load_project(bad).is_empty(), "Activation failure returns error")
 check(device_session._engine == old_device and device_session.audio_ready and old_device.initialized, "Activation failure restores old device")
 old_device.init_error = "Device disconnected"
 var readiness: Array[bool] = []
 device_session.audio_ready_changed.connect(func(value: bool): readiness.append(value))
 check(not device_session.load_project(bad).is_empty(), "Rollback failure returns error")
 check(not device_session.audio_ready and readiness == [false], "Rollback failure updates readiness")
 old_device.init_error = ""
 device_session._ready_audio = true
 device_session.stage_error = ""
 check(device_session.load_project(bad).is_empty(), "Successful activation commits staged engine")
 check(device_session._engine != old_device and device_session.audio_ready, "Successful commit retains readiness")
 device_session.shutdown()
 device_session.free()
 for file in DirAccess.get_files_at(folder): DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join(file)))
 DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
 if failures == 0: print("PASS: project round trip, relative audio references, detached handles, atomic overwrite and failure recovery")
 quit(0 if failures == 0 else 1)
