extends Label

func _process(_delta):
  text = global.timer.format(global.player.tickCount * 1 / 60.0)
