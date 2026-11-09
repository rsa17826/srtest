extends CanvasLayer
class_name ReplayViewer
# Add as a CanvasLayer node in the level scene (or add_child it from level.gd).
# F9 opens / closes it. Needs player.replay_buffer to be filled (record a run first).

@export var toggle_key: Key = KEY_F9

const FLY_SPEED := 10.0
const FLY_SENSITIVITY := 0.0025
const TELEPORT_DIST := 3.0 # frame-to-frame jump bigger than this = respawn, don't blend

# --- state ---
var player: Player
var active := false
var compiled := false
var positions := PackedVector3Array() # N+1 entries (every start_position + final end position)
var cam_rots := PackedVector3Array() # N+1 entries
var frame_time := 0.0 # seconds per frame
var playhead := 0.0 # in frames, fractional
var playing := false

# saved player state, restored on close
var saved_pos: Vector3
var saved_vel: Vector3
var saved_layer: int
var saved_cam_rot: Vector3
var saved_mouse_mode: Input.MouseMode

# free camera
var flying := false
var fly_cam: Camera3D
var player_cam: Camera3D
var fly_yaw := 0.0
var fly_pitch := 0.0
var fly_mult := 1.0
var marker: Node3D

# --- UI ---
var panel: PanelContainer
var slider: HSlider
var btn_compile: Button
var btn_back: Button
var btn_play: Button
var btn_fwd: Button
var btn_close: Button
var info: Label

func _ready() -> void:
  layer = 100
  player = global.player
  _build_ui()
  panel.hide()
  if Replays.pending_path != "":
    _open_pending.call_deferred() # wait until the player/level finished _ready

func _open_pending() -> void:
  var path := Replays.pending_path
  Replays.pending_path = ""
  open()
  player.replay_buffer = Replays.load_file(path)
  _compile()

func _go_menu() -> void:
  Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
  get_tree().change_scene_to_file(Replays.MENU_SCENE)

func _build_ui() -> void:
  panel = PanelContainer.new()
  var style := StyleBoxFlat.new()
  style.bg_color = Color(0.07, 0.07, 0.09, 0.92)
  style.set_content_margin_all(4)
  panel.add_theme_stylebox_override("panel", style)
  panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
  panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
  add_child(panel)

  var vbox := VBoxContainer.new()
  vbox.add_theme_constant_override("separation", 4)
  panel.add_child(vbox)

  slider = HSlider.new()
  slider.min_value = 0
  slider.max_value = 1
  slider.step = 0.001
  slider.editable = false
  slider.focus_mode = Control.FOCUS_NONE
  slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  slider.value_changed.connect(_on_slider_changed)
  vbox.add_child(slider)

  var row := HBoxContainer.new()
  row.add_theme_constant_override("separation", 4)
  vbox.add_child(row)

  btn_compile = _make_button("Compile", row, _compile)
  btn_back = _make_button("<", row, func(): _step(-1))
  btn_play = _make_button("Play", row, _toggle_play)
  btn_fwd = _make_button(">", row, func(): _step(1))

  info = Label.new()
  info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  row.add_child(info)

  btn_close = _make_button("Close", row, close)
  _make_button("Menu", row, _go_menu)
  _set_controls_enabled(false)
  _update_info()

func _make_button(text: String, parent: Control, callback: Callable) -> Button:
  var b := Button.new()
  b.text = text
  b.focus_mode = Control.FOCUS_NONE
  b.pressed.connect(callback)
  parent.add_child(b)
  return b

func _set_controls_enabled(on: bool) -> void:
  slider.editable = on
  btn_back.disabled = not on
  btn_play.disabled = not on
  btn_fwd.disabled = not on

# ---------------------------------------------------------------- open / close

func open() -> void:
  player = global.player
  assert(player != null, "ReplayViewer: no player")
  if player.current_mode == Player.ReplayMode.RECORDING:
    player.stop_recording()
  player.end_win()

  saved_pos = player.global_position
  saved_vel = player.velocity
  saved_layer = player.collision_layer
  saved_cam_rot = player.get_node("cam").rotation
  saved_mouse_mode = Input.mouse_mode

  player.current_mode = Player.ReplayMode.VIEWING
  player.velocity = Vector3.ZERO
  player.collision_layer = 0 # so goal / checkpoint Area3Ds don't fire while scrubbing

  var shape: CylinderShape3D = player.get_node("CollisionShape3D").shape
  marker = _make_marker(shape.radius, shape.height)
  marker.visible = false
  player.get_parent().add_child(marker)

  Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
  active = true
  panel.show()
  if compiled:
    _apply_playhead()
  _update_info()

func close() -> void:
  if flying:
    _stop_flight()
  playing = false
  btn_play.text = "Play"
  active = false
  panel.hide()
  marker.queue_free()
  marker = null

  player.collision_layer = saved_layer
  player.global_position = saved_pos
  player.velocity = saved_vel
  player.get_node("cam").rotation = saved_cam_rot
  player.current_mode = Player.ReplayMode.NORMAL
  Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _make_marker(radius: float, height: float) -> Node3D:
  var root := Node3D.new()
  var mat := StandardMaterial3D.new()
  mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
  mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
  mat.albedo_color = Color(0.3, 0.8, 1.0, 0.45)

  var body := MeshInstance3D.new()
  var capsule := CapsuleMesh.new()
  capsule.radius = radius
  capsule.height = height
  body.mesh = capsule
  body.material_override = mat
  root.add_child(body)

  var nose := MeshInstance3D.new()
  var box := BoxMesh.new()
  box.size = Vector3(radius, radius, radius)
  nose.mesh = box
  nose.material_override = mat
  nose.position = Vector3(0, height * 0.3, -radius) # -Z is forward
  root.add_child(nose)
  return root

# ---------------------------------------------------------------- compile

func _compile() -> void:
  var buf: Array = player.replay_buffer
  if buf.is_empty():
    info.text = "ERROR: player.replay_buffer is empty - record a run first"
    push_error("ReplayViewer: player.replay_buffer is empty")
    return

  var n := buf.size()
  positions.resize(n + 1)
  cam_rots.resize(n + 1)
  var total := 0.0
  for i in n:
    positions[i] = buf[i].start_position
    cam_rots[i] = buf[i].cam_rotation
    total += buf[i].delta
  # final point: where the last frame ended up
  positions[n] = buf[n - 1].expected_end_position
  cam_rots[n] = buf[n - 1].cam_rotation
  frame_time = total / n

  slider.max_value = n
  playhead = 0.0
  compiled = true
  _set_controls_enabled(true)
  _apply_playhead()
  _update_info()

# ---------------------------------------------------------------- playback

func _toggle_play() -> void:
  if playhead >= positions.size() - 1:
    playhead = 0.0
  playing = not playing
  btn_play.text = "Pause" if playing else "Play"

func _step(dir: int) -> void:
  playing = false
  btn_play.text = "Play"
  playhead = clampf(roundf(playhead) + dir, 0, positions.size() - 1)
  _apply_playhead()
  _update_info()

func _on_slider_changed(value: float) -> void:
  # only fires from user interaction (programmatic updates use set_value_no_signal)
  playhead = value
  _apply_playhead()
  _update_info()

func _process(delta: float) -> void:
  if not active: return
  if flying:
    _fly(delta)
  if compiled and playing:
    playhead += delta / frame_time
    var last := float(positions.size() - 1)
    if playhead >= last:
      playhead = last
      playing = false
      btn_play.text = "Play"
    _apply_playhead()
    _update_info()

func _apply_playhead() -> void:
  var i := int(floorf(playhead))
  var last := positions.size() - 1
  var pos: Vector3
  var rot: Vector3
  if i >= last:
    pos = positions[last]
    rot = cam_rots[last]
  else:
    var t := playhead - i
    var a := positions[i]
    var b := positions[i + 1]
    if a.distance_to(b) > TELEPORT_DIST:
      pos = a
    else:
      pos = a.lerp(b, t)
    var ra := cam_rots[i]
    var rb := cam_rots[i + 1]
    rot = Vector3(lerp_angle(ra.x, rb.x, t), lerp_angle(ra.y, rb.y, t), lerp_angle(ra.z, rb.z, t))

  player.global_position = pos
  player.get_node("cam").rotation = rot
  marker.global_position = pos
  marker.rotation.y = rot.y
  slider.set_value_no_signal(playhead)

func _update_info() -> void:
  if not compiled:
    info.text = "Not compiled (%d frames recorded)" % player.replay_buffer.size()
    return
  var last := positions.size() - 1
  info.text = "%s / %s   frame %d / %d" % [_fmt(playhead * frame_time), _fmt(last * frame_time), int(roundf(playhead)), last]

func _fmt(seconds: float) -> String:
  return "%d:%05.2f" % [int(seconds) / 60, fmod(seconds, 60.0)]

# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
  if event is InputEventKey and event.pressed and not event.echo and event.keycode == toggle_key:
    if active:
      close()
    else:
      open()
    get_viewport().set_input_as_handled()
    return
  if not active: return

  if event is InputEventMouseButton:
    if event.button_index == MOUSE_BUTTON_RIGHT:
      if event.pressed and not flying and not panel.get_global_rect().has_point(event.position):
        _start_flight()
      elif not event.pressed and flying:
        _stop_flight()
      get_viewport().set_input_as_handled()
      return
    if flying and event.pressed:
      if event.button_index == MOUSE_BUTTON_WHEEL_UP:
        fly_mult = clampf(fly_mult * 1.2, 0.1, 100.0)
      elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
        fly_mult = clampf(fly_mult / 1.2, 0.1, 100.0)
      get_viewport().set_input_as_handled()
      return

  if flying and event is InputEventMouseMotion:
    fly_yaw -= event.relative.x * FLY_SENSITIVITY
    fly_pitch = clampf(fly_pitch - event.relative.y * FLY_SENSITIVITY, -PI / 2 + 0.02, PI / 2 - 0.02)
    fly_cam.rotation = Vector3(fly_pitch, fly_yaw, 0)
    get_viewport().set_input_as_handled()
    return

  # keyboard shortcuts while not flying
  if not flying and compiled and event is InputEventKey and event.pressed:
    if event.keycode == KEY_SPACE and not event.echo:
      _toggle_play()
      get_viewport().set_input_as_handled()
    elif event.keycode == KEY_LEFT:
      _step(-1)
      get_viewport().set_input_as_handled()
    elif event.keycode == KEY_RIGHT:
      _step(1)
      get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- free camera

func _start_flight() -> void:
  player_cam = get_viewport().get_camera_3d()
  var src := player_cam
  fly_cam = Camera3D.new()
  fly_cam.fov = src.fov
  fly_cam.near = src.near
  fly_cam.far = src.far
  fly_cam.cull_mask = src.cull_mask
  player.get_parent().add_child(fly_cam)
  fly_cam.global_transform = src.global_transform
  fly_cam.make_current()

  var euler := fly_cam.global_transform.basis.get_euler()
  fly_pitch = euler.x
  fly_yaw = euler.y
  marker.visible = true
  flying = true
  Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _stop_flight() -> void:
  flying = false
  player_cam.make_current()
  fly_cam.queue_free()
  fly_cam = null
  marker.visible = false
  Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _fly(delta: float) -> void:
  # catch a missed release (e.g. focus lost while RMB was held)
  if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
    _stop_flight()
    return

  var forward := -fly_cam.global_transform.basis.z
  forward.y = 0
  forward = forward.normalized()
  var right := fly_cam.global_transform.basis.x
  right.y = 0
  right = right.normalized()

  var dir := Vector3.ZERO
  if Input.is_physical_key_pressed(KEY_W): dir += forward
  if Input.is_physical_key_pressed(KEY_S): dir -= forward
  if Input.is_physical_key_pressed(KEY_A): dir -= right
  if Input.is_physical_key_pressed(KEY_D): dir += right
  if Input.is_physical_key_pressed(KEY_SPACE): dir.y += 1.0
  if Input.is_physical_key_pressed(KEY_SHIFT): dir.y -= 1.0
  if dir == Vector3.ZERO: return

  # same feel as 3dmove: slower up close to the subject, faster far away
  var dist := maxf(0.5, fly_cam.global_position.distance_to(player.global_position))
  var speed := clampf(FLY_SPEED * dist * 0.08 * fly_mult, 0.5, 250.0)
  fly_cam.global_position += dir.normalized() * speed * delta
