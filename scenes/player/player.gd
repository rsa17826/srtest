extends CharacterBody3D

const USER_MOVE_SPEED = 5.5
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

# --- REPLAY SYSTEM VARIABLES ---
enum ReplayMode {NORMAL, RECORDING, REPLAYING}
var current_mode = ReplayMode.NORMAL
var replay_buffer: Array = []
var replay_frame_index: int = 0
const DESYNC_THRESHOLD: float = 0.001
# -------------------------------

@onready var grid: GridMap = global.level.gridmap
@onready var hazard_ids := [
  grid.mesh_library.find_item_by_name("spiky floor"),
  grid.mesh_library.find_item_by_name("spiky box"),
  grid.mesh_library.find_item_by_name("spiky ball"),
]
@onready var playerHeight = $CollisionShape3D.shape.height / 2
@onready var playerWidth = $CollisionShape3D.shape.radius / 2

func _ready():
  assert(not -1 in hazard_ids, "hazard tile name missing from mesh library")
  get_window().transparent = true
  get_window().borderless = true
  get_window().mode = Window.MODE_MAXIMIZED

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
  if current_mode == ReplayMode.REPLAYING: return

  if event is InputEventMouseButton:
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
  position = startPos
  velocity = Vector3.ZERO

func _unhandled_input(event):
  if event.is_action_pressed("restart"):
    die()
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
  currentUserMoveSpeed += JUMP_SPEED_BOOST
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
  current_mode = ReplayMode.RECORDING
  log.pp("--- RECORDING STARTED ---")

func stop_recording():
  current_mode = ReplayMode.NORMAL
  log.pp("--- RECORDING STOPPED (Frames recorded: ", replay_buffer.size(), ") ---")
  global.file.write("res://replay.json", replay_buffer)

func start_replay():
  if replay_buffer.is_empty():
    log.pp("No replay data found!")
    return

  current_mode = ReplayMode.REPLAYING
  replay_frame_index = 0

  var first_frame = replay_buffer[0]
  global_transform.origin = first_frame.start_position
  velocity = first_frame.velocity
  currentUserMoveSpeed = first_frame.currentUserMoveSpeed
  currentUserJumpHeight = first_frame.currentUserJumpHeight
  jumps = first_frame.jumps
  kt = first_frame.kt
  trypress.jump = first_frame.trypress_jump
  $cam.rotation = first_frame.cam_rotation
  $fake_cam.rotation = first_frame.fake_cam_rotation

  log.pp("--- REPLAY STARTED ---")

func _physics_process(delta: float) -> void:
  # var cell := grid.local_to_map(grid.to_local(global_position - Vector3(0, playerHeight + .01, 0)))
  var has2 = []
  delta = 1 / 60.0
  var playback_delta = delta

  # --- 1. STATE RESTORATION OR INPUT UPDATE ---
  if current_mode == ReplayMode.REPLAYING:
    if replay_frame_index >= replay_buffer.size():
      stop_replay()
      return

    var data = replay_buffer[replay_frame_index]
    playback_delta = data.delta

    global_transform.origin = data.start_position
    velocity = data.velocity
    currentUserMoveSpeed = data.currentUserMoveSpeed
    currentUserJumpHeight = data.currentUserJumpHeight
    jumps = data.jumps
    kt = data.kt
    trypress.jump = data.trypress_jump # Injected directly from history
    $cam.rotation = data.cam_rotation
    $fake_cam.rotation = data.fake_cam_rotation
  else:
    # Process physical keyboard/mouse input states for NORMAL and RECORDING modes
    updatetrypress(has2, playback_delta)

  # --- 2. SNAPSHOT INITIAL VARIABLES ---
  # We record the frame data AFTER inputs update, but BEFORE movement math alters them.
  if current_mode == ReplayMode.RECORDING:
    record_frame(playback_delta)

  # --- 3. STANDARD MOVEMENT CALCULATIONS ---
  if is_on_floor():
    kt = MAX_KT
    jumps = MAX_JUMPS
    velocity.y = 0
  else:
    var gravity = downgravity if velocity.y < 0 else upgravity
    velocity.y -= gravity * playback_delta
    if kt > 0:
      kt -= 60 * playback_delta
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

  # --- 4. INPUT DIRECTION MATCHING ---
  var input_dir := Vector2.ZERO
  if current_mode == ReplayMode.REPLAYING:
    input_dir = replay_buffer[replay_frame_index].input_dir
  else:
    input_dir = Input.get_vector("left", "right", "forward", "back")
    if current_mode == ReplayMode.RECORDING:
      replay_buffer[replay_frame_index].input_dir = input_dir

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

  # --- 5. EXECUTE MOVEMENT ---
  move_and_slide()
  if touching_hazard():
    die()
    return
  var id := grid.mesh_library.find_item_by_name("goal")
  print(grid.mesh_library.resource_path, " ", grid.mesh_library.get_item_mesh_transform(id))
  if is_on_wall():
    currentUserMoveSpeed = USER_MOVE_SPEED
  # TODO
  # clear speed when vel sign changes
  # --- 6. EVALUATE / POST-FRAME LOGIC ---
  if current_mode == ReplayMode.RECORDING:
    replay_buffer[replay_frame_index].expected_end_position = global_transform.origin
    replay_frame_index += 1
  elif current_mode == ReplayMode.REPLAYING:
    check_desync(replay_frame_index)
    replay_frame_index += 1

func record_frame(delta: float):
  var frame_data = {
    "start_position": global_transform.origin,
    "expected_end_position": Vector3.ZERO,
    "input_dir": Vector2.ZERO,
    "delta": delta,
    "velocity": velocity,
    "currentUserMoveSpeed": currentUserMoveSpeed,
    "currentUserJumpHeight": currentUserJumpHeight,
    "jumps": jumps,
    "kt": kt,
    "trypress_jump": trypress.jump, # Captures accurately now!
    "cam_rotation": $cam.rotation,
    "fake_cam_rotation": $fake_cam.rotation
  }
  replay_buffer.append(frame_data)

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
