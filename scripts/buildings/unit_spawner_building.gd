@tool
extends StaticBody2D

class_name UnitSpawnerBuilding

@export var spawn_unit_scene: PackedScene
@export var unit_data: UnitData
@export var building_data: Resource

@export var max_health: int = 150
@export var xp_reward: int = 25
@export var gold_reward: int = 10

@export var max_alive_units: int = 3
@export var initial_unit_count: int = 3
@export var auto_spawn_enabled: bool = false:
	set(value):
		auto_spawn_enabled = value
		update_process_mode()
@export var spawn_interval: float = 5.0
@export var spawn_radius: float = 160.0
@export var min_spawn_distance_from_units: float = 80.0
@export var max_spawn_attempts: int = 20
@export var debug_logging: bool = false
@export var target_scan_interval: float = 0.25

@export var tile_width: int = 2:
	set(value):
		tile_width = max(value, 1)
		update_tile_sizing()

@export var tile_height: int = 2:
	set(value):
		tile_height = max(value, 1)
		update_tile_sizing()

@export var fallback_tile_size: int = 64:
	set(value):
		fallback_tile_size = max(value, 1)
		update_tile_sizing()

@export var snap_to_grid_in_editor: bool = true:
	set(value):
		snap_to_grid_in_editor = value
		update_tile_sizing()

@export var snap_to_grid_on_ready: bool = true

var current_health: int
var spawned_units: Array[Node] = []

var spawn_timer: float = 0.0
var attack_timer: float = 0.0
var target_scan_timer: float = 0.0
var attack_target: Node2D = null
var is_destroyed: bool = false
var cached_grid_manager: Node = null
var cached_occupancy_manager: Node = null
var can_attack: bool = false
var can_attack_override: bool = false
var attack_damage: int = 0
var attack_range_tiles: int = 0
var attack_cooldown: float = 1.0
var production_component: ProductionComponent = null

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")
@onready var body_collision: CollisionShape2D = $CollisionShape2D
@onready var hitbox: Area2D = $Hitbox
@onready var hitbox_collision: CollisionShape2D = $Hitbox/CollisionShape2D
@onready var health_bar: ProgressBar = get_node_or_null("HealthBar")
@onready var unit_classification: UnitClassification = get_node_or_null("UnitClassification")
@onready var classification_label: Label = get_node_or_null("ClassificationLabel")

func _ready():
	apply_structure_data()
	update_tile_sizing()
	_spawn_subtype_indicator()
	update_process_mode()

	if Engine.is_editor_hint():
		return

	if snap_to_grid_on_ready:
		snap_building_to_grid()

	current_health = max_health
	setup_health_bar()

	var world_manager = get_tree().get_first_node_in_group("world_manager")
	if world_manager != null and is_enemy_camp_structure():
		world_manager.register_enemy_camp()

	spawn_timer = spawn_interval
	target_scan_timer = randf() * target_scan_interval
	cached_grid_manager = get_tree().get_first_node_in_group("grid_manager")
	cached_occupancy_manager = get_tree().get_first_node_in_group("grid_occupancy_manager")

	var occupancy_manager = get_occupancy_manager()
	if occupancy_manager != null:
		occupancy_manager.register_node(self)

	if auto_spawn_enabled:
		for i in range(initial_unit_count):
			spawn_unit()
			
	_setup_production()

	if debug_logging:
		print("Unit spawner building active. HP: ", current_health)

func _setup_production():
	production_component = get_node_or_null("ProductionComponent")
	if production_component == null:
		production_component = ProductionComponent.new()
		production_component.name = "ProductionComponent"
		add_child(production_component)

func _process(delta):
	if Engine.is_editor_hint():
		update_tile_sizing()
		return

	if is_destroyed:
		return

	if auto_spawn_enabled:
		spawn_timer -= delta

		if spawn_timer <= 0.0:
			spawn_timer = spawn_interval
			clean_spawned_unit_list()

			if spawned_units.size() < max_alive_units:
				spawn_unit()

	if not can_attack_override:
		process_auto_attack(delta)

func update_process_mode():
	if not is_inside_tree():
		return

	set_process(Engine.is_editor_hint() or auto_spawn_enabled or should_auto_attack())

func get_tile_size() -> int:
	var grid_manager = get_grid_manager()

	if grid_manager != null:
		return grid_manager.tile_size

	return fallback_tile_size

func get_pixel_size() -> Vector2:
	var tile_size = get_tile_size()
	return Vector2(tile_width * tile_size, tile_height * tile_size)

func apply_structure_data():
	if building_data != null:
		var building_display_name = str(building_data.get("display_name"))
		var building_id = str(building_data.get("building_id"))
		name = building_display_name if not building_display_name.is_empty() else building_id
		max_health = int(building_data.get("max_health"))
		tile_width = maxi(int(building_data.get("footprint_width")), 1)
		tile_height = maxi(int(building_data.get("footprint_height")), 1)
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

		update_classification_label()
		_spawn_subtype_indicator()
		return

	if unit_data == null:
		return

	name = unit_data.display_name if not unit_data.display_name.is_empty() else unit_data.unit_id
	max_health = unit_data.max_health
	tile_width = maxi(unit_data.footprint_width, 1)
	tile_height = maxi(unit_data.footprint_height, 1)
	can_attack = unit_data.can_attack
	attack_damage = unit_data.damage
	attack_range_tiles = maxi(unit_data.attack_range_tiles, 0)
	attack_cooldown = maxf(unit_data.attack_cooldown, 0.05)

	if sprite != null and unit_data.sprite_texture != null:
		sprite.texture = unit_data.sprite_texture

	apply_nation_visuals()

	if unit_classification != null:
		unit_classification.apply_unit_data(unit_data)

	update_classification_label()
	_spawn_subtype_indicator()

func update_tile_sizing():
	if not is_inside_tree():
		return

	var pixel_size = get_pixel_size()

	update_sprite_size(pixel_size)
	update_collision_size(pixel_size)
	update_hitbox_size(pixel_size)
	update_health_bar_size(pixel_size)

	if Engine.is_editor_hint() and snap_to_grid_in_editor:
		snap_building_to_grid()

func update_sprite_size(pixel_size: Vector2):
	if sprite == null:
		return

	if sprite.texture == null:
		return

	var texture_size = sprite.texture.get_size()

	if texture_size.x <= 0 or texture_size.y <= 0:
		return

	sprite.scale = Vector2(
		pixel_size.x / texture_size.x,
		pixel_size.y / texture_size.y
	)

func update_collision_size(pixel_size: Vector2):
	if body_collision == null:
		return

	if body_collision.shape == null:
		body_collision.shape = RectangleShape2D.new()

	if body_collision.shape is RectangleShape2D:
		body_collision.shape.size = pixel_size

func update_hitbox_size(pixel_size: Vector2):
	if hitbox_collision == null:
		return

	if hitbox_collision.shape == null:
		hitbox_collision.shape = RectangleShape2D.new()

	if hitbox_collision.shape is RectangleShape2D:
		hitbox_collision.shape.size = pixel_size

func update_health_bar_size(pixel_size: Vector2):
	if health_bar == null:
		return

	health_bar.position = Vector2(-pixel_size.x / 2.0, -pixel_size.y / 2.0 - 20.0)

	# ProgressBar has a minimum height, so we use scale for visual height.
	health_bar.size = Vector2(pixel_size.x * 2.0, 27.0)
	health_bar.scale = Vector2(0.5, 0.3)

	if classification_label != null:
		classification_label.position = Vector2(-pixel_size.x / 2.0, -13.0)
		classification_label.size = Vector2(pixel_size.x, 26.0)

func snap_building_to_grid():
	var grid_manager = get_grid_manager()

	if grid_manager == null:
		return

	global_position = grid_manager.snap_world_to_footprint_center(
		global_position,
		tile_width,
		tile_height
	)

func setup_health_bar():
	if health_bar == null:
		return

	health_bar.min_value = 0
	health_bar.max_value = max_health
	health_bar.value = current_health
	health_bar.show_percentage = false

func update_health_bar():
	if health_bar == null:
		return

	health_bar.value = current_health

func spawn_unit():
	if spawn_unit_scene == null:
		if debug_logging:
			print("UnitSpawnerBuilding error: spawn_unit_scene is not assigned.")
		return

	var spawned_unit = spawn_unit_scene.instantiate()
	var spawn_position = get_valid_spawn_position()
	spawned_unit.global_position = spawn_position
	_assign_spawned_unit_ownership(spawned_unit)

	get_parent().call_deferred("add_child", spawned_unit)
	spawned_units.append(spawned_unit)

	if debug_logging:
		print("Unit spawner building spawned a unit. Alive: ", spawned_units.size())

func get_valid_spawn_position() -> Vector2:
	var players = get_tree().get_nodes_in_group("player")

	for attempt in range(max_spawn_attempts):
		var random_angle = randf() * TAU
		var random_distance = randf_range(spawn_radius * 0.5, spawn_radius)
		var offset = Vector2(cos(random_angle), sin(random_angle)) * random_distance
		var possible_position = global_position + offset
		possible_position = snap_spawn_position_to_grid(possible_position)

		if is_spawn_position_clear(possible_position, players):
			return possible_position

	var fallback_angle = randf() * TAU
	var fallback_offset = Vector2(cos(fallback_angle), sin(fallback_angle)) * spawn_radius
	return snap_spawn_position_to_grid(global_position + fallback_offset)

func snap_spawn_position_to_grid(spawn_position: Vector2) -> Vector2:
	var grid_manager = get_grid_manager()

	if grid_manager == null:
		return spawn_position

	return grid_manager.snap_world_to_footprint_center(spawn_position, 1, 1)

func is_spawn_position_clear(possible_position: Vector2, players: Array) -> bool:
	if HitboxMath.get_hitbox_rect(self).has_point(possible_position):
		return false

	var grid_manager = get_grid_manager()

	if grid_manager != null and grid_manager.is_footprint_occupied(possible_position, 1, 1, self):
		return false

	var min_distance_squared := min_spawn_distance_from_units * min_spawn_distance_from_units

	for spawned_unit in spawned_units:
		if is_instance_valid(spawned_unit):
			if possible_position.distance_squared_to(spawned_unit.global_position) < min_distance_squared:
				return false

	for player in players:
		if player is Node2D:
			if possible_position.distance_squared_to(player.global_position) < min_distance_squared:
				return false

	return true

func clean_spawned_unit_list():
	var cleaned_list: Array[Node] = []

	for spawned_unit in spawned_units:
		if is_instance_valid(spawned_unit):
			cleaned_list.append(spawned_unit)

	spawned_units = cleaned_list

func get_alive_spawned_unit_count() -> int:
	var count = 0

	for spawned_unit in spawned_units:
		if is_instance_valid(spawned_unit):
			count += 1

	return count

func set_selected(selected: bool):
	if health_bar != null:
		health_bar.visible = selected or current_health < max_health
	
	if classification_label != null:
		classification_label.visible = selected

func process_auto_attack(delta: float):
	if not should_auto_attack():
		return

	attack_timer -= delta
	target_scan_timer -= delta

	if attack_target != null and not is_valid_attack_target(attack_target):
		attack_target = null
		target_scan_timer = 0.0

	if attack_target == null and target_scan_timer <= 0.0:
		target_scan_timer = target_scan_interval
		attack_target = find_attack_target()

	if attack_target == null or attack_timer > 0.0:
		return

	attack_timer = attack_cooldown
	attack_target.take_damage(CombatDamage.calculate_damage(attack_damage, self, attack_target))

func should_auto_attack() -> bool:
	if not can_attack or attack_damage <= 0 or attack_range_tiles <= 0:
		return false

	if building_data == null:
		return false

	return bool(building_data.get("is_defense_building"))

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

func is_valid_attack_target(candidate: Node) -> bool:
	if candidate == null or candidate == self or not is_instance_valid(candidate):
		return false

	if not candidate is Node2D:
		return false

	if not candidate.has_method("take_damage"):
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

func _assign_spawned_unit_ownership(spawned_unit: Node):
	if spawned_unit == null:
		return

	var spawner_ownership = get_ownership_component(self)

	if spawner_ownership == null:
		return

	var ownership = get_ownership_component(spawned_unit)

	if ownership == null:
		ownership = UnitOwnershipComponent.new()
		ownership.name = "UnitOwnershipComponent"
		spawned_unit.add_child(ownership)

	ownership.set_ownership(
		spawner_ownership.owner_nation,
		spawner_ownership.allegiance,
		spawner_ownership.owner_id
	)
	_assign_allegiance_groups(spawned_unit, ownership)

func _assign_allegiance_groups(node: Node, ownership: UnitOwnershipComponent):
	for group_name in ["player", "enemy", "enemy_unit", "ally", "neutral"]:
		if node.is_in_group(group_name):
			node.remove_from_group(group_name)

	if ownership.is_player_owned():
		node.add_to_group("player")
	elif ownership.is_enemy():
		node.add_to_group("enemy")
		node.add_to_group("enemy_unit")
	elif ownership.is_ally():
		node.add_to_group("ally")
	else:
		node.add_to_group("neutral")

func get_ownership_component(node: Node) -> UnitOwnershipComponent:
	if node == null:
		return null

	return node.get_node_or_null("UnitOwnershipComponent") as UnitOwnershipComponent

func take_damage(amount: int):
	if is_destroyed:
		return

	current_health -= amount
	current_health = max(current_health, 0)

	update_health_bar()

	if debug_logging:
		print("Unit spawner building took damage. HP: ", current_health)

	if current_health <= 0:
		die()

func die():
	is_destroyed = true
	if debug_logging:
		print("Unit spawner building destroyed!")

	var occupancy_manager = get_occupancy_manager()
	if occupancy_manager != null:
		occupancy_manager.unregister_node(self)

	var player_manager = get_tree().get_first_node_in_group("player_manager")
	if player_manager != null and is_enemy_target_for_rewards():
		player_manager.gain_xp(xp_reward)
		player_manager.gain_gold(gold_reward)

	var world_manager = get_tree().get_first_node_in_group("world_manager")
	if world_manager != null and is_enemy_camp_structure():
		world_manager.register_camp_destroyed()

	queue_free()

func get_hitbox() -> Area2D:
	return hitbox

func get_tile_footprint_size() -> Vector2i:
	return Vector2i(tile_width, tile_height)

func update_classification_label():
	if classification_label == null:
		return

	if building_data != null:
		classification_label.text = UnitClassification.get_unit_archetype_abbreviation(building_data.get("unit_archetype"))
		return

	if unit_data != null:
		classification_label.text = UnitClassification.get_unit_archetype_abbreviation(unit_data.unit_archetype)

func is_enemy_camp_structure() -> bool:
	if building_data != null:
		return bool(building_data.get("is_enemy_camp"))

	if unit_data != null:
		return unit_data.is_structure

	return false

func is_enemy_target_for_rewards() -> bool:
	var ownership = get_ownership_component(self)

	if ownership != null:
		return ownership.is_enemy()

	return is_in_group("enemy") or is_in_group("enemy_unit")

func get_grid_manager():
	if cached_grid_manager == null or not is_instance_valid(cached_grid_manager):
		cached_grid_manager = get_tree().get_first_node_in_group("grid_manager")

	return cached_grid_manager

func get_occupancy_manager():
	if cached_occupancy_manager == null or not is_instance_valid(cached_occupancy_manager):
		cached_occupancy_manager = get_tree().get_first_node_in_group("grid_occupancy_manager")

	return cached_occupancy_manager

func apply_nation_visuals():
	var source_data: Resource = building_data
	if source_data == null:
		source_data = unit_data

	NationVisuals.apply_owner_or_data_to_node(self, source_data)

func _spawn_subtype_indicator():
	if Engine.is_editor_hint():
		return

	var source_data: Resource = building_data
	if source_data == null:
		source_data = unit_data

	var indicator_scene = preload("res://scenes/ui/subtype_indicator.tscn")
	var indicator = get_node_or_null("SubtypeIndicator")
	if indicator == null:
		indicator = indicator_scene.instantiate()
		indicator.name = "SubtypeIndicator"
		add_child(indicator)

	indicator.z_index = 2
	if indicator.has_method("setup"):
		indicator.setup(source_data, Vector2i(tile_width, tile_height))
