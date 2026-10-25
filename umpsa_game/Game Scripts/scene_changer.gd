extends Button

# Export the scene path so you can select it easily in the Inspector
@export_file("*.tscn") var next_scene_path: String

func _ready() -> void:
	# Connect to button_down for instant mobile touch response
	if not button_down.is_connected(_on_button_down):
		button_down.connect(_on_button_down)

func _on_button_down() -> void:
	if next_scene_path and not next_scene_path.is_empty():
		get_tree().change_scene_to_file(next_scene_path)
	else:
		print("[ERROR] Target scene path is not assigned on the button script!")
