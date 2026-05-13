extends Node2D
class_name PlayerUnitSelectionManager

@export var placement_manager: Node
@export var grid_manager: Node
@export var unit_commander: UnitCommander
@export var click_drag_threshold: float = 8.0
@export var drag_fill_color: Color = Color(0.2, 0.75, 1.0, 0.12)
@export var drag_outline_color: Color = Color(0.2, 0.75, 1.0, 0.85)
@export var defend_radius_tiles: int = 6

signal selection_changed(units: Array[Node2D])

var selected_units: Array[Node2D] = []
var is_dragging: bool = false
var drag_start_screen_position: Vector2 = Vector2.ZERO
var drag_current_screen_position: Vector2 = Vector2.ZERO
var drag_start_world_position: Vector2 = Vector2.ZERO
var drag_current_world_position: Vector2 = Vector2.ZERO
var attack_move_armed: bool = false

func _ready():
	add_to_group("player_selection_manager")
	ensure_unit_commander()

func _process(_delta):
	if not selected_units.is_empty():
		var original_count = selected_units.size()
		prune_invalid_selection()
		if selected_units.size() != original_count:
			selection_changed.emit(selected_units)

func _unhandled_input(event):
	if not is_selection_input_enabled():
		return

	if event is InputEventKey and event.pressed and not event.echo:
		handle_key_command(event)
		return

	if event is InputEventMouseButton:
		handle_mouse_button(event)
		return

	if event is InputEventMouseMotion and is_dragging:
		drag_current_screen_position = event.position
		drag_current_world_position = get_global_mouse_position()
		queue_redraw()

func _draw():
	if not is_dragging:
		return

	if drag_start_screen_position.distance_to(drag_current_screen_position) < click_drag_threshold:
		return

	var drag_rect = Rect2(
		to_local(drag_start_world_position),
		drag_current_world_position - drag_start_world_position
	).abs()

	draw_rect(drag_rect, drag_fill_color, true)
	draw_rect(drag_rect, drag_outline_color, false, 2.0)

func handle_mouse_button(event: InputEventMouseButton):
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			start_selection_drag(event.position)
		else:
			finish_selection_drag(event.position, event.shift_pressed)
		get_viewport().set_input_as_handled()
		return

	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		issue_context_command(event.position)
		get_viewport().set_input_as_handled()

func handle_key_command(event: InputEventKey):
	match event.keycode:
		KEY_A:
			attack_move_armed = true
			get_viewport().set_input_as_handled()
		KEY_S:
			stop_selected_units()
			attack_move_armed = false
			get_viewport().set_input_as_handled()
		KEY_H:
			hold_selected_units()
			attack_move_armed = false
			get_viewport().set_input_as_handled()
		KEY_D:
			defend_selected_units()
			attack_move_armed = false
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			clear_selection()
			attack_move_armed = false
			get_viewport().set_input_as_handled()

func start_selection_drag(screen_position: Vector2):
	is_dragging = true
	drag_start_screen_position = screen_position
	drag_current_screen_position = screen_position
	drag_start_world_position = get_global_mouse_position()
	drag_current_world_position = drag_start_world_position
	queue_redraw()

func finish_selection_drag(screen_position: Vector2, additive_selection: bool):
	if not is_dragging:
		return

	is_dragging = false
	drag_current_screen_position = screen_position
	drag_current_world_position = get_global_mouse_position()

	if drag_start_screen_position.distance_to(drag_current_screen_position) >= click_drag_threshold:
		select_units_in_drag_rect(additive_selection)
	else:
		select_unit_under_mouse(additive_selection)

	queue_redraw()
	selection_changed.emit(selected_units)

func select_unit_under_mouse(additive_selection: bool):
	var unit = get_selectable_unit_under_mouse()

	if unit == null:
		if not additive_selection:
			clear_selection()
		return

	if additive_selection:
		toggle_unit_selection(unit)
		return

	set_selection([unit])

func select_units_in_drag_rect(additive_selection: bool):
	var drag_rect = get_drag_screen_rect()
	var found_units: Array[Node2D] = []

	for unit in get_player_selectable_units():
		if drag_rect.has_point(world_to_screen(unit.global_position)):
			found_units.append(unit)

	if additive_selection:
		for unit in found_units:
			add_unit_to_selection(unit)
		return

	set_selection(found_units)

func issue_context_command(screen_position: Vector2):
	if selected_units.is_empty():
		return

	prune_invalid_selection()

	var hostile_target = get_hostile_target_under_screen_position(screen_position)
	if hostile_target != null:
		attack_selected_units(hostile_target)
		attack_move_armed = false
		return

	var destination = get_global_mouse_position()
	if grid_manager != null and grid_manager.has_method("snap_world_to_tile_center"):
		destination = grid_manager.snap_world_to_tile_center(destination)

	if attack_move_armed:
		attack_move_selected_units(destination)
		attack_move_armed = false
		return

	move_selected_units(destination)

func move_selected_units(destination: Vector2):
	prune_invalid_selection()
	ensure_unit_commander()
	unit_commander.command_move_units(selected_units, destination)

func attack_selected_units(target: Node2D):
	prune_invalid_selection()
	ensure_unit_commander()
	unit_commander.command_attack_units(selected_units, target)

func attack_move_selected_units(destination: Vector2):
	prune_invalid_selection()
	ensure_unit_commander()
	unit_commander.command_attack_move_units(selected_units, destination)

func stop_selected_units():
	ensure_unit_commander()
	unit_commander.command_stop_units(selected_units)

func hold_selected_units():
	ensure_unit_commander()
	unit_commander.command_hold_units(selected_units)

func defend_selected_units():
	ensure_unit_commander()
	unit_commander.command_defend_units(selected_units)

func set_selection(units: Array[Node2D]):
	clear_selection()

	for unit in units:
		add_unit_to_selection(unit)

func add_unit_to_selection(unit: Node2D):
	if unit == null or selected_units.has(unit):
		return

	selected_units.append(unit)
	set_unit_selected(unit, true)

func toggle_unit_selection(unit: Node2D):
	if selected_units.has(unit):
		selected_units.erase(unit)
		set_unit_selected(unit, false)
		return

	add_unit_to_selection(unit)

func clear_selection():
	ensure_unit_commander()
	unit_commander.cancel_orders_for_units(selected_units)

	for unit in selected_units:
		if is_instance_valid(unit):
			set_unit_selected(unit, false)

	selected_units.clear()

func ensure_unit_commander():
	if unit_commander == null or not is_instance_valid(unit_commander):
		unit_commander = get_node_or_null("UnitCommander") as UnitCommander

		if unit_commander == null:
			unit_commander = UnitCommander.new()
			unit_commander.name = "UnitCommander"
			add_child(unit_commander)

	unit_commander.grid_manager = grid_manager
	unit_commander.defend_radius_tiles = defend_radius_tiles

func prune_invalid_selection():
	var valid_units: Array[Node2D] = []

	for unit in selected_units:
		if is_instance_valid(unit):
			valid_units.append(unit)

	selected_units = valid_units

func set_unit_selected(unit: Node, selected: bool):
	if unit != null and unit.has_method("set_selected"):
		unit.call("set_selected", selected)

func get_selectable_unit_under_mouse() -> Node2D:
	var mouse_world_position = get_global_mouse_position()
	var closest_unit: Node2D = null
	var closest_distance_squared = INF

	for unit in get_player_selectable_units():
		if not is_mouse_over_unit(unit, mouse_world_position):
			continue

		var distance_squared = unit.global_position.distance_squared_to(mouse_world_position)
		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_unit = unit

	return closest_unit

func get_hostile_target_under_screen_position(screen_position: Vector2) -> Node2D:
	var mouse_world_position = get_global_mouse_position()
	var closest_target: Node2D = null
	var closest_distance_squared = INF

	for target in get_attack_target_candidates_for_selection():
		if not target is Node2D:
			continue

		if not Rect2(screen_position - Vector2.ONE * 24.0, Vector2.ONE * 48.0).has_point(world_to_screen((target as Node2D).global_position)):
			if not HitboxMath.contains_point(target as Node2D, mouse_world_position):
				continue

		var distance_squared = (target as Node2D).global_position.distance_squared_to(mouse_world_position)
		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_target = target

	return closest_target

func get_attack_target_candidates_for_selection() -> Array[Node]:
	if selected_units.is_empty():
		return []

	var first_unit = selected_units[0]
	if is_instance_valid(first_unit) and first_unit.has_method("get_attack_target_candidates"):
		var candidates: Array[Node] = []

		for candidate in first_unit.call("get_attack_target_candidates"):
			if candidate is Node:
				candidates.append(candidate)

		return candidates

	return get_tree().get_nodes_in_group("enemy")

func get_player_selectable_units() -> Array[Node2D]:
	var units: Array[Node2D] = []

	for node in get_tree().get_nodes_in_group("player"):
		if not node is Node2D:
			continue

		if not node.has_method("set_selected"):
			continue

		units.append(node)

	return units

func is_mouse_over_unit(unit: Node2D, mouse_world_position: Vector2) -> bool:
	if unit == null:
		return false

	if unit.has_method("get_hitbox") and unit.call("get_hitbox") != null:
		return HitboxMath.contains_point(unit, mouse_world_position)

	return unit.global_position.distance_to(mouse_world_position) <= 36.0

func get_drag_screen_rect() -> Rect2:
	return Rect2(
		drag_start_screen_position,
		drag_current_screen_position - drag_start_screen_position
	).abs()

func world_to_screen(world_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_position

func is_selection_input_enabled() -> bool:
	if placement_manager == null:
		return true

	var placement_enabled = bool(placement_manager.get("placement_enabled")) if has_property(placement_manager, "placement_enabled") else false

	return not placement_enabled

func has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false

	for property in object.get_property_list():
		if str(property.get("name")) == property_name:
			return true

	return false
