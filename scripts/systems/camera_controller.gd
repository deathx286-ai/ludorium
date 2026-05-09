extends Camera2D

@export var move_speed: float = 600.0
@export var edge_scroll_enabled: bool = true
@export var edge_scroll_margin: float = 25.0
@export var edge_scroll_speed: float = 700.0

@export var keyboard_scroll_enabled: bool = true

@export var zoom_enabled: bool = true
@export var zoom_step: float = 1.12
@export var min_zoom: float = 0.45
@export var max_zoom: float = 2.25

func _unhandled_input(event):
	if not zoom_enabled:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_camera(zoom_step)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_camera(1.0 / zoom_step)
			get_viewport().set_input_as_handled()

func _process(delta):
	var movement = Vector2.ZERO

	if keyboard_scroll_enabled:
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			movement.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			movement.y += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			movement.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			movement.x += 1

	if edge_scroll_enabled:
		var mouse_pos = get_viewport().get_mouse_position()
		var viewport_size = get_viewport_rect().size

		if mouse_pos.x <= edge_scroll_margin:
			movement.x -= 1
		if mouse_pos.x >= viewport_size.x - edge_scroll_margin:
			movement.x += 1
		if mouse_pos.y <= edge_scroll_margin:
			movement.y -= 1
		if mouse_pos.y >= viewport_size.y - edge_scroll_margin:
			movement.y += 1

	if movement.length() > 0:
		movement = movement.normalized()

		var speed = move_speed
		if edge_scroll_enabled:
			speed = edge_scroll_speed

		global_position += movement * speed * delta
		clamp_camera_to_limits()

func clamp_camera_to_limits():
	global_position.x = clamp(global_position.x, limit_left, limit_right)
	global_position.y = clamp(global_position.y, limit_top, limit_bottom)

func zoom_camera(zoom_multiplier: float):
	var mouse_world_before_zoom = get_global_mouse_position()
	var new_zoom_value = clamp(zoom.x * zoom_multiplier, min_zoom, max_zoom)

	zoom = Vector2.ONE * new_zoom_value

	var mouse_world_after_zoom = get_global_mouse_position()
	global_position += mouse_world_before_zoom - mouse_world_after_zoom
	clamp_camera_to_limits()
