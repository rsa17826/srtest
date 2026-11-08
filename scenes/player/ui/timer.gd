extends Label

func _process(_delta):
  text = global.timer.format()
