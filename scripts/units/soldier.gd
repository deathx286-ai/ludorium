extends "res://scripts/units/base_unit.gd"

@export var stop_distance: float = 70.0
@export var double_click_time: float = 0.30
@export var show_attack_range_debug: bool = true
@export var target_scan_interval: float = 0.25

# Helps prevent nearby units from getting stuck together.
@export var personal_space_radius: float = 45.0
@export var personal_space_strength: float = 1.25

var is_selected: bool = false
var was_showing_attack_range: bool = false
var last_attack_range_cell: Vector2i = Vector2i(-1, -1)

var attack_target: Node2D = null
var is_chasing_attack_target: bool = false
var attack_timer: float = 0.0
var chase_destination_cell: Vector2i = Vector2i(-1, -1)
var has_assigned_attack_slot: bool = false
var assigned_attack_slot_cell: Vector2i = Vector2i(-1, -1)
var target_scan_timer: float = 0.0

var last_click_time: float = -1.0
var last_clicked_enemy: Node2D = null

@onready var selection_circle: Polygon2D = $SelectionCircle

func _ready():
	super._ready()
	if debug_logging:
		print("Soldier HP: ", current_health)

	selection_circle.polygon = PackedVector2Array([
		Vector2(-24, -24),
		Vector2(24, -24),
		Vector2(24, 24),
		Vector2(-24, 24)
	])

	selection_circle.color = Color(0.2, 0.8, 1.0, 0.35)
	selection_circle.visible = false

	if debug_logging:
		print("Soldier attack range tiles: ", attack_range_tiles)

	queue_redraw()

func _draw():
	if should_show_attack_range():
		draw_attack_range_tiles()

func draw_attack_range_tiles():
	if grid_manager == null:
		return

	var current_cell = grid_manager.world_to_cell(global_position)
	var range_cells = grid_manager.get_cells_in_tile_range(
		current_cell,
		get_attack_range_tile_count(),
		false
	)

	for cell in range_cells:
		var tile_center = to_local(grid_manager.cell_to_world(cell))
		var tile_rect = Rect2(
			tile_center - Vector2.ONE * grid_manager.tile_size / 2.0,
			Vector2.ONE * grid_manager.tile_size
		)

		draw_rect(tile_rect, Color(1.0, 0.2, 0.2, 0.12), true)
		draw_rect(tile_rect, Color(1.0, 0.2, 0.2, 0.65), false, 1.5)

func _input(event):
	if is_managed_by_selection_manager():
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			handle_left_click()

		if event.button_index == MOUSE_BUTTON_RIGHT and is_selected:
			handle_move_command()

func handle_left_click():
	var clicked_enemy = get_enemy_under_mouse()

	if is_selected and clicked_enemy != null:
		var current_click_time = Time.get_ticks_msec() / 1000.0

		var is_double_click = false
		if last_clicked_enemy == clicked_enemy:
			if current_click_time - last_click_time <= double_click_time:
				is_double_click = true

		last_click_time = current_click_time
		last_clicked_enemy = clicked_enemy

		attack_target = clicked_enemy
		issue_attack_target_order(clicked_enemy, is_double_click)

		if is_double_click:
			is_chasing_attack_target = true
			chase_destination_cell = Vector2i(-1, -1)
			if debug_logging:
				print("Double-click attack chase: ", attack_target.name)
		else:
			is_chasing_attack_target = false
			if debug_logging:
				print("Attack target set: ", attack_target.name)

		return

	# Otherwise, left-click selects or deselects the Soldier.
	var mouse_pos = get_global_mouse_position()
	var distance_to_mouse = global_position.distance_to(mouse_pos)

	if distance_to_mouse <= 35.0:
		is_selected = true
	else:
		is_selected = false
		is_chasing_attack_target = false

	selection_circle.visible = is_selected
	queue_redraw()
	if debug_logging:
		print("Selected: ", is_selected)

func handle_move_command():
	var clicked_enemy = get_enemy_under_mouse()

	if clicked_enemy != null:
		attack_target = clicked_enemy
		is_chasing_attack_target = true
		chase_destination_cell = Vector2i(-1, -1)
		issue_attack_target_order(clicked_enemy, true)

		if debug_logging:
			print("Right-click attack chase: ", attack_target.name)

		return

	var requested_position = get_global_mouse_position()

	if grid_manager != null:
		requested_position = grid_manager.snap_world_to_tile_center(requested_position)

	if not movement_component.move_to_world_position(requested_position):
		if debug_logging:
			print("Move blocked: no open path to target tile.")
		return

	issue_move_order(requested_position)
	attack_target = null
	is_chasing_attack_target = false
	clear_assigned_attack_slot()

	if debug_logging:
		print("Moving to tile position: ", movement_component.target_position)

func _physics_process(delta):
	attack_timer -= delta

	sync_attack_target_from_order()
	handle_attack_move_auto_acquire(delta)
	handle_attack_if_possible()
	handle_movement(delta)
	update_attack_range_debug_redraw()

func update_attack_range_debug_redraw():
	var is_showing_attack_range = should_show_attack_range()
	var should_redraw = was_showing_attack_range != is_showing_attack_range

	if is_showing_attack_range and grid_manager != null:
		var current_cell = grid_manager.world_to_cell(global_position)

		if current_cell != last_attack_range_cell:
			last_attack_range_cell = current_cell
			should_redraw = true
	elif not is_showing_attack_range:
		last_attack_range_cell = Vector2i(-1, -1)

	if should_redraw:
		queue_redraw()

	was_showing_attack_range = is_showing_attack_range

func handle_attack_if_possible():
	if attack_target == null:
		return

	if not is_instance_valid(attack_target) or is_attack_target_dead():
		if is_chasing_attack_target:
			finish_interrupted_chase_to_tile()

		clear_order_target_if_matching(attack_target)
		attack_target = null
		is_chasing_attack_target = false
		clear_assigned_attack_slot()
		return

	if movement_component.is_committed_step_in_progress() or not movement_component.is_settled():
		return

	movement_component.snap_to_tile_center_if_close()

	if is_target_in_attack_tile_range(attack_target):
		if attack_timer <= 0.0:
			attack_timer = attack_cooldown
			if attack_target.has_method("take_damage"):
				attack_target.take_damage(CombatDamage.calculate_damage(attack_damage, self, attack_target))
			else:
				attack_target = null
			if debug_logging:
				print("Soldier attacked!")

			if is_attack_target_dead() and is_chasing_attack_target:
				finish_interrupted_chase_to_tile()
				clear_order_target_if_matching(attack_target)
				attack_target = null
				is_chasing_attack_target = false
				clear_assigned_attack_slot()

func handle_movement(delta: float):
	# Double-click chase behavior.
	if is_chasing_attack_target and attack_target != null and is_instance_valid(attack_target):
		if not movement_component.is_moving and not movement_component.is_on_tile_center():
			finish_interrupted_chase_to_tile()
		elif movement_component.is_committed_step_in_progress():
			pass
		elif is_target_in_attack_tile_range(attack_target) and movement_component.is_settled():
			if has_assigned_attack_slot and not has_reached_assigned_attack_slot():
				update_chase_path_to_target()
				movement_component.physics_step(delta)
				return

			movement_component.snap_to_tile_center_if_close()
			movement_component.stop()
			clear_grid_reservations()
			return
		else:
			update_chase_path_to_target()
	elif should_follow_destination_order():
		handle_destination_order(delta)
		return
	elif not movement_component.is_moving and not movement_component.is_on_tile_center():
		movement_component.settle_to_nearest_tile()

	movement_component.physics_step(delta)

func handle_attack_move_auto_acquire(delta: float):
	if combat_orders == null or combat_orders.order_type != CombatOrderComponent.OrderType.ATTACK_MOVE:
		return

	if attack_target != null:
		return

	target_scan_timer -= delta
	if target_scan_timer > 0.0:
		return

	target_scan_timer = target_scan_interval
	var target = find_best_attack_target(detection_range)

	if target == null:
		return

	clear_movement_ignore_nodes()
	attack_target = target
	is_chasing_attack_target = true
	chase_destination_cell = Vector2i(-1, -1)
	clear_assigned_attack_slot()

func should_follow_destination_order() -> bool:
	if combat_orders == null or not combat_orders.has_destination:
		return false

	return combat_orders.order_type == CombatOrderComponent.OrderType.MOVE or combat_orders.order_type == CombatOrderComponent.OrderType.ATTACK_MOVE

func handle_destination_order(delta: float):
	if combat_orders == null or not combat_orders.has_destination:
		return

	if has_reached_order_destination():
		movement_component.stop()
		combat_orders.complete_current_order()
		return

	if movement_component.is_committed_step_in_progress():
		movement_component.physics_step(delta)
		return

	if not movement_component.is_moving and not movement_component.is_on_tile_center():
		movement_component.settle_to_nearest_tile()
	elif movement_component.is_settled():
		if not movement_component.move_to_world_position(combat_orders.destination):
			combat_orders.complete_current_order()
			movement_component.settle_to_nearest_tile()

	movement_component.physics_step(delta)

func has_reached_order_destination() -> bool:
	if combat_orders == null or not combat_orders.has_destination:
		return true

	if grid_manager != null:
		return (
			grid_manager.world_to_cell(global_position) == grid_manager.world_to_cell(combat_orders.destination)
			and movement_component.is_settled()
		)

	return global_position.distance_to(combat_orders.destination) <= waypoint_arrival_distance

func is_on_tile_center() -> bool:
	return movement_component.is_on_tile_center()

func snap_to_tile_center_if_close() -> bool:
	return movement_component.snap_to_tile_center_if_close()

func is_committed_tile_step_in_progress() -> bool:
	return movement_component.is_committed_step_in_progress()

func finish_interrupted_chase_to_tile():
	movement_component.settle_to_nearest_tile()

func update_chase_path_to_target():
	if grid_manager == null or attack_target == null or not is_instance_valid(attack_target):
		return

	if movement_component.is_committed_step_in_progress():
		return

	var desired_chase_position = get_best_chase_tile_near_target(grid_manager, attack_target)
	var desired_chase_cell = grid_manager.world_to_cell(desired_chase_position)
	var requires_exact_slot = false

	if has_assigned_attack_slot:
		if is_assigned_attack_slot_valid_for_target():
			desired_chase_cell = assigned_attack_slot_cell
			desired_chase_position = grid_manager.cell_to_world(assigned_attack_slot_cell)
			requires_exact_slot = true
		else:
			clear_assigned_attack_slot()

	if movement_component.is_moving and chase_destination_cell == desired_chase_cell and not movement_component.movement_path.is_empty():
		return

	var did_move = false
	if requires_exact_slot and movement_component.has_method("move_to_world_position_exact"):
		did_move = movement_component.move_to_world_position_exact(desired_chase_position)
	else:
		did_move = movement_component.move_to_world_position(desired_chase_position)

	if not did_move:
		return

	chase_destination_cell = desired_chase_cell

func get_best_chase_tile_near_target(grid_manager, target: Node2D) -> Vector2:
	var target_cells = grid_manager.get_footprint_cells_for_node(target)
	var blocked_cells = grid_manager.get_blocked_cell_lookup(self)
	var candidate_cells := {}

	for target_footprint_cell in target_cells:
		for cell in grid_manager.get_cells_in_tile_range(target_footprint_cell, get_attack_range_tile_count(), false):
			if not blocked_cells.has(cell):
				candidate_cells[cell] = true

	var best_cell = grid_manager.find_nearest_reachable_cell_in_lookup(
		grid_manager.world_to_cell(global_position),
		candidate_cells,
		blocked_cells
	)

	if best_cell == Vector2i(-1, -1):
		return grid_manager.snap_world_to_tile_center(global_position)

	return grid_manager.cell_to_world(best_cell)

func get_enemy_under_mouse() -> Node2D:
	var mouse_pos = get_global_mouse_position()

	for enemy in get_attack_target_candidates():
		if enemy is Node2D:
			if is_valid_attack_candidate(enemy) and is_mouse_over_enemy_hitbox(enemy, mouse_pos):
				return enemy

	return null

func is_mouse_over_enemy_hitbox(enemy: Node2D, mouse_pos: Vector2) -> bool:
	return HitboxMath.contains_point(enemy, mouse_pos)

func is_attack_target_dead() -> bool:
	if attack_target == null:
		return true

	var target_health = attack_target.get("current_health")

	if target_health == null:
		return false

	return int(target_health) <= 0

func should_show_attack_range() -> bool:
	return is_selected and (
		show_attack_range_debug or Input.is_key_pressed(KEY_SHIFT)
	)

func set_selected(selected: bool):
	is_selected = selected

	if selection_circle != null:
		selection_circle.visible = is_selected

	queue_redraw()

func is_managed_by_selection_manager() -> bool:
	return get_tree().get_first_node_in_group("player_selection_manager") != null

func command_move_to_position(destination: Vector2) -> bool:
	var move_destination = destination

	if grid_manager != null:
		move_destination = grid_manager.snap_world_to_tile_center(move_destination)

	var did_move = super.command_move_to_position(move_destination)
	if not did_move:
		return false

	attack_target = null
	is_chasing_attack_target = false
	chase_destination_cell = Vector2i(-1, -1)
	clear_assigned_attack_slot()
	return true

func command_attack_target(target: Node2D, should_chase: bool = true) -> bool:
	if target == null:
		return false

	if not is_valid_attack_candidate(target):
		return false

	var accepted = super.command_attack_target(target, should_chase)
	if not accepted:
		return false

	attack_target = target
	is_chasing_attack_target = should_chase
	chase_destination_cell = Vector2i(-1, -1)
	clear_assigned_attack_slot()
	return true

func command_attack_target_from_position(target: Node2D, attack_position: Vector2, should_chase: bool = true) -> bool:
	var accepted = command_attack_target(target, should_chase)
	if not accepted:
		return false

	if grid_manager == null:
		return true

	assigned_attack_slot_cell = grid_manager.world_to_cell(attack_position)
	has_assigned_attack_slot = true
	chase_destination_cell = Vector2i(-1, -1)
	return true

func command_attack_move_to_position(destination: Vector2) -> bool:
	var move_destination = destination

	if grid_manager != null:
		move_destination = grid_manager.snap_world_to_tile_center(move_destination)

	var did_move = super.command_attack_move_to_position(move_destination)
	if not did_move:
		return false

	attack_target = null
	is_chasing_attack_target = false
	chase_destination_cell = Vector2i(-1, -1)
	clear_assigned_attack_slot()
	return true

func command_hold_position():
	super.command_hold_position()
	attack_target = null
	is_chasing_attack_target = false
	chase_destination_cell = Vector2i(-1, -1)
	clear_assigned_attack_slot()

func command_stop():
	super.command_stop()
	attack_target = null
	is_chasing_attack_target = false
	chase_destination_cell = Vector2i(-1, -1)
	clear_assigned_attack_slot()

func sync_attack_target_from_order():
	if combat_orders == null:
		return

	var ordered_target = combat_orders.get_target()
	if ordered_target == null or ordered_target == attack_target:
		return

	attack_target = ordered_target
	clear_movement_ignore_nodes()
	is_chasing_attack_target = combat_orders.allows_chase_target()
	chase_destination_cell = Vector2i(-1, -1)
	clear_assigned_attack_slot()

func clear_order_target_if_matching(target_to_clear: Node2D):
	if combat_orders == null:
		return

	if combat_orders.target == target_to_clear:
		combat_orders.clear_target()

func has_reached_assigned_attack_slot() -> bool:
	if not has_assigned_attack_slot or grid_manager == null:
		return true

	return grid_manager.world_to_cell(global_position) == assigned_attack_slot_cell and movement_component.is_settled()

func is_assigned_attack_slot_valid_for_target() -> bool:
	if not has_assigned_attack_slot or grid_manager == null:
		return false

	if attack_target == null or not is_instance_valid(attack_target):
		return false

	var target_cells = grid_manager.get_footprint_cells_for_node(attack_target)
	if target_cells.has(assigned_attack_slot_cell):
		return false

	for target_cell in target_cells:
		var offset = assigned_attack_slot_cell - target_cell
		if maxi(abs(offset.x), abs(offset.y)) <= get_attack_range_tile_count():
			return true

	return false

func clear_assigned_attack_slot():
	has_assigned_attack_slot = false
	assigned_attack_slot_cell = Vector2i(-1, -1)
