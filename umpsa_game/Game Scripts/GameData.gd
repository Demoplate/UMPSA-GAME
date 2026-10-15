extends Node

enum ToolMode { SPAWN, SELECT, DELETE }
var current_tool = ToolMode.SPAWN
var selected_part = null

# Add this line so GameData can store your parts when transitioning scenes!
var saved_parts: Array = []

func set_tool(new_tool: ToolMode):
	if current_tool == ToolMode.SELECT and new_tool != ToolMode.SELECT:
		if selected_part and is_instance_valid(selected_part):
			# Reset any Sprite2D children anywhere inside the selected part
			for child in selected_part.find_children("*", "Sprite2D", true, false):
				child.modulate = Color(1, 1, 1)
		selected_part = null
		
	current_tool = new_tool
