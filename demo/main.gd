extends Control
const Timeline = preload("res://timeline.gd")
var engine: Object
var ready_audio := false
var status: Label
var time_label: Label
var device_list: OptionButton
var picker: FileDialog
var selected_track := 0
var timeline
var track_panel: VBoxContainer
var rows: Array[Dictionary] = []
var master_meters: Array[ProgressBar] = []
var transport: Array[Button] = []
var add_button: Button
var seek_slider: HSlider
var syncing := false
var seek_dragging := false

func _ready() -> void:
 var margin := MarginContainer.new()
 margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
 add_child(margin)
 var panel := VBoxContainer.new()
 panel.add_theme_constant_override("separation", 12)
 margin.add_child(panel)
 var title := Label.new()
 title.text = "GODOT × JUCE  /  Multitrack Session"
 title.add_theme_font_size_override("font_size", 26)
 panel.add_child(title)
 status = _label(panel, "Starting audio…")
 device_list = OptionButton.new()
 panel.add_child(device_list)
 device_list.item_selected.connect(func(index: int):
  var error: String = engine.call("select_output_device", device_list.get_item_text(index))
  status.text = "Output changed." if error.is_empty() else error)
 var controls := HBoxContainer.new()
 panel.add_child(controls)
 transport.append(_button(controls, "Play", func(): engine.call("play")))
 transport.append(_button(controls, "Pause", func(): engine.call("pause")))
 transport.append(_button(controls, "Stop", func(): engine.call("stop")))
 add_button = _button(controls, "Add track", _add_track)
 time_label = _label(controls, "0.00 / 0.00 seconds")
 seek_slider = _slider(panel, 0, 10, 0, func(value: float):
  if engine and not syncing: engine.call("seek", value))
 seek_slider.drag_started.connect(func(): seek_dragging = true)
 seek_slider.drag_ended.connect(func(_changed: bool): seek_dragging = false)
 var master := HBoxContainer.new()
 panel.add_child(master)
 _label(master, "Master")
 _slider(master, 0, 1, 0.5, func(value: float):
  if engine: engine.call("set_volume", value))
 for channel in ["L", "R"]:
  _label(master, channel)
  master_meters.append(_meter(master))
 var hint := _label(panel, "Click the timeline to seek. Drag a clip to move it. Loading, clearing, or moving clips stops and rewinds playback.")
 hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 var scroll := ScrollContainer.new()
 scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
 panel.add_child(scroll)
 var content := VBoxContainer.new()
 content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 content.add_theme_constant_override("separation", 16)
 scroll.add_child(content)
 timeline = Timeline.new()
 content.add_child(timeline)
 timeline.seek_requested.connect(func(seconds: float):
  if ready_audio: engine.call("seek", seconds))
 timeline.clip_moved.connect(_move_clip)
 track_panel = VBoxContainer.new()
 track_panel.add_theme_constant_override("separation", 14)
 content.add_child(track_panel)
 picker = FileDialog.new()
 picker.access = FileDialog.ACCESS_FILESYSTEM
 picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
 picker.filters = PackedStringArray(["*.wav ; WAV audio"])
 add_child(picker)
 picker.file_selected.connect(_load_file)
 if not ClassDB.class_exists("JuceEngine"):
  _unavailable("Native engine missing. Build the updated GDExtension, then reopen Godot.")
  return
 engine = ClassDB.instantiate("JuceEngine")
 if not engine.has_method("load_track_wav"):
  _unavailable("Old engine DLL detected. Close Godot, rebuild the extension, and reopen.")
  engine = null
  return
 var error: String = engine.call("initialize")
 ready_audio = error.is_empty()
 for track in range(engine.call("get_track_count")): _create_row(track)
 for device in engine.call("get_output_devices"): device_list.add_item(device)
 device_list.select(-1)
 device_list.text = "Output device (system default)"
 if not ready_audio:
  _unavailable("Audio initialization failed: " + error)
 else:
  status.text = "Audio ready. Load WAV files onto the two tracks."
 _refresh_timeline()

func _unavailable(message: String) -> void:
 status.text = message
 device_list.disabled = true
 add_button.disabled = true
 for button in transport: button.disabled = true
 seek_slider.editable = false
 for row in rows: row.load.disabled = true

func _label(parent: Node, text: String) -> Label:
 var label := Label.new()
 label.text = text
 parent.add_child(label)
 return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
 var button := Button.new()
 button.text = text
 button.pressed.connect(callback)
 parent.add_child(button)
 return button

func _slider(parent: Node, minimum: float, maximum: float, value: float, callback: Callable) -> HSlider:
 var slider := HSlider.new()
 slider.min_value = minimum
 slider.max_value = maximum
 slider.step = 0.001
 slider.value = value
 slider.custom_minimum_size.x = 90
 slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 parent.add_child(slider)
 slider.value_changed.connect(callback)
 return slider

func _meter(parent: Node) -> ProgressBar:
 var meter := ProgressBar.new()
 meter.max_value = 1
 meter.show_percentage = false
 meter.custom_minimum_size.x = 60
 meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 parent.add_child(meter)
 return meter

func _create_row(track: int) -> void:
 var box := VBoxContainer.new()
 track_panel.add_child(box)
 var header := HBoxContainer.new()
 box.add_child(header)
 _label(header, "Track %d" % (track + 1))
 var load_button := _button(header, "Open WAV…", func():
  selected_track = track
  picker.popup_centered_ratio(0.8))
 var name_label := _label(header, "Empty")
 name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
 _button(header, "Clear", func():
  var error: String = engine.call("clear_track", track)
  if error.is_empty():
   rows[track].name.text = "Empty"
   _refresh_timeline()
  status.text = "Track cleared." if error.is_empty() else error)
 var controls := HBoxContainer.new()
 box.add_child(controls)
 _label(controls, "Start (s)")
 var offset := SpinBox.new()
 offset.max_value = 86400
 offset.step = 0.01
 offset.custom_minimum_size.x = 100
 controls.add_child(offset)
 offset.value_changed.connect(func(value: float):
  if not syncing: _move_clip(track, value))
 _label(controls, "Volume")
 _slider(controls, 0, 1, 1, func(value: float): engine.call("set_track_volume", track, value))
 _label(controls, "Pan L / R")
 _slider(controls, -1, 1, 0, func(value: float): engine.call("set_track_pan", track, value))
 for item in [["Mute", "set_track_mute"], ["Solo", "set_track_solo"]]:
  var toggle := CheckButton.new()
  toggle.text = item[0]
  controls.add_child(toggle)
  toggle.toggled.connect(func(enabled: bool): engine.call(item[1], track, enabled))
 var meter_l := _meter(controls)
 var meter_r := _meter(controls)
 rows.append({"name": name_label, "offset": offset, "load": load_button, "meters": [meter_l, meter_r]})

func _add_track() -> void:
 var index: int = engine.call("add_track")
 if index < 0:
  status.text = "Track limit reached (16)."
  return
 _create_row(index)
 add_button.disabled = rows.size() >= 16
 _refresh_timeline()

func _load_file(path: String) -> void:
 var error: String = engine.call("load_track_wav", selected_track, path)
 if error.is_empty():
  rows[selected_track].name.text = path.get_file()
  _refresh_timeline()
 status.text = "Loaded " + path.get_file() if error.is_empty() else error

func _move_clip(track: int, seconds: float) -> void:
 var error: String = engine.call("set_track_offset", track, seconds)
 status.text = "Clip moved." if error.is_empty() else error
 _refresh_timeline()

func _refresh_timeline() -> void:
 syncing = true
 timeline.lengths.clear()
 timeline.offsets.clear()
 timeline.names.clear()
 for track in range(rows.size()):
  timeline.lengths.append(engine.call("get_track_duration", track))
  timeline.offsets.append(engine.call("get_track_offset", track))
  timeline.names.append(rows[track].name.text)
  rows[track].offset.value = engine.call("get_track_offset", track)
 timeline.span = maxf(10, engine.call("get_duration") * 1.15)
 timeline.custom_minimum_size.y = 28 + rows.size() * 38
 timeline.queue_redraw()
 seek_slider.max_value = maxf(0.001, engine.call("get_duration"))
 syncing = false

func _process(delta: float) -> void:
 if not engine or not engine.has_method("get_track_count"): return
 var levels: Vector2 = engine.call("get_levels")
 for channel in range(2): master_meters[channel].value = maxf(levels[channel], master_meters[channel].value - delta * 1.5)
 for track in range(rows.size()):
  var track_levels: Vector2 = engine.call("get_track_levels", track)
  for channel in range(2): rows[track].meters[channel].value = maxf(track_levels[channel], rows[track].meters[channel].value - delta * 1.5)
 var position: float = engine.call("get_position")
 timeline.playhead = position
 timeline.queue_redraw()
 syncing = true
 if not seek_dragging: seek_slider.value = position
 syncing = false
 time_label.text = "%.2f / %.2f seconds%s" % [position, engine.call("get_duration"), "  CLIPPING — lower master" if maxf(levels.x, levels.y) > 1 else ""]

func _exit_tree() -> void:
 if engine:
  engine.call("shutdown")
  engine = null
