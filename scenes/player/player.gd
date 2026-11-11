extends CharacterBody3D
class_name Player

const USER_MOVE_SPEED = 5.5
const GRENADE_BLAST_SPEED_BOOST = 4
const JUMP_SPEED_BOOST = 1.5
const JUMP_VEL = 10.4
var MAX_JUMPS = 1
const MAX_KT = 5
var MOUSE_SENSITIVITY: float = 0.009
var KEY_MAX_BUFFER: int = 15

const downgravity: float = 35
const upgravity: float = 22
var currentUserMoveSpeed: float = 0
var currentUserJumpHeight: float = 0
var lastGrenadeTick: float = -999
var tickCount: int = 0
var levelStarted: bool = false

var cpPos := Vector3.ZERO

var winning := false
var win_fx: MeshInstance3D
var win_mat: ShaderMaterial
var win_fade := 0.0
var win_cell: Vector3i
var win_item := GridMap.INVALID_CELL_ITEM
var win_orient := 0
var win_spin := 0.0 # extra rotation so far, in turns
var win_startY := 0.0 # extra rotation so far, in turns
var win_spin_rate := 0.0 # extra turns per second, ramps up
var winTimer := 0.0 # extra turns per second, ramps up

# --- REPLAY SYSTEM VARIABLES ---
enum ReplayMode {NORMAL, RECORDING, REPLAYING, VIEWING}
var current_mode = ReplayMode.NORMAL
var replay_buffer: Array = []
var replay_frame_index: int = 0
var pending_restart := false # restart pressed since the last recorded frame
var pending_grenade_spawn := false
var pending_grenade_explode := false
var canUseGrenade := false
var active_grenade: Grenade
const DESYNC_THRESHOLD: float = 0.001
# -------------------------------
func _init() -> void:
  global.player = self

var onTick: Array[Callable] = []

@onready var grid: GridMap = global.level.gridmap
func getTileId(name):
  var id := grid.mesh_library.find_item_by_name(name)
  assert(id != -1, "tile " + name + " missing from mesh library")
  return id
@onready var hazard_ids := [
  getTileId("spiky floor"),
  getTileId("spiky box"),
  # getTileId("spiky ball"),
]
# @onready var playerHeight = $CollisionShape3D.shape.height / 2
# @onready var playerWidth = $CollisionShape3D.shape.radius / 2

func _ready():
  assert(not -1 in hazard_ids, "hazard tile name missing from mesh library")
  fullReset()
  if global.canCaptureMouse:
    Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func touching_hazard() -> bool:
  for i in get_slide_collision_count():
    var col := get_slide_collision(i)
    if col.get_collider() != grid: continue
    # step a little *into* the surface so the point lands in the tile we hit
    var cell := grid.local_to_map(grid.to_local(col.get_position() - col.get_normal() * 0.05))
    if grid.get_cell_item(cell) in hazard_ids: return true
  return false

var jumps := 0
var kt: float = MAX_KT

var trypress = {
  "jump": 0,
}
func pressed(key):
  return !!trypress[key]
func unpress(key): return
  # trypress[key] = 0
func press(key):
  trypress[key] = KEY_MAX_BUFFER

func _input(event):
  if current_mode == ReplayMode.VIEWING: return

  if event is InputEventMouseButton and global.canCaptureMouse:
    Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
  if event is InputEventMouseMotion:
    $cam.rotation.y += -event.relative.x * MOUSE_SENSITIVITY
    $cam.rotation.x += -event.relative.y * MOUSE_SENSITIVITY
    var cap := 89.99
    if $cam.rotation_degrees.x > cap:
      $cam.rotation_degrees.x = cap
    if $cam.rotation_degrees.x < -cap:
      $cam.rotation_degrees.x = - cap
    $fake_cam.rotation = $cam.rotation
    $fake_cam.rotation.x = 0

@onready var startPos = position

func die():
  end_win()
  pending_restart = false
  position = cpPos
  currentUserMoveSpeed = 0
  currentUserJumpHeight = 0
  velocity = Vector3.ZERO

func fullReset():
  end_win()
  clear_grenades()
  tickCount = 0
  position = startPos
  pending_restart = false
  pending_grenade_spawn = false
  pending_grenade_explode = false
  cpPos = startPos
  velocity = Vector3.ZERO
  currentUserMoveSpeed = 0
  currentUserJumpHeight = 0
  lastGrenadeTick = -999
  levelStarted = false
  abort_recording()

func _unhandled_input(event):
  if current_mode == ReplayMode.VIEWING: return
  # inputs only raise flags; step() acts on them, so live play and resimulation do the same thing
  if not levelStarted:
    var found = false
    for k in [&"forward", &"back", &"left", &"right", &"jump", &"restart", &"explode_grenade", &"full_restart", &"spawn_grenade", ]:
      if event.is_action_pressed(k):
        levelStarted = true
        start_recording()
        found = true
        break
    if not found: return
  if event.is_action_pressed("full_restart"):
    fullReset()
  elif event.is_action_pressed("restart"):
    pending_restart = true
  if event.is_action_pressed("spawn_grenade"):
    pending_grenade_spawn = true
  elif event.is_action_released("spawn_grenade"):
    pending_grenade_spawn = false
  if event.is_action_pressed("explode_grenade"):
    pending_grenade_explode = true
  elif event.is_action_released("explode_grenade"):
    pending_grenade_explode = false
  # if event.is_action_pressed("ui_focus_next"):
  #   if current_mode == ReplayMode.NORMAL:
  #     position = Vector3.ZERO
  #     velocity = Vector3.ZERO
  #     start_recording()
  #   elif current_mode == ReplayMode.RECORDING:
  #     stop_recording()
  # if event.is_action_pressed("ui_accept") and current_mode == ReplayMode.NORMAL:
  #   start_replay()

func dojump():
  velocity.y = currentUserJumpHeight
  # currentUserMoveSpeed += JUMP_SPEED_BOOST
  unpress("jump")
  jumps -= 1

func updatetrypress(has2: Array, delta):
  for thing in trypress.keys():
    # if trypress[thing] > 0:
    #   trypress[thing] -= 60 * delta
    if thing in has2:
      if Input.is_action_just_pressed(thing) or Input.is_action_just_pressed(thing + '2'):
        trypress[thing] = KEY_MAX_BUFFER
      if !(Input.is_action_pressed(thing) or Input.is_action_pressed(thing + '2')):
        trypress[thing] = 0
      if Input.is_action_just_released(thing):
        trypress[thing] = 0
      if Input.is_action_just_released(thing + "2"):
        trypress[thing] = 0
    else:
      if Input.is_action_just_pressed(thing):
        trypress[thing] = KEY_MAX_BUFFER
      if !Input.is_action_pressed(thing):
        trypress[thing] = 0
      if Input.is_action_just_released(thing):
        trypress[thing] = 0

# --- REPLAY SYSTEM HELPER FUNCTIONS ---

func start_recording():
  replay_buffer.clear()
  pending_restart = false
  replay_frame_index = 0
  current_mode = ReplayMode.RECORDING
  log.pp("--- RECORDING STARTED ---")

func stop_recording():
  current_mode = ReplayMode.NORMAL
  log.pp("--- RECORDING STOPPED (Frames recorded: ", replay_buffer.size(), ") ---")
  var path := Replays.save(Replays.current_level_name(), replay_buffer)
  levelStarted = false
  log.pp("Saved replay to ", path)

func abort_recording():
  current_mode = ReplayMode.NORMAL

func _physics_process(delta: float) -> void:
  if not levelStarted: return
  delta = 1 / 60.0
  var input_dir := Vector2.ZERO
  if current_mode == ReplayMode.VIEWING: return # first line, before `if winning:`
  run_on_tick()
  if winning:
    winTimer += delta
    win_fade = global.rerange(winTimer, 0, 1, 0, 8)
    if current_mode == ReplayMode.RECORDING:
      record_frame(delta, input_dir)
    win_spin = global.rerange_clamp(winTimer, 0, 1, -.05, -4)
    win_mat.set_shader_parameter("top_fade", win_fade)
    win_mat.set_shader_parameter("intensity", global.rerange_clamp(winTimer, 0, .75, 1.5, 0))
    win_mat.set_shader_parameter("spin_offset", win_spin)
    global_position.y = win_startY + global.rerange_clamp(winTimer, 0, 1, 0, 10)
    if current_mode == ReplayMode.RECORDING:
      replay_buffer[replay_frame_index].expected_end_position = global_position # was left at (0,0,0)
      replay_frame_index += 1
    if winTimer >= 1:
      stop_recording()
      end_win()
    return
  var has2 = []

  updatetrypress(has2, delta)
  input_dir = Input.get_vector("left", "right", "forward", "back")

  # --- 2. SNAPSHOT: after inputs update, before movement math alters anything ---
  if current_mode == ReplayMode.RECORDING:
    record_frame(delta, input_dir)

  # --- 3. MOVEMENT (shared with the replay viewer's resimulation) ---
  step(delta, input_dir)

  # --- 4. POST-FRAME ---
  if current_mode == ReplayMode.RECORDING:
    replay_buffer[replay_frame_index].expected_end_position = global_transform.origin
    replay_frame_index += 1 # also runs on a hazard death, so frames stay aligned

# Effects queued by area triggers (die, speed zone, ...). Runs at the very start of a tick, before the
# frame is recorded; ReplayViewer calls it at the same point of every simulated tick.
func run_on_tick() -> void:
  while len(onTick):
    onTick.pop_front().call()

func spawnGrenade() -> void:
  var g: Grenade = preload("res://scenes/grenade/main.tscn").instantiate()
  get_parent().add_child(g) # not a child of the player, or it would move with it
  g.global_position = $cam.global_position
  g.velocity = -$cam.global_transform.basis.z * Grenade.THROW_SPEED + velocity
  g.add_collision_exception_with(self)
  g.predict_fuse_ticks(1.0 / 60.0, [get_rid()])
  active_grenade = g
  g.tick(1 / 60.0)

# Every grenade advances exactly once per player step, with the same fixed delta, so grenade
# state is a pure function of the recorded inputs. Anything a grenade does to the player
# (blast knockback) happens here, before the player's own movement for this tick.
func tick_grenades(delta: float, explode: bool) -> void:
  if active_grenade == null: return
  active_grenade.tick(delta)
  if explode:
    var off: Vector3 = global_position - active_grenade.global_position
    var dist := off.length()
    if dist < Grenade.BLAST_RADIUS:
      var dir := off.normalized()

      # -1 = running into the blast, 0 = sideways or standing still, +1 = running away from it
      var along := 0.0
      if velocity.length() > 0.1:
        along = velocity.normalized().dot(dir)
      var scale: float = clamp(remap(along, -1.0, 1.0, -1, 1 * 2), -1, 1)

      var boost := dir * Grenade.BLAST_FORCE
      for axis in 3:
        if velocity[axis] * boost[axis] < 0.0:
          velocity[axis] = boost[axis] # opposing: cancel what you had and set it
        else:
          velocity[axis] += boost[axis] # same direction (or at rest): stack
      var horizontal := Vector2(dir.x, dir.z).length()
      currentUserMoveSpeed += horizontal * GRENADE_BLAST_SPEED_BOOST * scale
    active_grenade.free()
    active_grenade = null

func clear_grenades() -> void:
  if active_grenade != null:
    active_grenade.free()
    active_grenade = null

# One fixed physics step. Everything it depends on is either player state or an argument
# (input_dir, trypress.jump, $fake_cam rotation), so ReplayViewer can re-run it from recorded inputs.
func step(delta: float, input_dir: Vector2) -> void:
  tickCount += 1
  if pending_restart:
    die()
    return
  if pending_grenade_spawn:
    if tickCount - lastGrenadeTick > 30 and canUseGrenade:
      canUseGrenade = false
      lastGrenadeTick = tickCount
      pending_grenade_spawn = false
      if active_grenade != null:
        clear_grenades()
      spawnGrenade()
  if pending_grenade_explode:
    pending_grenade_explode = false
    if active_grenade != null:
      tick_grenades(delta, true)
  tick_grenades(delta, false)
  if is_on_floor():
    kt = MAX_KT
    jumps = MAX_JUMPS
    velocity.y = 0
  else:
    var gravity = downgravity if velocity.y < 0 else upgravity
    velocity.y -= gravity * delta
    if kt > 0:
      kt -= 60 * delta
    if jumps == MAX_JUMPS and kt <= 0:
      jumps = MAX_JUMPS - 1

  if USER_MOVE_SPEED > currentUserMoveSpeed:
    currentUserMoveSpeed = USER_MOVE_SPEED
  if JUMP_VEL > currentUserJumpHeight:
    currentUserJumpHeight = JUMP_VEL

  if jumps > 0:
    if pressed("jump"):
      if velocity.y <= 1:
        dojump()
      elif trypress.jump <= 1:
        dojump()
    else:
      currentUserJumpHeight = 0

  var movedir = Vector3(input_dir.x, 0, input_dir.y)
  var camdir = $fake_cam.transform.basis
  var direction = (camdir * movedir).normalized()

  if direction:
    velocity.x = direction.x * currentUserMoveSpeed
    velocity.z = direction.z * currentUserMoveSpeed
  else:
    velocity.x = move_toward(velocity.x, 0, currentUserMoveSpeed / 5)
    velocity.z = move_toward(velocity.z, 0, currentUserMoveSpeed / 5)
    currentUserMoveSpeed = USER_MOVE_SPEED

  move_and_slide()
  if touching_hazard():
    die()
    return

  if is_on_wall():
    currentUserMoveSpeed = USER_MOVE_SPEED
  if is_on_floor():
    canUseGrenade = true

func record_frame(delta: float, input_dir: Vector2):
  var frame_data = {
    "start_position": global_transform.origin,
    "expected_end_position": Vector3.ZERO,
    "input_dir": input_dir,
    "restart": pending_restart,
    "pending_grenade_spawn": pending_grenade_spawn,
    "pending_grenade_explode": pending_grenade_explode,
    "winning": winning, # win animation frames are scripted, not simulated
    "cp_pos": cpPos, # respawn point at the start of this frame (die() uses it)
    "delta": delta,
    "velocity": velocity,
    "currentUserMoveSpeed": currentUserMoveSpeed,
    "currentUserJumpHeight": currentUserJumpHeight,
    "jumps": jumps,
    "kt": kt,
    "tick_count": tickCount,
    "last_grenade_tick": lastGrenadeTick,
    "trypress_jump": trypress.jump,
    "cam_rotation": $cam.rotation,
    "fake_cam_rotation": $fake_cam.rotation
  }
  replay_buffer.append(frame_data) # flags are cleared by step() when it consumes them

func stop_replay():
  current_mode = ReplayMode.NORMAL
  log.pp("--- REPLAY FINISHED ---")

func check_desync(frame: int):
  var recorded_pos = replay_buffer[frame].expected_end_position
  var actual_pos = global_transform.origin
  var distance = actual_pos.distance_to(recorded_pos)

  if distance > DESYNC_THRESHOLD:
    print_rich("[color=red][DESYNC Frame %d][/color] Drift: %.4f units. Expected %s, Got %s" % [frame, distance, recorded_pos, actual_pos])
    global_transform.origin = recorded_pos

func win(goal: Area3D) -> void:
  if winning:
    return # contact fired again while the effect is already running
  end_win() # undo a leftover effect from an earlier win that was never cleaned up
  global_position.x = goal.global_position.x
  global_position.z = goal.global_position.z
  win_startY = global_position.y
  winning = true
  win_spin = 0.0
  win_spin_rate = 0.0
  winTimer = 0

  win_cell = goal.get_meta("cell")
  win_item = grid.get_cell_item(win_cell)
  win_orient = grid.get_cell_item_orientation(win_cell)
  assert(win_item != GridMap.INVALID_CELL_ITEM, "goal cell is empty")

  var lib := grid.mesh_library
  var mesh := lib.get_item_mesh(win_item)
  win_mat = mesh.surface_get_material(0).duplicate() # private copy, other goals are untouched
  win_fade = win_mat.get_shader_parameter("top_fade")

  win_fx = MeshInstance3D.new()
  win_fx.mesh = mesh
  win_fx.material_override = win_mat
  win_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  grid.add_child(win_fx)
  win_fx.transform = Transform3D(grid.get_cell_item_basis(win_cell), grid.map_to_local(win_cell)) \
      * lib.get_item_mesh_transform(win_item)
  grid.set_cell_item(win_cell, GridMap.INVALID_CELL_ITEM) # hide the shared cell, the copy replaces it

func end_win() -> void:
  winning = false
  if win_fx == null:
    return # no effect is active, nothing to undo
  win_fx.queue_free()
  win_fx = null
  grid.set_cell_item(win_cell, win_item, win_orient)
func setCheckpoint(pos: Vector3):
  cpPos = pos
