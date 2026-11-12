class_name Replays
# Static helpers: save / list / load replays at user://replays/<level>/<timestamp>.json

const ROOT := "user://replays"
const LEVEL_DIR := "res://scenes/level"
const MENU_SCENE := "res://scenes/level-select/level-select.tscn" # one-node scene: Control + level_select.gd

const VEC3_KEYS := ["start_position", "expected_end_position", "velocity", "cam_rotation", "fake_cam_rotation", "cp_pos", "grenade_pos"]
const VEC2_KEYS := ["input_dir"]
const INT_KEYS := ["jumps", "trypress_jump"]

# set by the level select menu; the ReplayViewer in the level picks it up on _ready
static var pending_path := ""

static func level_name_of(scene_path: String) -> String:
  return scene_path.get_file().get_basename()

static func current_level_name() -> String:
  assert(global.level.scene_file_path != "", "level root must be the scene root so scene_file_path is set")
  return level_name_of(global.level.scene_file_path)

static func list_levels() -> Array[String]:
  var out: Array[String] = []
  var dir := DirAccess.open(LEVEL_DIR)
  assert(dir != null, "can't open " + LEVEL_DIR)
  for f in dir.get_files():
    f = f.trim_suffix(".remap") # exported builds list scenes as .tscn.remap
    if f.ends_with(".tscn") or f.ends_with(".scn"):
      out.append(LEVEL_DIR + "/" + f)
  out.sort()
  return out

static func list_replays(level: String) -> Array[String]:
  var out: Array[String] = []
  var dir := DirAccess.open(ROOT + "/" + level) # null if this level has never been recorded
  if dir == null:
    return out
  for f in dir.get_files():
    if f.ends_with(".json"):
      out.append(ROOT + "/" + level + "/" + f)
  out.sort()
  out.reverse() # newest first (timestamps sort chronologically)
  return out

static func save(level: String, buffer: Array) -> String:
  assert(not buffer.is_empty(), "nothing to save")
  var dir := ROOT + "/" + level
  DirAccess.make_dir_recursive_absolute(dir)
  var stamp := Time.get_datetime_string_from_system().replace(":", "-")
  var frames := []
  for frame in buffer:
    var o := {}
    for k in frame:
      var v = frame[k]
      o[k] = [v.x, v.y, v.z] if k in VEC3_KEYS else ([v.x, v.y] if k in VEC2_KEYS else v)
    frames.append(o)
  var path := dir + "/" + stamp + " - " + str(len(frames)) + ".json"
  var file := FileAccess.open(path, FileAccess.WRITE)
  assert(file != null, "can't write %s (error %d)" % [path, FileAccess.get_open_error()])
  file.store_string(JSON.stringify({"level": level, "frames": frames}))
  file.close()
  return path

static func load_file(path: String) -> Array:
  var file := FileAccess.open(path, FileAccess.READ)
  assert(file != null, "can't read %s (error %d)" % [path, FileAccess.get_open_error()])
  var data = JSON.parse_string(file.get_as_text())
  assert(data is Dictionary and data.has("frames"), "bad replay file " + path)
  var buffer := []
  for o in data.frames:
    var frame := {}
    for k in o:
      var v = o[k]
      if k in VEC3_KEYS: frame[k] = Vector3(v[0], v[1], v[2])
      elif k in VEC2_KEYS: frame[k] = Vector2(v[0], v[1])
      elif k in INT_KEYS: frame[k] = int(v)
      else: frame[k] = v
    buffer.append(frame)
  return buffer

static func level_of_file(path: String) -> String:
  return path.get_base_dir().get_file()

static func pretty_name(path: String) -> String:
  return path.get_file().get_basename().replace("T", "  ")
