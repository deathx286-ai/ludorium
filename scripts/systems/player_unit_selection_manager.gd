extends Node2D
class_name PlayerUnitSelectionManager

@export var placement_manager: Node
@export var grid_manager: Node
@export var click_drag_threshold: float = 8.0
@export var drag_fill_color: Color = Color(0.2, 0.75, 1.0, 0.12)
@export var drag_outline_color: Color = Color(0.2, 0.75, 1.0, 0.85)
@export var formation_spacing_tiles: int = 1
@export var defend_radius_tiles: int = 6

var selected_units: Array[Node2D] = []
var is_dragging: bool = false
var drag_start_screen_position: Vector2 = Vector2.ZERO
var drag_current_screen_position: Vector2 = Vector2.ZERO
var drag_start_world_position: Vector2 = Vector2.ZERO
var drag_current_world_position: Vector2 = Vector2.ZERO
var attack_move_armed: bool = false

func _ready():
	add_to_group("player_selection_manager")

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
	var formation_destinations = get_current_formation_destinations(destination)
	clear_group_reservations()
	apply_group_movement_context(formation_destinations)

	for i in range(selected_units.size()):
		var unit = selected_units[i]
		if not is_instance_valid(unit):
			continue

		var unit_destination = formation_destinations.get(unit.get_instance_id(), get_formation_destination(destination, i))
		if unit.has_method("command_move_to_position"):
			unit.call("command_move_to_position", unit_destination)

func attack_selected_units(target: Node2D):
	var attack_destinations = get_surround_attack_destinations(target)
	var accepted_attack_destinations := {}
	clear_group_reservations()

	for unit in selected_units:
		if not is_instance_valid(unit):
			continue

		var unit_id = unit.get_instance_id()
		if attack_destinations.has(unit_id) and unit.has_method("command_attack_target_from_position"):
			if bool(unit.call("command_attack_target_from_position", target, attack_destinations[unit_id], true)):
				accepted_attack_destinations[unit_id] = attack_destinations[unit_id]
		elif unit.has_method("command_attack_target"):
			unit.call("command_attack_target", target, true)

	apply_group_path_ignore_for_units(accepted_attack_destinations)

func attack_move_selected_units(destination: Vector2):
	var formation_destinations = get_current_formation_destinations(destination)
	clear_group_reservations()
	apply_group_movement_context(formation_destinations)

	for i in range(selected_units.size()):
		var unit = selected_units[i]
		if not is_instance_valid(unit):
			continue

		var unit_destination = formation_destinations.get(unit.get_instance_id(), get_formation_destination(destination, i))
		if unit.has_method("command_attack_move_to_position"):
			unit.call("command_attack_move_to_position", unit_destination)

func stop_selected_units():
	for unit in selected_units:
		if is_instance_valid(unit) and unit.has_method("command_stop"):
			unit.call("command_stop")

func hold_selected_units():
	for unit in selected_units:
		if is_instance_valid(unit) and unit.has_method("command_hold_position"):
			unit.call("command_hold_position")

func defend_selected_units():
	for unit in selected_units:
		if is_instance_valid(unit) and unit.has_method("command_defend_area"):
			unit.call("command_defend_area", unit.global_position, defend_radius_tiles)

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
	for unit in selected_units:
		if is_instance_valid(unit):
			set_unit_selected(unit, false)

	selected_units.clear()

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

func get_formation_destination(center_destination: Vector2, unit_index: int) -> Vector2:
	if grid_manager == null:
		return center_destination

	var center_cell = grid_manager.world_to_cell(center_destination)
	var offset = get_formation_cell_offset(unit_index) * maxi(formation_spacing_tiles, 1)
	return grid_manager.cell_to_world(center_cell + offset)

func get_current_formation_destinations(destination: Vector2) -> Dictionary:
	var destinations := {}

	if grid_manager == null or selected_units.is_empty():
		return destinations

	var valid_units: Array[Node2D] = []
	var unit_cells := {}
	var min_cell = Vector2i(999999, 999999)
	var max_cell = Vector2i(-999999, -999999)

	for unit in selected_units:
		if not is_instance_valid(unit):
			continue

		var cell = grid_manager.world_to_cell(unit.global_position)
		valid_units.append(unit)
		unit_cells[unit.get_instance_id()] = cell
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)

	if valid_units.is_empty():
		return destinations

	var clicked_cell = grid_manager.world_to_cell(destination)
	var formation_size = max_cell - min_cell + Vector2i.ONE
	var destination_anchor = clicked_cell - Vector2i(
		floori(float(formation_size.x) / 2.0),
		floori(float(formation_size.y) / 2.0)
	)
	var used_destination_cells := {}

	for unit in valid_units:
		var unit_id = unit.get_instance_id()
		var current_cell: Vector2i = unit_cells[unit_id]
		var offset = current_cell - min_cell
		var preferred_destination_cell = clamp_cell_to_grid(destination_anchor + offset)
		var destination_cell = get_nearest_unused_formation_destination_cell(preferred_destination_cell, used_destination_cells)
		used_destination_cells[destination_cell] = true
		destinations[unit_id] = grid_manager.cell_to_world(destination_cell)

	return destinations

func get_nearest_unused_formation_destination_cell(preferred_cell: Vector2i, used_cells: Dictionary) -> Vector2i:
	if not used_cells.has(preferred_cell):
		return preferred_cell

	if grid_manager == null or not grid_manager.has_method("get_cells_in_tile_range"):
		return preferred_cell

	var search_radius_limit = maxi(selected_units.size() + 2, 2)

	for radius in range(1, search_radius_limit + 1):
		for candidate in grid_manager.get_cells_in_tile_range(preferred_cell, radius, true):
			if used_cells.has(candidate):
				continue

			return candidate

	return preferred_cell

func get_surround_attack_destinations(target: Node2D) -> Dictionary:
	var destinations := {}

	if grid_manager == null or target == null or not is_instance_valid(target):
		return destinations

	var used_cells := {}

	for unit in selected_units:
		if not is_instance_valid(unit):
			continue

		var attack_cell = get_best_attack_slot_cell_for_unit(unit, target, used_cells)
		if attack_cell == Vector2i(-1, -1):
			continue

		used_cells[attack_cell] = true
		destinations[unit.get_instance_id()] = grid_manager.cell_to_world(attack_cell)

	return destinations

func get_best_attack_slot_cell_for_unit(unit: Node2D, target: Node2D, used_cells: Dictionary) -> Vector2i:
	var best_cell = Vector2i(-1, -1)
	var best_score = INF
	var target_cells = grid_manager.get_footprint_cells_for_node(target)
	var target_cell_lookup := {}
	var candidate_cells := {}
	var range_tiles = 1

	if unit.has_method("get_attack_range_tile_count"):
		range_tiles = maxi(int(unit.call("get_attack_range_tile_count")), 1)

	if target_cells.is_empty():
		return best_cell

	for target_cell in target_cells:
		target_cell_lookup[target_cell] = true

	for target_cell in target_cells:
		for radius in range(1, range_tiles + 1):
			for candidate in grid_manager.get_cells_in_tile_range(target_cell, radius, false):
				if target_cell_lookup.has(candidate):
					continue

				if used_cells.has(candidate):
					continue

				candidate_cells[candidate] = true

	for candidate in candidate_cells.keys():
		var candidate_world_position = grid_manager.cell_to_world(candidate)
		var distance_score = unit.global_position.distance_squared_to(candidate_world_position)
		var tile_range_score = abs(range_tiles - get_tile_distance_to_target_cells(candidate, target_cells))
		var score = distance_score + float(tile_range_score * tile_range_score * grid_manager.tile_size * grid_manager.tile_size)

		if score < best_score:
			best_score = score
			best_cell = candidate

	return best_cell

func get_tile_distance_to_target_cells(candidate: Vector2i, target_cells: Array[Vector2i]) -> int:
	var best_distance = 999999

	for target_cell in target_cells:
		var offset = candidate - target_cell
		var distance = maxi(abs(offset.x), abs(offset.y))
		best_distance = mini(best_distance, distance)

	return best_distance

func apply_group_movement_context(formation_destinations: Dictionary, require_destination: bool = false):
	for unit in selected_units:
		if not is_instance_valid(unit):
			continue

		var allowed_destination_cells: Array[Vector2i] = []
		var unit_id = unit.get_instance_id()

		if require_destination and not formation_destinations.has(unit_id):
			continue

		if grid_manager != null and formation_destinations.has(unit_id):
			allowed_destination_cells.append(grid_manager.world_to_cell(formation_destinations[unit_id]))

		if unit.has_method("set_movement_group_context"):
			unit.call("set_movement_group_context", selected_units, allowed_destination_cells)
		elif unit.has_method("set_movement_ignore_nodes"):
			unit.call("set_movement_ignore_nodes", selected_units)

func apply_group_path_ignore_for_units(unit_destinations: Dictionary):
	for unit in selected_units:
		if not is_instance_valid(unit):
			continue

		if not unit_destinations.has(unit.get_instance_id()):
			continue

		if unit.has_method("set_movement_ignore_nodes"):
			unit.call("set_movement_ignore_nodes", selected_units)

func clear_group_reservations():
	for unit in selected_units:
		if is_instance_valid(unit) and unit.has_method("clear_grid_reservations"):
			unit.call("clear_grid_reservations")

func clamp_cell_to_grid(cell: Vector2i) -> Vector2i:
	if grid_manager == null:
		return cell

	var max_x = int(grid_manager.get("grid_width")) - 1 if has_property(grid_manager, "grid_width") else cell.x
	var max_y = int(grid_manager.get("grid_height")) - 1 if has_property(grid_manager, "grid_height") else cell.y

	return Vector2i(
		clampi(cell.x, 0, max_x),
		clampi(cell.y, 0, max_y)
	)

func get_formation_cell_offset(unit_index: int) -> Vector2i:
	if unit_index <= 0:
		return Vector2i.ZERO

	var ring = 1
	var remaining_index = unit_index

	while true:
		var ring_count = ring * 8
		if remaining_index <= ring_count:
			break

		remaining_index -= ring_count
		ring += 1

	var side_length = ring * 2
	var side_index = remaining_index - 1
	var side = int(side_index / side_length)
	var step = side_index % side_length

	match side:
		0:
			return Vector2i(-ring + step, -ring)
		1:
			return Vector2i(ring, -ring + step)
		2:
			return Vector2i(ring - step, ring)
		_:
			return Vector2i(-ring, ring - step)

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

	var debug_active = bool(placement_manager.get("debug_active")) if has_property(placement_manager, "debug_active") else false
	var placement_enabled = bool(placement_manager.get("placement_enabled")) if has_property(placement_manager, "placement_enabled") else false

	return not (debug_active and placement_enabled)

func has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false

	for property in object.get_property_list():
		if str(property.get("name")) == property_name:
			return true

	return false
