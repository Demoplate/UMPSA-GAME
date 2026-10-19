extends Area2D

# Export a variable so you can select your next scene easily in the Inspector
@export_file("*.tscn") var next_scene_path: String

func _ready() -> void:
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	# Check if we touched the flagpole
	if area.name == "flagpole" or area.is_in_group("flagpole"):
		print("[Level] Flagpole reached by RigidBody command module! Switching scene...")
		
		if next_scene_path and not next_scene_path.is_empty():
			get_tree().change_scene_to_file(next_scene_path)
		else:
			print("[ERROR] Next scene path is not assigned on the command module!")
