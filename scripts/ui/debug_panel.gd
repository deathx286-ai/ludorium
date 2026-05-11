extends CanvasLayer
class_name DebugPanel

@export var debug_enabled: bool = true
@export var compact_mode: bool = false
@export var refresh_interval: float = 0.35

@export var debug_manager: Node
@export var diplomacy_debugger: Node
@export var resources_debugger: Node
@export var combat_debugger: Node
@export var placement_manager: Node
@export var economy_debug_manager: Node
@export var road_supply_manager: Node
@export var resource_manager: Node
@export var player_selection_manager: Node

var root_control: Control
var panel: PanelContainer
var title_label: Label
var compact_label: Label
var collapse_button: Button
var tabs: TabContainer
var tab_vboxes: Dictionary = {}
var _refresh_timer: float = 0.0

func _ready():
	_discover_managers()
	_build_panel()
	set_debug_visible(debug_enabled)
	_refresh_all_tabs()

func _process(delta: float):
	if not visible or not debug_enabled:
		return

	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return

	_refresh_timer = refresh_interval
	_refresh_all_tabs()

func set_debug_visible(is_visible: bool):
	debug_enabled = is_visible
	visible = is_visible

func set_compact_mode(is_compact: bool):
	compact_mode = is_compact
	if tabs != null:
		tabs.visible = not compact_mode
	if compact_label != null:
		compact_label.visible = compact_mode
	if collapse_button != null:
		collapse_button.text = "Expand" if compact_mode else "Collapse"

func _build_panel():
	root_control = Control.new()
	root_control.name = "Root"
	root_control.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root_control)

	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(520, 360)
	panel.offset_left = 12.0
	panel.offset_top = 44.0
	panel.offset_right = 560.0
	panel.offset_bottom = 620.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root_control.add_child(panel)

	var outer_vbox = VBoxContainer.new()
	outer_vbox.name = "VBox"
	outer_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(outer_vbox)

	var header = HBoxContainer.new()
	header.name = "Header"
	outer_vbox.add_child(header)

	title_label = Label.new()
	title_label.text = "Debug Panel"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	collapse_button = Button.new()
	collapse_button.text = "Collapse"
	collapse_button.pressed.connect(func(): set_compact_mode(not compact_mode))
	header.add_child(collapse_button)

	compact_label = Label.new()
	compact_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	compact_label.visible = compact_mode
	outer_vbox.add_child(compact_label)

	tabs = TabContainer.new()
	tabs.name = "Tabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.visible = not compact_mode
	outer_vbox.add_child(tabs)

	for tab_name in ["Overview", "Diplomacy", "Resources", "Combat", "Placement", "Spawning / Testing", "Shortcuts / Help"]:
		_add_tab(tab_name)

func _add_tab(tab_name: String):
	var scroll = ScrollContainer.new()
	scroll.name = tab_name
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	tabs.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.name = "Content"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	tab_vboxes[tab_name] = vbox

func _refresh_all_tabs():
	if tabs == null:
		return

	_discover_managers()
	compact_label.text = _get_compact_summary()

	update_overview_tab()
	update_diplomacy_tab()
	update_resources_tab()
	update_combat_tab()
	update_placement_tab()
	update_spawning_tab()
	update_shortcuts_tab()

func update_overview_tab():
	var vbox = _reset_tab("Overview")
	_add_label(vbox, "Active Debug: %s" % _get_active_debug_title())
	_add_label(vbox, "Selected Nation: %s" % _get_selected_nation_name())
	
	var is_placement = _get_bool(placement_manager, "placement_enabled")
	_add_label(vbox, "Current Mode: %s" % ("PLACEMENT" if is_placement else "GAMEPLAY"))
	
	if is_placement:
		_add_button(vbox, "Exit to Gameplay Mode", func(): _placement_toggle_enabled())
	else:
		_add_button(vbox, "Enter Placement Mode", func(): _placement_toggle_enabled())
	
	_add_label(vbox, "Selected Object: %s" % _get_selected_object_name())
	_add_label(vbox, "Toggles: %s" % _get_toggle_summary())
	_add_label(vbox, "Last Action: %s" % _get_last_action())
	_add_label(vbox, "Warnings: %s" % _get_warning_summary())

func update_diplomacy_tab():
	var vbox = _reset_tab("Diplomacy")

	if diplomacy_debugger == null:
		_add_label(vbox, "Not connected")
		return

	var state = _call_dictionary(diplomacy_debugger, "get_debug_state")
	_add_label(vbox, "Selected Nation: %s" % state.get("selected_player_nation", "Unknown"))
	_add_label(vbox, "Selected Pair: %s" % state.get("selected_pair", "None"))
	_add_label(vbox, "Relationships:\n%s" % state.get("relationship_summary", ""))
	_add_button(vbox, "Cycle Pair", func(): diplomacy_debugger.call("cycle_pair", 1) if diplomacy_debugger.has_method("cycle_pair") else null)
	_add_button(vbox, "Set/Cycle Relationship", func(): diplomacy_debugger.call("cycle_selected_pair_relationship") if diplomacy_debugger.has_method("cycle_selected_pair_relationship") else null)
	_add_button(vbox, "Print Diplomacy State", func(): print(state.get("pairwise_summary", "")))

func update_resources_tab():
	var vbox = _reset_tab("Resources")
	var amounts = _get_resource_amounts()

	_add_label(vbox, "Owner: %s" % _get_selected_nation_name())
	_add_label(vbox, "Wood: %s" % int(amounts.get("wood", 0)))
	_add_label(vbox, "Food: %s" % int(amounts.get("food", 0)))
	_add_label(vbox, "Gold: %s" % int(amounts.get("gold", 0)))
	_add_label(vbox, "Stone: %s" % int(amounts.get("stone", 0)))
	_add_label(vbox, "Metal: %s" % int(amounts.get("metal", 0)))

	var row = _add_row(vbox)
	_add_button(row, "+100 Wood", func(): _debug_add_resource(BuildingData.ResourceType.WOOD, 100))
	_add_button(row, "+100 Food", func(): _debug_add_resource(BuildingData.ResourceType.FOOD, 100))
	_add_button(row, "+100 Gold", func(): _debug_add_resource(BuildingData.ResourceType.GOLD, 100))
	var row_2 = _add_row(vbox)
	_add_button(row_2, "+100 Stone", func(): _debug_add_resource(BuildingData.ResourceType.STONE, 100))
	_add_button(row_2, "+100 Metal", func(): _debug_add_resource(BuildingData.ResourceType.METAL, 100))
	_add_button(row_2, "+500 All", func(): _debug_add_all_resources(500))

	_add_checkbox(vbox, "Free-build mode", _get_bool(placement_manager, "free_build_mode"), func(value): _set_free_build(value))
	_add_checkbox(vbox, "Ignore resource/placement rules", _get_bool(placement_manager, "ignore_placement_rules_mode"), func(value): _set_ignore_rules(value))
	_add_checkbox(vbox, "Show resource node visuals", _get_resource_node_visuals_enabled(), func(value): _set_resource_node_visuals(value))
	_add_checkbox(vbox, "Show resource node contest radius", _get_resource_node_contest_radius_enabled(), func(value): _set_resource_node_contest_radius(value))

	_add_label(vbox, "Closest Resource Node:\n%s" % _format_closest_resource_node())
	_add_label(vbox, "Resource node buttons arm placement. Click an open map cell to place; Esc or right-click cancels.")

	var spawn_row = _add_row(vbox)
	_add_button(spawn_row, "Place Wood Node", func(): _spawn_resource_node(BuildingData.ResourceType.WOOD))
	_add_button(spawn_row, "Place Food Node", func(): _spawn_resource_node(BuildingData.ResourceType.FOOD))
	_add_button(spawn_row, "Place Gold Node", func(): _spawn_resource_node(BuildingData.ResourceType.GOLD))
	var spawn_row_2 = _add_row(vbox)
	_add_button(spawn_row_2, "Place Stone Node", func(): _spawn_resource_node(BuildingData.ResourceType.STONE))
	_add_button(spawn_row_2, "Place Metal Node", func(): _spawn_resource_node(BuildingData.ResourceType.METAL))

func update_combat_tab():
	var vbox = _reset_tab("Combat")

	if combat_debugger == null:
		_add_label(vbox, "Not connected")
	else:
		var state = _call_dictionary(combat_debugger, "get_debug_state")
		_add_label(vbox, "Recent Events:\n%s" % "\n".join(state.get("recent_events", [])))
		_add_button(vbox, "Print Counter Matrix", func(): combat_debugger.call("verify_counter_system") if combat_debugger.has_method("verify_counter_system") else null)

	_add_label(vbox, "Selected Combat Object:\n%s" % _format_selected_combat_object())
	_add_button(vbox, "Spawn Enemy Near Resource Node", func(): economy_debug_manager.call("spawn_enemy_combat_near_closest_resource_node") if economy_debug_manager != null and economy_debug_manager.has_method("spawn_enemy_combat_near_closest_resource_node") else null)
	_add_button(vbox, "Spawn Enemy Combat Unit", func(): economy_debug_manager.call("spawn_enemy_combat_unit_at_mouse") if economy_debug_manager != null and economy_debug_manager.has_method("spawn_enemy_combat_unit_at_mouse") else null)

func update_placement_tab():
	var vbox = _reset_tab("Placement")

	if placement_manager == null:
		_add_label(vbox, "Not connected")
		return

	var state = _call_dictionary(placement_manager, "get_debug_state")
	
	var is_placement = bool(state.get("placement_enabled", true))
	_add_label(vbox, "Current Mode: %s" % ("PLACEMENT" if is_placement else "GAMEPLAY"))
	
	if is_placement:
		_add_button(vbox, "Exit to Gameplay Mode (P)", func(): _placement_toggle_enabled())
	else:
		_add_button(vbox, "Enter Placement Mode (P)", func(): _placement_toggle_enabled())

	_add_label(vbox, "Mode: %s" % state.get("placement_mode", "Unknown"))
	_add_label(vbox, "Category: %s" % state.get("category", "Unknown"))
	_add_label(vbox, "Selected: %s" % state.get("selected_name", "None"))
	_add_label(vbox, "Index: %s" % state.get("selected_index", 0))
	_add_label(vbox, "Owner: %s / %s" % [state.get("selected_nation", "None"), state.get("allegiance_override", "Auto")])
	_add_label(vbox, "Mouse Cell: %s" % state.get("mouse_cell", Vector2i(-1, -1)))
	_add_label(vbox, "Cost: %s" % state.get("cost_text", "Free"))

	_add_label(vbox, "Placement Tabs")
	_add_option_tabs(vbox, "Mode", _placement_get_options("get_mode_tab_options"), "_placement_set_mode")
	_add_option_tabs(vbox, "Category", _placement_get_options("get_category_tab_options"), "_placement_set_category")
	_add_option_tabs(vbox, "Type", _placement_get_options("get_type_tab_options"), "_placement_set_type")
	_add_placement_item_buttons(vbox)

	var owner_row = _add_row(vbox)
	_add_button(owner_row, "Prev Owner", Callable(self, "_placement_cycle_nation").bind(-1))
	_add_button(owner_row, "Next Owner", Callable(self, "_placement_cycle_nation").bind(1))
	_add_button(owner_row, "Cycle Side", Callable(self, "_placement_cycle_side"))
	_add_button(owner_row, "Place At Mouse", Callable(self, "_placement_place_at_mouse"))

	var validation = state.get("last_validation", {})
	_add_label(vbox, "Valid: %s" % ("Yes" if bool(validation.get("valid", false)) else "No"))
	_add_label(vbox, "Failure Reason: %s" % validation.get("reason", "not checked"))

	_add_checkbox(vbox, "Show placement ghost", bool(state.get("show_placement_ghost", true)), func(value): placement_manager.set("show_placement_ghost", value))
	_add_checkbox(vbox, "Show valid placement cells", bool(state.get("show_valid_placement_cells", false)), func(value): placement_manager.set("show_valid_placement_cells", value))
	_add_checkbox(vbox, "Show invalid placement cells", bool(state.get("show_invalid_placement_cells", false)), func(value): placement_manager.set("show_invalid_placement_cells", value))
	_add_checkbox(vbox, "Show supply radius", _get_bool(road_supply_manager, "show_supply_radius"), func(value): _set_if_connected(road_supply_manager, "show_supply_radius", value))
	_add_checkbox(vbox, "Show road network", _get_bool(road_supply_manager, "show_road_network"), func(value): _set_if_connected(road_supply_manager, "show_road_network", value))
	_add_checkbox(vbox, "Show outpost range", _get_bool(road_supply_manager, "show_outpost_range"), func(value): _set_if_connected(road_supply_manager, "show_outpost_range", value))
	_add_checkbox(vbox, "Free-build mode", bool(state.get("free_build_mode", false)), func(value): _set_free_build(value))
	_add_checkbox(vbox, "Ignore-placement-rules mode", bool(state.get("ignore_placement_rules_mode", false)), func(value): _set_ignore_rules(value))

func update_spawning_tab():
	var vbox = _reset_tab("Spawning / Testing")

	if economy_debug_manager == null:
		_add_label(vbox, "EconomyDebugManager not connected")
		return

	_add_label(vbox, "Owner: %s" % _get_selected_nation_name())
	_add_button(vbox, "Cycle Debug Owner", func(): economy_debug_manager.call("cycle_selected_nation", 1))

	var unit_row = _add_row(vbox)
	_add_button(unit_row, "Player General Worker", func(): economy_debug_manager.call("spawn_player_worker_at_mouse"))
	_add_button(unit_row, "Enemy General Worker", func(): economy_debug_manager.call("spawn_enemy_worker_at_mouse"))
	var unit_row_2 = _add_row(vbox)
	_add_button(unit_row_2, "Player Lumberjack", func(): economy_debug_manager.call("spawn_player_lumber_worker_at_mouse"))
	_add_button(unit_row_2, "Player Farmer", func(): economy_debug_manager.call("spawn_player_farm_worker_at_mouse"))
	_add_button(unit_row_2, "Player Miner", func(): economy_debug_manager.call("spawn_player_mine_worker_at_mouse"))
	var unit_row_3 = _add_row(vbox)
	_add_button(unit_row_3, "Enemy Lumberjack", func(): economy_debug_manager.call("spawn_enemy_lumber_worker_at_mouse"))
	_add_button(unit_row_3, "Enemy Farmer", func(): economy_debug_manager.call("spawn_enemy_farm_worker_at_mouse"))
	_add_button(unit_row_3, "Enemy Miner", func(): economy_debug_manager.call("spawn_enemy_mine_worker_at_mouse"))
	var unit_row_4 = _add_row(vbox)
	_add_button(unit_row_4, "Player Combat", func(): economy_debug_manager.call("spawn_player_combat_unit_at_mouse"))
	_add_button(unit_row_4, "Enemy Combat", func(): economy_debug_manager.call("spawn_enemy_combat_unit_at_mouse"))
	_add_button(unit_row_4, "Contest Node", func(): economy_debug_manager.call("spawn_enemy_combat_near_closest_resource_node"))

	_add_label(vbox, "Resource Nodes")
	var resource_row = _add_row(vbox)
	_add_button(resource_row, "Place Wood Node", func(): _spawn_resource_node(BuildingData.ResourceType.WOOD))
	_add_button(resource_row, "Place Food Node", func(): _spawn_resource_node(BuildingData.ResourceType.FOOD))
	_add_button(resource_row, "Place Gold Node", func(): _spawn_resource_node(BuildingData.ResourceType.GOLD))
	var resource_row_2 = _add_row(vbox)
	_add_button(resource_row_2, "Place Stone Node", func(): _spawn_resource_node(BuildingData.ResourceType.STONE))
	_add_button(resource_row_2, "Place Metal Node", func(): _spawn_resource_node(BuildingData.ResourceType.METAL))

	_add_label(vbox, "Buildings")
	for kind in [
		EconomyTypes.BuildingKind.CAPITAL,
		EconomyTypes.BuildingKind.ROAD,
		EconomyTypes.BuildingKind.OUTPOST,
		EconomyTypes.BuildingKind.WATCH_TOWER,
		EconomyTypes.BuildingKind.BARRACKS,
		EconomyTypes.BuildingKind.STABLES,
		EconomyTypes.BuildingKind.HANGAR,
		EconomyTypes.BuildingKind.WORKSHOP,
		EconomyTypes.BuildingKind.ALTAR,
		EconomyTypes.BuildingKind.HOUSE,
		EconomyTypes.BuildingKind.TRADING_HALL,
		EconomyTypes.BuildingKind.WALL,
		EconomyTypes.BuildingKind.GATE
	]:
		_add_button(vbox, "Spawn %s" % EconomyTypes.get_building_kind_name(kind), Callable(self, "_spawn_building_kind_from_panel").bind(kind))

func update_shortcuts_tab():
	var vbox = _reset_tab("Shortcuts / Help")

	_add_label(vbox, "General debug shortcuts")
	_add_label(vbox, "F1: Show/hide debug UI\nTab: Cycle active debug system")
	_add_shortcuts(vbox, "Diplomacy shortcuts", diplomacy_debugger)
	_add_shortcuts(vbox, "Resources shortcuts", resources_debugger)
	_add_shortcuts(vbox, "Combat shortcuts", combat_debugger)
	_add_shortcuts(vbox, "Placement shortcuts", placement_manager)
	_add_shortcuts(vbox, "Spawning/testing shortcuts", economy_debug_manager)

func _reset_tab(tab_name: String) -> VBoxContainer:
	var vbox = tab_vboxes.get(tab_name, null)
	if vbox == null:
		return null

	for child in vbox.get_children():
		child.queue_free()

	return vbox

func _add_label(parent: Node, text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func _add_button(parent: Node, text: String, callback: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _add_checkbox(parent: Node, text: String, pressed: bool, callback: Callable) -> CheckBox:
	var checkbox = CheckBox.new()
	checkbox.text = text
	checkbox.button_pressed = pressed
	checkbox.focus_mode = Control.FOCUS_NONE
	checkbox.toggled.connect(callback)
	parent.add_child(checkbox)
	return checkbox

func _add_row(parent: Node) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	return row

func _add_tab_button(parent: Node, text: String, selected: bool, callback: Callable) -> Button:
	var button = Button.new()
	button.text = "[%s]" % text if selected else text
	button.disabled = selected
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _add_option_tabs(parent: Node, title: String, options: Array, callback_method: String, columns: int = 4):
	if options.is_empty():
		return

	_add_label(parent, title)
	var row: HBoxContainer = null

	for index in range(options.size()):
		if index % columns == 0:
			row = _add_row(parent)

		var option = options[index]
		if not option is Dictionary:
			continue

		_add_tab_button(
			row,
			str(option.get("label", "Option")),
			bool(option.get("selected", false)),
			Callable(self, callback_method).bind(int(option.get("value", 0)))
		)

func _add_placement_item_buttons(parent: Node):
	var options = _placement_get_options("get_current_option_debug_list")
	if options.is_empty():
		_add_label(parent, "Items\nNone")
		return

	_add_label(parent, "Items")

	for option in options:
		if not option is Dictionary:
			continue

		var label = str(option.get("label", "Item"))
		if option.has("cost_text"):
			label = "%s | %s" % [label, option.get("cost_text", "Free")]

		_add_tab_button(
			parent,
			label,
			bool(option.get("selected", false)),
			Callable(self, "_placement_select_item").bind(int(option.get("index", 0)))
		)

func _add_shortcuts(parent: Node, title: String, manager: Node):
	_add_label(parent, title)
	if manager == null or not manager.has_method("get_debug_shortcuts"):
		_add_label(parent, "Not connected")
		return

	var lines: Array[String] = []
	for item in manager.call("get_debug_shortcuts"):
		if item is Dictionary:
			lines.append("%s: %s" % [item.get("keys", ""), item.get("description", "")])
	_add_label(parent, "\n".join(lines))

func _debug_add_resource(resource_type: int, amount: int):
	if economy_debug_manager != null and economy_debug_manager.has_method("add_resource_to_selected_nation"):
		economy_debug_manager.call("add_resource_to_selected_nation", resource_type, amount)
	elif resources_debugger != null and resources_debugger.has_method("add_resource"):
		resources_debugger.call("add_resource", resource_type, amount)

func _debug_add_all_resources(amount: int):
	if economy_debug_manager != null and economy_debug_manager.has_method("add_all_resources_to_selected_nation"):
		economy_debug_manager.call("add_all_resources_to_selected_nation", amount)
	elif resources_debugger != null and resources_debugger.has_method("add_all_resources"):
		resources_debugger.call("add_all_resources", amount)

func _spawn_resource_node(resource_type: int):
	if economy_debug_manager != null and economy_debug_manager.has_method("arm_resource_node_placement"):
		economy_debug_manager.call("arm_resource_node_placement", resource_type)
	elif economy_debug_manager != null and economy_debug_manager.has_method("spawn_resource_node_at_mouse"):
		economy_debug_manager.call("spawn_resource_node_at_mouse", resource_type)

func _spawn_building_kind_from_panel(building_kind: int):
	if economy_debug_manager != null and economy_debug_manager.has_method("spawn_building_kind_at_mouse"):
		economy_debug_manager.call("spawn_building_kind_at_mouse", building_kind)

func _placement_toggle_mode():
	if placement_manager != null and placement_manager.has_method("toggle_mode"):
		placement_manager.call("toggle_mode")

func _placement_toggle_enabled():
	if placement_manager != null and placement_manager.has_method("toggle_placement_enabled"):
		placement_manager.call("toggle_placement_enabled")

func _placement_get_options(method_name: String) -> Array:
	if placement_manager == null or not placement_manager.has_method(method_name):
		return []

	var value = placement_manager.call(method_name)
	return value if value is Array else []

func _placement_set_mode(mode: int):
	if placement_manager != null and placement_manager.has_method("set_placement_mode"):
		placement_manager.call("set_placement_mode", mode)

func _placement_set_category(category: int):
	if placement_manager == null:
		return

	var mode = int(placement_manager.get("placement_mode")) if _has_property(placement_manager, "placement_mode") else 0
	if mode == PlacementManager.PlacementMode.BUILDINGS:
		if placement_manager.has_method("set_building_category"):
			placement_manager.call("set_building_category", category)
	elif placement_manager.has_method("set_unit_category"):
		placement_manager.call("set_unit_category", category)

func _placement_set_type(type_index: int):
	if placement_manager != null and placement_manager.has_method("set_unit_archetype_index"):
		placement_manager.call("set_unit_archetype_index", type_index)

func _placement_select_item(index: int):
	if placement_manager != null and placement_manager.has_method("select_option_index"):
		placement_manager.call("select_option_index", index)

func _placement_cycle_nation(direction: int):
	if placement_manager != null and placement_manager.has_method("cycle_nation"):
		placement_manager.call("cycle_nation", direction)

func _placement_cycle_side():
	if placement_manager != null and placement_manager.has_method("cycle_allegiance_override"):
		placement_manager.call("cycle_allegiance_override", 1)

func _placement_cycle_category(direction: int):
	if placement_manager != null and placement_manager.has_method("cycle_category"):
		placement_manager.call("cycle_category", direction)

func _placement_cycle_archetype(direction: int):
	if placement_manager != null and placement_manager.has_method("cycle_archetype"):
		placement_manager.call("cycle_archetype", direction)

func _placement_cycle_selected(direction: int):
	if placement_manager != null and placement_manager.has_method("cycle_selected"):
		placement_manager.call("cycle_selected", direction)

func _placement_place_at_mouse():
	if placement_manager != null and placement_manager.has_method("place_selected_at"):
		var camera = get_viewport().get_camera_2d()
		var mouse_position = camera.get_global_mouse_position() if camera != null else get_viewport().get_mouse_position()
		placement_manager.call("place_selected_at", mouse_position)

func _set_free_build(value: bool):
	if economy_debug_manager != null and economy_debug_manager.has_method("set_free_build_mode"):
		economy_debug_manager.call("set_free_build_mode", value)
	elif placement_manager != null:
		placement_manager.set("free_build_mode", value)

func _set_ignore_rules(value: bool):
	if economy_debug_manager != null and economy_debug_manager.has_method("set_ignore_placement_rules_mode"):
		economy_debug_manager.call("set_ignore_placement_rules_mode", value)
	elif placement_manager != null:
		placement_manager.set("ignore_placement_rules_mode", value)

func _set_resource_node_visuals(value: bool):
	for node in get_tree().get_nodes_in_group("resource_node"):
		if _has_property(node, "debug_visuals_enabled"):
			node.set("debug_visuals_enabled", value)

func _set_resource_node_contest_radius(value: bool):
	for node in get_tree().get_nodes_in_group("resource_node"):
		if _has_property(node, "show_contest_radius"):
			node.set("show_contest_radius", value)

func _get_resource_node_visuals_enabled() -> bool:
	for node in get_tree().get_nodes_in_group("resource_node"):
		if _has_property(node, "debug_visuals_enabled"):
			return bool(node.get("debug_visuals_enabled"))

	return true

func _get_resource_node_contest_radius_enabled() -> bool:
	for node in get_tree().get_nodes_in_group("resource_node"):
		if _has_property(node, "show_contest_radius"):
			return bool(node.get("show_contest_radius"))

	return true

func _format_closest_resource_node() -> String:
	if economy_debug_manager == null or not economy_debug_manager.has_method("get_closest_resource_node_to_mouse"):
		return "Not connected"

	var node = economy_debug_manager.call("get_closest_resource_node_to_mouse")
	if node == null or not is_instance_valid(node):
		return "None"

	if node.has_method("get_debug_state"):
		var state = node.call("get_debug_state")
		return "%s | Worker: %s | Tick: %s every %.1fs | Workers: %s/%s | Contested: %s" % [
			state.get("resource_name", "Resource"),
			state.get("required_worker_name", "Any"),
			state.get("harvest_amount", 0),
			float(state.get("harvest_interval", 0.0)),
			state.get("assigned_workers", 0),
			state.get("max_workers", 0),
			"Yes" if bool(state.get("contested", false)) else "No"
		]

	return node.name

func _format_selected_combat_object() -> String:
	var selected = _get_first_selected_unit()
	if selected == null:
		return "None"

	var health = "%s/%s" % [_get_property_or_default(selected, "current_health", "?"), _get_property_or_default(selected, "max_health", "?")]
	var damage = _get_property_or_default(selected, "attack_damage", _get_property_or_default(selected, "attack_damage", "?"))
	var attack_range = _get_property_or_default(selected, "attack_range_tiles", "?")
	var cooldown = _get_property_or_default(selected, "attack_cooldown", "?")
	var target = selected.get("attack_target") if _has_property(selected, "attack_target") else null
	var order = "Unknown"
	var orders = selected.get_node_or_null("CombatOrderComponent") if selected is Node else null
	if orders != null and orders.has_method("get_order_name"):
		order = orders.call("get_order_name")

	return "%s | HP %s | Damage %s | Range %s | Cooldown %s | Target %s | Order %s" % [
		selected.name,
		health,
		damage,
		attack_range,
		cooldown,
		target.name if target != null and is_instance_valid(target) else "None",
		order
	]

func _get_resource_amounts() -> Dictionary:
	if resources_debugger != null and resources_debugger.has_method("get_resource_amounts"):
		return resources_debugger.call("get_resource_amounts")

	return {"wood": 0, "food": 0, "gold": 0, "stone": 0, "metal": 0}

func _get_active_debug_title() -> String:
	if debug_manager == null or not debug_manager.has_method("get_active_tab"):
		return "Unknown"

	var active = debug_manager.call("get_active_tab")
	if active != null and active.has_method("get_debug_title"):
		return active.call("get_debug_title")

	return active.name if active != null else "None"

func _get_selected_nation_name() -> String:
	if economy_debug_manager != null and economy_debug_manager.has_method("get_selected_nation"):
		return _get_resource_display_name(economy_debug_manager.call("get_selected_nation"))

	if placement_manager != null and placement_manager.has_method("get_selected_nation"):
		return _get_resource_display_name(placement_manager.call("get_selected_nation"))

	return "None"

func _get_selected_object_name() -> String:
	var unit = _get_first_selected_unit()
	if unit != null:
		return unit.name

	if placement_manager != null and placement_manager.has_method("get_selected_data"):
		return _get_resource_display_name(placement_manager.call("get_selected_data"))

	return "None"

func _get_toggle_summary() -> String:
	return "Free-build %s, Ignore rules %s, Supply %s, Roads %s" % [
		"On" if _get_bool(placement_manager, "free_build_mode") else "Off",
		"On" if _get_bool(placement_manager, "ignore_placement_rules_mode") else "Off",
		"On" if _get_bool(road_supply_manager, "show_supply_radius") else "Off",
		"On" if _get_bool(road_supply_manager, "show_road_network") else "Off"
	]

func _get_last_action() -> String:
	if economy_debug_manager != null and _has_property(economy_debug_manager, "last_action"):
		var action = str(economy_debug_manager.get("last_action"))
		if not action.is_empty():
			return action

	if placement_manager != null and _has_property(placement_manager, "last_action"):
		return str(placement_manager.get("last_action"))

	return "None"

func _get_warning_summary() -> String:
	var missing: Array[String] = []
	for item in {
		"Diplomacy": diplomacy_debugger,
		"Resources": resources_debugger,
		"Combat": combat_debugger,
		"Placement": placement_manager,
		"Spawning": economy_debug_manager,
		"Road/Supply": road_supply_manager
	}.keys():
		var node = {
			"Diplomacy": diplomacy_debugger,
			"Resources": resources_debugger,
			"Combat": combat_debugger,
			"Placement": placement_manager,
			"Spawning": economy_debug_manager,
			"Road/Supply": road_supply_manager
		}[item]
		if node == null:
			missing.append("%s not connected" % item)

	return "None" if missing.is_empty() else ", ".join(missing)

func _get_compact_summary() -> String:
	if debug_manager != null and debug_manager.has_method("get_active_tab"):
		var active = debug_manager.call("get_active_tab")
		if active != null and active.has_method("get_current_debug_summary"):
			return active.call("get_current_debug_summary")

	return _get_toggle_summary()

func _get_first_selected_unit() -> Node2D:
	if player_selection_manager == null or not _has_property(player_selection_manager, "selected_units"):
		return null

	for unit in player_selection_manager.get("selected_units"):
		if unit is Node2D and is_instance_valid(unit):
			return unit

	return null

func _discover_managers():
	if debug_manager == null:
		debug_manager = get_tree().get_first_node_in_group("debug_manager")
	if diplomacy_debugger == null:
		diplomacy_debugger = get_tree().get_first_node_in_group("diplomacy_debugger")
	if resources_debugger == null:
		resources_debugger = get_tree().get_first_node_in_group("resources_debugger")
	if combat_debugger == null:
		combat_debugger = get_tree().get_first_node_in_group("combat_debugger")
	if placement_manager == null:
		placement_manager = get_tree().get_first_node_in_group("placement_manager")
	if economy_debug_manager == null:
		economy_debug_manager = get_tree().get_first_node_in_group("economy_debug_manager")
	if road_supply_manager == null:
		road_supply_manager = get_tree().get_first_node_in_group("road_supply_manager")
	if resource_manager == null:
		resource_manager = get_tree().get_first_node_in_group("resource_manager")
	if player_selection_manager == null:
		player_selection_manager = get_tree().get_first_node_in_group("player_selection_manager")

func _call_dictionary(node: Node, method_name: String) -> Dictionary:
	if node == null or not node.has_method(method_name):
		return {}

	var value = node.call(method_name)
	return value if value is Dictionary else {}

func _get_bool(node: Node, property_name: String) -> bool:
	if node == null or not _has_property(node, property_name):
		return false

	return bool(node.get(property_name))

func _set_if_connected(node: Node, property_name: String, value):
	if node != null and _has_property(node, property_name):
		node.set(property_name, value)

func _get_property_or_default(object: Object, property_name: String, default_value):
	if object == null or not _has_property(object, property_name):
		return default_value

	return object.get(property_name)

func _has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false

	for property in object.get_property_list():
		if str(property.get("name")) == property_name:
			return true

	return false

func _get_resource_display_name(resource) -> String:
	if resource == null:
		return "None"

	if resource is Resource:
		for property_name in ["display_name", "unit_id", "building_id", "nation_id"]:
			var value = str(resource.get(property_name))
			if not value.is_empty():
				return value
		return resource.resource_path.get_file()

	return str(resource)
