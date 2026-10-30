extends Node

const SAVE_PATH: String = "user://completed_levels.json"

# Dictionary to keep track of finished levels (e.g., {"level_1": true, "level_2": true})
var completed_levels: Dictionary = {}

func _ready() -> void:
	load_completed_levels()

# Call this whenever a level is cleared
func mark_level_completed(level_name: String) -> void:
	completed_levels[level_name] = true
	save_completed_levels()
	print("Level completed and saved: ", level_name)

# Helper function to check if a level was finished
func is_level_completed(level_name: String) -> bool:
	return completed_levels.get(level_name, false)

# Save completed levels to disk
func save_completed_levels() -> void:
	var json_string = JSON.stringify(completed_levels)
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(json_string)

# Load completed levels from disk
func load_completed_levels() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
		
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		if error == OK:
			completed_levels = json.get_data()
			print("Loaded completed levels: ", completed_levels)
