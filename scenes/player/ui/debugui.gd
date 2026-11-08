extends TextEdit

# Called when the node enters the scene tree for the first time.
func _ready():
  visible = false
  global.event.on("debugui start", debuguistart)

func debuguiadd(dataname, data):
  text = text + "\n" + dataname + ": " + str(data)

func debuguistart():
  global.event.on("debugui add", debuguiadd)
  visible = true

# # Called every frame. 'delta' is the elapsed time since the previous frame.
# func _process(delta):
#     pass
