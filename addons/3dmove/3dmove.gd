@tool
extends EditorPlugin

var is_flying: bool = false
var custom_cam: Camera3D = null
var original_cam: Camera3D = null
var viewport: SubViewport = null

# Flight Adjustments
var move_speed: float = 10.0
var mouse_sensitivity: float = 0.0025

# Camera Tracking States
var rot_x: float = 0.0
var rot_y: float = 0.0
var keys_pressed: Dictionary = {
  KEY_W: false,
  KEY_S: false,
  KEY_A: false,
  KEY_D: false,
  KEY_SPACE: false,
  KEY_SHIFT: false
}
var flight_speed_multiplier: float = 1.0
func _enter_tree() -> void:
  log.pp("3dmove Enabled.")

func _exit_tree() -> void:
  log.pp("3dmove Disabled.")
  if is_flying:
    disable_flight()

func _input(event: InputEvent) -> void:
  if is_flying and event is InputEventMouseButton and event.pressed:
    if event.button_index == MOUSE_BUTTON_WHEEL_UP:
      flight_speed_multiplier = clamp(flight_speed_multiplier * 1.2, 0.1, 100.0)
    elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
      flight_speed_multiplier = clamp(flight_speed_multiplier / 1.2, 0.1, 100.0)
    get_viewport().set_input_as_handled()
    log.pp(flight_speed_multiplier)
  if event is InputEventMouseButton:
    var vp = get_editor_interface().get_editor_viewport_3d(0)
    if event.button_mask & MOUSE_BUTTON_RIGHT:
      var target = get_viewport().gui_get_hovered_control()
      var is_hovering = target == vp.get_parent().get_parent().get_child(1)
      # if target:
      #   log.pp("Mouse is over: ", target == vp.get_parent().get_parent().get_child(1))
      if is_hovering and !is_flying:
        enable_flight()
      if vp:
        if is_flying or is_hovering:
          get_viewport().set_input_as_handled()
          return
    else:
      disable_flight()

  if is_flying and event is InputEventKey and event.physical_keycode == KEY_ESCAPE and event.pressed:
    disable_flight()
    get_viewport().set_input_as_handled()
    return

  # Handle FPS Look Orientation
  if is_flying and event is InputEventMouseMotion:
    rot_x -= event.relative.x * mouse_sensitivity
    rot_y -= event.relative.y * mouse_sensitivity
    rot_y = clamp(rot_y, -PI / 2 + 0.02, PI / 2 - 0.02)

    if custom_cam:
      custom_cam.transform.basis = Basis() # Reset base orientation
      custom_cam.rotate_object_local(Vector3.UP, rot_x)
      custom_cam.rotate_object_local(Vector3.RIGHT, rot_y)
    get_viewport().set_input_as_handled()

  # Real-time Key Capture
  if event is InputEventKey:
    if event.physical_keycode in keys_pressed:
      keys_pressed[event.physical_keycode] = event.pressed
      if is_flying:
        get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
  if not is_flying or not custom_cam: return
  var final_speed = move_speed * flight_speed_multiplier
  final_speed = clamp(final_speed, 0.5, 250.0) # Safe guard boundary

  # 3. RUN FLIGHT LOGIC
  var move_dir := Vector3.ZERO
  var forward = - custom_cam.global_transform.basis.z
  forward.y = 0
  forward = forward.normalized()

  var right = custom_cam.global_transform.basis.x
  right.y = 0
  right = right.normalized()

  if forward.is_zero_approx():
    forward = - custom_cam.global_transform.basis.y
    forward.y = 0
    forward = forward.normalized()

  if keys_pressed[KEY_W]: move_dir += forward
  if keys_pressed[KEY_S]: move_dir -= forward
  if keys_pressed[KEY_A]: move_dir -= right
  if keys_pressed[KEY_D]: move_dir += right
  if keys_pressed[KEY_SPACE]: move_dir.y += 1.0
  if keys_pressed[KEY_SHIFT]: move_dir.y -= 1.0

  if move_dir != Vector3.ZERO:
    custom_cam.global_position += move_dir.normalized() * final_speed * delta

func enable_flight() -> void:
  viewport = get_editor_interface().get_editor_viewport_3d(0)
  if not viewport: return

  original_cam = viewport.get_camera_3d()
  if not original_cam: return

  is_flying = true

  # Configure proxy camera
  custom_cam = Camera3D.new()
  custom_cam.keep_aspect = original_cam.keep_aspect
  custom_cam.cull_mask = original_cam.cull_mask
  custom_cam.fov = original_cam.fov
  custom_cam.near = original_cam.near
  custom_cam.far = original_cam.far
  custom_cam.global_transform = original_cam.global_transform

  # Set tracking rotation to current angles
  var euler = original_cam.global_transform.basis.get_euler()
  rot_x = euler.y
  rot_y = euler.x

  # Inject into persistent editor workspace hierarchy
  get_editor_interface().get_base_control().add_child(custom_cam)

  # Divert Viewport rendering directly to our proxy camera
  RenderingServer.viewport_attach_camera(viewport.get_viewport_rid(), custom_cam.get_camera_rid())

  # Trap Mouse Control
  Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func disable_flight() -> void:
  is_flying = false

  Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

  if viewport and original_cam:
    # Return rendering pipeline back to original editor camera
    RenderingServer.viewport_attach_camera(viewport.get_viewport_rid(), original_cam.get_camera_rid())
    if custom_cam:
      original_cam.global_transform = custom_cam.global_transform

  if custom_cam:
    custom_cam.queue_free()
    custom_cam = null

  for k in keys_pressed:
    keys_pressed[k] = false
