extends Control
class_name BuildingMenu

@onready var buttons_grid: GridContainer = $VBox/ScrollContainer/ButtonsGrid
@onready var category_buttons: HBoxContainer = $VBox/CategoryButtons

var placement_manager: PlacementManager
var current_category: BuildingData.BuildMenuCategory = BuildingData.BuildMenuCategory.MILITARY

func _ready():
	placement_manager = get_tree().get_first_node_in_group("placement_manager")
	if placement_manager != null:
		_setup_category_buttons()
		_setup_menu()

func _setup_category_buttons():
	var buttons = category_buttons.get_children()
	for i in range(buttons.size()):
		var btn = buttons[i] as Button
		btn.pressed.connect(_on_category_button_pressed.bind(i))

func _on_category_button_pressed(idx: int):
	# Update toggles
	var buttons = category_buttons.get_children()
	for i in range(buttons.size()):
		buttons[i].button_pressed = (i == idx)
	
	match idx:
		0: current_category = BuildingData.BuildMenuCategory.MILITARY
		1: current_category = BuildingData.BuildMenuCategory.DEFENSE
		2: current_category = BuildingData.BuildMenuCategory.ECONOMY
		3: current_category = BuildingData.BuildMenuCategory.INFRASTRUCTURE
		4: current_category = BuildingData.BuildMenuCategory.SPECIAL
		
	_setup_menu()

func _setup_menu():
	# Clear old buttons
	for child in buttons_grid.get_children():
		child.queue_free()
		
	# Important: Use the building_options from PlacementManager
	# It already merges nation-specific buildings with core infrastructure (Capitals, Roads, etc.)
	var buildings = []
	if placement_manager.get("building_options") != null:
		buildings = placement_manager.get("building_options")
	else:
		# Fallback to nation directly if options list is missing
		var nation = placement_manager.call("get_selected_nation")
		if nation != null and nation.has_method("get_all_buildings"):
			buildings = nation.call("get_all_buildings")
	
	for building_data in buildings:
		if building_data == null: continue
		
		if _get_building_category(building_data) != current_category:
			continue
			
		var btn = Button.new()
		btn.text = building_data.display_name
		
		var cost = EconomyTypes.get_cost_for_building_data(building_data)
		btn.tooltip_text = "Cost: %s" % EconomyTypes.format_cost(cost)
		btn.pressed.connect(func(): _on_building_selected(building_data))
		buttons_grid.add_child(btn)

func _get_building_category(data: Resource) -> BuildingData.BuildMenuCategory:
	# 1. Check for manual override FIRST if it's NOT Military (the default)
	# This allows users to manually move things to Special or Infra.
	if data.get("build_menu_category") != null:
		var manual_cat = data.get("build_menu_category")
		if manual_cat != BuildingData.BuildMenuCategory.MILITARY:
			return manual_cat

	# 2. Check for Infrastructure (Roads, Capitals, Outposts)
	var kind = EconomyTypes.get_building_kind_for_data(data)
	if kind == EconomyTypes.BuildingKind.CAPITAL or \
	   kind == EconomyTypes.BuildingKind.ROAD or \
	   kind == EconomyTypes.BuildingKind.OUTPOST:
		return BuildingData.BuildMenuCategory.INFRASTRUCTURE
		
	# 3. Check for Defense
	if bool(data.get("is_defense_building")) or \
	   kind == EconomyTypes.BuildingKind.WATCH_TOWER or \
	   kind == EconomyTypes.BuildingKind.WALL or \
	   kind == EconomyTypes.BuildingKind.GATE:
		return BuildingData.BuildMenuCategory.DEFENSE
		
	# 4. Check for Economy
	if bool(data.get("is_resource_building")) or \
	   kind == EconomyTypes.BuildingKind.HOUSE or \
	   kind == EconomyTypes.BuildingKind.TRADING_HALL or \
	   kind == EconomyTypes.BuildingKind.RESOURCE_CAMP:
		return BuildingData.BuildMenuCategory.ECONOMY
		
	# 5. Check for Military (Production)
	if bool(data.get("is_production_building")) or \
	   kind == EconomyTypes.BuildingKind.BARRACKS or \
	   kind == EconomyTypes.BuildingKind.STABLES or \
	   kind == EconomyTypes.BuildingKind.HANGAR or \
	   kind == EconomyTypes.BuildingKind.WORKSHOP or \
	   kind == EconomyTypes.BuildingKind.ALTAR:
		return BuildingData.BuildMenuCategory.MILITARY

	return BuildingData.BuildMenuCategory.MILITARY

func _on_building_selected(building_data: Resource):
	if placement_manager == null: return
	
	# Set PlacementManager to building mode
	if placement_manager.has_method("set_placement_mode"):
		placement_manager.call("set_placement_mode", PlacementManager.PlacementMode.BUILDINGS)
	else:
		placement_manager.set("placement_mode", PlacementManager.PlacementMode.BUILDINGS)
		
	# Ensure category is set to ALL so our index search matches the internal options list
	if placement_manager.has_method("set_building_category"):
		placement_manager.call("set_building_category", PlacementManager.BuildingCategory.ALL)
	else:
		placement_manager.set("selected_building_category", PlacementManager.BuildingCategory.ALL)
		
	placement_manager.set("placement_enabled", true)
	
	# Force refresh building options if they might have changed
	if placement_manager.has_method("_refresh_options_from_selected_nation"):
		placement_manager.call("_refresh_options_from_selected_nation")
	
	# Find the index of this building in the placement manager's current options
	var options = placement_manager.get("building_options")
	var idx = options.find(building_data)
	
	if idx != -1:
		if placement_manager.has_method("select_index"):
			placement_manager.call("select_index", idx)
		else:
			placement_manager.set("selected_index", idx)
			placement_manager.call("_update_status_label")
		
		# Feedback
		var gameplay_ui = get_tree().get_first_node_in_group("gameplay_ui")
		if gameplay_ui != null and gameplay_ui.has_method("show_notification"):
			gameplay_ui.call("show_notification", "Placement Armed: " + building_data.display_name)
