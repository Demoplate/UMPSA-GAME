extends Area2D

var is_dragging := false
var is_in_build_area := false
@export var grid_size: float = 16.0

func _ready():
	is_dragging = true
	
	# Connect the overlap signals
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

func start_dragging():
	is_dragging = true

func _input(event):
	if not is_dragging:
		return
		
	if event is InputEventScreenDrag or event is InputEventMouseMotion:
		var target_pos = event.position
		
		# Only snap to grid if we are inside the building area!
		if is_in_build_area:
			global_position = target_pos.snapped(Vector2(grid_size, grid_size))
		else:
			global_position = target_pos # Moves freely outside the zone
			
	# Drop the part when released
	if (event is InputEventScreenTouch and not event.pressed) or \
	   (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed):
		is_dragging = false
		
		# Check if we are overlapping any other parts (ignoring BuildingArea)
		var overlapping_with_part = false
		for area in get_overlapping_areas():
			if area.name != "BuildingArea":
				overlapping_with_part = true
				break
		
		# If it's inside the build area AND not on top of another part, lock it down!
		if is_in_build_area and not overlapping_with_part:
			global_position = global_position.snapped(Vector2(grid_size, grid_size))
		else:
			# Otherwise, delete itself (dropped outside or on another part)
			queue_free()

# Check when entering areas
func _on_area_entered(area):
	if not is_dragging:
		return
		
	if area.name == "BuildingArea":
		is_in_build_area = true

# Check when leaving the build zone
func _on_area_exited(area):
	if not is_dragging:
		return
		
	if area.name == "BuildingArea":
		is_in_build_area = false
