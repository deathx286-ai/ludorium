extends Node2D

@export var prop_type: String = "tree"
@onready var label: Label = $Label
@onready var sprite: Sprite2D = $Sprite2D

func setup(type: String):
	prop_type = type
	if label == null:
		label = Label.new()
		label.name = "Label"
		add_child(label)
	
	label.text = prop_type.substr(0, 1).to_upper()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector2(-10, -10)
	
	# Color based on type for visual distinction
	match prop_type:
		"tree": modulate = Color.FOREST_GREEN
		"dead_tree": modulate = Color.SADDLE_BROWN
		"rock": modulate = Color.GRAY
		"mushroom", "reeds": modulate = Color.PURPLE
		"lava_crack": modulate = Color.ORANGE_RED
		"bones": modulate = Color.ANTIQUE_WHITE
		"ruins": modulate = Color.DARK_SLATE_GRAY
		"black_crystal": modulate = Color.BLACK
