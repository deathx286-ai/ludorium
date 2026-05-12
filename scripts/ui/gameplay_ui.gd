extends CanvasLayer
class_name GameplayUI

@onready var resource_bar: ResourceBar = $Control/ResourceBar/HBox
@onready var selection_panel: SelectionPanel = $Control/SelectionPanel
@onready var building_menu: BuildingMenu = $Control/BuildingMenu
@onready var notification_label: Label = $Control/NotificationLabel

var selection_manager: PlayerUnitSelectionManager

func _ready():
	add_to_group("gameplay_ui")
	selection_manager = get_tree().get_first_node_in_group("player_selection_manager")
	if selection_manager != null:
		selection_manager.selection_changed.connect(_on_selection_changed)
		
	var diplomacy = get_tree().get_first_node_in_group("run_diplomacy_manager")
	if diplomacy != null:
		var nation = diplomacy.get("selected_player_nation")
		if nation != null:
			resource_bar.setup(nation.get("nation_id"))
			building_menu._setup_menu()
			
	notification_label.text = ""

func _on_selection_changed(units: Array[Node2D]):
	if units.is_empty():
		selection_panel.set_target(null)
		return
		
	var unit = units[0]
	
	# Only show our panel if it's a building
	var is_building = unit.has_method("is_structure") and unit.call("is_structure")
	if not is_building and "building_data" in unit:
		is_building = unit.get("building_data") != null
	
	if is_building:
		selection_panel.set_target(unit)
	else:
		selection_panel.set_target(null)

func show_notification(message: String, duration: float = 3.0):
	notification_label.text = message
	await get_tree().create_timer(duration).timeout
	if notification_label.text == message:
		notification_label.text = ""
