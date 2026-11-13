class_name AudioSession
extends Node
## Main-thread GDScript API over the native JUCE renderer. Add to the scene tree
## to initialize devices and receive polled audio notifications automatically.
const ProjectFile = preload("res://addons/juce_bridge/api/project_file.gd")
const Track = preload("res://addons/juce_bridge/api/audio_track.gd")
signal project_saved(path: String)
signal project_loaded(path: String)
signal playback_finished
signal state_changed(state: StringName)
signal audio_error(message: String)
signal audio_ready_changed(ready: bool)
signal device_changed(device_name: String)
signal track_added(track: AudioTrack)
signal position_changed(seconds: float)
signal levels_changed(levels: Vector2)
signal session_changed

@export var auto_initialize := true
var _engine: Object
var _tracks: Array[AudioTrack] = []
var _ready_audio := false
var _state: StringName = &"stopped"
var _finish_armed := false
var _master := 0.5
var _last_position := -1.0
var _selected_device := ""

var master_volume: float:
 get: return _master
 set(value):
  if not is_finite(value): return
  _master = clampf(value, 0, 1)
  if _engine: _engine.set_volume(_master)
var audio_ready: bool:
 get: return _ready_audio
var state: StringName:
 get: return _state
var position: float:
 get: return _engine.get_position() if _engine else 0.0
var duration: float:
 get: return _engine.get_duration() if _engine else 0.0
var levels: Vector2:
 get: return _engine.get_levels() if _engine else Vector2.ZERO
var tracks: Array[AudioTrack]:
 get: return _tracks.duplicate()

func _ready() -> void:
 if auto_initialize: initialize()

func _ensure_engine() -> String:
 if _engine: return ""
 if not ClassDB.class_exists("JuceEngine"):
  return "JUCE engine missing. Build the GDExtension and reopen Godot."
 _engine = ClassDB.instantiate("JuceEngine")
 if not _engine.has_method("set_track_eq_gain"):
  _engine = null
  return "EQ engine update required. Close Godot, rebuild the DLL, and reopen."
 _engine.set_volume(_master)
 return ""

func _report(error: String) -> String:
 if not error.is_empty(): audio_error.emit(error)
 return error

func initialize() -> String:
 if _ready_audio: return ""
 var error := _ensure_engine()
 if error.is_empty(): error = _engine.initialize()
 if not error.is_empty(): return _report(error)
 _ready_audio = true
 audio_ready_changed.emit(true)
 return ""

func shutdown() -> void:
 _finish_armed = false
 if _engine: _engine.shutdown()
 _set_state(&"stopped")
 if _ready_audio:
  _ready_audio = false
  audio_ready_changed.emit(false)

func add_track(label: String = "") -> AudioTrack:
 var error := _ensure_engine()
 if not error.is_empty():
  _report(error)
  return null
 var native_index := _tracks.size()
 if native_index >= _engine.get_track_count(): native_index = _engine.add_track()
 if native_index < 0:
  _report("Track limit reached (16).")
  return null
 var track: AudioTrack = Track.new()
 track._attach(self, native_index, label if not label.is_empty() else "Track %d" % (native_index + 1))
 _tracks.append(track)
 track_added.emit(track)
 session_changed.emit()
 return track

func get_output_devices() -> PackedStringArray:
 return _engine.get_output_devices() if _engine else PackedStringArray()

func select_output_device(device_name: String) -> String:
 if not _ready_audio: return _report("Initialize audio before selecting a device.")
 var error: String = _engine.select_output_device(device_name)
 if error.is_empty():
  _selected_device = device_name
  device_changed.emit(device_name)
 return _report(error)

func play() -> String:
 if not _ready_audio: return _report("Initialize audio before playing.")
 if duration <= 0: return _report("Load audio onto a track before playing.")
 _engine.play()
 if _engine.is_playing():
  _finish_armed = true
  _set_state(&"playing")
 return ""

func pause() -> void:
 _finish_armed = false
 if _engine: _engine.pause()
 _set_state(&"paused")

func stop() -> void:
 _finish_armed = false
 if _engine: _engine.stop()
 _set_state(&"stopped")

func seek(seconds: float) -> void:
 if not is_finite(seconds):
  _report("Seek position must be finite.")
  return
 if _engine: _engine.seek(seconds)

func _set_state(value: StringName) -> void:
 if _state == value: return
 _state = value
 state_changed.emit(value)

func _structural_edit() -> void:
 _finish_armed = false
 _set_state(&"stopped")
 session_changed.emit()

func _process(_delta: float) -> void:
 if not _engine: return
 if _finish_armed and not _engine.is_playing():
  var finished := duration > 0 and position >= duration - 0.000001
  _finish_armed = false
  _set_state(&"stopped")
  if finished: playback_finished.emit()
 var current := position
 if current != _last_position:
  _last_position = current
  position_changed.emit(current)
 levels_changed.emit(levels)
 for track in _tracks: track.levels_changed.emit(track.levels)

func _exit_tree() -> void:
 shutdown()

func save_project(path: String) -> String:
 var target: String = ProjectFile.absolute(path)
 if not target.is_absolute_path(): return _report("Project path must be absolute, res://, or user://.")
 var items: Array[Dictionary] = []
 for track in _tracks:
  var audio_path := ""
  if not track.file_path.is_empty():
   audio_path = ProjectFile.absolute(track.file_path)
   var prefix := target.get_base_dir().trim_suffix("/") + "/"
   if audio_path.begins_with(prefix): audio_path = audio_path.trim_prefix(prefix)
  items.append({"name": track.track_name, "file": audio_path, "volume": track.volume,
   "pan": track.pan, "muted": track.muted, "solo": track.solo, "offset": track.offset, "eq": track.eq._settings()})
 var error: String = ProjectFile.write(path, {"format": ProjectFile.FORMAT, "version": ProjectFile.VERSION, "master_volume": _master, "tracks": items})
 if not error.is_empty(): return _report(error)
 project_saved.emit(path)
 return ""

func load_project(path: String) -> String:
 var result: Dictionary = ProjectFile.read(path)
 if not result.error.is_empty(): return _report(result.error)
 var staged = _create_project_session()
 staged.auto_initialize = false
 staged.master_volume = result.data.master_volume
 var staged_error: String = staged._ensure_engine()
 if not staged_error.is_empty():
  staged.free()
  return _report(staged_error)
 # Decode all referenced files into a separate, unopened engine. Errors leave
 # the running session and its track handles untouched.
 for item in result.data.tracks:
  var track: AudioTrack = staged.add_track(item.name)
  if not track:
   staged.free()
   return _report("Cannot allocate project track. Check the native engine.")
  track.track_name = item.name
  if not item.file.is_empty():
   var audio_path: String = item.file
   if not audio_path.is_absolute_path(): audio_path = ProjectFile.absolute(path).get_base_dir().path_join(audio_path).simplify_path()
   var error: String = track.load_wav(audio_path)
   if not error.is_empty():
    staged.free()
    return _report("Cannot load project audio '%s': %s" % [audio_path, error])
  track.volume = item.volume
  track.pan = item.pan
  track.muted = item.muted
  track.solo = item.solo
  track.offset = item.offset
  if item.has("eq"):
   track.eq.low_gain_db = item.eq.low_gain_db
   track.eq.mid_gain_db = item.eq.mid_gain_db
   track.eq.high_gain_db = item.eq.high_gain_db
   track.eq.bypassed = item.eq.bypassed
 var engine_error: String = staged._ensure_engine()
 if not engine_error.is_empty():
  staged.free()
  return _report(engine_error)
 if _ready_audio:
  # Exclusive devices cannot be opened twice. Only release the active device
  # after all validation/decoding succeeded, and restore it on open failure.
  _engine.shutdown()
  engine_error = staged._engine.initialize()
  if engine_error.is_empty() and not _selected_device.is_empty(): engine_error = staged._engine.select_output_device(_selected_device)
  if not engine_error.is_empty():
   staged._engine.shutdown()
   var restore_error: String = _engine.initialize()
   if restore_error.is_empty() and not _selected_device.is_empty(): restore_error = _engine.select_output_device(_selected_device)
   _finish_armed = false
   _set_state(&"stopped")
   if not restore_error.is_empty():
    _ready_audio = false
    audio_ready_changed.emit(false)
   staged.free()
   return _report("Cannot activate project audio: %s%s" % [engine_error, " Restore failed: " + restore_error if not restore_error.is_empty() else ""])
 for track in _tracks: track._owner = null
 if _engine: _engine.shutdown()
 _engine = staged._engine
 staged._engine = null
 _tracks = staged._tracks.duplicate()
 staged._tracks.clear()
 for track in _tracks: track._owner = weakref(self)
 _master = staged._master
 staged.free()
 _last_position = -1
 _structural_edit()
 project_loaded.emit(path)
 return ""

# Internal factory also permits deterministic device-activation tests.
func _create_project_session():
 return load("res://addons/juce_bridge/api/audio_session.gd").new()
