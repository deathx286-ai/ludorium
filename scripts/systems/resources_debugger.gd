extends Node
class_name ResourcesDebugger

signal resources_changed(snapshot: Dictionary)
signal resource_changed(resource_type: int, amount: int)

@export var debugger_enabled: bool = true
@export var player_manager: Node
@export var resource_manager: Node
@export var selected_nation: Resource
@export var resource_scan_root: Node
@export var status_label: Label
@export var debug_grant_amount: int = 10
@export var selected_resource_type: int = BuildingData.ResourceType.GOLD
@export var include_unowned_resource_buildings: bool = false
@export var include_ally_resource_buildings: bool = false
@export var refresh_interval_seconds: float = 0.5
@export var debug_active: bool = false

@export_group("Starting Resources")
@export var starting_wood: int = 0
@export var starting_food: int = 0
@export var starting_stone: int = 0
@export var starting_metal: int = 0

var level: int = 1
var current_xp: int = 0
var xp_needed: int = 0
var xp_percent: float = 0.0

var wood: int = 0
var food: int = 0
var gold: int = 0
var stone: int = 0
var metal: int = 0

var income_wood_per_second: float = 0.0
var income_food_per_second: float = 0.0
var income_gold_per_second: float = 0.0
var income_stone_per_second: float = 0.0
var income_metal_per_second: float = 0.0

var resource_building_counts: Dictionary = {}
var _refresh_timer: float = 0.0
var _last_snapshot: Dictionary = {}

func _ready():
	if resource_manager == null:
		resource_manager = get_tree().get_first_node_in_group("resource_manager")

	if selected_nation == null and resource_manager != null:
		var manager_nations = resource_manager.get("known_nations")
		if manager_nations is Array and not manager_nations.is_empty():
			selected_nation = manager_nations[0]

	wood = starting_wood
	food = starting_food
	stone = starting_stone
	metal = starting_metal

	if resource_scan_root == null:
		resource_scan_root = get_tree().current_scene

	_connect_player_manager()
	refresh_values()

func _process(delta: float):
	if not debugger_enabled and _last_snapshot.is_empty():
		return

	_refresh_timer -= delta

	if _refresh_timer > 0.0:
		return

	_refresh_timer = maxf(refresh_interval_seconds, 0.1)
	refresh_values()

func refresh_values():
	_sync_player_values()
	_refresh_income_values()
	_update_status_label()
	_emit_resources_changed_if_needed()

func get_hud_resource_values() -> Dictionary:
	return {
		"level": level,
		"current_xp": current_xp,
		"xp_needed": xp_needed,
		"xp_percent": xp_percent,
		"amounts": get_resource_amounts(),
		"income_per_second": get_income_per_second_by_resource(),
		"resource_building_counts": resource_building_counts.duplicate()
	}

func get_resource_amounts() -> Dictionary:
	return {
		"wood": wood,
		"food": food,
		"gold": gold,
		"stone": stone,
		"metal": metal
	}

func get_income_per_second_by_resource() -> Dictionary:
	return {
		"wood": income_wood_per_second,
		"food": income_food_per_second,
		"gold": income_gold_per_second,
		"stone": income_stone_per_second,
		"metal": income_metal_per_second
	}

func get_resource_amount(resource_type: int) -> int:
	match resource_type:
		BuildingData.ResourceType.WOOD:
			return wood
		BuildingData.ResourceType.FOOD:
			return food
		BuildingData.ResourceType.GOLD:
			return gold
		BuildingData.ResourceType.STONE:
			return stone
		BuildingData.ResourceType.METAL:
			return metal
		_:
			return 0

func set_resource_amount(resource_type: int, amount: int):
	if resource_manager != null and resource_manager.has_method("set_resource"):
		resource_manager.call("set_resource", selected_nation, resource_type, amount)
		refresh_values()
		return

	var clamped_amount = maxi(amount, 0)

	match resource_type:
		BuildingData.ResourceType.WOOD:
			wood = clamped_amount
		BuildingData.ResourceType.FOOD:
			food = clamped_amount
		BuildingData.ResourceType.GOLD:
			gold = clamped_amount
		BuildingData.ResourceType.STONE:
			stone = clamped_amount
		BuildingData.ResourceType.METAL:
			metal = clamped_amount
		_:
			return

	emit_signal("resource_changed", resource_type, clamped_amount)
	_emit_resources_changed_if_needed()
	_update_status_label()

func add_resource(resource_type: int, amount: int):
	if amount == 0:
		return

	if resource_manager != null and resource_manager.has_method("add_resource"):
		resource_manager.call("add_resource", selected_nation, resource_type, amount)
		refresh_values()
		return

	if resource_type == BuildingData.ResourceType.GOLD and player_manager != null and player_manager.has_method("gain_gold"):
		player_manager.gain_gold(amount)
		return

	set_resource_amount(resource_type, get_resource_amount(resource_type) + amount)

func spend_resource(resource_type: int, amount: int) -> bool:
	if amount <= 0:
		return true

	if resource_manager != null and resource_manager.has_method("spend_resources"):
		var cost := {resource_type: amount}
		var spent = bool(resource_manager.call("spend_resources", selected_nation, cost))
		refresh_values()
		return spent

	if resource_type == BuildingData.ResourceType.GOLD and player_manager != null and player_manager.has_method("spend_gold"):
		return player_manager.spend_gold(amount)

	if get_resource_amount(resource_type) < amount:
		return false

	set_resource_amount(resource_type, get_resource_amount(resource_type) - amount)
	return true

func can_afford(resource_type: int, amount: int) -> bool:
	if resource_manager != null and resource_manager.has_method("can_afford"):
		return bool(resource_manager.call("can_afford", selected_nation, {resource_type: amount}))

	return amount <= 0 or get_resource_amount(resource_type) >= amount

func add_all_resources(amount: int):
	if resource_manager != null and resource_manager.has_method("add_all_resources"):
		resource_manager.call("add_all_resources", selected_nation, amount)
		refresh_values()
		return

	for resource_type in _get_debug_resource_types():
		add_resource(resource_type, amount)

func can_afford_cost(cost: Dictionary) -> bool:
	if resource_manager != null and resource_manager.has_method("can_afford"):
		return bool(resource_manager.call("can_afford", selected_nation, cost))

	for resource_type in EconomyTypes.RESOURCE_TYPES:
		if get_resource_amount(resource_type) < int(cost.get(resource_type, 0)):
			return false

	return true

func spend_resources(cost: Dictionary) -> bool:
	if resource_manager != null and resource_manager.has_method("spend_resources"):
		var spent = bool(resource_manager.call("spend_resources", selected_nation, cost))
		refresh_values()
		return spent

	if not can_afford_cost(cost):
		return false

	for resource_type in EconomyTypes.RESOURCE_TYPES:
		spend_resource(resource_type, int(cost.get(resource_type, 0)))

	return true

func get_resource_name(resource_type: int) -> String:
	match resource_type:
		BuildingData.ResourceType.WOOD:
			return "Wood"
		BuildingData.ResourceType.FOOD:
			return "Food"
		BuildingData.ResourceType.GOLD:
			return "Gold"
		BuildingData.ResourceType.STONE:
			return "Stone"
		BuildingData.ResourceType.METAL:
			return "Metal"
		_:
			return "None"

func _connect_player_manager():
	if player_manager == null:
		player_manager = get_tree().get_first_node_in_group("player_manager")

	if player_manager == null:
		return

	var gold_changed_callable = Callable(self, "_on_gold_changed")
	var xp_changed_callable = Callable(self, "_on_xp_changed")
	var level_changed_callable = Callable(self, "_on_level_changed")

	if player_manager.has_signal("gold_changed") and not player_manager.is_connected("gold_changed", gold_changed_callable):
		player_manager.connect("gold_changed", gold_changed_callable)

	if player_manager.has_signal("xp_changed") and not player_manager.is_connected("xp_changed", xp_changed_callable):
		player_manager.connect("xp_changed", xp_changed_callable)

	if player_manager.has_signal("level_changed") and not player_manager.is_connected("level_changed", level_changed_callable):
		player_manager.connect("level_changed", level_changed_callable)

func _sync_player_values():
	if player_manager == null:
		pass
	else:
		level = int(player_manager.get("level"))
		current_xp = int(player_manager.get("current_xp"))
		xp_needed = int(player_manager.get("xp_needed"))
		gold = int(player_manager.get("gold"))

	if resource_manager != null and resource_manager.has_method("get_resource_amounts"):
		var amounts: Dictionary = resource_manager.call("get_resource_amounts", selected_nation)
		wood = int(amounts.get(BuildingData.ResourceType.WOOD, wood))
		food = int(amounts.get(BuildingData.ResourceType.FOOD, food))
		gold = int(amounts.get(BuildingData.ResourceType.GOLD, gold))
		stone = int(amounts.get(BuildingData.ResourceType.STONE, stone))
		metal = int(amounts.get(BuildingData.ResourceType.METAL, metal))

	xp_percent = float(current_xp) / float(xp_needed) if xp_needed > 0 else 0.0

func _refresh_income_values():
	var income_by_resource = _get_empty_resource_float_dictionary()
	resource_building_counts = _get_empty_resource_count_dictionary()

	if resource_scan_root == null:
		return

	for node in get_tree().get_nodes_in_group("resource_building"):
		if is_instance_valid(node) and node is Node and _is_node_inside_scan_root(node):
			_collect_income_from_building(node, income_by_resource)

	income_wood_per_second = income_by_resource[BuildingData.ResourceType.WOOD]
	income_food_per_second = income_by_resource[BuildingData.ResourceType.FOOD]
	income_gold_per_second = income_by_resource[BuildingData.ResourceType.GOLD]
	income_stone_per_second = income_by_resource[BuildingData.ResourceType.STONE]
	income_metal_per_second = income_by_resource[BuildingData.ResourceType.METAL]

func _collect_income_from_building(node: Node, income_by_resource: Dictionary):
	var building_data = node.get("building_data") as Resource

	if building_data == null or not bool(building_data.get("is_resource_building")):
		return

	if not _should_count_building(node):
		return

	var resource_type = int(building_data.get("resource_type"))

	if resource_type == BuildingData.ResourceType.NONE:
		return

	var tick_seconds = maxf(float(building_data.get("resource_tick_seconds")), 0.001)
	var amount_per_tick = int(building_data.get("resource_amount_per_tick"))
	income_by_resource[resource_type] += float(amount_per_tick) / tick_seconds
	resource_building_counts[resource_type] += 1

func _should_count_building(node: Node) -> bool:
	var ownership = node.get_node_or_null("UnitOwnershipComponent") as UnitOwnershipComponent

	if ownership == null:
		return include_unowned_resource_buildings

	return ownership.is_player_owned() or (include_ally_resource_buildings and ownership.is_ally())

func _is_node_inside_scan_root(node: Node) -> bool:
	if resource_scan_root == null:
		return true

	return node == resource_scan_root or resource_scan_root.is_ancestor_of(node)

func set_debug_active(active: bool):
	debug_active = active
	_update_status_label()

func get_debug_title() -> String:
	return "Resources"

func handle_debug_input(event: InputEventKey) -> bool:
	if event.keycode == KEY_Q or event.keycode == KEY_BRACKETLEFT:
		_cycle_selected_resource(-1)
		return true
	elif event.keycode == KEY_E or event.keycode == KEY_BRACKETRIGHT:
		_cycle_selected_resource()
		return true
	elif event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
		if event.shift_pressed:
			spend_resource(selected_resource_type, debug_grant_amount)
		else:
			add_resource(selected_resource_type, debug_grant_amount)
		return true

	return false

func _cycle_selected_resource(direction: int = 1):
	var resource_types = _get_debug_resource_types()
	var current_index = resource_types.find(selected_resource_type)

	if current_index == -1:
		selected_resource_type = resource_types[0]
	else:
		selected_resource_type = resource_types[wrapi(current_index + direction, 0, resource_types.size())]

	_update_status_label()

func _update_status_label():
	if status_label == null:
		return

	status_label.visible = debug_active

	if not debug_active:
		return

	status_label.text = "DEBUG [Resources] | %s" % get_debug_text()

func get_debug_text() -> String:
	return "L%s XP %s/%s | %s | Income/s %s | Nation %s | Selected %s | Q/E resource, Space +%s, Shift+Space -%s" % [
		level,
		current_xp,
		xp_needed,
		_format_amounts(),
		_format_income(),
		_get_display_name(selected_nation),
		get_resource_name(selected_resource_type),
		debug_grant_amount,
		debug_grant_amount
	]

func get_current_debug_summary() -> String:
	return "Resources | %s | Wood: %s | Gold: %s | Stone: %s | Metal: %s" % [
		_get_display_name(selected_nation),
		wood,
		gold,
		stone,
		metal
	]

func get_debug_state() -> Dictionary:
	return {
		"nation": _get_display_name(selected_nation),
		"amounts": get_resource_amounts(),
		"income_per_second": get_income_per_second_by_resource(),
		"selected_resource_type": selected_resource_type,
		"selected_resource_name": get_resource_name(selected_resource_type),
		"debug_grant_amount": debug_grant_amount
	}

func get_debug_shortcuts() -> Array:
	return [
		{"keys": "Q/E", "description": "Cycle selected resource"},
		{"keys": "Space", "description": "Grant selected resource"},
		{"keys": "Shift+Space", "description": "Spend selected resource"}
	]

func _format_amounts() -> String:
	return "Wood %s, Food %s, Gold %s, Stone %s, Metal %s" % [
		wood,
		food,
		gold,
		stone,
		metal
	]

func _format_income() -> String:
	return "W %.1f, F %.1f, G %.1f, S %.1f, M %.1f" % [
		income_wood_per_second,
		income_food_per_second,
		income_gold_per_second,
		income_stone_per_second,
		income_metal_per_second
	]

func _get_empty_resource_float_dictionary() -> Dictionary:
	return {
		BuildingData.ResourceType.WOOD: 0.0,
		BuildingData.ResourceType.FOOD: 0.0,
		BuildingData.ResourceType.GOLD: 0.0,
		BuildingData.ResourceType.STONE: 0.0,
		BuildingData.ResourceType.METAL: 0.0
	}

func _get_empty_resource_count_dictionary() -> Dictionary:
	return {
		BuildingData.ResourceType.WOOD: 0,
		BuildingData.ResourceType.FOOD: 0,
		BuildingData.ResourceType.GOLD: 0,
		BuildingData.ResourceType.STONE: 0,
		BuildingData.ResourceType.METAL: 0
	}

func _get_debug_resource_types() -> Array[int]:
	return [
		BuildingData.ResourceType.WOOD,
		BuildingData.ResourceType.FOOD,
		BuildingData.ResourceType.GOLD,
		BuildingData.ResourceType.STONE,
		BuildingData.ResourceType.METAL
	]

func _get_display_name(resource: Resource) -> String:
	if resource == null:
		return "None"

	var display_name = str(resource.get("display_name"))
	if not display_name.is_empty():
		return display_name

	var nation_id = str(resource.get("nation_id"))
	if not nation_id.is_empty():
		return nation_id

	return resource.resource_path.get_file()

func _emit_resources_changed_if_needed():
	var snapshot = get_hud_resource_values()

	if snapshot == _last_snapshot:
		return

	_last_snapshot = snapshot.duplicate(true)
	emit_signal("resources_changed", snapshot)

func _on_gold_changed(new_gold: int):
	gold = new_gold
	refresh_values()

func _on_xp_changed(new_current_xp: int, new_xp_needed: int):
	current_xp = new_current_xp
	xp_needed = new_xp_needed
	xp_percent = float(current_xp) / float(xp_needed) if xp_needed > 0 else 0.0
	refresh_values()

func _on_level_changed(new_level: int):
	level = new_level
	refresh_values()
