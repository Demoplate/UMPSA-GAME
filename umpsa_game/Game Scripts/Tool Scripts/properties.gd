extends Control

@onready var wheel_group: Control = $Wheel
@onready var piston_group: Control = $Piston
@onready var thruster_group: Control = $Thruster
@onready var laser_group: Control = $Laser
@onready var saw_group = $Saw

@onready var line_edit_forwards: LineEdit = $Wheel/Forwards
@onready var line_edit_reverse: LineEdit = $Wheel/Reverse
@onready var confirm_btn_wheel: Button = $Wheel/Button2

@onready var line_edit_extend: LineEdit = $Piston/Extend
@onready var line_edit_retract: LineEdit = $Piston/Retract
@onready var confirm_btn_piston: Button = $Piston/Button2

@onready var line_edit_thruster: LineEdit = $Thruster/LineEdit
@onready var confirm_btn_thruster: Button = $Thruster/Button

@onready var line_edit_laser: LineEdit = $Laser/LineEdit
@onready var confirm_btn_laser: Button = $Laser/Button

@onready var line_edit_saw: LineEdit = $Saw/Forwards
@onready var confirm_btn_saw: Button = $Saw/Button2

var target_part: Node2D = null
var is_target_wheel: bool = false
var is_target_piston: bool = false
var is_target_laser: bool = false
var is_target_saw: bool = false
var last_tool = -1

func _ready() -> void:
	hide()
	wheel_group.hide()
	piston_group.hide()
	thruster_group.hide()
	laser_group.hide()
	saw_group.hide()

	confirm_btn_wheel.pressed.connect(_on_confirm_pressed)
	confirm_btn_piston.pressed.connect(_on_confirm_pressed)
	confirm_btn_thruster.pressed.connect(_on_confirm_pressed)
	confirm_btn_laser.pressed.connect(_on_confirm_pressed)
	confirm_btn_saw.pressed.connect(_on_confirm_pressed)

	line_edit_forwards.text_submitted.connect(func(_text): _on_confirm_pressed())
	line_edit_reverse.text_submitted.connect(func(_text): _on_confirm_pressed())
	line_edit_extend.text_submitted.connect(func(_text): _on_confirm_pressed())
	line_edit_retract.text_submitted.connect(func(_text): _on_confirm_pressed())
	line_edit_thruster.text_submitted.connect(func(_text): _on_confirm_pressed())
	line_edit_laser.text_submitted.connect(func(_text): _on_confirm_pressed())
	line_edit_saw.text_submitted.connect(func(_text): _on_confirm_pressed())

	last_tool = GameData.current_tool

func _process(_delta: float) -> void:
	if visible and GameData.current_tool != last_tool:
		close_ui()
	last_tool = GameData.current_tool

func open_for_part(part: Node2D) -> void:
	var scene_path = part.scene_file_path.to_lower() if "scene_file_path" in part else ""

	if not "wheel" in scene_path and not "saw" in scene_path and not "thruster" in scene_path and not "watergun" in scene_path and not "piston" in scene_path and not "laser" in scene_path:
		return

	target_part = part
	show()

	is_target_wheel = "wheel" in scene_path
	is_target_saw = "saw" in scene_path
	is_target_piston = "piston" in scene_path
	is_target_laser = "laser" in scene_path

	wheel_group.visible = is_target_wheel
	saw_group.visible = is_target_saw
	piston_group.visible = is_target_piston
	laser_group.visible = is_target_laser
	thruster_group.visible = not is_target_wheel and not is_target_saw and not is_target_piston and not is_target_laser

	if is_target_wheel:
		if "assigned_key" in part:
			line_edit_forwards.text = part.assigned_key
		if "reverse_key" in part:
			line_edit_reverse.text = part.reverse_key
		line_edit_forwards.grab_focus()
		line_edit_forwards.select_all()
	elif is_target_saw:
		if "assigned_key" in part:
			line_edit_saw.text = part.assigned_key
		line_edit_saw.grab_focus()
		line_edit_saw.select_all()
	elif is_target_piston:
		if "assigned_key" in part:
			line_edit_extend.text = part.assigned_key
		if "reverse_key" in part:
			line_edit_retract.text = part.reverse_key
		line_edit_extend.grab_focus()
		line_edit_extend.select_all()
	elif is_target_laser:
		if "assigned_key" in part:
			line_edit_laser.text = part.assigned_key
		line_edit_laser.grab_focus()
		line_edit_laser.select_all()
	else:
		if "assigned_key" in part:
			line_edit_thruster.text = part.assigned_key
		line_edit_thruster.grab_focus()
		line_edit_thruster.select_all()

func open_for_thruster(thruster: Node2D) -> void:
	open_for_part(thruster)

func open_for_wheel(wheel: Node2D) -> void:
	open_for_part(wheel)

func open_for_saw(saw: Node2D) -> void:
	open_for_part(saw)

func open_for_watergun(watergun: Node2D) -> void:
	open_for_part(watergun)

func open_for_piston(piston: Node2D) -> void:
	open_for_part(piston)

func open_for_laser(laser: Node2D) -> void:
	open_for_part(laser)

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
		elif is_target_saw:
			var saw_text = line_edit_saw.text.strip_edges()
			if saw_text.length() > 0:
				target_part.assigned_key = saw_text[0].to_upper()
				print("Assigned key ", target_part.assigned_key, " to saw.")
		elif is_target_piston:
			var ext_text = line_edit_extend.text.strip_edges()
			var ret_text = line_edit_retract.text.strip_edges()

			if ext_text.length() > 0:
				target_part.assigned_key = ext_text[0].to_upper()
			if ret_text.length() > 0:
				target_part.reverse_key = ret_text[0].to_upper()

			print("Assigned keys - Extend: ", target_part.get("assigned_key"), ", Retract: ", target_part.get("reverse_key"), " to piston.")
		elif is_target_laser:
			var laser_text = line_edit_laser.text.strip_edges()
			if laser_text.length() > 0:
				target_part.assigned_key = laser_text[0].to_upper()
				print("Assigned key ", target_part.assigned_key, " to laser.")
		else:
			var typed_text = line_edit_thruster.text.strip_edges()
			if typed_text.length() > 0:
				target_part.assigned_key = typed_text[0].to_upper()
				print("Assigned key ", target_part.assigned_key, " to part.")

	close_ui()

func close_ui() -> void:
	hide()
	wheel_group.hide()
	piston_group.hide()
	thruster_group.hide()
	laser_group.hide()
	saw_group.hide()
	target_part = null
