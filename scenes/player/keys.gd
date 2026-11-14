extends Label

func _process(_delta: float) -> void:
  text = "%s/%s" % [global.player.keysCollected, global.level.totalKeys]
