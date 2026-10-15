extends Control

@onready var line_edit: LineEdit = $LineEdit
@onready var confirm_button: Button = $Button

var target_thruster: Node2D = null

func _ready() -> void:
	hide()
	confirm_button.pressed.connect(_on_confirm_pressed)

# Called from the thruster when selected
func open_for_thruster(thruster: Node2D) -> void:
	target_thruster = thruster
	if "assigned_key" in thruster:
		line_edit.text = thruster.assigned_key
	show()
	line_edit.grab_focus()

func _on_confirm_pressed() -> void:
	if target_thruster and is_instance_valid(target_thruster):
		# Take the first character, make it uppercase, and assign it
		var typed_text = line_edit.text.strip_edges()
		if typed_text.length() > 0:
			target_thruster.assigned_key = typed_text[0].to_upper()
			print("Assigned key ", target_thruster.assigned_key, " to thruster.")
	
	hide()
	target_thruster = null
