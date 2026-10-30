extends Control

@export var level_1_button: Button
@export var level_2_button: Button
@export var level_3_button: Button
@export var level_4_button: Button

func _ready() -> void:
	if level_1_button:
		level_1_button.disabled = false

	if level_2_button:
		level_2_button.disabled = not LevelManager.is_level_completed("lvl1")
	if level_3_button:
		level_3_button.disabled = not LevelManager.is_level_completed("lvl2")
	if level_4_button:
		level_4_button.disabled = not LevelManager.is_level_completed("lvl3")
