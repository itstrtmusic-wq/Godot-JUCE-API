extends Control
const Timeline = preload("res://timeline.gd")
const Session = preload("res://addons/juce_bridge/api/audio_session.gd")
var session: AudioSession
var ready_audio := false
var status: Label
var time_label: Label
var device_list: OptionButton
var picker: FileDialog
var project_picker: FileDialog
var master_slider: HSlider
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
  var error: String = session.select_output_device(device_list.get_item_text(index))
  status.text = "Output changed." if error.is_empty() else error)
 var controls := HBoxContainer.new()
 panel.add_child(controls)
 transport.append(_button(controls, "Play", func(): session.play()))
 transport.append(_button(controls, "Pause", func(): session.pause()))
 transport.append(_button(controls, "Stop", func(): session.stop()))
 add_button = _button(controls, "Add track", _add_track)
 _button(controls, "Open project…", func(): _project_dialog(false))
 _button(controls, "Save project…", func(): _project_dialog(true))
 time_label = _label(controls, "0.00 / 0.00 seconds")
 seek_slider = _slider(panel, 0, 10, 0, func(value: float):
  if session and not syncing: session.seek(value))
 seek_slider.drag_started.connect(func(): seek_dragging = true)
 seek_slider.drag_ended.connect(func(_changed: bool): seek_dragging = false)
 var master := HBoxContainer.new()
 panel.add_child(master)
 _label(master, "Master")
 master_slider = _slider(master, 0, 1, 0.5, func(value: float):
  if session: session.master_volume = value)
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
  if ready_audio: session.seek(seconds))
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
 project_picker = FileDialog.new()
 project_picker.access = FileDialog.ACCESS_FILESYSTEM
 project_picker.filters = PackedStringArray(["*.gjproject ; Godot JUCE session"])
 add_child(project_picker)
 project_picker.file_selected.connect(func(path: String):
  if project_picker.file_mode == FileDialog.FILE_MODE_SAVE_FILE: _save_project(path)
  else: _open_project(path))
 session = Session.new()
 session.auto_initialize = false
 add_child(session)
 session.audio_error.connect(func(message: String): status.text = message)
 session.project_loaded.connect(func(_path: String): _rebuild_rows())
 session.playback_finished.connect(func(): status.text = "Playback finished.")
 var error: String = session.initialize()
 ready_audio = error.is_empty()
 for number in range(2):
  var track := session.add_track()
  if track: _create_row(track.index)
 for device in session.get_output_devices(): device_list.add_item(device)
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
 _label(header, session.tracks[track].track_name)
 var load_button := _button(header, "Open WAV…", func():
  selected_track = track
  picker.popup_centered_ratio(0.95))
 var audio := session.tracks[track]
 var name_label := _label(header, audio.file_path.get_file() if not audio.file_path.is_empty() else "Empty")
 name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
 _button(header, "Clear", func():
  var error: String = session.tracks[track].clear()
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
 offset.value = audio.offset
 offset.custom_minimum_size.x = 100
 controls.add_child(offset)
 offset.value_changed.connect(func(value: float):
  if not syncing: _move_clip(track, value))
 _label(controls, "Volume")
 _slider(controls, 0, 1, audio.volume, func(value: float): session.tracks[track].volume = value)
 _label(controls, "Pan L / R")
 _slider(controls, -1, 1, audio.pan, func(value: float): session.tracks[track].pan = value)
 for item in [["Mute", "muted"], ["Solo", "solo"]]:
  var toggle := CheckButton.new()
  toggle.text = item[0]
  toggle.button_pressed = audio.get(item[1])
  controls.add_child(toggle)
  toggle.toggled.connect(func(enabled: bool): session.tracks[track].set(item[1], enabled))
 var meter_l := _meter(controls)
 var meter_r := _meter(controls)
 var eq_controls := HBoxContainer.new()
 box.add_child(eq_controls)
 _label(eq_controls, "EQ (dB)")
 for band in [["Low 200 Hz", "low_gain_db"], ["Mid 1 kHz", "mid_gain_db"], ["High 6 kHz", "high_gain_db"]]:
  _label(eq_controls, band[0])
  var knob := SpinBox.new()
  knob.min_value = -18
  knob.max_value = 18
  knob.step = 0.1
  knob.value = audio.eq.get(band[1])
  eq_controls.add_child(knob)
  knob.value_changed.connect(func(value: float): session.tracks[track].eq.set(band[1], value))
 var bypass := CheckButton.new()
 bypass.text = "EQ bypass"
 bypass.button_pressed = audio.eq.bypassed
 eq_controls.add_child(bypass)
 bypass.toggled.connect(func(value: bool): session.tracks[track].eq.bypassed = value)
 rows.append({"name": name_label, "offset": offset, "load": load_button, "meters": [meter_l, meter_r]})

func _add_track() -> void:
 var track := session.add_track()
 if not track:
  status.text = "Track limit reached (16)."
  return
 _create_row(track.index)
 add_button.disabled = rows.size() >= 16
 _refresh_timeline()

func _load_file(path: String) -> void:
 var error: String = session.tracks[selected_track].load_wav(path)
 if error.is_empty():
  rows[selected_track].name.text = path.get_file()
  _refresh_timeline()
 status.text = "Loaded " + path.get_file() if error.is_empty() else error

func _move_clip(track: int, seconds: float) -> void:
 var error: String = session.tracks[track].set_offset(seconds)
 status.text = "Clip moved." if error.is_empty() else error
 _refresh_timeline()

func _refresh_timeline() -> void:
 syncing = true
 timeline.lengths.clear()
 timeline.offsets.clear()
 timeline.names.clear()
 for track in range(rows.size()):
  timeline.lengths.append(session.tracks[track].duration)
  timeline.offsets.append(session.tracks[track].offset)
  timeline.names.append(rows[track].name.text)
  rows[track].offset.value = session.tracks[track].offset
 timeline.span = maxf(10, session.duration * 1.15)
 timeline.custom_minimum_size.y = 28 + rows.size() * 38
 timeline.queue_redraw()
 seek_slider.max_value = maxf(0.001, session.duration)
 syncing = false

func _process(delta: float) -> void:
 if not session: return
 var levels: Vector2 = session.levels
 for channel in range(2): master_meters[channel].value = maxf(levels[channel], master_meters[channel].value - delta * 1.5)
 for track in range(rows.size()):
  var track_levels: Vector2 = session.tracks[track].levels
  for channel in range(2): rows[track].meters[channel].value = maxf(track_levels[channel], rows[track].meters[channel].value - delta * 1.5)
 var position: float = session.position
 timeline.playhead = position
 timeline.queue_redraw()
 syncing = true
 if not seek_dragging: seek_slider.value = position
 syncing = false
 time_label.text = "%.2f / %.2f seconds%s" % [position, session.duration, "  CLIPPING — lower master" if maxf(levels.x, levels.y) > 1 else ""]

func _exit_tree() -> void:
 if session:
  session.shutdown()

func _project_dialog(saving: bool) -> void:
 project_picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE if saving else FileDialog.FILE_MODE_OPEN_FILE
 project_picker.title = "Save session" if saving else "Open session"
 if saving: project_picker.current_file = "session.gjproject"
 project_picker.popup_centered_ratio(0.85)

func _save_project(path: String) -> void:
 if not path.ends_with(".gjproject"): path += ".gjproject"
 var error: String = session.save_project(path)
 status.text = "Saved " + path.get_file() if error.is_empty() else error

func _open_project(path: String) -> void:
 var error: String = session.load_project(path)
 ready_audio = session.audio_ready
 if not ready_audio: _unavailable(error)
 status.text = "Opened " + path.get_file() if error.is_empty() else error

func _rebuild_rows() -> void:
 for child in track_panel.get_children():
  track_panel.remove_child(child)
  child.queue_free()
 rows.clear()
 for track in session.tracks: _create_row(track.index)
 selected_track = 0
 master_slider.set_value_no_signal(session.master_volume)
 add_button.disabled = not ready_audio or rows.size() >= 16
 _refresh_timeline()
 if not ready_audio: _unavailable("Session loaded. Audio device is unavailable.")
