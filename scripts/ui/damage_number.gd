extends Label
class_name DamageNumber

func _ready():
	z_index = 100
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	# Initial styling
	add_theme_color_override("font_color", Color.RED)
	add_theme_font_size_override("font_size", 14)
	add_theme_constant_override("outline_size", 3)
	add_theme_color_override("font_outline_color", Color.BLACK)
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Float up (Reduced distance: 50 -> 25)
	tween.tween_property(self, "position:y", position.y - 100, 0.8)\
		.set_trans(Tween.TRANS_QUART)\
		.set_ease(Tween.EASE_OUT)
	
	# Scale pulse
	scale = Vector2(0.5, 0.5)
	tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.1)
	tween.chain().tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)
	
	# Fade out
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.6).set_delay(0.2)
	
	# Cleanup
	tween.chain().tween_callback(queue_free)

static func create(amount: int, start_pos: Vector2, parent: Node) -> DamageNumber:
	var dn = DamageNumber.new()
	dn.text = str(amount)
	parent.add_child(dn)
	# Start much closer to the unit's center (-40 -> -15)
	dn.global_position = start_pos + Vector2(randf_range(-10, 10), -5)
	return dn
