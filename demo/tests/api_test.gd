extends SceneTree
const Session = preload("res://addons/juce_bridge/api/audio_session.gd")
var failures := 0

# Controlled native boundary: verify notifications without needing an audio device.
class FakeEngine extends RefCounted:
 var playing := false
 var cursor := 0.0
 var init_error := ""
 var count := 2
 var commands: Array = []
 func initialize() -> String: return init_error
 func shutdown() -> void: playing = false
 func get_track_count() -> int: return count
 func add_track() -> int:
  if count == 16: return -1
  count += 1
  return count - 1
 func get_duration() -> float: return 1.0
 func get_position() -> float: return cursor
 func get_levels() -> Vector2: return Vector2(0.25, 0.5)
 func get_track_levels(_index: int) -> Vector2: return Vector2(0.1, 0.2)
 func play() -> void: playing = true
 func pause() -> void: playing = false
 func stop() -> void: playing = false
 func is_playing() -> bool: return playing
 func seek(seconds: float) -> void: cursor = clampf(seconds, 0, 1)
 func set_volume(value: float) -> void: commands.append(["master", value])
 func set_track_volume(index: int, value: float) -> void: commands.append(["volume", index, value])
 func set_track_pan(index: int, value: float) -> void: commands.append(["pan", index, value])
 func set_track_mute(index: int, value: bool) -> void: commands.append(["mute", index, value])
 func set_track_solo(index: int, value: bool) -> void: commands.append(["solo", index, value])
 func select_output_device(device: String) -> String: return "Bad device" if device == "bad" else ""
 func get_output_devices() -> PackedStringArray: return PackedStringArray(["Test output"])

func check(condition: bool, message: String) -> void:
 if not condition:
  failures += 1
  push_error(message)

func _initialize() -> void:
 call_deferred("run")

func run() -> void:
 # Exercise the facade against the actual extension, without initializing devices.
 var session = Session.new()
 session.auto_initialize = false
 root.add_child(session)
 var errors: Array[String] = []
 session.audio_error.connect(func(message: String): errors.append(message))
 var track: AudioTrack = session.add_track("Drums")
 if track == null:
  push_error("Native extension required")
  session.free()
  quit(1)
  return
 var loaded: Array[String] = []
 var failed: Array[String] = []
 track.loaded.connect(func(path: String): loaded.append(path))
 track.load_failed.connect(func(message: String): failed.append(message))
 check(track.load_wav("res://tests/tone.wav").is_empty(), "Facade must load Godot loose-file paths")
 check(loaded == ["res://tests/tone.wav"], "Successful load emits exactly once")
 check(absf(track.duration - 0.1) < 0.000001, "Track duration forwards native metadata")
 track.offset = 0.25
 check(absf(session.duration - 0.35) < 0.000001, "Property offset updates native timeline")
 check(not track.load_wav("res://missing.wav").is_empty(), "Failed load returns error")
 check(failed.size() == 1 and errors.size() == 1, "Failed load emits track and session errors")
 check(track.file_path == "res://tests/tone.wav" and track.duration > 0, "Failed load preserves metadata")
 check(not track.set_offset(-1).is_empty(), "Invalid offset reports error")
 check(absf(track.offset - 0.25) < 0.000001, "Invalid offset preserves previous value")
 check(not track.load_wav("relative.wav").is_empty(), "Relative paths fail safely before reaching native code")
 check(track.clear().is_empty() and track.file_path.is_empty(), "Clear updates file metadata")
 var copy: Array = session.tracks
 copy.clear()
 check(session.tracks.size() == 1, "Caller cannot mutate owned track collection")
 session.free()
 check(track.levels == Vector2.ZERO, "Retained track is safe after session deletion")
 check(not track.load_wav("res://tests/tone.wav").is_empty(), "Orphan track load fails safely")
 track.volume = 0.2
 track = null

 # Simulate native progress/EOF and confirm main-thread signals and command routing.
 var fake := FakeEngine.new()
 session = Session.new()
 session.auto_initialize = false
 session._engine = fake
 root.add_child(session)
 var events: Array = []
 session.audio_error.connect(func(message: String): events.append(["error", message]))
 session.audio_ready_changed.connect(func(ready: bool): events.append(["ready", ready]))
 session.playback_finished.connect(func(): events.append(["finished", OS.get_thread_caller_id() == OS.get_main_thread_id()]))
 session.state_changed.connect(func(state: StringName): events.append(["state", state]))
 session.device_changed.connect(func(device: String): events.append(["device", device]))
 fake.init_error = "No device"
 check(not session.initialize().is_empty() and not session.audio_ready, "Initialization failure stays recoverable")
 fake.init_error = ""
 check(session.initialize().is_empty() and session.audio_ready, "Initialization can be retried")
 session.initialize()
 check(events.count(["ready", true]) == 1, "Idempotent initialize must not duplicate signals")
 track = session.add_track("Synth")
 track.volume = 0.25
 track.volume = NAN
 track.pan = -2
 track.muted = true
 track.solo = true
 session.master_volume = 2
 check(fake.commands.has(["volume", 0, 0.25]), "Volume routes correct track and value")
 check(fake.commands.has(["pan", 0, -1.0]), "Pan is clamped before forwarding")
 check(fake.commands.has(["mute", 0, true]) and fake.commands.has(["solo", 0, true]), "Mute and solo route independently")
 check(fake.commands.has(["master", 1.0]) and track.volume == 0.25, "Master clamps and nonfinite gain is ignored")
 check(session.select_output_device("Test output").is_empty(), "Device selection succeeds")
 session.select_output_device("bad")
 check(events.count(["device", "Test output"]) == 1 and not events.has(["device", "bad"]), "Device signal only fires on success")
 check(session.play().is_empty() and session.state == &"playing", "Play changes state")
 fake.cursor = 1
 fake.playing = false
 session._process(0)
 session._process(0)
 check(events.count(["finished", true]) == 1, "EOF emits once, on main thread")
 check(session.state == &"stopped", "EOF sets stopped state")
 session.play()
 session.pause()
 session._process(0)
 session.play()
 session.stop()
 session._process(0)
 check(events.count(["finished", true]) == 1, "Explicit pause/stop must not emit EOF")
 var meter_events: Array[Vector2] = []
 track.levels_changed.connect(func(value: Vector2): meter_events.append(value))
 session._process(0)
 check(meter_events == [Vector2(0.1, 0.2)], "Track meters arrive through signals")
 for number in range(1, 16): check(session.add_track() != null, "Track allocation within limit")
 check(session.add_track() == null and session.tracks.size() == 16, "Track limit returns null and error")
 session.shutdown()
 session.shutdown()
 check(events.count(["ready", false]) == 1, "Idempotent shutdown emits readiness once")
 session.free()
 track = null
 if failures == 0: print("PASS: GDScript facade, properties, errors, EOF signals, main-thread delivery and lifetime")
 quit(0 if failures == 0 else 1)
