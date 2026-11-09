@tool
extends Node

# REM: don't call globals by name until onready

# tilemap
# file
# arr
# event

#

func _ready() -> void:
  if !InputMap.has_action("quit"): return
  # InputMap.load_from_project_settings()
  localReady()

func _process(delta: float) -> void:
  if openMsgBoxCount: return
  if timer.started:
    timer.time += delta
  for i: Array in wait_until_wait_list:
    if has_user_signal(i[0]) and i[1] and i[1].is_valid() and i[1].call():
      Signal(self, i[0]).emit()
      remove_user_signal(i[0])
  if !InputMap.has_action("quit"): return
  localProcess(delta)

var openMsgBoxCount: int = 0

var promptPromise: Promise
const windowSize = Vector2(1152, 648)

enum PromptTypes {
  int,
  confirm,
  string,
  float,
  info,
  _enum,
  # multiSelect,
  bool,
  rgb,
  rgba,
  multiLineString
}

func prompt(msg: String, type: PromptTypes = PromptTypes.info, startVal: Variant = null, default: Variant = null, singleArrValues: Variant = []) -> Variant:
  if openMsgBoxCount:
    while openMsgBoxCount:
      await wait(10)
  var lastMouseMode := Input.mouse_mode
  Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
  openMsgBoxCount += 1

  var promptCanvas := preload("res://GLOBAL/__prompt.tscn").instantiate()
  get_tree().root.add_child(promptCanvas)
  promptCanvas.get_node("ColorRect").size = windowSize
  promptCanvas.get_node("ColorRect/CenterContainer").size = windowSize
  promptCanvas.promptText.text = msg

  promptCanvas.numEdit.visible = false
  promptCanvas.strEdit.visible = false
  promptCanvas.enumEdit.visible = false
  promptCanvas.colEdit.visible = false
  promptCanvas.textEdit.visible = false
  # log.pp(type)
  promptCanvas.btnCancel.text = "cancel"
  promptCanvas.btnOk.text = "ok"
  promptCanvas.btnCancel.visible = true
  if same(default, null) or same(default, startVal):
    promptCanvas.btnDefault.visible = false
  else:
    promptCanvas.btnDefault.visible = true
    promptCanvas.btnDefault.connect("pressed", _on_resetToDefault)

  match type:
    PromptTypes.info:
      promptCanvas.btnCancel.visible = false
    PromptTypes.int:
      promptCanvas.numEdit.value = 0 if startVal == null else startVal
      promptCanvas.numEdit.step = 1
      promptCanvas.numEdit.rounded = true
      promptCanvas.numEdit.get_line_edit().connect("text_submitted", _on_submit)
      promptCanvas.numEdit.visible = true
      promptCanvas.numEdit.get_line_edit().grab_focus()
    PromptTypes.confirm:
      promptCanvas.btnCancel.text = "cancel"
      promptCanvas.btnOk.text = "ok"
    PromptTypes.bool:
      promptCanvas.btnCancel.text = "false"
      promptCanvas.btnOk.text = "true"
    PromptTypes.multiLineString:
      promptCanvas.textEdit.text = '' if startVal == null else startVal
      promptCanvas.textEdit.visible = true
      promptCanvas.textEdit.grab_focus()
    PromptTypes.string:
      promptCanvas.strEdit.text = '' if startVal == null else startVal
      promptCanvas.strEdit.connect("text_submitted", _on_submit)
      promptCanvas.strEdit.visible = true
      promptCanvas.strEdit.grab_focus()
    PromptTypes.float:
      promptCanvas.numEdit.value = 0.0 if startVal == null else startVal
      promptCanvas.numEdit.rounded = false
      promptCanvas.numEdit.step = .1
      promptCanvas.numEdit.get_line_edit().connect("text_submitted", _on_submit)
      promptCanvas.numEdit.visible = true
      promptCanvas.numEdit.get_line_edit().grab_focus()
    PromptTypes.rgb:
      promptCanvas.colEdit.visible = true
      promptCanvas.colEdit.edit_alpha = false
      promptCanvas.colEdit.color = startVal
      promptCanvas.colEdit.connect("popup_closed", _on_submit)
    PromptTypes.rgba:
      promptCanvas.colEdit.visible = true
      promptCanvas.colEdit.edit_alpha = true
      promptCanvas.colEdit.color = startVal
      promptCanvas.colEdit.connect("popup_closed", _on_submit)
    PromptTypes._enum:
      promptCanvas.enumEdit.clear()
      for thing: String in singleArrValues:
        promptCanvas.enumEdit.add_item(thing)
      promptCanvas.enumEdit.select(-1 if startVal == null else startVal)
      promptCanvas.enumEdit.connect("item_selected", _on_submit)
      promptCanvas.enumEdit.visible = true
      promptCanvas.enumEdit.grab_focus()
      promptCanvas.btnOk.visible = false
    # PromptTypes._enum:
    #   promptCanvas.enumEdit.clear()
    #   for thing: String in singleArrValues:
    #     promptCanvas.enumEdit.add_item(thing)
    #   promptCanvas.enumEdit.select(-1 if startVal == null else singleArrValues.find(startVal))
    #   promptCanvas.enumEdit.connect("item_selected", _on_submit)
    #   promptCanvas.enumEdit.visible = true
    #   promptCanvas.enumEdit.grab_focus()
    #   promptCanvas.btnOk.visible = false

  promptCanvas.btnOk.connect("pressed", _on_submit)
  promptCanvas.btnCancel.connect("pressed", _on_cancel)
  promptCanvas.visible = true
  promptPromise = Promise.new()
  var confirmed = await promptPromise.wait()
  if same(confirmed, "default"):
    promptCanvas.queue_free.call_deferred()
    return default

  var val: Variant
  match type:
    PromptTypes.confirm: val = confirmed
    PromptTypes.bool: val = confirmed
    PromptTypes.string: val = promptCanvas.strEdit.text if confirmed else startVal
    PromptTypes.multiLineString: val = promptCanvas.textEdit.text if confirmed else startVal
    PromptTypes.float: val = float(promptCanvas.numEdit.value) if confirmed else startVal
    PromptTypes.int: val = int(promptCanvas.numEdit.value) if confirmed else startVal
    PromptTypes._enum: val = int(promptCanvas.enumEdit.selected) if confirmed else startVal
    # PromptTypes._enum: val = singleArrValues[int(promptCanvas.enumEdit.selected)] if confirmed else startVal
    PromptTypes.rgb: val = promptCanvas.colEdit.color
    PromptTypes.rgba: val = promptCanvas.colEdit.color
  Input.mouse_mode = lastMouseMode
  promptCanvas.queue_free.call_deferred()
  return val

func _on_resetToDefault() -> void:
  openMsgBoxCount -= 1
  promptPromise.resolve("default")
func _on_submit(text: Variant = null) -> void:
  openMsgBoxCount -= 1
  promptPromise.resolve(true)
func _on_cancel() -> void:
  openMsgBoxCount -= 1
  promptPromise.resolve(false)

# var __pressedKeys = []

func _input(event: InputEvent) -> void:
  if !InputMap.has_action("quit"): return
  # if event is InputEventKey:
  #   if event.pressed and event.keycode not in __pressedKeys:
  #     __pressedKeys.push_back(event.keycode)
  #   elif event.keycode in __pressedKeys:
  #     __pressedKeys.erase(event.keycode)
  # localInput(event)

# func isActionJustPressedWithNoExtraMods(thing: String) -> bool:
#   return event.is_action_pressed(thing) and isActionPressedWithNoExtraMods(thing)
# # func isActionJustReleasedWithNoExtraMods(thing: String) -> bool:
# #   return Input.is_action_just_released(thing) and isActionPressedWithNoExtraMods(thing)
# func isActionPressedWithNoExtraMods(thing: String) -> bool:
#   var actions: Array = InputMap.action_get_events(thing).map(func(e: InputEvent) -> Dictionary:
#     if "button_index" in e:
#       return {
#         "which": "mouse",
#         "button": e.button_index,
#         "c": e.ctrl_pressed,
#         "a": e.alt_pressed,
#         "s": e.shift_pressed,
#         "m": e.meta_pressed
#       }
#     else:
#       return {
#         "which": "key",
#         "key": e.physical_keycode,
#         "c": e.ctrl_pressed,
#         "a": e.alt_pressed,
#         "s": e.shift_pressed,
#         "m": e.meta_pressed
#       }
#     )
#   # log.pp(actions)
#   for action in actions:
#     if action.which == "key":
#       if Input.is_key_pressed(action.key) \
#       and Input.is_key_pressed(KEY_CTRL) == action.c \
#       and Input.is_key_pressed(KEY_ALT) == action.a \
#       and Input.is_key_pressed(KEY_SHIFT) == action.s \
#       and Input.is_key_pressed(KEY_META) == action.m \
#       :
#         return true
#     elif action.which == "mouse":
#       if Input.is_mouse_button_pressed(action.button) \
#       and Input.is_key_pressed(KEY_CTRL) == action.c \
#       and Input.is_key_pressed(KEY_ALT) == action.a \
#       and Input.is_key_pressed(KEY_SHIFT) == action.s \
#       and Input.is_key_pressed(KEY_META) == action.m \
#       :
#         return true
#   return false

func remove_recursive(directory: String) -> void:
  for dir_name in DirAccess.get_directories_at(directory):
    remove_recursive(directory.path_join(dir_name))
  for file_name in DirAccess.get_files_at(directory):
    DirAccess.remove_absolute(directory.path_join(file_name))

  DirAccess.remove_absolute(directory)

var regexCache: Cache = Cache.new()
var regMatchCache: Cache = Cache.new()
func regMatch(str: String, reg: String) -> Variant:
  if regMatchCache.__has([reg, str]):
    return regMatchCache.__get()
  var reg2: RegEx
  if regexCache.__has(reg):
    reg2 = regexCache.__get()
  else:
    reg2 = regexCache.__set(RegEx.create_from_string(reg))
  var res := reg2.search(str)
  if not res: return regMatchCache.__set(res)
  var out := []
  for i in range(0, res.get_group_count() + 1):
    out.push_back(res.get_string(i))
  return regMatchCache.__set(out)

var regMatchAllCache: Cache = Cache.new()
func regMatchAll(str: String, reg: String) -> Variant:
  if regMatchAllCache.__has([reg, str]):
    return regMatchAllCache.__get()
  var reg2: RegEx
  if regexCache.__has(reg):
    reg2 = regexCache.__get()
  else:
    reg2 = regexCache.__set(RegEx.create_from_string(reg))
  var res := reg2.search_all(str)
  var out := []
  for j in len(res):
    out.append([])
    for i in range(0, res[j].get_group_count() + 1):
      out[len(out) - 1].push_back(res[j].get_string(i))
  return regMatchAllCache.__set(out)

var regReplaceCache: Cache = Cache.new()
func regReplace(str: String, reg: String, with: String, all:=true) -> String:
  if regReplaceCache.__has([reg, str, with, all]):
    return regReplaceCache.__get()
  var reg2: RegEx
  if regexCache.__has(reg):
    reg2 = regexCache.__get()
  else:
    reg2 = regexCache.__set(RegEx.create_from_string(reg))
  reg2.compile(reg)
  return regReplaceCache.__set(reg2.sub(str, with, all))

# const filepath = {
# }

func same(x: Variant, y: Variant) -> bool:
  return typeof(x) == typeof(y) and x == y

func randstr(length:=10, fromchars:="qwertyuiopasdfghjklzxcvbnm1234567890~!@#$%^&*()_+-={ }[']\\|;:\",.<>/?`") -> String:
  var s := ''
  for i in range(length):
    s += (fromchars[randfrom(0, len(fromchars) - 2)])
  return s

var wait_until_wait_list := []
func waituntil(cb: Callable) -> Signal:
  var sig := "wait until signal - " + randstr(30)
  add_user_signal(sig)
  wait_until_wait_list.append([sig, cb])
  return Signal(self, sig)

# class link:
#   static var links = []
#   static func create(varname, node, cb=func(a):
#     return a, prop="text"):
#     link.links.append({"node": node, "varname": varname, "prop": prop, "val": null, "cb": cb})
#   # s=set because error when name is set
#   static func s(varname, val):
#     for l in link.links:
#       if l.node == varname:
#         l.val = val
#         l.node[l.prop] = l.cb(val)

# class lableformat:
#   static var lableformats := {}
#   static func create(name, label, format):
#     global.lableformat.lableformats[name] = {"text": format, "node": label}
#   static func update(name, newtext: Dictionary):
#     var keys = newtext.keys();
#     var temp = global.lableformat.lableformats[name]
#     var node = temp.node
#     var text = temp.text
#     for key in keys:
#       var val = newtext[key]
#       text = text.replace("{" + str(key) + "}", str(val))
#     node.text = text

  # for link in global.link.links:
  #   if link.node.is_inside_tree() and link.node.is_node_ready():
  #     link.node[link.prop] = link.cb.call(link.val)
func dictmap(dict, cb):
  for key in dict:
    dict[key] = cb.call(key, dict[key])
  return dict

class timer:
  static var time: float = 0
  static var started: bool = false
  static func reset() -> void:
    timer.time = 0
  static func format(temptime: Variant = "DJKASDHjkaDHJkashdjkAS") -> String:
    var time: float = timer.time if global.same(temptime, "DJKASDHjkaDHJkashdjkAS") else float(temptime)
    var minutes: float = time / 60
    var seconds: float = fmod(time, 60)
    var milliseconds: float = fmod(time, 1) * 100
    return "%02d:%02d:%02d" % [minutes, seconds, milliseconds]
  static func stop() -> void:
    timer.started = false
  static func start() -> void:
    timer.started = true

class path:
  static func abs(p: String) -> String:
    if OS.has_feature("editor"):
      return ProjectSettings.globalize_path(p)
    if global.starts_with(p, "user://"):
      return ProjectSettings.globalize_path(p)
    if global.starts_with(p, "res://"):
      return OS.get_executable_path().get_base_dir() + '/' + p.substr(6)
    return p

  static func join(path1: String, path2:="", path3:="", path4:="") -> String:
    var fullPath := path1
    if len(path2):
      var slash := 0
      if global.ends_with(fullPath, "/"):
        slash += 1
      if global.starts_with(path2, "/"):
        slash += 1
      match slash:
        0: fullPath += "/" + path2
        1: fullPath += path2
        2: fullPath += global.regReplace(path2, '^/', '')
    if len(path3):
      var slash := 0
      if global.ends_with(fullPath, "/"):
        slash += 1
      if global.starts_with(path3, "/"):
        slash += 1
      match slash:
        0: fullPath += "/" + path3
        1: fullPath += path3
        2: fullPath += global.regReplace(path3, '^/', '')
    if len(path4):
      var slash := 0
      if global.ends_with(fullPath, "/"):
        slash += 1
      if global.starts_with(path4, "/"):
        slash += 1
      match slash:
        0: fullPath += "/" + path4
        1: fullPath += path4
        2: fullPath += global.regReplace(path4, '^/', '')
    return global.regReplace(fullPath, r"\s*/+\s*$", '').strip_edges().replace("\\", "/")
    # return global.regReplace(parsePath(fullPath), r"\s*/+\s*$", '').strip_edges().replace("\\", "/")
    # return parsePath((global.regReplace(path1 + "/" + path2 + "/" + path3 + "/" + path4, "(?<!res:)/{2,}", "/")

class tilemap:
  static func save(tile_map: TileMap) -> Array:
    var layers: int = tile_map.get_layers_count()
    var tile_map_layers := []
    tile_map_layers.resize(layers)
    for layer in layers:
      tile_map_layers[layer] = tile_map.get("layer_%s/tile_data" % layer)
    return tile_map_layers
  static func load(tile_map: TileMap, data: Array) -> void:
    for layer in data.size():
      var tiles = data[layer]
      tile_map.set('layer_%s/tile_data' % layer, tiles)

class file:
  static func write(p: String, text: Variant, asjson:=true) -> void:
    # p = path.parsePath(p)
    FileAccess.open(p, FileAccess.WRITE_READ).store_string(JSON.stringify(text, "  " if OS.has_feature("editor") else '') if asjson else text)
  static func isFile(p: String) -> bool:
    return !!FileAccess.open(p, FileAccess.READ)
  static func read(p: String, asjson:=true, default:='') -> Variant:
    # p = path.parsePath(p)
    var f := FileAccess.open(p, FileAccess.READ)
    if !f:
      f = FileAccess.open(p, FileAccess.WRITE_READ)
      if f:
        f.store_string(default)
      else:
        log.err(p)
      return JSON.parse_string(default) if asjson else default
      # return null if asjson else default
    if asjson:
      if JSON.parse_string(f.get_as_text()) != null:
        return JSON.parse_string(f.get_as_text())
      else:
        if JSON.parse_string(default) != null:
          return JSON.parse_string(default)
        else: return default
    else:
      return f.get_as_text()
class arr:
  static func unique(array: Array) -> Variant:
    var i = {"i": - 1}
    return array.filter(func(e):
      i.i += 1
      return array.find(e) == i.i
      )
  static func getcount(array: Array, count: int) -> Variant:
    var newarr := []
    for i in range(count):
      if array.size() == 0: return null
      newarr.append(array[0])
      array.remove_at(0)
    return newarr
class event:
  static var triggers: Dictionary = {}
  static func trigger(msg: String, data1: Variant = "AHDSJKHDASJK", data2: Variant = "AHDSJKHDASJK", data3: Variant = "AHDSJKHDASJK") -> void:
    if !msg in triggers:
      log.error('no triggers set for call', msg)
      return
    for cb: Callable in triggers[msg]:
      if cb != null and cb.is_valid():
        var default := "AHDSJKHDASJK"
        if global.same(data3, default):
          if global.same(data2, default):
            if global.same(data1, default):
              cb.call()
            else:
              cb.call(data1)
          else:
            cb.call(data1, data2)
        else:
          cb.call(data1, data2, data3)
  static func off(obj: Dictionary) -> void:
    var msg: String = obj.msg
    var i: int = obj.index
    if !msg in triggers:
      log.error(triggers, 'cant remove ' + str(i) + ' from ' + msg + ' because ' + msg + ' doesnt exist')
      return
    if len(triggers[msg]) <= i:
      log.error(triggers[msg], 'cant remove ' + str(i) + ' from ' + msg + ' because ' + str(i) + ' doesnt exist in ' + msg)
      return
    triggers[msg][i] = null
  static func on(msg: String, cb: Callable) -> Dictionary:
    if !msg in triggers:
      triggers[msg] = []
    triggers[msg].append(cb)
    return {'msg': msg, 'index': len(triggers[msg]) - 1}

func sinFrom(start: float, end: float, time: float, speed: float = 1) -> float:
  # Calculate the sine value, ensuring it starts at 0 when time is 0
  var sine_value = (sin(time * speed - PI / 2) + 1) / 2 # Shifted to start at 0
  return lerp(start, end, sine_value)

func filterDict(data: Dictionary, cb: Callable) -> Dictionary:
  var filtered_data := {}
  for k in data:
    if cb.call(k, data[k]):
      filtered_data[k] = data[k]
  return filtered_data

# class InputManager:
#   func _init(_init_key_names):
#     self.key_names = _init_key_names
#     for key in self._data.key_names.keys():
#       self.unpress(key)

#     _update_key_press_states()
#   var trypress = {}
#   var key_names = {}
#   var KEY_MAX_BUFFER: int = 15

#   func pressed(key) -> int:
#     return !!trypress[key].pressed

#   func just_pressed(key) -> int:
#     var ret = !!trypress[key].just_pressed
#     if ret:
#       trypress[key].just_pressed = 0
#     return ret

#   func just_released(key) -> int:
#     return Input.is_action_just_released(key_names[key])
#   func compare(neg, pos) -> int:
#     var input_dir = 0
#     if self.pressed(neg) == self.pressed(pos):
#       input_dir = 0
#     elif self.pressed(neg) and not self.pressed(pos):
#       input_dir = -1
#     elif self.pressed(pos):
#       input_dir = 1
#     return input_dir
#   func unpress(key):
#     trypress[key] = {
#       "pressed": 0,
#       "just_pressed": 0,
#     }
#   func press(key) -> void:
#     trypress[key] = {
#       "pressed": KEY_MAX_BUFFER,
#       "just_pressed": KEY_MAX_BUFFER,
#     }
#   func _update_key_press_states() -> void:
#     for key in self._data.key_names.keys():
#       if !key_names[key]: continue
#       if event.is_action_pressed(key_names[key]):
#         trypress[key].just_pressed = KEY_MAX_BUFFER
#       elif trypress[key].just_pressed:
#         trypress[key].just_pressed -= 1

#       if Input.is_action_pressed(key_names[key]):
#         trypress[key].pressed = 1
#       else:
#         unpress(key)

func wait(time: float = 0, ignore_time_scale: bool = false) -> Variant:
  if time == 0:
    return await get_tree().process_frame
  return await get_tree().create_timer(time / 1000.0, true, false, ignore_time_scale).timeout

func starts_with(x: String, y: String) -> bool:
  return x.substr(0, len(y)) == y
func ends_with(x: String, y: String) -> bool:
  return x.substr(len(x) - len(y)) == y

func randfrom(min: float, max: float) -> int:
  # if global.same(max, "unset"):
  #   return min[randfrom(0, len(min) - 1)]
  return int(randf() * (max - min + 1) + min)

func rerange_clamp(val: Variant, low1: Variant, high1: Variant, low2: Variant, high2: Variant) -> Variant:
  var min = low2 if low2 < high2 else high2
  var max = low2 if low2 > high2 else high2
  return clamp(self.rerange(val, low1, high1, low2, high2), min, max)
func rerange(val: Variant, low1: Variant, high1: Variant, low2: Variant, high2: Variant) -> Variant:
  if typeof(val) == typeof(0) or typeof(val) == typeof(0.0):
    val = float(val)
    low1 = float(low1)
    high1 = float(high1)
  if typeof(low2) == typeof(0) or typeof(low2) == typeof(0.0):
    low2 = float(low2)
    high2 = float(high2)
  return ((val - low1) / (high1 - low1)) * (high2 - low2) + low2

var tick: float = 0
var stopTicking := false
func _physics_process(delta: float) -> void:
  if openMsgBoxCount: return
  if stopTicking: return
  tick += delta

func clearLow(v):
  match typeof(v):
    TYPE_VECTOR2, TYPE_VECTOR2I:
      if is_zero_approx(v.x): v.x = 0
      if is_zero_approx(v.y): v.y = 0
    TYPE_FLOAT:
      if is_zero_approx(v): v = 0
    TYPE_INT:
      log.err("no use of int here!!!")
    _:
      log.warn("clearLow: unknown type", type_string(typeof(v)))
      breakpoint
  return v

# local game only data
func localReady(): pass
func localProcess(delta: float): pass
var level: Level
