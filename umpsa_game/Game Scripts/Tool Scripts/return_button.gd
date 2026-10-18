extends Button

@export var build_scene_path: String = "res://Level_Scenes/builder_scene.tscn" # Update to your builder scene filename

func _ready() -> void:
	if not pressed.is_connected(_on_return_pressed):
		pressed.connect(_on_return_pressed)

func _on_return_pressed() -> void:
	get_tree().change_scene_to_file(build_scene_path)
