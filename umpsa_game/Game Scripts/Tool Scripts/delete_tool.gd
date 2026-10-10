# SelectButton.gd
extends Area2D
func _input_event(_viewport, event, _shape_idx):
	if (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		GameData.set_tool(GameData.ToolMode.DELETE)
		print("Switched to Delete Tool")
