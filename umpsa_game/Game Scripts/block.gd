extends Area2D

@export var grid_size: float = 32.0
var is_dragging := false
var is_in_build_area := false

func _ready():
	is_dragging = true
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

func start_dragging():
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
