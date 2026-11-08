extends RayCast3D

# Called when the node enters the scene tree for the first time.
func _ready():
  pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
  var point = get_collision_point()
  var temp = global.map.local_to_map(point)
  global.debuguiadd("posonmap", temp)
  global.debuguiadd("pos", point)
  global.debuguiadd("asjkshdjkasd", global.map.get_cell_item(temp))