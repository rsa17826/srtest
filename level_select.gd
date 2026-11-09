extends Control
# Root script of res://scenes/level_select.tscn (a single Control node). Set it as the main scene.

var content: VBoxContainer
var header: VBoxContainer
var window: PanelContainer

func _ready() -> void:
  theme = SystemUI.theme()
  Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
  set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

  var center := CenterContainer.new()
  center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  add_child(center)

  window = PanelContainer.new()
  center.add_child(window)
  SystemUI.add_brackets(window)

  var vbox := VBoxContainer.new()
  vbox.add_theme_constant_override("separation", 6)
  window.add_child(vbox)

  header = SystemUI.header("")
  vbox.add_child(header)

  var scroll := ScrollContainer.new()
  scroll.custom_minimum_size = Vector2(520, 340)
  scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
  vbox.add_child(scroll)

  content = VBoxContainer.new()
  content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  content.add_theme_constant_override("separation", 3)
  scroll.add_child(content)

  vbox.add_child(SystemUI.dim_label("REPLAYS ARE SAVED TO user://replays/<level>/"))
  _show_levels()
  SystemUI.fade_in(window)

func _clear() -> void:
  for c in content.get_children():
    c.queue_free()

func _button(text: String, callback: Callable) -> Button:
  var b := Button.new()
  b.text = text
  b.pressed.connect(callback)
  return b

func _row_button(text: String, callback: Callable) -> Button:
  var b := _button("> " + text, callback)
  b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  b.alignment = HORIZONTAL_ALIGNMENT_LEFT
  return b

func _show_levels() -> void:
  _clear()
  SystemUI.set_title(header, "Level Select")
  for path in Replays.list_levels():
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 3)
    content.add_child(row)

    var level := Replays.level_name_of(path)
    row.add_child(_row_button(level, _play.bind(path)))

    var count := Replays.list_replays(level).size()
    var rep := _button("REPLAYS [%d]" % count, _show_replays.bind(path))
    rep.disabled = count == 0
    row.add_child(rep)

func _show_replays(level_path: String) -> void:
  _clear()
  var level := Replays.level_name_of(level_path)
  SystemUI.set_title(header, "Replays :: " + level)
  content.add_child(_button("< BACK", _show_levels))
  for replay in Replays.list_replays(level):
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 3)
    content.add_child(row)

    row.add_child(_row_button(Replays.pretty_name(replay), _watch.bind(level_path, replay)))
    var del := _button("DELETE", _delete.bind(level_path, replay))
    SystemUI.make_danger(del)
    row.add_child(del)

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
