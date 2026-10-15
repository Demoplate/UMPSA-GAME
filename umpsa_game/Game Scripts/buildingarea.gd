extends Area2D

@export var part_scene: PackedScene
@export var rotate_button: Area2D # Drag your rotate button Area2D here

@onready var collision_shape: CollisionShape2D = $CollisionShape2D 
@onready var sprite: Sprite2D = $Sprite2D # Make sure this matches your sprite node name, or delete if you don't have one named Sprite2D

func _ready() -> void:
	if rotate_button:
		rotate_button.input_event.connect(_on_rotate_button_clicked)
	else:
		print("Bro, assign the rotate_button in the inspector!")

func _process(_delta: float) -> void:
	var is_select_or_delete = false
	
	# Check GameData's current_tool enum
	if "current_tool" in GameData:
		if GameData.current_tool == GameData.ToolMode.SELECT or GameData.current_tool == GameData.ToolMode.DELETE:
			is_select_or_delete = true

	# Hide/show and disable/enable collisions based on the tool mode
	visible = !is_select_or_delete
	
	if sprite:
		sprite.visible = !is_select_or_delete
		
	if collision_shape:
		collision_shape.disabled = is_select_or_delete
		
	if rotate_button:
		rotate_button.visible = !is_select_or_delete
		for child in rotate_button.get_children():
			if child is CollisionShape2D:
				child.disabled = is_select_or_delete
# Triggered when clicking the rotation button
func _on_rotate_button_clicked(viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not visible:
		return
		
	if (event is InputEventScreenTouch and event.pressed) or \
	   (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		
		viewport.set_input_as_handled()
		rotate(deg_to_rad(90.0))

# Triggered when clicking the main spawner to clone a part
func _input_event(viewport, event, _shape_idx):
	if not visible:
		return
		
	if (event is InputEventScreenTouch and event.pressed) or \
	   (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		
		viewport.set_input_as_handled()
		spawn_and_drag(global_position)

func spawn_and_drag(pos: Vector2):
	if not part_scene:
		return
		
	var new_part = part_scene.instantiate() as Node2D
	get_tree().current_scene.add_child(new_part)
	
	new_part.top_level = true
	new_part.global_position = pos
	new_part.global_rotation = global_rotation
	
	if new_part.has_method("start_dragging"):
		new_part.start_dragging()
