extends Control

enum Speaker { ALIEN, HUMAN }

@export var dialogue_speakers: Array[Speaker] = [
	Speaker.ALIEN,
	Speaker.HUMAN,
	Speaker.ALIEN,
	Speaker.HUMAN
]

@export_multiline var dialogue_lines: Array[String] = [
	"Hello! I am an alien from outer space.",
	"Greetings, human! Welcome to our dialogue system.",
	"This text appears one letter at a time automatically.",
	"You can click NEXT to continue, or SKIP to exit."
]

@export_file("*.tscn") var next_scene_path: String # Assign your next scene in the Inspector

@export var text_speed: float = 0.03 # Time in seconds per letter

@export_group("Audio Streams")
@export var alien_blip_sound: AudioStream
@export var human_blip_sound: AudioStream

@export_group("Alien Pitch")
@export var alien_min_pitch: float = 1.1
@export var alien_max_pitch: float = 1.4

@export_group("Human Pitch")
@export var human_min_pitch: float = 0.8
@export var human_max_pitch: float = 1.0

@onready var cute_alien_node: Sprite2D = $Cutealien
@onready var human_node: Sprite2D = $Human
@onready var panel_node: Control = $Panel
@onready var text_label: Label = $Text
@onready var next_button: Button = $NEXT
@onready var skip_button: Button = $SKIP
@onready var blip_sound: AudioStreamPlayer = $BlipSound

var current_line_index: int = 0
var tween: Tween
var is_typing: bool = false
var _last_visible_chars: int = 0

func _ready() -> void:
	next_button.pressed.connect(_on_next_pressed)
	skip_button.pressed.connect(_on_skip_pressed)
	show_line(current_line_index)

func _process(_delta: float) -> void:
	if is_typing and text_label.visible_characters > _last_visible_chars:
		_play_blip_sound()
		_last_visible_chars = text_label.visible_characters

func show_line(index: int) -> void:
	# If we've gone past the last line, trigger scene change or finish
	if index >= dialogue_lines.size():
		_finish_dialogue()
		return
		
	current_line_index = index
	text_label.text = dialogue_lines[current_line_index]
	
	var current_speaker = dialogue_speakers[current_line_index] if current_line_index < dialogue_speakers.size() else Speaker.ALIEN
	
	if current_speaker == Speaker.ALIEN:
		cute_alien_node.visible = true
		human_node.visible = false
		panel_node.modulate = Color.WHITE
	else:
		cute_alien_node.visible = false
		human_node.visible = true
		panel_node.modulate = Color(0.2, 1.0, 0.2)
	
	text_label.visible_characters = 0
	_last_visible_chars = 0
	is_typing = true
	
	if tween and tween.is_valid():
		tween.kill()
		
	tween = create_tween()
	var total_chars = text_label.text.length()
	tween.tween_property(text_label, "visible_characters", total_chars, total_chars * text_speed)
	tween.finished.connect(func(): is_typing = false)

func _play_blip_sound() -> void:
	if not blip_sound:
		return
		
	var current_speaker = dialogue_speakers[current_line_index] if current_line_index < dialogue_speakers.size() else Speaker.ALIEN
	
	if current_speaker == Speaker.ALIEN:
		if alien_blip_sound:
			blip_sound.stream = alien_blip_sound
		blip_sound.pitch_scale = randf_range(alien_min_pitch, alien_max_pitch)
	else:
		if human_blip_sound:
			blip_sound.stream = human_blip_sound
		blip_sound.pitch_scale = randf_range(human_min_pitch, human_max_pitch)
		
	if blip_sound.stream:
		blip_sound.play()

func _on_next_pressed() -> void:
	if is_typing:
		if tween and tween.is_valid():
			tween.kill()
		text_label.visible_characters = text_label.text.length()
		is_typing = false
	else:
		# Advance to the next line (or finish if it's the last one)
		show_line(current_line_index + 1)

func _on_skip_pressed() -> void:
	_finish_dialogue()

func _finish_dialogue() -> void:
	if next_scene_path and not next_scene_path.is_empty():
		get_tree().change_scene_to_file(next_scene_path)
	else:
		hide()
