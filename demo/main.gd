extends Control

var engine: Object
var status: Label
var time_label: Label
var device_list: OptionButton
var meters: Array[ProgressBar] = []
var picker: FileDialog
var play_button: Button
var pause_button: Button
var stop_button: Button

func _ready() -> void:
 var panel := VBoxContainer.new()
 panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 panel.add_theme_constant_override("separation", 18)
 var margin := MarginContainer.new()
 margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for side in ["left", "top", "right", "bottom"]:
  margin.add_theme_constant_override("margin_" + side, 32)
 add_child(margin)
 margin.add_child(panel)
 var title := Label.new()
 title.text = "GODOT × JUCE  /  Audio Bridge"
 title.add_theme_font_size_override("font_size", 28)
 panel.add_child(title)
 status = Label.new()
 status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 panel.add_child(status)
 device_list = OptionButton.new()
 panel.add_child(device_list)
 device_list.item_selected.connect(_select_device)
 var load_button := Button.new()
 load_button.text = "Open WAV…"
 panel.add_child(load_button)
 picker = FileDialog.new()
 picker.access = FileDialog.ACCESS_FILESYSTEM
 picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
 picker.filters = PackedStringArray(["*.wav ; WAV audio"])
 add_child(picker)
 load_button.pressed.connect(func(): picker.popup_centered_ratio(0.8))
 picker.file_selected.connect(_load_file)
 var transport := HBoxContainer.new()
 panel.add_child(transport)
 play_button = _button(transport, "Play", func(): engine.call("play"))
 pause_button = _button(transport, "Pause", func(): engine.call("pause"))
 stop_button = _button(transport, "Stop", func(): engine.call("stop"))
 _enable_transport(false)
 var volume_label := Label.new()
 volume_label.text = "Output volume"
 panel.add_child(volume_label)
 var volume := HSlider.new()
 volume.min_value = 0.0
 volume.max_value = 1.0
 volume.step = 0.001
 volume.value = 0.5
 panel.add_child(volume)
 volume.value_changed.connect(func(value: float):
  if engine: engine.call("set_volume", value))
 for channel in ["Left", "Right"]:
  var label := Label.new()
  label.text = channel
  panel.add_child(label)
  var meter := ProgressBar.new()
  meter.max_value = 1.0
  meter.show_percentage = false
  panel.add_child(meter)
  meters.append(meter)
 time_label = Label.new()
 panel.add_child(time_label)
 if not ClassDB.class_exists("JuceEngine"):
  status.text = "Native engine missing. Build the GDExtension using the README, then reopen Godot."
  device_list.disabled = true
  load_button.disabled = true
  return
 engine = ClassDB.instantiate("JuceEngine")
 var error: String = engine.call("initialize")
 if not error.is_empty():
  status.text = "Audio initialization failed: " + error
  load_button.disabled = true
  return
 status.text = "Audio ready. Open a mono or stereo WAV file."
 for device in engine.call("get_output_devices"):
  device_list.add_item(device)
 device_list.select(-1)
 device_list.text = "Select output device (currently system default)"

func _button(parent: Node, text: String, callback: Callable) -> Button:
 var button := Button.new()
 button.text = text
 button.pressed.connect(callback)
 parent.add_child(button)
 return button

func _enable_transport(enabled: bool) -> void:
 for button in [play_button, pause_button, stop_button]:
  button.disabled = not enabled

func _select_device(index: int) -> void:
 var error: String = engine.call("select_output_device", device_list.get_item_text(index))
 status.text = "Output changed." if error.is_empty() else "Device error: " + error

func _load_file(path: String) -> void:
 var error: String = engine.call("load_wav", path)
 status.text = path.get_file() if error.is_empty() else error
 if error.is_empty(): _enable_transport(true)

func _process(delta: float) -> void:
 if not engine: return
 var levels: Vector2 = engine.call("get_levels")
 for i in range(2):
  meters[i].value = maxf(levels[i], meters[i].value - delta * 1.5)
 time_label.text = "%.2f / %.2f seconds" % [engine.call("get_position"), engine.call("get_duration")]

func _exit_tree() -> void:
 if engine:
  engine.call("shutdown")
  engine = null
