extends Control
class_name SelectionPanel

@onready var name_label: Label = $VBox/NameLabel
@onready var health_label: Label = $VBox/HealthLabel
@onready var owner_label: Label = $VBox/OwnerLabel
@onready var construction_label: Label = $VBox/ConstructionLabel
@onready var stats_label: Label = $VBox/StatsLabel

@onready var production_container: Control = $VBox/ProductionContainer
@onready var production_progress: ProgressBar = $VBox/ProductionContainer/ProgressBar
@onready var production_queue_label: Label = $VBox/ProductionContainer/QueueLabel
@onready var production_buttons_grid: GridContainer = $VBox/ProductionContainer/ButtonsGrid

var current_target: Node2D = null

func _ready():
	visible = false

func _process(_delta):
	if visible and is_instance_valid(current_target):
		_update_dynamic_info()

func set_target(target: Node2D):
	current_target = target
	if target == null:
		visible = false
		return
	
	visible = true
	_update_static_info()
	_update_dynamic_info()
	_update_production_controls()

func _update_static_info():
	if not is_instance_valid(current_target): return
	
	var display_name = current_target.name
	var owner_name = "Neutral"
	
	if "unit_data" in current_target and current_target.unit_data != null:
		display_name = current_target.unit_data.display_name
	elif "building_data" in current_target and current_target.building_data != null:
		display_name = current_target.building_data.display_name
		
	var ownership = current_target.get_node_or_null("UnitOwnershipComponent")
	if ownership != null:
		var nation = ownership.get("owner_nation")
		if nation != null:
			owner_name = nation.get("display_name")
			
	name_label.text = display_name
	owner_label.text = "Owner: %s" % owner_name
	
	# Basic stats
	var stats = ""
	if "attack_damage" in current_target:
		stats += "Atk: %d  " % current_target.get("attack_damage")
	if "attack_range_tiles" in current_target:
		stats += "Rng: %d  " % current_target.get("attack_range_tiles")
	if "move_speed" in current_target:
		stats += "Spd: %d" % current_target.get("move_speed")
	stats_label.text = stats

func _update_dynamic_info():
	if not is_instance_valid(current_target): return
	
	# Health
	var hp = current_target.get("current_health")
	var max_hp = current_target.get("max_health")
	if hp != null and max_hp != null:
		health_label.text = "HP: %d / %d" % [hp, max_hp]
		
	# Construction
	var construction = current_target.get_node_or_null("ConstructionComponent")
	if construction != null and construction.get("is_under_construction"):
		construction_label.visible = true
		construction_label.text = "Under Construction: %d%%" % [construction.call("get_progress") * 100]
	else:
		construction_label.visible = false
		
	_update_production_progress()

func _update_production_controls():
	# Clear old buttons
	for child in production_buttons_grid.get_children():
		child.queue_free()
		
	var production = current_target.get_node_or_null("ProductionComponent")
	if production == null:
		production_container.visible = false
		return
		
	production_container.visible = true
	
	# Get available units to train
	var nation = _get_player_nation()
	if nation == null: return
	
	var building_data = current_target.get("building_data")
	var building_kind = EconomyTypes.get_building_kind_for_data(building_data)
	
	var all_units = []
	if nation.has_method("get_all_roster_units"):
		all_units = nation.call("get_all_roster_units")
	
	# Filter units based on building type
	var filtered_units = []
	for unit in all_units:
		if _building_can_train_unit(building_kind, unit):
			filtered_units.append(unit)
	
	# If no specific mapping found, fallback to showing all units if building is production-enabled
	if filtered_units.is_empty():
		filtered_units = all_units
	
	for unit in filtered_units:
		var btn = Button.new()
		btn.text = unit.display_name
		
		# Get cost
		var cost = {}
		if "resource_cost" in unit and not unit.resource_cost.is_empty():
			cost = unit.resource_cost
		else:
			if unit.get("wood_cost") > 0: cost[BuildingData.ResourceType.WOOD] = unit.wood_cost
			if unit.get("food_cost") > 0: cost[BuildingData.ResourceType.FOOD] = unit.food_cost
			if unit.get("gold_cost") > 0: cost[BuildingData.ResourceType.GOLD] = unit.gold_cost
			if unit.get("stone_cost") > 0: cost[BuildingData.ResourceType.STONE] = unit.stone_cost
			if unit.get("metal_cost") > 0: cost[BuildingData.ResourceType.METAL] = unit.metal_cost
			
		btn.tooltip_text = "Cost: %s" % EconomyTypes.format_cost(cost)
		btn.pressed.connect(func(): production.call("add_to_queue", unit))
		production_buttons_grid.add_child(btn)

func _building_can_train_unit(kind: int, unit_data: Resource) -> bool:
	var domain = int(unit_data.get("unit_domain"))
	var tags = unit_data.get("unit_tags")
	var is_worker = bool(unit_data.get("can_harvest")) or (tags is Array and tags.has("worker"))
	
	match kind:
		EconomyTypes.BuildingKind.CAPITAL:
			return is_worker
		EconomyTypes.BuildingKind.BARRACKS:
			return domain == UnitClassification.UnitDomain.INFANTRY or domain == UnitClassification.UnitDomain.RANGED
		EconomyTypes.BuildingKind.STABLES:
			return domain == UnitClassification.UnitDomain.CAVALRY
		EconomyTypes.BuildingKind.HANGAR:
			return domain == UnitClassification.UnitDomain.AIR
		EconomyTypes.BuildingKind.WORKSHOP:
			return domain == UnitClassification.UnitDomain.SIEGE
		EconomyTypes.BuildingKind.ALTAR:
			return domain == UnitClassification.UnitDomain.CHAMPION
		_:
			return false

func _get_player_nation() -> Resource:
	var diplomacy = get_tree().get_first_node_in_group("run_diplomacy_manager")
	if diplomacy != null:
		return diplomacy.get("selected_player_nation")
	return null

func _format_cost(unit_data: Resource) -> String:
	var parts = []
	if unit_data.get("wood_cost") > 0: parts.append("Wood: %d" % unit_data.wood_cost)
	if unit_data.get("food_cost") > 0: parts.append("Food: %d" % unit_data.food_cost)
	if unit_data.get("gold_cost") > 0: parts.append("Gold: %d" % unit_data.gold_cost)
	return ", ".join(parts) if not parts.is_empty() else "Free"

func _update_production_progress():
	var production = current_target.get_node_or_null("ProductionComponent")
	if production != null:
		production_progress.value = production.call("get_progress") * 100
		production_queue_label.text = production.call("get_debug_summary")
