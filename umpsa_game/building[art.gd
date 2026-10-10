extends Area2D

@export var part_scene: PackedScene

# This function ONLY fires when the collision shape of this Area2D is touched or clicked
func _input_event(_viewport, event, _shape_idx):
	if (event is InputEventScreenTouch and event.pressed) or \
	   (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		spawn_and_drag(event.global_position)

func spawn_and_drag(pos: Vector2):
	if not part_scene:
		return
		
	var new_part = part_scene.instantiate()
	
	# Add directly to the root viewport/scene tree
	get_tree().root.add_child(new_part)
	
	# Force scale back to normal and set global position
	new_part.scale = Vector2(1, 1)
	new_part.global_position = pos
	
	if new_part.has_method("start_dragging"):
		new_part.start_dragging()
