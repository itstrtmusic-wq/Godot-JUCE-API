class_name AudioTrack
extends RefCounted
## One track in an AudioSession. Create tracks with session.add_track().
signal loaded(path: String)
signal load_failed(message: String)
signal changed(property: StringName)
signal levels_changed(levels: Vector2)

var _owner: WeakRef
var _index := -1
var _path := ""
var _name := ""
var _volume := 1.0
var _pan := 0.0
var _muted := false
var _solo := false

var track_name: String:
 get: return _name
 set(value):
  if _name != value:
   _name = value
   changed.emit(&"track_name")
var volume: float:
 get: return _volume
 set(value):
  if not is_finite(value): return
  value = clampf(value, 0, 1)
  if _volume == value: return
  _volume = value
  _send(&"set_track_volume", value)
  changed.emit(&"volume")
var pan: float:
 get: return _pan
 set(value):
  if not is_finite(value): return
  value = clampf(value, -1, 1)
  if _pan == value: return
  _pan = value
  _send(&"set_track_pan", value)
  changed.emit(&"pan")
var muted: bool:
 get: return _muted
 set(value):
  if _muted == value: return
  _muted = value
  _send(&"set_track_mute", value)
  changed.emit(&"muted")
var solo: bool:
 get: return _solo
 set(value):
  if _solo == value: return
  _solo = value
  _send(&"set_track_solo", value)
  changed.emit(&"solo")
var offset: float:
 get:
  var session = _session()
  return session._engine.get_track_offset(_index) if session else 0.0
 set(value): set_offset(value)
var duration: float:
 get:
  var session = _session()
  return session._engine.get_track_duration(_index) if session else 0.0
var levels: Vector2:
 get:
  var session = _session()
  return session._engine.get_track_levels(_index) if session else Vector2.ZERO
var file_path: String:
 get: return _path
var index: int:
 get: return _index

func _attach(session: Node, native_index: int, label: String) -> void:
 _owner = weakref(session)
 _index = native_index
 _name = label

func _session():
 return _owner.get_ref() if _owner else null

func _send(method: StringName, value: Variant) -> void:
 var session = _session()
 if session: session._engine.call(method, _index, value)

func _error(message: String) -> String:
 var session = _session()
 if session: session.audio_error.emit(message)
 return message

func load_wav(path: String) -> String:
 var session = _session()
 var error := "AudioSession is no longer available."
 if session:
  var absolute := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
  error = session._engine.load_track_wav(_index, absolute) if absolute.is_absolute_path() else "Use an absolute path, res:// path, or user:// path."
 if not error.is_empty():
  _error(error)
  load_failed.emit(error)
  return error
 _path = path
 session._structural_edit()
 changed.emit(&"file_path")
 loaded.emit(path)
 return ""

func clear() -> String:
 var session = _session()
 if not session: return _error("AudioSession is no longer available.")
 var error: String = session._engine.clear_track(_index)
 if not error.is_empty(): return _error(error)
 _path = ""
 session._structural_edit()
 changed.emit(&"file_path")
 return ""

func set_offset(seconds: float) -> String:
 var session = _session()
 if not session: return _error("AudioSession is no longer available.")
 var error: String = session._engine.set_track_offset(_index, seconds)
 if not error.is_empty(): return _error(error)
 session._structural_edit()
 changed.emit(&"offset")
 return ""
