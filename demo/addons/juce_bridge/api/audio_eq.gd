class_name AudioEQ
extends RefCounted
## One fixed-frequency, native three-band EQ per track; parameters use dB.
signal changed(property: StringName)
var _track: WeakRef
var _gains: Array[float] = [0.0, 0.0, 0.0]
var _bypassed := false
var low_gain_db: float:
 get: return _gains[0]
 set(value): _set_gain(0, value)
var mid_gain_db: float:
 get: return _gains[1]
 set(value): _set_gain(1, value)
var high_gain_db: float:
 get: return _gains[2]
 set(value): _set_gain(2, value)
var bypassed: bool:
 get: return _bypassed
 set(value):
  if _bypassed == value: return
  _bypassed = value
  var track = _track.get_ref() if _track else null
  var session = track._session() if track else null
  if session: session._engine.set_track_eq_bypassed(track.index, value)
  changed.emit(&"bypassed")

func _attach(track: RefCounted) -> void:
 _track = weakref(track)

func _set_gain(band: int, value: float) -> void:
 if not is_finite(value): return
 value = clampf(value, -18, 18)
 if _gains[band] == value: return
 _gains[band] = value
 var track = _track.get_ref() if _track else null
 var session = track._session() if track else null
 if session: session._engine.set_track_eq_gain(track.index, band, value)
 changed.emit([&"low_gain_db", &"mid_gain_db", &"high_gain_db"][band])

func reset() -> void:
 low_gain_db = 0
 mid_gain_db = 0
 high_gain_db = 0
 bypassed = false

func _settings() -> Dictionary:
 return {"low_gain_db": low_gain_db, "mid_gain_db": mid_gain_db, "high_gain_db": high_gain_db, "bypassed": bypassed}
