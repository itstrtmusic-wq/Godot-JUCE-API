extends Control
signal seek_requested(seconds: float)
signal clip_moved(track: int, seconds: float)

var lengths: Array[float] = []
var offsets: Array[float] = []
var names: Array[String] = []
var playhead := 0.0
var span := 10.0
var drag_track := -1
var drag_origin := Vector2.ZERO
var drag_offset := 0.0
var dragging := false
const LABEL_WIDTH := 95.0
const ROW_HEIGHT := 38.0
const TOP := 28.0

func time_at(x: float) -> float:
 return clampf((x - LABEL_WIDTH) / maxf(size.x - LABEL_WIDTH - 12, 1) * span, 0, span)

func x_at(seconds: float) -> float:
 return LABEL_WIDTH + seconds / span * maxf(size.x - LABEL_WIDTH - 12, 1)

func _draw() -> void:
 draw_rect(Rect2(Vector2.ZERO, size), Color("171d29"))
 var font := ThemeDB.fallback_font
 for tick in range(11):
  var seconds := span * tick / 10.0
  var x := x_at(seconds)
  draw_line(Vector2(x, TOP), Vector2(x, size.y), Color("303a4d"))
  draw_string(font, Vector2(x + 2, 18), "%.1fs" % seconds, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("a9b5cb"))
 for track in range(lengths.size()):
  var y := TOP + track * ROW_HEIGHT
  draw_string(font, Vector2(10, y + 24), "Track %d" % (track + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
  if lengths[track] > 0:
   var rect := Rect2(x_at(offsets[track]), y + 4, maxf(x_at(lengths[track]) - x_at(0), 3), ROW_HEIGHT - 8)
   draw_rect(rect, Color("327f98") if track % 2 == 0 else Color("6355a3"))
   draw_string(font, rect.position + Vector2(6, 20), names[track], HORIZONTAL_ALIGNMENT_LEFT, maxf(rect.size.x - 12, 0), 12)
 draw_line(Vector2(x_at(playhead), TOP), Vector2(x_at(playhead), size.y), Color("ffcf70"), 2)

func _gui_input(event: InputEvent) -> void:
 if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
  if event.pressed:
   drag_track = -1
   var track := int(floor((event.position.y - TOP) / ROW_HEIGHT))
   if track >= 0 and track < lengths.size() and lengths[track] > 0:
    var seconds := time_at(event.position.x)
    if seconds >= offsets[track] and seconds <= offsets[track] + lengths[track]:
     drag_track = track
     drag_offset = offsets[track]
   drag_origin = event.position
   dragging = false
  else:
   if dragging and drag_track >= 0:
    clip_moved.emit(drag_track, offsets[drag_track])
   elif event.position.x >= LABEL_WIDTH:
    seek_requested.emit(time_at(event.position.x))
   drag_track = -1
   dragging = false
  accept_event()
 if event is InputEventMouseMotion and drag_track >= 0 and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
  if event.position.distance_to(drag_origin) > 4: dragging = true
  if dragging:
   offsets[drag_track] = clampf(drag_offset + (event.position.x - drag_origin.x) / maxf(size.x - LABEL_WIDTH - 12, 1) * span, 0, 86400)
   queue_redraw()
  accept_event()
