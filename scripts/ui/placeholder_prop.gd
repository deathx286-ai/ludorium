extends Node2D

@export var prop_type: String = "tree"

func setup(type: String) -> void:
	prop_type = type
	queue_redraw()

func _draw() -> void:
	match prop_type:
		"tree":
			draw_rect(Rect2(Vector2(-3.0, -2.0), Vector2(6.0, 14.0)), Color.SADDLE_BROWN, true)
			draw_circle(Vector2(0.0, -8.0), 12.0, Color.FOREST_GREEN)
		"dead_tree":
			draw_line(Vector2(0.0, 12.0), Vector2(0.0, -12.0), Color.SADDLE_BROWN, 4.0)
			draw_line(Vector2(0.0, -5.0), Vector2(-9.0, -13.0), Color.SADDLE_BROWN, 3.0)
			draw_line(Vector2(0.0, -3.0), Vector2(9.0, -10.0), Color.SADDLE_BROWN, 3.0)
		"rock":
			draw_colored_polygon(PackedVector2Array([
				Vector2(-12.0, 8.0),
				Vector2(-8.0, -8.0),
				Vector2(4.0, -12.0),
				Vector2(13.0, -1.0),
				Vector2(8.0, 10.0)
			]), Color.GRAY)
		"mushroom":
			draw_rect(Rect2(Vector2(-3.0, -1.0), Vector2(6.0, 12.0)), Color.ANTIQUE_WHITE, true)
			draw_circle(Vector2(0.0, -4.0), 10.0, Color.PURPLE)
		"reeds":
			for x in [-8.0, -3.0, 3.0, 8.0]:
				draw_line(Vector2(x, 12.0), Vector2(x * 0.5, -12.0), Color.DARK_GREEN, 2.0)
		"lava_crack":
			draw_line(Vector2(-12.0, 8.0), Vector2(-3.0, -2.0), Color.ORANGE_RED, 4.0)
			draw_line(Vector2(-3.0, -2.0), Vector2(6.0, 2.0), Color.ORANGE_RED, 4.0)
			draw_line(Vector2(6.0, 2.0), Vector2(12.0, -10.0), Color.ORANGE_RED, 4.0)
		"bones":
			draw_line(Vector2(-10.0, -8.0), Vector2(10.0, 8.0), Color.ANTIQUE_WHITE, 3.0)
			draw_line(Vector2(-10.0, 8.0), Vector2(10.0, -8.0), Color.ANTIQUE_WHITE, 3.0)
		"ruins":
			draw_rect(Rect2(Vector2(-12.0, -10.0), Vector2(8.0, 20.0)), Color.DARK_SLATE_GRAY, true)
			draw_rect(Rect2(Vector2(3.0, -6.0), Vector2(9.0, 16.0)), Color.DARK_SLATE_GRAY, true)
		"black_crystal":
			draw_colored_polygon(PackedVector2Array([
				Vector2(0.0, -14.0),
				Vector2(10.0, -2.0),
				Vector2(4.0, 13.0),
				Vector2(-7.0, 9.0),
				Vector2(-10.0, -3.0)
			]), Color.BLACK)
		_:
			draw_circle(Vector2.ZERO, 8.0, Color.WHITE)
