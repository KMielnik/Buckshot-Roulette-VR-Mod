extends "res://scripts/Steam.gd"

# This test-only autoload preserves the retail Steam type for script parsing.
func _ready() -> void:
	GlobalVariables.using_steam = false
	set_process(false)


func InitializeSteam() -> void:
	pass


func _process(_delta: float) -> void:
	pass
