extends RefCounted
## Versioned, data-only project files. No scripts or resources are deserialized.
const FORMAT := "godot-juce-session"
const VERSION := 2
const MAX_FILE_BYTES := 1024 * 1024

static func absolute(path: String) -> String:
 return ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path

static func number(value: Variant, low: float, high: float) -> bool:
 return (value is float or value is int) and is_finite(float(value)) and value >= low and value <= high

static func validate(data: Variant) -> String:
 if not data is Dictionary: return "Project must be a JSON object."
 if data.get("format") != FORMAT or not number(data.get("version"), 1, VERSION) or (float(data.version) != 1.0 and float(data.version) != 2.0): return "Unsupported project format or version."
 if not number(data.get("master_volume"), 0, 1): return "Invalid master volume."
 var tracks: Variant = data.get("tracks")
 if not tracks is Array or tracks.size() > 16: return "Project must contain at most 16 tracks."
 for item in tracks:
  if not item is Dictionary: return "Invalid track object."
  if not item.get("name") is String or not item.get("file") is String: return "Track name and file must be strings."
  if not number(item.get("volume"), 0, 1) or not number(item.get("pan"), -1, 1) or not number(item.get("offset"), 0, 86400): return "Invalid track volume, pan, or offset."
  if not item.get("muted") is bool or not item.get("solo") is bool: return "Mute and solo must be booleans."
  if data.version == 2 or item.has("eq"):
   var eq: Variant = item.get("eq")
   if not eq is Dictionary: return "Track EQ settings must be an object."
   for band in ["low_gain_db", "mid_gain_db", "high_gain_db"]:
    if not number(eq.get(band), -18, 18): return "EQ gains must be finite numbers between -18 and 18 dB."
   if not eq.get("bypassed") is bool: return "EQ bypass must be a boolean."
 return ""

static func write(path: String, data: Dictionary) -> String:
 var target := absolute(path)
 if not target.is_absolute_path(): return "Project path must be absolute, res://, or user://."
 var error := validate(data)
 if not error.is_empty(): return error
 # Write beside the destination, then replace it only after a successful flush.
 var encoded := JSON.stringify(data, "  ")
 if encoded.to_utf8_buffer().size() > MAX_FILE_BYTES: return "Project file exceeds 1 MiB."
 var temporary := target + ".tmp-%d-%d" % [Time.get_ticks_usec(), randi()]
 var file := FileAccess.open(temporary, FileAccess.WRITE)
 if not file: return "Cannot write project: " + error_string(FileAccess.get_open_error())
 file.store_string(encoded)
 file.flush()
 var result := file.get_error()
 file.close()
 if result != OK:
  DirAccess.remove_absolute(temporary)
  return "Project write failed: " + error_string(result)
 result = DirAccess.rename_absolute(temporary, target)
 if result != OK:
  DirAccess.remove_absolute(temporary)
  return "Cannot replace project file: " + error_string(result)
 return ""

static func read(path: String) -> Dictionary:
 var target := absolute(path)
 if not target.is_absolute_path(): return {"error": "Project path must be absolute, res://, or user://."}
 var file := FileAccess.open(target, FileAccess.READ)
 if not file: return {"error": "Cannot open project: " + error_string(FileAccess.get_open_error())}
 if file.get_length() > MAX_FILE_BYTES: return {"error": "Project file exceeds 1 MiB."}
 var parser := JSON.new()
 var result := parser.parse(file.get_as_text())
 file.close()
 if result != OK: return {"error": "Invalid project JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]}
 var error := validate(parser.data)
 return {"error": error, "data": parser.data}
