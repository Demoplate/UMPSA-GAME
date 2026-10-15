extends Area2D

@export var grid_size: float = 32.0
var is_dragging := false
var is_in_build_area := false

func _ready():
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	
	# Only start dragging if we are actually in SPAWN mode!
	if GameData.current_tool == GameData.ToolMode.SPAWN:
		is_dragging = true
	else:
		is_dragging = false
		queue_free() # Instantly remove if spawned while select tool is active

func start_dragging():
	# If the Select Tool is active, ignore the spawn/drag request entirely
	if GameData.current_tool == GameData.ToolMode.SELECT:
		return
		
	is_dragging = true

func _input(event):
	if not is_dragging:
		return
		
	if event is InputEventScreenDrag or event is InputEventMouseMotion:
		var target_pos = event.position
		if is_in_build_area:
			global_position = target_pos.snapped(Vector2(grid_size, grid_size))
		else:
			global_position = target_pos
			
	if (event is InputEventScreenTouch and not event.pressed) or \
	   (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed):
		is_dragging = false
		
		var overlapping_with_part = false
		for area in get_overlapping_areas():
			if area.name != "BuildingArea":
				overlapping_with_part = true
				break
		
		if is_in_build_area and not overlapping_with_part:
			global_position = global_position.snapped(Vector2(grid_size, grid_size))
		else:
			queue_free()

func _input_event(_viewport, event, _shape_idx):
	if is_dragging:
		return
		
	var is_click = (event is InputEventScreenTouch and event.pressed) or \
				   (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed)
				   
	if is_click:
		if GameData.current_tool == GameData.ToolMode.SELECT:
			select_this_part()
		elif GameData.current_tool == GameData.ToolMode.DELETE:
			delete_this_part()

func select_this_part():
	if GameData.selected_part and is_instance_valid(GameData.selected_part):
		# Find any Sprite2D anywhere inside the old selected part to reset its color
		for child in GameData.selected_part.find_children("*", "Sprite2D", true, false):
			child.modulate = Color(1, 1, 1)
			
	GameData.selected_part = self
	print("Selected part: ", name)
	
	# Find any Sprite2D inside this part to highlight it
	for child in find_children("*", "Sprite2D", true, false):
		child.modulate = Color(1.4, 1.4, 0.6)

func delete_this_part():
	if GameData.selected_part == self:
		GameData.selected_part = null
		
	print("Deleted part: ", name)
	queue_free()

func _on_area_entered(area):
	if not is_dragging:
		return
	if area.name == "BuildingArea":
		is_in_build_area = true

func _on_area_exited(area):
	if not is_dragging:
		return
	if area.name == "BuildingArea":
		is_in_build_area = false
