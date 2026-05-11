extends BaseUnit

class_name EnemyUnit

@export var stop_distance: float = 70.0
@export var separation_radius: float = 55.0
@export var separation_strength: float = 1.5
@export var target_scan_interval: float = 0.25

func _ready():
	super._ready()
	target_scan_timer = randf() * target_scan_interval

	if debug_logging:
		print("Enemy unit spawned with health: ", current_health)

func _physics_process(delta):
	tick_combat_order_state(delta)
	if tick_harvest_order(delta):
		return

	if should_clear_current_attack_target():
		clear_current_attack_target()

	if attack_target == null:
		if not should_auto_acquire_target():
			handle_current_order_without_target(delta)
			return

		if movement_component != null and movement_component.is_committed_step_in_progress():
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
	var closest_target = find_best_attack_target(get_auto_acquire_range_pixels(), true)

	if closest_target != null:
		set_current_attack_target(closest_target, can_chase_attack_target())

		if debug_logging:
			print("Enemy unit found target: ", closest_target.name)

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

	if candidate.has_method("can_take_combat_damage") and not bool(candidate.call("can_take_combat_damage")):
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
		try_attack_current_target("Enemy unit")
		return

	if not can_chase_attack_target():
		handle_current_order_without_target(delta)
		return

	if not movement_component.is_moving and not movement_component.is_on_tile_center():
		movement_component.settle_to_nearest_tile()
	elif movement_component.is_settled():
		var desired_attack_tile = get_best_attack_tile_near_target(attack_target)
		movement_component.move_to_world_position(desired_attack_tile)

	movement_component.physics_step(delta)

func after_damage_taken(_amount: int):
	if debug_logging:
		print("Enemy unit took damage. HP: ", current_health)

func handle_current_order_without_target(delta: float):
	if movement_component == null:
		return

	if combat_orders == null:
		settle_or_step(delta)
		return

	match combat_orders.order_type:
		CombatOrderComponent.OrderType.MOVE, CombatOrderComponent.OrderType.ATTACK_MOVE:
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
	return get_best_attack_tile_near_target(target)

func get_best_attack_cell_near_target(target: Node2D) -> Vector2i:
	return super.get_best_attack_cell_near_target(target)
