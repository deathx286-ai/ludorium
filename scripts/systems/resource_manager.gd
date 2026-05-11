extends Node
class_name ResourceManager

signal resource_changed(nation_key: String, resource_type: int, amount: int, delta: int)
signal resources_changed(nation_key: String, amounts: Dictionary)

@export var debug_print_changes: bool = true
@export var known_nations: Array[Resource] = []

@export_group("Default Starting Resources")
@export var starting_wood: int = 300
@export var starting_food: int = 300
@export var starting_gold: int = 200
@export var starting_stone: int = 250
@export var starting_metal: int = 100

var resources_by_nation: Dictionary = {}
var last_change_text: String = ""

func _ready():
	add_to_group("resource_manager")

	for nation in known_nations:
		ensure_nation(nation)

func ensure_nation(nation) -> String:
	var nation_key = get_nation_key(nation)
	if nation_key.is_empty():
		return ""

	if not resources_by_nation.has(nation_key):
		resources_by_nation[nation_key] = _get_default_resource_amounts()

	return nation_key

func get_resource(nation, resource_type: int) -> int:
	var nation_key = ensure_nation(nation)
	if nation_key.is_empty():
		return 0

	return int(resources_by_nation[nation_key].get(resource_type, 0))

func set_resource(nation, resource_type: int, amount: int):
	if not EconomyTypes.RESOURCE_TYPES.has(resource_type):
		return

	var nation_key = ensure_nation(nation)
	if nation_key.is_empty():
		return

	var previous_amount = int(resources_by_nation[nation_key].get(resource_type, 0))
	var new_amount = maxi(amount, 0)
	resources_by_nation[nation_key][resource_type] = new_amount
	_emit_change(nation_key, resource_type, new_amount, new_amount - previous_amount)

func add_resource(nation, resource_type: int, amount: int):
	if amount == 0 or not EconomyTypes.RESOURCE_TYPES.has(resource_type):
		return

	set_resource(nation, resource_type, get_resource(nation, resource_type) + amount)

func add_all_resources(nation, amount: int):
	for resource_type in EconomyTypes.RESOURCE_TYPES:
		add_resource(nation, resource_type, amount)

func can_afford(nation, cost: Dictionary) -> bool:
	var normalized_cost = EconomyTypes.normalize_cost(cost)

	for resource_type in EconomyTypes.RESOURCE_TYPES:
		if get_resource(nation, resource_type) < int(normalized_cost.get(resource_type, 0)):
			return false

	return true

func spend_resources(nation, cost: Dictionary) -> bool:
	var normalized_cost = EconomyTypes.normalize_cost(cost)
	if not can_afford(nation, normalized_cost):
		return false

	for resource_type in EconomyTypes.RESOURCE_TYPES:
		var amount = int(normalized_cost.get(resource_type, 0))
		if amount > 0:
			add_resource(nation, resource_type, -amount)

	return true

func get_resource_amounts(nation) -> Dictionary:
	var nation_key = ensure_nation(nation)
	if nation_key.is_empty():
		return _get_empty_resource_amounts()

	return resources_by_nation[nation_key].duplicate()

func get_resource_amounts_by_key(nation_key: String) -> Dictionary:
	if nation_key.is_empty():
		return _get_empty_resource_amounts()

	if not resources_by_nation.has(nation_key):
		resources_by_nation[nation_key] = _get_default_resource_amounts()

	return resources_by_nation[nation_key].duplicate()

func get_debug_state(nation = null) -> Dictionary:
	var nation_key = get_nation_key(nation)

	if nation_key.is_empty() and not known_nations.is_empty():
		nation_key = ensure_nation(known_nations[0])

	return {
		"nation_key": nation_key,
		"amounts": get_resource_amounts_by_key(nation_key),
		"last_change": last_change_text,
		"known_nations": known_nations.duplicate()
	}

func get_current_debug_summary(nation = null) -> String:
	var state = get_debug_state(nation)
	var amounts = state.get("amounts", {})
	return "%s | Wood: %s | Food: %s | Gold: %s | Stone: %s | Metal: %s" % [
		str(state.get("nation_key", "None")),
		int(amounts.get(BuildingData.ResourceType.WOOD, 0)),
		int(amounts.get(BuildingData.ResourceType.FOOD, 0)),
		int(amounts.get(BuildingData.ResourceType.GOLD, 0)),
		int(amounts.get(BuildingData.ResourceType.STONE, 0)),
		int(amounts.get(BuildingData.ResourceType.METAL, 0))
	]

func get_nation_key(nation) -> String:
	if nation == null:
		return ""

	if nation is Resource:
		var nation_id = str(nation.get("nation_id"))
		if not nation_id.is_empty():
			return nation_id

	if nation is String:
		return str(nation)

	return str(nation)

func _emit_change(nation_key: String, resource_type: int, amount: int, delta: int):
	last_change_text = "%s %s %+d => %d" % [
		nation_key,
		EconomyTypes.get_resource_name(resource_type),
		delta,
		amount
	]

	if debug_print_changes and delta != 0:
		print("ResourceManager: ", last_change_text)

	resource_changed.emit(nation_key, resource_type, amount, delta)
	resources_changed.emit(nation_key, resources_by_nation[nation_key].duplicate())

func _get_default_resource_amounts() -> Dictionary:
	return {
		BuildingData.ResourceType.WOOD: maxi(starting_wood, 0),
		BuildingData.ResourceType.FOOD: maxi(starting_food, 0),
		BuildingData.ResourceType.GOLD: maxi(starting_gold, 0),
		BuildingData.ResourceType.STONE: maxi(starting_stone, 0),
		BuildingData.ResourceType.METAL: maxi(starting_metal, 0)
	}

func _get_empty_resource_amounts() -> Dictionary:
	return {
		BuildingData.ResourceType.WOOD: 0,
		BuildingData.ResourceType.FOOD: 0,
		BuildingData.ResourceType.GOLD: 0,
		BuildingData.ResourceType.STONE: 0,
		BuildingData.ResourceType.METAL: 0
	}
