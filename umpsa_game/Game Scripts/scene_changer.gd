extends Button

# Export the scene path so you can select it easily in the Inspector
@export_file("*.tscn") var next_scene_path: String

func _ready() -> void:
	# Connect the button's pressed signal to our function automatically
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)

func _on_pressed() -> void:
	if next_scene_path and not next_scene_path.is_empty():
		get_tree().change_scene_to_file(next_scene_path)
	else:
		print("[ERROR] Target scene path is not assigned on the button script!")
