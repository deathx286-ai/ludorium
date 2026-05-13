@tool
extends Node2D
class_name ResourceNode

@export var resource_type: BuildingData.ResourceType = BuildingData.ResourceType.WOOD:
	set(value):
		resource_type = value
		required_worker_type = EconomyTypes.get_required_worker_for_resource(resource_type)
		_update_visuals()

@export var required_worker_type: EconomyTypes.WorkerType = EconomyTypes.WorkerType.LUMBER:
	set(value):
		required_worker_type = value
		_update_visuals()

@export var harvest_amount: int = 10
@export var harvest_interval: float = 2.0
@export var max_workers: int = 3
@export var contest_radius: float = 5.0
@export var harvest_range: float = 1.0
@export var footprint_width: int = 1
@export var footprint_height: int = 1
@export var debug_visuals_enabled: bool = true:
	set(value):
		debug_visuals_enabled = value
		queue_redraw()
@export var show_contest_radius: bool = true:
	set(value):
		show_contest_radius = value
		queue_redraw()
@export var debug_print_harvesting: bool = true

var assigned_harvesters: Dictionary = {}
var contested: bool = false
var last_debug_action: String = ""

@onready var label: Label = get_node_or_null("Label")
@onready var hitbox: Area2D = get_node_or_null("Hitbox")
@onready var hitbox_collision: CollisionShape2D = get_node_or_null("Hitbox/CollisionShape2D")
@onready var grid_manager = get_tree().get_first_node_in_group("grid_manager") if not Engine.is_editor_hint() else null
@onready var resource_manager: ResourceManager = get_tree().get_first_node_in_group("resource_manager") as ResourceManager if not Engine.is_editor_hint() else null

func _ready():
	add_to_group("resource_node")
	_update_visuals()

	if Engine.is_editor_hint():
		return

	_register_occupancy()
	set_process(true)

func _exit_tree():
	if Engine.is_editor_hint():
		return

	var occupancy_manager = get_tree().get_first_node_in_group("grid_occupancy_manager")
	if occupancy_manager != null and occupancy_manager.has_method("unregister_node"):
		occupancy_manager.unregister_node(self)

func _process(delta: float):
	if Engine.is_editor_hint():
		return

	_tick_harvesters(delta)
	var new_contested = is_contested()
	if new_contested != contested:
		contested = new_contested
		queue_redraw()

func _draw():
	if not debug_visuals_enabled:
		return

	var tile_size = _get_tile_size()
	var body_size = Vector2(footprint_width, footprint_height) * tile_size
	var rect = Rect2(-body_size / 2.0, body_size)
	var node_color = _get_resource_color(resource_type)

	draw_rect(rect, node_color * Color(1, 1, 1, 0.55), true)
	draw_rect(rect, node_color, false, 3.0)
	draw_circle(Vector2.ZERO, min(body_size.x, body_size.y) * 0.28, node_color.lightened(0.25))

	if show_contest_radius:
		var contest_color = Color(1.0, 0.2, 0.1, 0.22) if contested else Color(1.0, 0.85, 0.15, 0.12)
		draw_arc(Vector2.ZERO, contest_radius * tile_size, 0.0, TAU, 48, contest_color, 3.0)

func request_harvester(worker: Node2D) -> bool:
	if worker == null or not is_instance_valid(worker):
		return false

	if not is_harvestable_by(worker):
		_print_harvest("harvest rejected: %s cannot harvest %s" % [_get_node_display_name(worker), EconomyTypes.get_resource_name(resource_type)])
		return false

	var worker_id = worker.get_instance_id()
	if assigned_harvesters.has(worker_id):
		return true

	if assigned_harvesters.size() >= max_workers:
		_print_harvest("harvest rejected: %s is full (%s/%s)" % [name, assigned_harvesters.size(), max_workers])
		return false

	if not is_worker_in_harvest_range(worker):
		return false

	assigned_harvesters[worker_id] = {
		"worker": worker,
		"timer": 0.0,
		"paused": false
	}
	_print_harvest("harvest start: %s -> %s" % [_get_node_display_name(worker), name])
	_update_visuals()
	queue_redraw()
	return true

func stop_harvester(worker: Node2D, reason: String = "stopped"):
	if worker == null:
		return

	var worker_id = worker.get_instance_id()
	if not assigned_harvesters.has(worker_id):
		return

	assigned_harvesters.erase(worker_id)
	_print_harvest("harvest stop: %s -> %s (%s)" % [_get_node_display_name(worker), name, reason])
	_update_visuals()
	queue_redraw()

func is_harvestable_by(worker: Node) -> bool:
	if worker == null or not is_instance_valid(worker):
		return false

	var worker_type = EconomyTypes.WorkerType.NONE
	var unit_data = _get_property_or_null(worker, "unit_data")
	if unit_data != null:
		if not bool(_get_property_or_default(unit_data, "can_harvest", false)):
			return false
		worker_type = int(_get_property_or_default(unit_data, "worker_type", EconomyTypes.WorkerType.NONE))

	if worker.has_method("get_worker_type"):
		worker_type = int(worker.call("get_worker_type"))

	return EconomyTypes.worker_can_harvest(worker_type, required_worker_type)

func is_worker_in_harvest_range(worker: Node2D) -> bool:
	if worker == null or not is_instance_valid(worker):
		return false

	if grid_manager != null:
		var range_tiles = maxi(ceili(harvest_range), 0)
		var worker_cells = grid_manager.get_footprint_cells_for_node(worker)
		var node_cells = grid_manager.get_footprint_cells_for_node(self)

		for worker_cell in worker_cells:
			for node_cell in node_cells:
				var offset = worker_cell - node_cell
				if maxi(abs(offset.x), abs(offset.y)) <= range_tiles:
					return true

		return false

	return worker.global_position.distance_to(global_position) <= harvest_range * _get_tile_size()

func is_contested() -> bool:
	for data in assigned_harvesters.values():
		var worker = data.get("worker", null)
		if is_instance_valid(worker) and worker is Node2D and is_contested_for_worker(worker):
			return true

	return false

func is_contested_for_worker(worker: Node2D) -> bool:
	if worker == null or not is_instance_valid(worker):
		return false

	var radius_pixels = contest_radius * _get_tile_size()
	var seen_ids := {}

	for group_name in ["player", "ally", "enemy", "enemy_unit"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node) or node == worker or not node is Node2D:
				continue

			var node_id = node.get_instance_id()
			if seen_ids.has(node_id):
				continue

			seen_ids[node_id] = true
			var candidate = node as Node2D

			if candidate.global_position.distance_to(global_position) > radius_pixels:
				continue

			if not _is_combat_unit(candidate):
				continue

			if _is_hostile(worker, candidate):
				return true

	return false

func take_damage(_amount: int):
	_print_harvest("ignored combat damage: %s is indestructible" % name)

func can_take_combat_damage() -> bool:
	return false

func get_tile_footprint_size() -> Vector2i:
	return Vector2i(maxi(footprint_width, 1), maxi(footprint_height, 1))

func get_hitbox() -> Area2D:
	return hitbox

func contains_world_position(world_position: Vector2) -> bool:
	if hitbox != null and HitboxMath.contains_point(self, world_position):
		return true

	var tile_size = _get_tile_size()
	var rect = Rect2(global_position - Vector2(footprint_width, footprint_height) * tile_size / 2.0, Vector2(footprint_width, footprint_height) * tile_size)
	return rect.has_point(world_position)

func get_debug_state() -> Dictionary:
	return {
		"name": name,
		"resource_type": resource_type,
		"resource_name": EconomyTypes.get_resource_name(resource_type),
		"required_worker_type": required_worker_type,
		"required_worker_name": EconomyTypes.get_worker_type_name(required_worker_type),
		"harvest_amount": harvest_amount,
		"harvest_interval": harvest_interval,
		"assigned_workers": assigned_harvesters.size(),
		"max_workers": max_workers,
		"contested": contested,
		"contest_radius": contest_radius,
		"harvest_range": harvest_range,
		"last_action": last_debug_action
	}

func _tick_harvesters(delta: float):
	var harvesters_to_remove: Array[Node2D] = []

	for worker_id in assigned_harvesters.keys():
		var data = assigned_harvesters[worker_id]
		var worker = data.get("worker", null)

		if not worker is Node2D or not is_instance_valid(worker):
			assigned_harvesters.erase(worker_id)
			continue

		var worker_health = _get_property_or_default(worker, "current_health", 1)
		if int(worker_health) <= 0:
			harvesters_to_remove.append(worker)
			continue

		if not is_worker_in_harvest_range(worker):
			harvesters_to_remove.append(worker)
			continue

		if is_contested_for_worker(worker):
			if not bool(data.get("paused", false)):
				data["paused"] = true
				_print_harvest("harvest pause: %s contested by hostile units" % name)
			assigned_harvesters[worker_id] = data
			continue

		if bool(data.get("paused", false)):
			data["paused"] = false
			_print_harvest("harvest resume: %s" % name)

		data["timer"] = float(data.get("timer", 0.0)) + delta

		if float(data["timer"]) >= maxf(harvest_interval, 0.05):
			data["timer"] = 0.0
			_grant_harvest(worker)

		assigned_harvesters[worker_id] = data

	for worker in harvesters_to_remove:
		stop_harvester(worker, "worker left range or died")

func _grant_harvest(worker: Node2D):
	if resource_manager == null or not is_instance_valid(resource_manager):
		resource_manager = get_tree().get_first_node_in_group("resource_manager") as ResourceManager

	var owner_nation = _get_owner_nation(worker)
	if resource_manager != null:
		resource_manager.add_resource(owner_nation, resource_type, harvest_amount)

	_print_harvest("harvest tick: %s +%s %s" % [
		_get_owner_key(worker),
		harvest_amount,
		EconomyTypes.get_resource_name(resource_type)
	])

func _register_occupancy():
	var occupancy_manager = get_tree().get_first_node_in_group("grid_occupancy_manager")
	if occupancy_manager != null and occupancy_manager.has_method("register_node"):
		occupancy_manager.register_node(self)

func _update_visuals():
	if not is_inside_tree():
		return

	name = "%s Node" % EconomyTypes.get_resource_name(resource_type)

	if label != null:
		label.text = "%s\n%s/%s" % [
			EconomyTypes.get_resource_name(resource_type),
			assigned_harvesters.size(),
			max_workers
		]

	if hitbox_collision != null:
		if hitbox_collision.shape == null:
			hitbox_collision.shape = RectangleShape2D.new()
		if hitbox_collision.shape is RectangleShape2D:
			hitbox_collision.shape.size = Vector2(footprint_width, footprint_height) * _get_tile_size()

	queue_redraw()

func _get_resource_color(type: int) -> Color:
	match type:
		BuildingData.ResourceType.WOOD:
			return Color(0.16, 0.52, 0.20, 1.0)
		BuildingData.ResourceType.FOOD:
			return Color(0.86, 0.70, 0.18, 1.0)
		BuildingData.ResourceType.GOLD:
			return Color(1.0, 0.72, 0.08, 1.0)
		BuildingData.ResourceType.STONE:
			return Color(0.55, 0.58, 0.62, 1.0)
		BuildingData.ResourceType.METAL:
			return Color(0.45, 0.62, 0.72, 1.0)
		_:
			return Color.WHITE

func _is_combat_unit(node: Node) -> bool:
	if node == null:
		return false

	var unit_data = _get_property_or_null(node, "unit_data")
	if unit_data != null:
		return bool(_get_property_or_default(unit_data, "can_attack", false))

	var building_data = _get_property_or_null(node, "building_data")
	if building_data != null:
		return bool(_get_property_or_default(building_data, "can_attack", false))

	return node.has_method("try_attack_current_target")

func _is_hostile(a: Node, b: Node) -> bool:
	var a_ownership = _get_ownership_component(a)
	var b_ownership = _get_ownership_component(b)

	if a_ownership != null and b_ownership != null:
		if a_ownership.is_enemy():
			return b_ownership.is_player_owned() or b_ownership.is_ally()
		if a_ownership.is_player_owned() or a_ownership.is_ally():
			return b_ownership.is_enemy()
		return false

	if a.is_in_group("enemy") or a.is_in_group("enemy_unit"):
		return b.is_in_group("player") or b.is_in_group("ally")

	if a.is_in_group("player") or a.is_in_group("ally"):
		return b.is_in_group("enemy") or b.is_in_group("enemy_unit")

	return false

func _get_ownership_component(node: Node) -> UnitOwnershipComponent:
	if node == null:
		return null

	return node.get_node_or_null("UnitOwnershipComponent") as UnitOwnershipComponent

func _get_owner_nation(node: Node):
	var ownership = _get_ownership_component(node)
	return ownership.owner_nation if ownership != null else null

func _get_owner_key(node: Node) -> String:
	var ownership = _get_ownership_component(node)
	if ownership != null:
		if not ownership.owner_id.is_empty():
			return ownership.owner_id
		if ownership.owner_nation != null:
			return str(ownership.owner_nation.get("nation_id"))

	return "unknown"

func _get_node_display_name(node: Node) -> String:
	if node == null:
		return "Unknown"

	var unit_data = _get_property_or_null(node, "unit_data")
	if unit_data != null:
		var display_name = str(_get_property_or_default(unit_data, "display_name", ""))
		if not display_name.is_empty():
			return display_name

	return node.name

func _get_tile_size() -> float:
	if grid_manager != null:
		return float(grid_manager.get("tile_size"))

	return 64.0

func _print_harvest(text: String):
	last_debug_action = text
	if debug_print_harvesting:
		print("ResourceNode: ", text)

func _get_property_or_null(object: Object, property_name: String):
	if object == null:
		return null

	for property in object.get_property_list():
		if str(property.get("name")) == property_name:
			return object.get(property_name)

	return null

func _get_property_or_default(object: Object, property_name: String, default_value):
	var value = _get_property_or_null(object, property_name)
	return default_value if value == null else value
