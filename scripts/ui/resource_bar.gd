extends HBoxContainer
class_name ResourceBar

@onready var wood_label: Label = $WoodLabel
@onready var food_label: Label = $FoodLabel
@onready var gold_label: Label = $GoldLabel
@onready var stone_label: Label = $StoneLabel
@onready var metal_label: Label = $MetalLabel

var resource_manager: ResourceManager
var current_nation_key: String = ""

func setup(nation_key: String):
	current_nation_key = nation_key
	resource_manager = get_tree().get_first_node_in_group("resource_manager")
	
	if resource_manager != null:
		resource_manager.resources_changed.connect(_on_resources_changed)
		resource_manager.resource_changed.connect(_on_resource_changed)
		
		# Initial update
		var amounts = resource_manager.call("get_resource_amounts_by_key", current_nation_key)
		_update_display(amounts)

func _on_resources_changed(nation_key: String, amounts: Dictionary):
	if nation_key == current_nation_key:
		_update_display(amounts)

func _on_resource_changed(nation_key: String, _type: int, _amount: int, _delta: int):
	if nation_key == current_nation_key:
		var amounts = resource_manager.call("get_resource_amounts_by_key", current_nation_key)
		_update_display(amounts)

func _update_display(amounts: Dictionary):
	wood_label.text = "🪵: %d" % amounts.get(BuildingData.ResourceType.WOOD, 0)
	food_label.text = "🍞: %d" % amounts.get(BuildingData.ResourceType.FOOD, 0)
	gold_label.text = "💰: %d" % amounts.get(BuildingData.ResourceType.GOLD, 0)
	stone_label.text = "🪨: %d" % amounts.get(BuildingData.ResourceType.STONE, 0)
	metal_label.text = "⚔️: %d" % amounts.get(BuildingData.ResourceType.METAL, 0)
