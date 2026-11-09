extends Control
# Root script of res://scenes/level_select.tscn (a single Control node). Set it as the main scene.

var content: VBoxContainer

func _ready() -> void:
  Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
  set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  var bg := ColorRect.new()
  bg.color = Color(0.06, 0.06, 0.08)
  bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  add_child(bg)

  var scroll := ScrollContainer.new()
  scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  scroll.offset_left = 8
  scroll.offset_top = 8
  scroll.offset_right = -8
  scroll.offset_bottom = -8
  add_child(scroll)

  content = VBoxContainer.new()
  content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  content.add_theme_constant_override("separation", 4)
  scroll.add_child(content)
  _show_levels()

func _clear() -> void:
  for c in content.get_children():
    c.queue_free()

func _label(text: String, size := 16) -> Label:
  var l := Label.new()
  l.text = text
  l.add_theme_font_size_override("font_size", size)
  return l

func _button(text: String, callback: Callable) -> Button:
  var b := Button.new()
  b.text = text
  b.pressed.connect(callback)
  return b

func _show_levels() -> void:
  _clear()
  content.add_child(_label("Levels", 28))
  log.pp(Replays.list_levels())
  for path in Replays.list_levels():
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 4)
    content.add_child(row)

    var name := Replays.level_name_of(path)
    var play := _button(name, _play.bind(path))
    play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    play.alignment = HORIZONTAL_ALIGNMENT_LEFT
    row.add_child(play)

    var count := Replays.list_replays(name).size()
    var rep := _button("Replays (%d)" % count, _show_replays.bind(path))
    rep.disabled = count == 0
    row.add_child(rep)

func _show_replays(level_path: String) -> void:
  _clear()
  var level := Replays.level_name_of(level_path)
  content.add_child(_button("< Back", _show_levels))
  content.add_child(_label("Replays - " + level, 28))
  for replay in Replays.list_replays(level):
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 4)
    content.add_child(row)

    var watch := _button(Replays.pretty_name(replay), _watch.bind(level_path, replay))
    watch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    watch.alignment = HORIZONTAL_ALIGNMENT_LEFT
    row.add_child(watch)

    row.add_child(_button("Delete", _delete.bind(level_path, replay)))

func _play(level_path: String) -> void:
  Replays.pending_path = ""
  get_tree().change_scene_to_file(level_path)

func _watch(level_path: String, replay_path: String) -> void:
  Replays.pending_path = replay_path
  get_tree().change_scene_to_file(level_path)

func _delete(level_path: String, replay_path: String) -> void:
  var err := DirAccess.remove_absolute(replay_path)
  assert(err == OK, "couldn't delete %s (error %d)" % [replay_path, err])
  _show_replays(level_path)
