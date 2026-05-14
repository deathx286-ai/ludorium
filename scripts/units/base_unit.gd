extends CharacterBody2D
class_name BaseUnit

# Optional manual override. AUTO derives the marker from unit_data.unit_archetype.
enum Subtype { AUTO, HEAVY, LIGHT, SUPPORT, SPECIALIST, ARCANE, WAR_BEAST, MARTIAL, DIVINE_FALLEN, PRODUCTION, DEFENSE, ENEMY_CAMP }
@export var subtype: Subtype = Subtype.AUTO

@export var unit_data: UnitData
@export var max_health: int = 100
@export var attack_damage: int = 10
@export var attack_range_tiles: float = 1.0
@export var attack_cooldown: float = 1.0
@export var move_speed: float = 150.0
@export var detection_range: float = 250.0
@export var waypoint_arrival_distance: float = 4.0
@export var xp_reward: int = 0
@export var gold_reward: int = 0
@export var debug_logging: bool = false
@export var show_attack_range_debug: bool = false

var current_health: int = 0
var footprint_width: int = 1
var footprint_height: int = 1
var archetype_stat_rule: Dictionary = {}
var targets_air: bool = false
var attacks_over_blocking_structures: bool = false
var moves_over_blocking_structures: bool = false
var movement_ignore_node_ids := {}
var attack_target: Node2D = null
var is_chasing_attack_target: bool = false
var attack_timer: float = 0.0
var target_scan_timer: float = 0.0
var harvest_target: Node2D = null
var harvest_destination_cell: Vector2i = Vector2i(-1, -1)

var is_selected: bool = false
var was_showing_attack_range: bool = false
var last_attack_range_cell: Vector2i = Vector2i(-1, -1)

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")
@onready var hitbox: Area2D = get_node_or_null("Hitbox")
@onready var health_bar: ProgressBar = get_node_or_null("HealthBar")
@onready var unit_tile_sizer = get_node_or_null("UnitTileSizer")
@onready var movement_component = get_node_or_null("TileMovementComponent")
@onready var unit_classification: UnitClassification = get_node_or_null("UnitClassification")
@onready var classification_label: Label = get_node_or_null("ClassificationLabel")
@onready var combat_orders: CombatOrderComponent = get_node_or_null("CombatOrderComponent") as CombatOrderComponent
@onready var grid_manager = get_tree().get_first_node_in_group("grid_manager")

func _ready():
	ensure_combat_orders()
	apply_unit_data()
	setup_health_bar()
	initialize_movement()
	_spawn_subtype_indicator()

func _draw():
	if is_selected:
		draw_selection_indicator()

	if should_show_attack_range():
		draw_attack_range_tiles()

func draw_selection_indicator():
	var size = 24.0
	if footprint_width > 1 or footprint_height > 1:
		size = 32.0 * max(footprint_width, footprint_height)

	var rect = Rect2(-Vector2(size, size), Vector2(size * 2, size * 2))
	draw_rect(rect, Color(0.2, 0.8, 1.0, 0.35), true)
	draw_rect(rect, Color(0.2, 0.8, 1.0, 0.8), false, 1.5)

func should_show_attack_range() -> bool:
	return is_selected and (show_attack_range_debug or Input.is_key_pressed(KEY_SHIFT))

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

func set_selected(selected: bool):
	is_selected = selected
	update_health_bar_visibility()
	queue_redraw()

func update_health_bar_visibility():
	if health_bar == null:
		return

	if is_selected:
		health_bar.visible = true
	elif current_health < max_health:
		health_bar.visible = true
	else:
		health_bar.visible = false

func ensure_combat_orders():
	if combat_orders == null:
		combat_orders = get_node_or_null("CombatOrderComponent") as CombatOrderComponent

	if combat_orders == null:
		combat_orders = CombatOrderComponent.new()
		combat_orders.name = "CombatOrderComponent"
		add_child(combat_orders)

	if not combat_orders.has_anchor_position:
		combat_orders.set_anchor_position(global_position)

func apply_unit_data():
	if unit_data == null:
		current_health = max_health
		return

	name = unit_data.display_name if not unit_data.display_name.is_empty() else unit_data.unit_id
	archetype_stat_rule = UnitArchetypeStatRules.get_rule_for_unit_data(unit_data)
	max_health = UnitArchetypeStatRules.apply_health(unit_data.max_health, archetype_stat_rule)
	attack_damage = UnitArchetypeStatRules.apply_damage(unit_data.damage, archetype_stat_rule)
	attack_range_tiles = UnitArchetypeStatRules.apply_range(unit_data.attack_range_tiles, archetype_stat_rule)
	attack_cooldown = UnitArchetypeStatRules.apply_attack_cooldown(unit_data.attack_cooldown, archetype_stat_rule)
	move_speed = UnitArchetypeStatRules.apply_move_speed(unit_data.move_speed, archetype_stat_rule)
	targets_air = bool(archetype_stat_rule.get("can_target_air", false))
	attacks_over_blocking_structures = bool(archetype_stat_rule.get("can_attack_over_blocking_structures", false))
	moves_over_blocking_structures = bool(archetype_stat_rule.get("can_move_over_blocking_structures", false))
	current_health = max_health
	xp_reward = unit_data.xp_reward
	gold_reward = unit_data.gold_reward
	footprint_width = maxi(unit_data.footprint_width, 1)
	footprint_height = maxi(unit_data.footprint_height, 1)

	if grid_manager != null:
		detection_range = unit_data.vision_range_tiles * grid_manager.tile_size

	if sprite != null and unit_data.sprite_texture != null:
		sprite.texture = unit_data.sprite_texture

	apply_nation_visuals()

	if unit_tile_sizer != null:
		unit_tile_sizer.set("tile_width", footprint_width)
		unit_tile_sizer.set("tile_height", footprint_height)
		if unit_tile_sizer.has_method("update_tile_sizing"):
			unit_tile_sizer.update_tile_sizing()

	if unit_classification != null:
		unit_classification.apply_unit_data(unit_data)

	update_classification_label()

func setup_health_bar():
	if health_bar == null:
		return

	health_bar.min_value = 0
	health_bar.max_value = max_health
	health_bar.value = current_health
	health_bar.show_percentage = false
	update_health_bar_visibility()

func initialize_movement():
	if movement_component == null:
		return

	if unit_data != null and not unit_data.can_move:
		return

	movement_component.initialize(self, move_speed, waypoint_arrival_distance)

func get_tile_footprint_size() -> Vector2i:
	return Vector2i(footprint_width, footprint_height)

func get_worker_type() -> int:
	if unit_data == null:
		return EconomyTypes.WorkerType.NONE

	return int(unit_data.worker_type)

func can_harvest_resource_node(resource_node: Node) -> bool:
	if resource_node == null or not is_instance_valid(resource_node):
		return false

	if unit_data == null or not unit_data.can_harvest:
		return false

	if resource_node.has_method("is_harvestable_by"):
		return bool(resource_node.call("is_harvestable_by", self))

	return false

func uses_grid_occupancy() -> bool:
	return true

func can_target_air() -> bool:
	return targets_air

func can_attack_over_blocking_structures() -> bool:
	return attacks_over_blocking_structures

func can_move_over_blocking_structures() -> bool:
	return moves_over_blocking_structures

func set_movement_ignore_nodes(nodes: Array):
	movement_ignore_node_ids.clear()

	for node in nodes:
		if node != null and is_instance_valid(node):
			movement_ignore_node_ids[node.get_instance_id()] = true

func clear_movement_ignore_nodes():
	movement_ignore_node_ids.clear()

func should_ignore_movement_blocker(blocker_node: Node) -> bool:
	if blocker_node == null or not is_instance_valid(blocker_node):
		return false

	if blocker_node == self:
		return true

	return movement_ignore_node_ids.has(blocker_node.get_instance_id())

func get_hitbox() -> Area2D:
	return hitbox

func get_distance_to_target_hitbox(target: Node2D) -> float:
	return HitboxMath.distance_from_point_to_hitbox(global_position, target)

func get_attack_range_pixels() -> float:
	if grid_manager == null:
		return attack_range_tiles * 64.0

	return attack_range_tiles * grid_manager.tile_size

func get_attack_range_tile_count() -> int:
	return maxi(ceili(attack_range_tiles), 0)

func is_target_in_attack_tile_range(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return false

	if not can_attack_target(target):
		return false

	if grid_manager == null:
		return get_distance_to_target_hitbox(target) <= get_attack_range_pixels()

	var range_tiles = get_attack_range_tile_count()
	var self_cells = grid_manager.get_footprint_cells_for_node(self)
	var target_cells = grid_manager.get_footprint_cells_for_node(target)

	for self_cell in self_cells:
		for target_cell in target_cells:
			var offset = target_cell - self_cell

			if maxi(abs(offset.x), abs(offset.y)) <= range_tiles:
				return true

	return false

func can_attack_target(target: Node) -> bool:
	if unit_data != null and not unit_data.can_attack:
		return false

	if target == null or not is_instance_valid(target):
		return false

	if not target is Node2D:
		return false

	if is_air_target(target) and not can_target_air():
		return false

	if attacks_over_blocking_structures:
		return true

	if grid_manager != null and grid_manager.has_method("has_blocking_structure_between_nodes"):
		return not grid_manager.has_blocking_structure_between_nodes(self, target)

	return true

func get_attack_target_candidates() -> Array[Node]:
	var candidates: Array[Node] = []
	var seen_instance_ids := {}

	for group_name in get_hostile_target_groups():
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

		return []

	if is_in_group("enemy") or is_in_group("enemy_unit"):
		return ["player", "ally"]

	if is_in_group("player") or is_in_group("ally"):
		return ["enemy", "enemy_unit"]

	return []

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
	return is_basic_attack_candidate(candidate) and can_attack_target(candidate)

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

	return false

func get_ownership_component(node: Node) -> UnitOwnershipComponent:
	if node == null:
		return null

	return node.get_node_or_null("UnitOwnershipComponent") as UnitOwnershipComponent

func find_best_attack_target(max_range_pixels: float = -1.0, require_reachable: bool = false) -> Node2D:
	var closest_target: Node2D = null
	var closest_distance_squared = INF
	var has_range_limit = max_range_pixels >= 0.0
	var range_squared = max_range_pixels * max_range_pixels

	for candidate in get_attack_target_candidates():
		if not is_basic_attack_candidate(candidate):
			continue

		var target = candidate as Node2D
		var distance_squared = global_position.distance_squared_to(target.global_position)

		if has_range_limit and distance_squared > range_squared:
			continue

		if not is_target_allowed_by_current_order(target):
			continue

		if not can_attack_target(target):
			continue

		if require_reachable and not has_reachable_attack_position(target):
			continue

		if distance_squared >= closest_distance_squared:
			continue

		closest_distance_squared = distance_squared
		closest_target = target

	return closest_target

func has_reachable_attack_position(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return false

	if is_target_in_attack_tile_range(target):
		return true

	return get_best_attack_cell_near_target(target) != Vector2i(-1, -1)

func get_best_attack_cell_near_target(target: Node2D) -> Vector2i:
	if grid_manager == null or target == null or not is_instance_valid(target):
		return Vector2i(-1, -1)

	var target_cells = grid_manager.get_footprint_cells_for_node(target)
	var blocked_cells = grid_manager.get_blocked_cell_lookup(self)
	var candidate_cells := {}

	if target_cells.is_empty():
		return Vector2i(-1, -1)

	for target_footprint_cell in target_cells:
		for cell in grid_manager.get_cells_in_tile_range(target_footprint_cell, get_attack_range_tile_count(), false):
			if not blocked_cells.has(cell):
				candidate_cells[cell] = true

	return grid_manager.find_nearest_reachable_cell_in_lookup(
		grid_manager.world_to_cell(global_position),
		candidate_cells,
		blocked_cells
	)

func get_best_attack_tile_near_target(target: Node2D) -> Vector2:
	var best_cell = get_best_attack_cell_near_target(target)
	if best_cell == Vector2i(-1, -1):
		if grid_manager != null:
			return grid_manager.snap_world_to_tile_center(global_position)

		return global_position

	return grid_manager.cell_to_world(best_cell)

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

func should_auto_acquire_target() -> bool:
	if combat_orders == null:
		return true

	return combat_orders.allows_auto_acquire()

func can_chase_attack_target() -> bool:
	if combat_orders == null:
		return true

	return combat_orders.allows_chase_target()

func get_order_tile_size() -> float:
	if grid_manager != null:
		return float(grid_manager.tile_size)

	return 64.0

func tick_combat_order_state(delta: float):
	attack_timer -= delta
	sync_attack_target_from_order()
	update_attack_range_debug_redraw()

func sync_attack_target_from_order():
	if combat_orders == null:
		return

	if combat_orders.order_type != CombatOrderComponent.OrderType.ATTACK_TARGET:
		return

	var ordered_target = combat_orders.get_target()
	if ordered_target == null or ordered_target == attack_target:
		return

	set_current_attack_target(ordered_target, combat_orders.allows_chase_target())

func set_current_attack_target(target: Node2D, should_chase: bool = true):
	attack_target = target
	is_chasing_attack_target = should_chase
	clear_movement_ignore_nodes()
	after_attack_target_changed(target)
	queue_redraw()

func after_attack_target_changed(_target: Node2D):
	pass

func clear_current_attack_target(clear_matching_order: bool = true):
	var cleared_target = attack_target
	var was_chasing = is_chasing_attack_target
	attack_target = null
	is_chasing_attack_target = false
	clear_movement_ignore_nodes()

	if clear_matching_order and combat_orders != null and combat_orders.target == cleared_target:
		combat_orders.clear_target()

	after_attack_target_cleared(cleared_target, was_chasing)
	queue_redraw()

func after_attack_target_cleared(_cleared_target: Node2D, _was_chasing: bool):
	pass

func should_clear_current_attack_target() -> bool:
	if attack_target == null:
		return false

	if not is_instance_valid(attack_target):
		return true

	if is_attack_target_dead(attack_target):
		return true

	if not is_valid_attack_candidate(attack_target):
		return true

	return not is_target_allowed_by_current_order(attack_target)

func is_attack_target_dead(target: Node2D) -> bool:
	if target == null:
		return true

	var target_health = target.get("current_health")

	if target_health == null:
		return false

	return int(target_health) <= 0

func try_attack_current_target(debug_attack_name: String = "Unit") -> bool:
	if attack_target == null:
		return false

	if should_clear_current_attack_target():
		clear_current_attack_target()
		return false

	if movement_component != null and (movement_component.is_committed_step_in_progress() or not movement_component.is_settled()):
		return false

	if movement_component != null:
		movement_component.snap_to_tile_center_if_close()

	if not is_target_in_attack_tile_range(attack_target):
		return false

	if attack_timer > 0.0:
		return true

	attack_timer = attack_cooldown
	if attack_target.has_method("take_damage"):
		attack_target.take_damage(CombatDamage.calculate_damage(attack_damage, self, attack_target))
	else:
		clear_current_attack_target()
		return false

	if debug_logging:
		print(debug_attack_name, " attacked!")

	if attack_target != null and is_attack_target_dead(attack_target):
		clear_current_attack_target()

	return true

func issue_move_order(destination: Vector2):
	ensure_combat_orders()
	if combat_orders != null:
		combat_orders.set_move_order(destination)

func issue_attack_target_order(target: Node2D, should_chase: bool = true):
	ensure_combat_orders()
	if combat_orders != null:
		combat_orders.set_attack_target_order(target, should_chase)

func issue_attack_move_order(destination: Vector2):
	ensure_combat_orders()
	if combat_orders != null:
		combat_orders.set_attack_move_order(destination)

func issue_defend_area_order(anchor_position: Vector2, radius_tiles: int = -1):
	ensure_combat_orders()
	if combat_orders != null:
		combat_orders.set_defend_area_order(anchor_position, radius_tiles)

func issue_hold_position_order(anchor_position: Vector2):
	ensure_combat_orders()
	if combat_orders != null:
		combat_orders.set_hold_position_order(anchor_position)

func issue_idle_order():
	ensure_combat_orders()
	if combat_orders != null:
		combat_orders.set_idle_order()

func command_move_to_position(destination: Vector2) -> bool:
	clear_harvest_target("new move order")
	issue_move_order(destination)
	clear_current_attack_target(false)

	if movement_component == null:
		clear_movement_ignore_nodes()
		return false

	var did_move = movement_component.move_to_world_position(destination)
	if not did_move:
		movement_component.stop()
		clear_movement_ignore_nodes()

	return did_move

func command_attack_target(target: Node2D, should_chase: bool = true) -> bool:
	if target == null:
		return false

	clear_harvest_target("new attack order")
	clear_movement_ignore_nodes()
	issue_attack_target_order(target, should_chase)
	set_current_attack_target(target, should_chase)
	return true

func command_attack_move_to_position(destination: Vector2) -> bool:
	clear_harvest_target("new attack-move order")
	issue_attack_move_order(destination)
	clear_current_attack_target(false)

	if movement_component == null:
		clear_movement_ignore_nodes()
		return false

	var did_move = movement_component.move_to_world_position(destination)
	if not did_move:
		movement_component.stop()
		clear_movement_ignore_nodes()

	return did_move

func command_group_move_along_path(path: Array[Vector2], final_destination: Vector2) -> bool:
	clear_harvest_target("new group move order")
	issue_move_order(final_destination)
	clear_current_attack_target(false)

	if movement_component == null:
		clear_movement_ignore_nodes()
		return false

	movement_component.target_position = final_destination
	movement_component.set_path(path)
	return true

func command_hold_position():
	clear_harvest_target("hold position")
	clear_movement_ignore_nodes()
	clear_current_attack_target(false)
	issue_hold_position_order(global_position)

	if movement_component != null:
		movement_component.stop()

func command_defend_area(anchor_position: Vector2, radius_tiles: int = -1):
	clear_harvest_target("defend area")
	clear_movement_ignore_nodes()
	clear_current_attack_target(false)
	issue_defend_area_order(anchor_position, radius_tiles)

func command_stop():
	clear_harvest_target("stop order")
	clear_movement_ignore_nodes()
	clear_current_attack_target(false)
	issue_idle_order()

	if movement_component != null:
		movement_component.stop()

func command_harvest_resource_node(resource_node: Node2D) -> bool:
	if resource_node == null or not is_instance_valid(resource_node):
		return false

	if not can_harvest_resource_node(resource_node):
		return false

	clear_harvest_target("new harvest order")
	clear_current_attack_target(false)
	clear_movement_ignore_nodes()
	ensure_combat_orders()

	harvest_target = resource_node
	harvest_destination_cell = Vector2i(-1, -1)

	if combat_orders != null and combat_orders.has_method("set_harvest_order"):
		combat_orders.call("set_harvest_order", resource_node)

	return true

func clear_harvest_target(reason: String = "cleared"):
	if harvest_target != null and is_instance_valid(harvest_target) and harvest_target.has_method("stop_harvester"):
		harvest_target.call("stop_harvester", self, reason)

	harvest_target = null
	harvest_destination_cell = Vector2i(-1, -1)

func tick_harvest_order(delta: float) -> bool:
	if combat_orders == null or combat_orders.order_type != CombatOrderComponent.OrderType.HARVEST:
		return false

	var ordered_target = combat_orders.get_target()
	if ordered_target != null and ordered_target != harvest_target:
		harvest_target = ordered_target

	if harvest_target == null or not is_instance_valid(harvest_target):
		clear_harvest_target("target missing")
		if combat_orders != null:
			combat_orders.set_idle_order()
		return true

	if not can_harvest_resource_node(harvest_target):
		clear_harvest_target("invalid worker type")
		if combat_orders != null:
			combat_orders.set_idle_order()
		return true

	if harvest_target.has_method("is_worker_in_harvest_range") and bool(harvest_target.call("is_worker_in_harvest_range", self)):
		if movement_component != null:
			movement_component.snap_to_tile_center_if_close()
			movement_component.stop()
		clear_grid_reservations()
		harvest_destination_cell = Vector2i(-1, -1)
		if harvest_target.has_method("request_harvester"):
			if not bool(harvest_target.call("request_harvester", self)):
				if debug_logging:
					print(name, " harvest failed: node full or invalid")
		return true

	if harvest_target.has_method("stop_harvester"):
		harvest_target.call("stop_harvester", self, "moving to harvest range")

	if movement_component == null:
		return true

	if movement_component.is_committed_step_in_progress():
		movement_component.physics_step(delta)
		return true

	if not movement_component.is_moving and not movement_component.is_on_tile_center():
		movement_component.settle_to_nearest_tile()
	elif movement_component.is_settled():
		var harvest_cell = get_best_harvest_cell_near_resource_node(harvest_target)
		if harvest_cell == Vector2i(-1, -1):
			movement_component.stop()
			return true

		if harvest_destination_cell != harvest_cell or not movement_component.is_moving:
			harvest_destination_cell = harvest_cell
			movement_component.move_to_world_position(grid_manager.cell_to_world(harvest_cell))

	movement_component.physics_step(delta)
	return true

func get_best_harvest_cell_near_resource_node(resource_node: Node2D) -> Vector2i:
	if grid_manager == null or resource_node == null or not is_instance_valid(resource_node):
		return Vector2i(-1, -1)

	var range_tiles = 1
	if _has_property(resource_node, "harvest_range"):
		range_tiles = maxi(ceili(float(resource_node.get("harvest_range"))), 1)

	var target_cells = grid_manager.get_footprint_cells_for_node(resource_node)
	if target_cells.is_empty():
		return Vector2i(-1, -1)

	var blocked_cells = grid_manager.get_blocked_cell_lookup(self)
	var candidate_cells := {}

	for target_cell in target_cells:
		for candidate_cell in grid_manager.get_cells_in_tile_range(target_cell, range_tiles, false):
			if target_cells.has(candidate_cell):
				continue
			if blocked_cells.has(candidate_cell):
				continue
			candidate_cells[candidate_cell] = true

	if candidate_cells.is_empty():
		return Vector2i(-1, -1)

	return grid_manager.find_nearest_reachable_cell_in_lookup(
		grid_manager.world_to_cell(global_position),
		candidate_cells,
		blocked_cells
	)

func is_air_target(target: Node) -> bool:
	var target_unit_data = target.get("unit_data")
	if target_unit_data != null:
		return int(target_unit_data.get("movement_type")) == UnitClassification.MovementType.AIR or int(target_unit_data.get("unit_domain")) == UnitClassification.UnitDomain.AIR

	var classification = target.get_node_or_null("UnitClassification") as UnitClassification
	if classification != null:
		return classification.is_air()

	return false

func _get_property_or_null(object: Object, property_name: String):
	if object == null:
		return null

	for property in object.get_property_list():
		if str(property.get("name")) == property_name:
			return object.get(property_name)

	return null

func _has_property(object: Object, property_name: String) -> bool:
	return _get_property_or_null(object, property_name) != null

func take_damage(amount: int):
	current_health = maxi(current_health - amount, 0)

	if health_bar != null:
		health_bar.value = current_health

	update_health_bar_visibility()
	spawn_damage_number(amount)
	play_hit_flash()

	after_damage_taken(amount)

	if current_health <= 0:
		die()

func play_hit_flash():
	if sprite == null:
		return

	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(10, 10, 10, 1), 0.05)
	tween.tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.1)

func spawn_damage_number(amount: int):
	DamageNumber.create(amount, global_position, self)

func after_damage_taken(_amount: int):
	if debug_logging:
		print(name, " took damage. HP: ", current_health)

func die():
	if debug_logging:
		print(name, " died")

	clear_harvest_target("worker died")
	clear_grid_reservations()

	var occupancy_manager = get_tree().get_first_node_in_group("grid_occupancy_manager")
	if occupancy_manager != null and occupancy_manager.has_method("unregister_node"):
		occupancy_manager.unregister_node(self)

	if is_in_group("enemy") or is_in_group("enemy_unit"):
		var player_manager = get_tree().get_first_node_in_group("player_manager")
		if player_manager != null:
			if xp_reward > 0:
				player_manager.gain_xp(xp_reward)
			if gold_reward > 0:
				player_manager.gain_gold(gold_reward)

		var world_manager = get_tree().get_first_node_in_group("world_manager")
		if world_manager != null:
			world_manager.register_enemy_kill()

	# Death animation
	if sprite != null:
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(sprite, "scale", Vector2.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
		tween.chain().tween_callback(queue_free)
	else:
		queue_free()

func clear_grid_reservations():
	if movement_component != null and movement_component.has_method("clear_reservations"):
		movement_component.clear_reservations()

func update_classification_label():
	if classification_label == null or unit_data == null:
		return

	classification_label.text = UnitClassification.get_unit_archetype_abbreviation(unit_data.unit_archetype)

func apply_nation_visuals():
	NationVisuals.apply_owner_or_data_to_node(self, unit_data)

func _spawn_subtype_indicator():
	var indicator_scene = preload("res://scenes/ui/subtype_indicator.tscn")
	var indicator = get_node_or_null("SubtypeIndicator")
	if indicator == null:
		indicator = indicator_scene.instantiate()
		indicator.name = "SubtypeIndicator"
		add_child(indicator)

	indicator.z_index = 2
	if indicator.has_method("setup"):
		if subtype == Subtype.AUTO:
			indicator.setup(unit_data, Vector2i(footprint_width, footprint_height))
		else:
			indicator.setup(int(subtype), Vector2i(footprint_width, footprint_height))
