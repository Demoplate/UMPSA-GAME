extends Button

@export_file("*.tscn") var next_scene_path: String
@export_file("*.tscn") var fallback_scene_path: String
@export var required_level: String = "lvl1"

func _ready() -> void:
	if not button_down.is_connected(_on_button_down):
		button_down.connect(_on_button_down)

func _on_button_down() -> void:
	var target = next_scene_path

	if not required_level.is_empty() and not LevelManager.is_level_completed(required_level):
		target = fallback_scene_path

	if target.is_empty():
		push_error("Target scene path is not assigned on the button script!")
		return

	get_tree().change_scene_to_file(target)
