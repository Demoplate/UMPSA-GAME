# SelectButton.gd
extends Area2D

@onready var open_lid: Sprite2D = $OpenedLid
@onready var closed_lid: Sprite2D = $ClosedLid

func _process(_delta: float) -> void:
	# Check if GameData's active tool is DELETE
	var is_delete_active = (GameData.current_tool == GameData.ToolMode.DELETE)
	open_lid.visible = is_delete_active
	closed_lid.visible = not is_delete_active

func _input_event(_viewport, event, _shape_idx):
	if (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		GameData.set_tool(GameData.ToolMode.DELETE)
		print("Switched to Delete Tool")
