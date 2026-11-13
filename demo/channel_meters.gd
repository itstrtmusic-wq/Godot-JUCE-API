@tool
extends ProgressBar
class_name ChannelMeter


@export_group("Meter Colors")
@export var low_color: Color = Color.GREEN
@export var medium_color: Color = Color.YELLOW
@export var high_color: Color = Color.RED

@export_group("Thresholds")
@export_range(0.0, 1.0) var medium_threshold: float = 0.6
@export_range(0.0, 1.0) var high_threshold: float = 0.9

@export_group("Animation")
@export var transition_duration: float = 0.7


var _fill_style: StyleBoxFlat
var _color_tween: Tween


func _ready() -> void:
	_fill_style = get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	add_theme_stylebox_override("fill", _fill_style)

	value_changed.connect(_on_value_changed)
	_update_color(value, true)
	show_percentage = false
	custom_minimum_size.y = 220
	custom_minimum_size.x = 4
	fill_mode = FillMode.FILL_BOTTOM_TO_TOP


func _on_value_changed(new_value: float) -> void:
	_update_color(new_value)


func _update_color(
	new_value: float,
	instant: bool = false
) -> void:
	if not is_instance_valid(_fill_style):
		return

	var normalized_value: float = clampf(
		inverse_lerp(min_value, max_value, new_value),
		0.0,
		1.0
	)

	var target_color: Color

	if normalized_value >= high_threshold:
		target_color = high_color
	elif normalized_value >= medium_threshold:
		target_color = medium_color
	else:
		target_color = low_color

	if _color_tween and _color_tween.is_running():
		_color_tween.kill()

	if instant or transition_duration <= 0.0:
		_fill_style.bg_color = target_color
		return

	_color_tween = create_tween()
	_color_tween.set_trans(Tween.TRANS_SINE)
	_color_tween.set_ease(Tween.EASE_OUT)

	_color_tween.tween_property(
		_fill_style,
		"bg_color",
		target_color,
		transition_duration
	)
