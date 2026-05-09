extends "res://scripts/units/base_unit.gd"

class_name EnemyUnit

@export var stop_distance: float = 70.0
@export var separation_radius: float = 55.0
@export var separation_strength: float = 1.5
@export var target_scan_interval: float = 0.25

# Helps prevent nearby units from getting stuck together.
@export var personal_space_radius: float = 45.0
@export var personal_space_strength: float = 1.25

# Flee settings
@export var flee_health_percent: float = 0.25
@export var flee_chance: float = 0.35
@export var flee_duration: float = 2.0
@export var flee_speed_multiplier: float = 1.4

var attack_target: Node2D = null
var attack_timer: float = 0.0

var has_checked_flee: bool = false
var is_fleeing: bool = false
var flee_timer: float = 0.0
var flee_direction: Vector2 = Vector2.ZERO
var flee_tile_target: Vector2 = Vector2.ZERO
var player_target_candidate: Node2D = null
var target_scan_timer: float = 0.0

func _ready():
	super._ready()
	target_scan_timer = randf() * target_scan_interval

	if debug_logging:
		print("Enemy unit spawned with health: ", current_health)

func _physics_process(delta):
	attack_timer -= delta
	sync_attack_target_from_order()

	if is_fleeing:
		handle_fleeing(delta)
		return

	if attack_target != null and (
		not is_instance_valid(attack_target)
		or not is_valid_attack_candidate(attack_target)
		or not is_target_allowed_by_current_order(attack_target)
	):
		clear_current_attack_target()

	if attack_target == null:
		if not should_auto_acquire_target():
			handle_current_order_without_target(delta)
			return

		target_scan_timer -= delta
		if target_scan_timer > 0.0:
			handle_current_order_without_target(delta)
			return

		target_scan_timer = target_scan_interval
		find_player_target()

	if attack_target != null and is_instance_valid(attack_target):
		handle_attack_target(delta)
	else:
		handle_current_order_without_target(delta)

func find_player_target():
	var closest_target: Node2D = null
	var closest_distance_squared = INF
	var acquire_range = get_auto_acquire_range_pixels()
	var detection_range_squared = acquire_range * acquire_range
	var candidates = get_attack_target_candidates()

	for candidate in candidates:
		if not is_basic_attack_candidate(candidate):
			continue

		var target = candidate as Node2D

		if not is_target_allowed_by_current_order(target):
			continue

		var distance_squared = global_position.distance_squared_to(target.global_position)

		if distance_squared > detection_range_squared or distance_squared >= closest_distance_squared:
			continue

		if not can_attack_target(candidate):
			continue

		closest_target = target
		closest_distance_squared = distance_squared

	if closest_target != null:
		player_target_candidate = closest_target
		attack_target = closest_target
		clear_movement_ignore_nodes()
		if debug_logging:
			print("Enemy unit found target: ", player_target_candidate.name)

func get_attack_target_candidates() -> Array[Node]:
	var candidates: Array[Node] = []
	var seen_instance_ids := {}
	var target_groups = get_hostile_target_groups()

	for group_name in target_groups:
		for node in get_tree().get_nodes_in_group(group_name):
			var instance_id = node.get_instance_id()

			if seen_instance_ids.has(instance_id):
				continue

			seen_instance_ids[instance_id] = true
			candidates.append(node)

	return candidates

func get_hostile_target_groups() -> Array[String]:
	var ownership = get_ownership_component(self)

	if ownership != null:
		if ownership.is_enemy():
			return ["player", "ally"]

		if ownership.is_player_owned() or ownership.is_ally():
			return ["enemy", "enemy_unit"]

	if is_in_group("enemy") or is_in_group("enemy_unit"):
		return ["player", "ally"]

	if is_in_group("player") or is_in_group("ally"):
		return ["enemy", "enemy_unit"]

	return ["player", "ally"]

func is_basic_attack_candidate(candidate: Node) -> bool:
	if candidate == null or candidate == self or not is_instance_valid(candidate):
		return false

	if not candidate is Node2D:
		return false

	if not candidate.has_method("take_damage"):
		return false

	var target_health = candidate.get("current_health")
	if target_health != null and int(target_health) <= 0:
		return false

	return is_hostile_to_self(candidate)

func is_valid_attack_candidate(candidate: Node) -> bool:
	return is_basic_attack_candidate(candidate) and can_attack_target(candidate) and is_target_allowed_by_current_order(candidate)

func is_hostile_to_self(candidate: Node) -> bool:
	var self_ownership = get_ownership_component(self)
	var target_ownership = get_ownership_component(candidate)

	if self_ownership != null and target_ownership != null:
		if self_ownership.is_enemy():
			return target_ownership.is_player_owned() or target_ownership.is_ally()

		if self_ownership.is_player_owned() or self_ownership.is_ally():
			return target_ownership.is_enemy()

		return false

	if is_in_group("enemy") or is_in_group("enemy_unit"):
		return candidate.is_in_group("player") or candidate.is_in_group("ally")

	if is_in_group("player") or is_in_group("ally"):
		return candidate.is_in_group("enemy") or candidate.is_in_group("enemy_unit")

	return candidate.is_in_group("player") or candidate.is_in_group("ally")

func get_ownership_component(node: Node) -> UnitOwnershipComponent:
	if node == null:
		return null

	return node.get_node_or_null("UnitOwnershipComponent") as UnitOwnershipComponent

func handle_attack_target(delta: float):
	if movement_component.is_committed_step_in_progress():
		movement_component.physics_step(delta)
		return

	if not is_target_allowed_by_current_order(attack_target):
		clear_current_attack_target()
		handle_current_order_without_target(delta)
		return

	if is_target_in_attack_tile_range(attack_target) and movement_component.is_settled():
		movement_component.snap_to_tile_center_if_close()
		movement_component.stop()
		clear_grid_reservations()

		if attack_timer <= 0.0:
			attack_timer = attack_cooldown
			if attack_target.has_method("take_damage"):
				attack_target.take_damage(CombatDamage.calculate_damage(attack_damage, self, attack_target))
			else:
				attack_target = null
			if debug_logging:
				print("Enemy unit attacked!")

		return

	if not can_chase_attack_target():
		handle_current_order_without_target(delta)
		return

	if not movement_component.is_moving and not movement_component.is_on_tile_center():
		movement_component.settle_to_nearest_tile()
	elif movement_component.is_settled():
		var desired_attack_tile = get_best_tile_near_target(attack_target)
		movement_component.move_to_world_position(desired_attack_tile)

	movement_component.physics_step(delta)

func after_damage_taken(_amount: int):
	if debug_logging:
		print("Enemy unit took damage. HP: ", current_health)

	check_for_flee()

func check_for_flee():
	if has_checked_flee:
		return

	var health_percent = float(current_health) / float(max_health)

	if health_percent <= flee_health_percent:
		has_checked_flee = true

		var roll = randf()

		if roll <= flee_chance:
			start_fleeing()
		else:
			if debug_logging:
				print("Enemy unit stayed and kept fighting.")

func start_fleeing():
	is_fleeing = true
	flee_timer = flee_duration
	clear_grid_reservations()
	movement_component.settle_to_nearest_tile()

	if attack_target != null and is_instance_valid(attack_target):
		flee_direction = attack_target.global_position.direction_to(global_position)
	else:
		flee_direction = Vector2.RIGHT.rotated(randf() * TAU)

	flee_tile_target = get_best_flee_tile()

	if combat_orders != null:
		combat_orders.set_flee_order(flee_tile_target)

	if debug_logging:
		print("Enemy unit is fleeing!")

func handle_fleeing(delta):
	flee_timer -= delta

	if flee_timer > 0.0:
		if grid_manager == null:
			movement_component.settle_to_nearest_tile()
			return

		if not movement_component.is_moving and not movement_component.is_on_tile_center():
			movement_component.settle_to_nearest_tile()
		elif movement_component.is_settled():
			flee_tile_target = get_best_flee_tile()
			movement_component.move_to_world_position(flee_tile_target)

		movement_component.move_speed = move_speed * flee_speed_multiplier
		movement_component.physics_step(delta)
		movement_component.move_speed = move_speed
	else:
		is_fleeing = false
		movement_component.stop()
		clear_grid_reservations()
		if combat_orders != null and combat_orders.order_type == CombatOrderComponent.OrderType.FLEE:
			combat_orders.complete_current_order()
		if debug_logging:
			print("Enemy unit stopped fleeing.")

func get_best_flee_tile() -> Vector2:
	if grid_manager == null:
		return global_position + flee_direction.normalized() * 64.0

	var current_cell = grid_manager.world_to_cell(global_position)
	var neighbor_cells = grid_manager.get_neighbor_cells(current_cell, false)
	var best_cell = Vector2i(-1, -1)
	var best_score = -INF
	var normalized_flee_direction = flee_direction.normalized()

	for cell in neighbor_cells:
		if grid_manager.is_cell_blocked(cell, self):
			continue

		var world_pos = grid_manager.cell_to_world(cell)
		var direction_to_cell = global_position.direction_to(world_pos)
		var score = direction_to_cell.dot(normalized_flee_direction)

		if score > best_score:
			best_score = score
			best_cell = cell

	if best_cell == Vector2i(-1, -1):
		return grid_manager.snap_world_to_tile_center(global_position)

	return grid_manager.cell_to_world(best_cell)

func sync_attack_target_from_order():
	if combat_orders == null:
		return

	var ordered_target = combat_orders.get_target()
	if ordered_target == null:
		return

	if attack_target == ordered_target:
		return

	attack_target = ordered_target
	player_target_candidate = ordered_target
	clear_movement_ignore_nodes()

func clear_current_attack_target():
	var cleared_target = attack_target
	attack_target = null
	player_target_candidate = null

	if combat_orders != null and combat_orders.target == cleared_target:
		combat_orders.clear_target()

func should_auto_acquire_target() -> bool:
	if combat_orders == null:
		return true

	return combat_orders.allows_auto_acquire()

func can_chase_attack_target() -> bool:
	if combat_orders == null:
		return true

	return combat_orders.allows_chase_target()

func is_target_allowed_by_current_order(candidate: Node) -> bool:
	if combat_orders == null:
		return true

	if not candidate is Node2D:
		return false

	return combat_orders.is_world_position_allowed((candidate as Node2D).global_position, get_order_tile_size())

func get_auto_acquire_range_pixels() -> float:
	var acquire_range = detection_range

	if combat_orders != null:
		acquire_range = combat_orders.get_auto_acquire_range_pixels(detection_range, get_order_tile_size())

		if not combat_orders.allows_chase_target():
			acquire_range = min(acquire_range, get_attack_range_pixels())

	return acquire_range

func get_order_tile_size() -> float:
	if grid_manager != null:
		return float(grid_manager.tile_size)

	return 64.0

func handle_current_order_without_target(delta: float):
	if movement_component == null:
		return

	if combat_orders == null:
		settle_or_step(delta)
		return

	match combat_orders.order_type:
		CombatOrderComponent.OrderType.MOVE, CombatOrderComponent.OrderType.ATTACK_MOVE, CombatOrderComponent.OrderType.FLEE:
			handle_destination_order(delta)
		_:
			settle_or_step(delta)

func handle_destination_order(delta: float):
	if combat_orders == null or not combat_orders.has_destination:
		settle_or_step(delta)
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

func settle_or_step(delta: float):
	if movement_component.is_moving:
		movement_component.physics_step(delta)
		return

	if not movement_component.is_on_tile_center():
		movement_component.settle_to_nearest_tile()
		movement_component.physics_step(delta)
		return

	movement_component.settle_to_nearest_tile()

func get_best_tile_near_target(target: Node2D) -> Vector2:
	if grid_manager == null:
		return target.global_position

	var snapped_target_position = grid_manager.snap_world_to_tile_center(target.global_position)
	var target_cells = grid_manager.get_footprint_cells_for_node(target)
	var blocked_cells = grid_manager.get_blocked_cell_lookup(self)
	var candidate_cells := {}

	if target_cells.is_empty():
		return snapped_target_position

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
