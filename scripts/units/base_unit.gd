extends CharacterBody2D
class_name BaseUnit

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

var current_health: int = 0
var footprint_width: int = 1
var footprint_height: int = 1
var archetype_stat_rule: Dictionary = {}
var targets_air: bool = false
var attacks_over_blocking_structures: bool = false
var moves_over_blocking_structures: bool = false
var movement_ignore_node_ids := {}
var movement_allowed_destination_cells := {}

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

func initialize_movement():
	if movement_component == null:
		return

	if unit_data != null and not unit_data.can_move:
		return

	movement_component.initialize(self, move_speed, waypoint_arrival_distance)

func get_tile_footprint_size() -> Vector2i:
	return Vector2i(footprint_width, footprint_height)

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

func set_movement_group_context(nodes: Array, allowed_destination_cells: Array):
	set_movement_ignore_nodes(nodes)
	movement_allowed_destination_cells.clear()

	for cell in allowed_destination_cells:
		movement_allowed_destination_cells[cell] = true

func clear_movement_ignore_nodes():
	movement_ignore_node_ids.clear()
	movement_allowed_destination_cells.clear()

func should_ignore_movement_blocker(blocker_node: Node) -> bool:
	if blocker_node == null or not is_instance_valid(blocker_node):
		return false

	if blocker_node == self:
		return true

	return movement_ignore_node_ids.has(blocker_node.get_instance_id())

func should_ignore_destination_blocker(cell: Vector2i, blocker_node: Node) -> bool:
	if not movement_allowed_destination_cells.has(cell):
		return false

	return should_ignore_movement_blocker(blocker_node)

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

func find_best_attack_target(max_range_pixels: float = -1.0) -> Node2D:
	var closest_target: Node2D = null
	var closest_distance_squared = INF
	var has_range_limit = max_range_pixels >= 0.0
	var range_squared = max_range_pixels * max_range_pixels

	for candidate in get_attack_target_candidates():
		if not is_valid_attack_candidate(candidate):
			continue

		var target = candidate as Node2D
		var distance_squared = global_position.distance_squared_to(target.global_position)

		if has_range_limit and distance_squared > range_squared:
			continue

		if distance_squared >= closest_distance_squared:
			continue

		closest_distance_squared = distance_squared
		closest_target = target

	return closest_target

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
	issue_move_order(destination)

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

	clear_movement_ignore_nodes()
	issue_attack_target_order(target, should_chase)
	return true

func command_attack_move_to_position(destination: Vector2) -> bool:
	issue_attack_move_order(destination)

	if movement_component == null:
		clear_movement_ignore_nodes()
		return false

	var did_move = movement_component.move_to_world_position(destination)
	if not did_move:
		movement_component.stop()
		clear_movement_ignore_nodes()

	return did_move

func command_hold_position():
	clear_movement_ignore_nodes()
	issue_hold_position_order(global_position)

	if movement_component != null:
		movement_component.stop()

func command_defend_area(anchor_position: Vector2, radius_tiles: int = -1):
	clear_movement_ignore_nodes()
	issue_defend_area_order(anchor_position, radius_tiles)

func command_stop():
	clear_movement_ignore_nodes()
	issue_idle_order()

	if movement_component != null:
		movement_component.stop()

func is_air_target(target: Node) -> bool:
	var target_unit_data = _get_property_or_null(target, "unit_data")
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

func take_damage(amount: int):
	current_health = maxi(current_health - amount, 0)

	if health_bar != null:
		health_bar.value = current_health

	after_damage_taken(amount)

	if current_health <= 0:
		die()

func after_damage_taken(_amount: int):
	if debug_logging:
		print(name, " took damage. HP: ", current_health)

func die():
	if debug_logging:
		print(name, " died")

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
