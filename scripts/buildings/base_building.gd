@tool
extends StaticBody2D
class_name BaseBuilding

@export var building_data: Resource:
	set(value):
		building_data = value
		apply_building_data()

@export var target_scan_interval: float = 0.25

@export var fallback_tile_size: int = 64:
	set(value):
		fallback_tile_size = max(value, 1)
		apply_building_data()

@export var construction_time: float = 10.0
@export var start_under_construction: bool = false

var max_health: int = 0
var current_health: int = 0
var footprint_width: int = 1
var footprint_height: int = 1
var can_attack: bool = false
var can_attack_override: bool = false
var attack_damage: int = 0
var attack_range_tiles: int = 0
var attack_cooldown: float = 1.0
var xp_reward: int = 0
var gold_reward: int = 0
var attack_timer: float = 0.0
var target_scan_timer: float = 0.0
var attack_target: Node2D = null
var is_destroyed: bool = false
var construction_component: ConstructionComponent = null
var production_component: ProductionComponent = null
var cached_grid_manager: Node = null
var cached_occupancy_manager: Node = null

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")
@onready var body_collision: CollisionShape2D = get_node_or_null("CollisionShape2D")
@onready var hitbox_collision: CollisionShape2D = get_node_or_null("Hitbox/CollisionShape2D")
@onready var health_bar: ProgressBar = get_node_or_null("HealthBar")
@onready var classification_label: Label = get_node_or_null("ClassificationLabel")
@onready var unit_classification: UnitClassification = get_node_or_null("UnitClassification")

func _ready():
	apply_building_data()

	if Engine.is_editor_hint():
		return

	current_health = max_health
	target_scan_timer = randf() * target_scan_interval
	setup_health_bar()
	update_process_mode()

	var world_manager = get_tree().get_first_node_in_group("world_manager")
	if world_manager != null and is_enemy_camp_structure():
		world_manager.register_enemy_camp()

	var occupancy_manager = get_occupancy_manager()
	if occupancy_manager != null:
		occupancy_manager.register_node(self)

	_setup_construction()
	_setup_production()

func _setup_construction():
	construction_component = get_node_or_null("ConstructionComponent")
	if construction_component == null:
		construction_component = ConstructionComponent.new()
		construction_component.name = "ConstructionComponent"
		construction_component.construction_time = construction_time
		add_child(construction_component)
	
	if start_under_construction:
		construction_component.start_construction()

func _setup_production():
	if building_data != null and not bool(building_data.get("is_production_building")):
		return
		
	production_component = get_node_or_null("ProductionComponent")
	if production_component == null:
		production_component = ProductionComponent.new()
		production_component.name = "ProductionComponent"
		add_child(production_component)

func _process(delta: float):
	if Engine.is_editor_hint() or is_destroyed or not should_auto_attack() or can_attack_override:
		return

	attack_timer -= delta
	target_scan_timer -= delta

	if attack_target != null and not is_valid_attack_target(attack_target):
		attack_target = null
		target_scan_timer = 0.0

	if attack_target == null and target_scan_timer <= 0.0:
		target_scan_timer = target_scan_interval
		attack_target = find_attack_target()

	if attack_target == null:
		return

	if attack_timer > 0.0:
		return

	attack_timer = attack_cooldown
	attack_target.take_damage(CombatDamage.calculate_damage(attack_damage, self, attack_target))

func apply_building_data():
	if not is_inside_tree():
		return

	if building_data == null:
		_update_sizes()
		return

	var display_name = str(building_data.get("display_name"))
	var building_id = str(building_data.get("building_id"))
	name = display_name if not display_name.is_empty() else building_id

	max_health = int(building_data.get("max_health"))
	current_health = max_health
	footprint_width = maxi(int(building_data.get("footprint_width")), 1)
	footprint_height = maxi(int(building_data.get("footprint_height")), 1)
	can_attack = bool(building_data.get("can_attack"))
	attack_damage = int(building_data.get("damage"))
	attack_range_tiles = maxi(int(building_data.get("attack_range_tiles")), 0)
	attack_cooldown = maxf(float(building_data.get("attack_cooldown")), 0.05)

	var sprite_texture = building_data.get("sprite_texture") as Texture2D
	if sprite != null and sprite_texture != null:
		sprite.texture = sprite_texture

	apply_nation_visuals()

	if unit_classification != null:
		unit_classification.apply_building_data(building_data)

	if bool(building_data.get("is_resource_building")):
		add_to_group("resource_building")
	else:
		remove_from_group("resource_building")

	update_classification_label()
	_update_sizes()
	_spawn_subtype_indicator()
	setup_health_bar()
	update_process_mode()

func update_process_mode():
	if not is_inside_tree():
		return

	set_process(not Engine.is_editor_hint() and should_auto_attack())

func setup_health_bar():
	if health_bar == null:
		return

	health_bar.min_value = 0
	health_bar.max_value = max_health
	health_bar.value = current_health
	health_bar.show_percentage = false

func take_damage(amount: int):
	if is_destroyed:
		return

	if has_method("can_take_combat_damage") and not can_take_combat_damage():
		return

	current_health = maxi(current_health - amount, 0)

	if health_bar != null:
		health_bar.value = current_health

	if current_health <= 0:
		die()

func die():
	is_destroyed = true

	var occupancy_manager = get_occupancy_manager()
	if occupancy_manager != null:
		occupancy_manager.unregister_node(self)

	var road_supply_manager = get_tree().get_first_node_in_group("road_supply_manager")
	if road_supply_manager != null and road_supply_manager.has_method("unregister_building"):
		road_supply_manager.unregister_building(self)

	if is_enemy_target_for_rewards():
		var player_manager = get_tree().get_first_node_in_group("player_manager")
		if player_manager != null:
			if xp_reward > 0:
				player_manager.gain_xp(xp_reward)
			if gold_reward > 0:
				player_manager.gain_gold(gold_reward)

	var world_manager = get_tree().get_first_node_in_group("world_manager")
	if world_manager != null and is_enemy_camp_structure():
		world_manager.register_camp_destroyed()

	queue_free()

func get_tile_size() -> int:
	var grid_manager = get_grid_manager()

	if grid_manager != null:
		return grid_manager.tile_size

	return fallback_tile_size

func get_tile_footprint_size() -> Vector2i:
	return Vector2i(footprint_width, footprint_height)

func can_take_combat_damage() -> bool:
	return true

func get_hitbox() -> Area2D:
	return get_node_or_null("Hitbox")

func update_classification_label():
	if classification_label == null or building_data == null:
		return

	classification_label.text = UnitClassification.get_unit_archetype_abbreviation(building_data.get("unit_archetype"))

func find_attack_target() -> Node2D:
	var closest_target: Node2D = null
	var closest_distance_squared = INF
	var seen_instance_ids := {}

	for group_name in get_hostile_target_groups():
		for node in get_tree().get_nodes_in_group(group_name):
			if not is_valid_attack_target(node):
				continue

			var node_id = node.get_instance_id()
			if seen_instance_ids.has(node_id):
				continue

			seen_instance_ids[node_id] = true
			var target = node as Node2D
			var distance_squared = global_position.distance_squared_to(target.global_position)

			if distance_squared < closest_distance_squared:
				closest_distance_squared = distance_squared
				closest_target = target

	return closest_target

func should_auto_attack() -> bool:
	if not can_attack or attack_damage <= 0 or attack_range_tiles <= 0:
		return false

	if building_data == null:
		return false

	return bool(building_data.get("is_defense_building"))

func is_valid_attack_target(candidate: Node) -> bool:
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

	return is_hostile_to_self(candidate) and is_target_in_attack_tile_range(candidate as Node2D)

func is_target_in_attack_tile_range(target: Node2D) -> bool:
	if target == null or attack_range_tiles <= 0:
		return false

	var grid_manager = get_grid_manager()

	if grid_manager == null:
		var attack_range_pixels := float(attack_range_tiles * fallback_tile_size)
		return global_position.distance_squared_to(target.global_position) <= attack_range_pixels * attack_range_pixels

	var self_cells = grid_manager.get_footprint_cells_for_node(self)
	var target_cells = grid_manager.get_footprint_cells_for_node(target)

	for self_cell in self_cells:
		for target_cell in target_cells:
			var offset = target_cell - self_cell

			if maxi(abs(offset.x), abs(offset.y)) <= attack_range_tiles:
				return true

	return false

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

func is_enemy_camp_structure() -> bool:
	return building_data != null and bool(building_data.get("is_enemy_camp"))

func is_enemy_target_for_rewards() -> bool:
	var ownership = get_ownership_component(self)

	if ownership != null:
		return ownership.is_enemy()

	return is_in_group("enemy") or is_in_group("enemy_unit")

func _update_sizes():
	var pixel_size = Vector2(footprint_width, footprint_height) * get_tile_size()

	if sprite != null and sprite.texture != null:
		var texture_size = sprite.texture.get_size()
		if texture_size.x > 0 and texture_size.y > 0:
			sprite.scale = Vector2(pixel_size.x / texture_size.x, pixel_size.y / texture_size.y)

	if body_collision != null:
		if body_collision.shape == null:
			body_collision.shape = RectangleShape2D.new()
		if body_collision.shape is RectangleShape2D:
			body_collision.shape.size = pixel_size

	if hitbox_collision != null:
		if hitbox_collision.shape == null:
			hitbox_collision.shape = RectangleShape2D.new()
		if hitbox_collision.shape is RectangleShape2D:
			hitbox_collision.shape.size = pixel_size

	if health_bar != null:
		health_bar.position = Vector2(-pixel_size.x / 2.0, -pixel_size.y / 2.0 - 20.0)
		health_bar.size = Vector2(pixel_size.x * 2.0, 27.0)
		health_bar.scale = Vector2(0.5, 0.3)

	if classification_label != null:
		classification_label.position = Vector2(-pixel_size.x / 2.0, -13.0)
		classification_label.size = Vector2(pixel_size.x, 26.0)

func apply_nation_visuals():
	NationVisuals.apply_owner_or_data_to_node(self, building_data)

func set_selected(selected: bool):
	if health_bar != null:
		health_bar.visible = selected or current_health < max_health
	
	if classification_label != null:
		classification_label.visible = selected

func get_grid_manager():
	if cached_grid_manager == null or not is_instance_valid(cached_grid_manager):
		cached_grid_manager = get_tree().get_first_node_in_group("grid_manager")

	return cached_grid_manager

func get_occupancy_manager():
	if cached_occupancy_manager == null or not is_instance_valid(cached_occupancy_manager):
		cached_occupancy_manager = get_tree().get_first_node_in_group("grid_occupancy_manager")

	return cached_occupancy_manager

func _spawn_subtype_indicator():
	if Engine.is_editor_hint():
		return

	var indicator_scene = preload("res://scenes/ui/subtype_indicator.tscn")
	var indicator = get_node_or_null("SubtypeIndicator")
	if indicator == null:
		indicator = indicator_scene.instantiate()
		indicator.name = "SubtypeIndicator"
		add_child(indicator)

	indicator.z_index = 2
	if indicator.has_method("setup"):
		indicator.setup(building_data, Vector2i(footprint_width, footprint_height))
