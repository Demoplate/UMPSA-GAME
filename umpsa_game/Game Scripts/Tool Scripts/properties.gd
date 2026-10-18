extends Control

@onready var wheel_group: Control = $Wheel
@onready var thruster_group: Control = $Thruster

@onready var line_edit_forwards: LineEdit = $Wheel/Forwards
@onready var line_edit_reverse: LineEdit = $Wheel/Reverse
@onready var confirm_btn_wheel: Button = $Wheel/Button2

@onready var line_edit_thruster: LineEdit = $Thruster/LineEdit
@onready var confirm_btn_thruster: Button = $Thruster/Button

var target_part: Node2D = null
var is_target_wheel: bool = false
var last_tool = -1

func _ready() -> void:
	hide()
	wheel_group.hide()
	thruster_group.hide()
	
	confirm_btn_wheel.pressed.connect(_on_confirm_pressed)
	confirm_btn_thruster.pressed.connect(_on_confirm_pressed)
	
	line_edit_forwards.text_submitted.connect(func(_text): _on_confirm_pressed())
	line_edit_reverse.text_submitted.connect(func(_text): _on_confirm_pressed())
	line_edit_thruster.text_submitted.connect(func(_text): _on_confirm_pressed())
	
	last_tool = GameData.current_tool

func _process(_delta: float) -> void:
	if visible and GameData.current_tool != last_tool:
		close_ui()
	last_tool = GameData.current_tool

func open_for_part(part: Node2D) -> void:
	var scene_path = part.scene_file_path.to_lower() if "scene_file_path" in part else ""
	
	# If it's a standard block or command part, they don't use keys—don't open UI
	if not "wheel" in scene_path and not "thruster" in scene_path and not "watergun" in scene_path:
		return

	target_part = part
	show()
	
	is_target_wheel = "wheel" in scene_path
	
	wheel_group.visible = is_target_wheel
	thruster_group.visible = not is_target_wheel
	
	if is_target_wheel:
		if "assigned_key" in part:
			line_edit_forwards.text = part.assigned_key
		if "reverse_key" in part:
			line_edit_reverse.text = part.reverse_key
		line_edit_forwards.grab_focus()
		line_edit_forwards.select_all()
	else:
		# Handles both thrusters and waterguns since they both use a single assigned key
		if "assigned_key" in part:
			line_edit_thruster.text = part.assigned_key
		line_edit_thruster.grab_focus()
		line_edit_thruster.select_all()

func open_for_thruster(thruster: Node2D) -> void:
	open_for_part(thruster)

func open_for_wheel(wheel: Node2D) -> void:
	open_for_part(wheel)

func open_for_watergun(watergun: Node2D) -> void:
	open_for_part(watergun)

func _on_confirm_pressed() -> void:
	if target_part and is_instance_valid(target_part):
		if is_target_wheel:
			var fwd_text = line_edit_forwards.text.strip_edges()
			var rev_text = line_edit_reverse.text.strip_edges()
			
			if fwd_text.length() > 0:
				target_part.assigned_key = fwd_text[0].to_upper()
			if rev_text.length() > 0:
				target_part.reverse_key = rev_text[0].to_upper()
				
			print("Assigned keys - Forward: ", target_part.get("assigned_key"), ", Reverse: ", target_part.get("reverse_key"), " to wheel.")
		else:
			var typed_text = line_edit_thruster.text.strip_edges()
			if typed_text.length() > 0:
				target_part.assigned_key = typed_text[0].to_upper()
				print("Assigned key ", target_part.assigned_key, " to part.")
	
	close_ui()

func close_ui() -> void:
	hide()
	wheel_group.hide()
	thruster_group.hide()
	target_part = null
