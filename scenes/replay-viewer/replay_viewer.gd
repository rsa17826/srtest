extends CanvasLayer
class_name ReplayViewer
# Add as a CanvasLayer node in the level scene (or add_child it from level.gd).
# F9 opens / closes it. Needs player.replay_buffer to be filled (record a run first).

@export var toggle_key: Key = KEY_F9

const FLY_SPEED := 16.0
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
var saved_state := {}
var first_diverge := -1 # first frame where the resimulation leaves the recorded path

# checkpoints (level.checkpoints = [{"area": Area3D, "pane": MeshInstance3D}, ...])
var cps: Array
var cp_first: Array[int] = [] # first frame each checkpoint is touched, -1 = never
var cp_state: Array[bool] = [] # currently shown as collected?
var cp_tweens := {}

# grenades, as seen by the resimulation: per frame, an Array of Vector4(x, y, z, fuse 0..1)
const GRENADE_SCENE := preload("res://scenes/grenade/main.tscn")
var grenade_frames: Array = []
var ghosts: Array[Grenade] = []
var saved_cp: Array[float] = []

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
  panel.theme = SystemUI.theme()
  SystemUI.add_brackets(panel)
  SystemUI.pulse(panel)
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
  info.add_theme_color_override("font_color", SystemUI.CYAN)
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
    player.abort_recording()
  player.end_win()

  saved_pos = player.global_position
  saved_vel = player.velocity
  saved_layer = player.collision_layer
  saved_cam_rot = player.get_node("cam").rotation
  saved_mouse_mode = Input.mouse_mode
  saved_state = {
    "speed": player.currentUserMoveSpeed, "jump": player.currentUserJumpHeight,
    "jumps": player.jumps, "kt": player.kt, "trypress": player.trypress.jump,
    "fake_rot": player.get_node("fake_cam").rotation,
    "cp_pos": player.cpPos,
  }

  cps = global.level.checkpoints
  saved_cp.clear()
  cp_state.clear()
  for cp in cps:
    saved_cp.append(cp.pane.get_instance_shader_parameter("collected"))
    cp.pane.set_instance_shader_parameter("collected", 0.0) # viewer drives them from here
    cp_state.append(false)

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
  if len(cps) != len(saved_cp):
    cps = global.level.checkpoints
    saved_cp.clear()
    cp_state.clear()
    for cp in cps:
      saved_cp.append(cp.pane.get_instance_shader_parameter("collected"))
      cp.pane.set_instance_shader_parameter("collected", 0.0) # viewer drives them from here
      cp_state.append(false)
  playing = false
  btn_play.text = "Play"
  active = false
  _free_ghosts()
  panel.hide()
  marker.queue_free()
  marker = null

  for c in cps.size():
    if cp_tweens.has(c):
      cp_tweens[c].kill()
    cps[c].pane.set_instance_shader_parameter("collected", saved_cp[c])
  cp_tweens.clear()
  player.collision_layer = saved_layer
  player.global_position = saved_pos
  player.velocity = saved_vel
  player.get_node("cam").rotation = saved_cam_rot
  player.get_node("fake_cam").rotation = saved_state.fake_rot
  player.currentUserMoveSpeed = saved_state.speed
  player.currentUserJumpHeight = saved_state.jump
  player.jumps = saved_state.jumps
  player.kt = saved_state.kt
  player.trypress.jump = saved_state.trypress
  player.cpPos = saved_state.cp_pos
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

# move_and_slide() uses the *render* frame delta when it isn't called from a physics frame, which makes
# every simulated step slightly (or wildly) the wrong length. So the actual work runs in _physics_process.
var compile_requested := false

func _compile() -> void:
  compiled = false
  playing = false
  btn_play.text = "Play"
  _set_controls_enabled(false)
  info.text = "Compiling..."
  compile_requested = true

func _physics_process(_delta: float) -> void:
  if compile_requested:
    compile_requested = false
    _do_compile()

func _do_compile() -> void:
  var buf: Array = player.replay_buffer
  if buf.is_empty():
    info.text = "ERROR: player.replay_buffer is empty - record a run first"
    push_error("ReplayViewer: player.replay_buffer is empty")
    return

  var n := buf.size()
  positions.resize(n + 1)
  cam_rots.resize(n + 1)
  var total := 0.0
  for f in buf:
    total += f.delta
  _simulate(buf)
  frame_time = total / n
  _find_checkpoint_frames()

  slider.max_value = n
  playhead = 0.0
  compiled = true
  _set_controls_enabled(true)
  _apply_playhead()
  _update_info()

# ---------------------------------------------------------------- resimulation
# Rebuilds the path by re-running the player's own physics step (Player.step) from the recorded
# *inputs* only: input_dir, trypress_jump, camera rotations, restart. Positions/velocities stored in
# the replay are used for frame 0 and for the "differs from recording" check, never to place the player.

func _simulate(buf: Array) -> void:
  assert(Engine.is_in_physics_frame(), "_simulate must run inside _physics_process (move_and_slide delta)")
  assert(Engine.physics_ticks_per_second == 60, "resimulation assumes 60 physics ticks per second")
  var n := buf.size()
  var cam: Node3D = player.get_node("cam")
  var fake: Node3D = player.get_node("fake_cam")
  var first = buf[0]

  # refresh floor / wall flags at the start position (a zero-velocity slide touches nothing)
  player.global_position = first.start_position
  player.velocity = Vector3.ZERO
  player.move_and_slide()

  player.global_position = first.start_position
  player.velocity = first.velocity
  player.currentUserMoveSpeed = first.currentUserMoveSpeed
  player.currentUserJumpHeight = first.currentUserJumpHeight
  player.jumps = first.jumps
  player.kt = first.kt

  first_diverge = -1
  player.clear_grenades()
  grenade_frames.clear()
  grenade_frames.resize(n)
  var lastf = null
  for i in n:
    var f = buf[i]
    assert(is_equal_approx(f.delta, 1.0 / 60.0), "frame %d: delta isn't 1/60" % i)
    cam_rots[i] = f.cam_rotation
    cam.rotation = f.cam_rotation
    fake.rotation = f.fake_cam_rotation
    if f.winning:
      # the win animation is scripted (rises, snaps to the goal), so take it from the recording
      player.global_position = f.start_position
      positions[i] = f.start_position
      grenade_frames[i] = []
      continue
    player.cpPos = f.cp_pos # checkpoints are not re-derived; respawns use the recorded one
    player.pending_restart = f.restart
    player.pending_grenade = f.pending_grenade
    positions[i] = player.global_position
    player.trypress.jump = f.trypress_jump
    player.step(f.delta, f.input_dir)
    var snap: Array = []
    for g in player.grenades:
      snap.append(Vector4(g.global_position.x, g.global_position.y, g.global_position.z, float(g.ticks) / Grenade.FUSE_TICKS))
    grenade_frames[i] = snap
    if first_diverge == -1 and player.global_position.distance_to(f.expected_end_position) > 0:
      log.pp(player.global_position.distance_to(f.expected_end_position), i)
      log.pp("on_floor:", player.is_on_floor(), "slide collisions:", player.get_slide_collision_count())
      log.pp(lastf, f)
      first_diverge = i
    lastf = f
  positions[n] = buf[n - 1].expected_end_position if buf[n - 1].winning else player.global_position
  cam_rots[n] = buf[n - 1].cam_rotation
  player.clear_grenades() # the resimulation's grenades were only needed for their effect on the player

# ---------------------------------------------------------------- grenades
# Frame i's snapshot is the state at the END of frame i, i.e. what the player sees at playhead i + 1.

func _show_grenades() -> void:
  var j := int(roundf(playhead)) - 1
  var snap: Array = grenade_frames[j] if j >= 0 else []
  while ghosts.size() < snap.size():
    var gh: Grenade = GRENADE_SCENE.instantiate()
    player.get_parent().add_child(gh)
    ghosts.append(gh)
  for k in ghosts.size():
    ghosts[k].visible = k < snap.size()
    if k < snap.size():
      ghosts[k].global_position = Vector3(snap[k].x, snap[k].y, snap[k].z)
      ghosts[k].mesh.set_instance_shader_parameter("fuse", snap[k].w)

func _free_ghosts() -> void:
  for gh in ghosts:
    gh.queue_free()
  ghosts.clear()

# ---------------------------------------------------------------- checkpoints
# Player collision is off while viewing, so Area3Ds never fire. Instead, find the frame at
# which the recorded path first overlaps each checkpoint area, then derive the state from the playhead.

func _find_checkpoint_frames() -> void:
  cp_first.clear()
  cp_first.resize(cps.size())
  cp_first.fill(-1)
  var space := player.get_world_3d().direct_space_state
  var shape_node: CollisionShape3D = player.get_node("CollisionShape3D")
  var q := PhysicsShapeQueryParameters3D.new()
  q.shape = shape_node.shape
  q.collide_with_areas = true
  q.collide_with_bodies = false
  q.collision_mask = 0xFFFFFFFF
  var remaining := cps.size()
  for i in positions.size():
    if remaining == 0: break
    q.transform = Transform3D(Basis.IDENTITY, positions[i]) * shape_node.transform
    for hit in space.intersect_shape(q, 32):
      for c in cps.size():
        if cp_first[c] == -1 and hit.collider == cps[c].area:
          cp_first[c] = i
          remaining -= 1

func _apply_checkpoints() -> void:
  for c in cps.size():
    var want: bool = cp_first[c] != -1 and playhead >= cp_first[c]
    if want == cp_state[c]: continue
    cp_state[c] = want
    var pane: MeshInstance3D = cps[c].pane
    if cp_tweens.has(c):
      cp_tweens[c].kill()
    if want and playing: # collected during normal playback: play the wipe
      var tw := create_tween()
      tw.tween_method(func(v: float): pane.set_instance_shader_parameter("collected", v), 0.0, 1.0, 0.6)
      cp_tweens[c] = tw
    else: # seeking / stepping: snap
      pane.set_instance_shader_parameter("collected", 1.0 if want else 0.0)

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
  _show_grenades()
  _apply_checkpoints()

func _update_info() -> void:
  if not compiled:
    info.text = "Not compiled (%d frames recorded)" % player.replay_buffer.size()
    return
  var last := positions.size() - 1
  var text := "%s / %s   frame %d / %d" % [_fmt(playhead * frame_time), _fmt(last * frame_time), int(roundf(playhead)), last]
  if first_diverge == -1:
    text += "  |  matches recording"
  else:
    text += "  |  differs from recording at frame %d" % first_diverge
  info.text = text

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
    fly_yaw -= event.relative.x * global.player.MOUSE_SENSITIVITY
    fly_pitch = clampf(fly_pitch - event.relative.y * global.player.MOUSE_SENSITIVITY, -PI / 2 + 0.02, PI / 2 - 0.02)
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

  var speed := clampf(FLY_SPEED * fly_mult, 0.5, 250.0)
  fly_cam.global_position += dir.normalized() * speed * delta
