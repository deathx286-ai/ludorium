extends Control

@export var selection_manager: PlayerUnitSelectionManager

@onready var unit_portrait: TextureRect = %UnitPortrait
@onready var unit_name_label: Label = %UnitNameLabel
@onready var health_label: Label = %HealthLabel
@onready var damage_label: Label = %DamageLabel
@onready var range_label: Label = %RangeLabel
@onready var speed_label: Label = %SpeedLabel
@onready var move_speed_label: Label = %MoveSpeedLabel
@onready var archetype_label: Label = %ArchetypeLabel
@onready var order_label: Label = %OrderLabel
@onready var target_label: Label = %TargetLabel

var selected_unit: Node2D = null

func _ready():
	visible = false
	if selection_manager == null:
		selection_manager = get_tree().get_first_node_in_group("player_selection_manager")
	
	if selection_manager != null:
		selection_manager.selection_changed.connect(_on_selection_changed)
		_on_selection_changed(selection_manager.selected_units)
	else:
		push_warning("CombatUIPanel: PlayerSelectionManager not found!")

func _process(_delta):
	if visible and is_instance_valid(selected_unit):
		update_dynamic_stats()

func _on_selection_changed(units: Array[Node2D]):
	if units.is_empty():
		selected_unit = null
		visible = false
		return
	
	var unit = units[0]
	
	# Only show if it's a unit, not a building
	var is_building = unit.has_method("is_structure") and unit.call("is_structure")
	if not is_building and "building_data" in unit:
		is_building = unit.get("building_data") != null
		
	if is_instance_valid(unit) and not is_building:
		selected_unit = unit
		update_static_stats()
		update_dynamic_stats()
		visible = true
	else:
		selected_unit = null
		visible = false

func update_static_stats():
	if not is_instance_valid(selected_unit):
		return
	
	var display_name = "Unknown Unit"
	var archetype = "N/A"
	var portrait_tex = null
	
	if "unit_data" in selected_unit and selected_unit.unit_data != null:
		var data = selected_unit.unit_data
		display_name = data.display_name if not data.display_name.is_empty() else data.unit_id
		archetype = UnitClassification.get_unit_archetype_name(data.unit_archetype)
		portrait_tex = data.icon if data.icon != null else data.sprite_texture
	else:
		display_name = selected_unit.name
	
	unit_portrait.texture = portrait_tex
	unit_name_label.text = display_name
	archetype_label.text = "🛡 Armor/Class (Archetype): " + archetype
	
	var damage = selected_unit.get("attack_damage")
	var cooldown = selected_unit.get("attack_cooldown")
	
	if damage != null and cooldown != null and cooldown > 0:
		var dps = float(damage) / cooldown
		damage_label.text = "⚔ Damage (DPS): %d (%.1f)" % [damage, dps]
		speed_label.text = "⚡ Atk Speed (Attacks/s): %.1f" % (1.0 / cooldown)
	else:
		damage_label.text = "⚔ Damage (DPS): N/A"
		speed_label.text = "⚡ Atk Speed (Attacks/s): N/A"
	
	var attack_range = selected_unit.get("attack_range_tiles")
	range_label.text = "➵ Range (Tiles): " + (str(attack_range) if attack_range != null else "N/A")
		
	var move_speed = selected_unit.get("move_speed")
	move_speed_label.text = "👣 Movement (Units/s): " + (str(move_speed) if move_speed != null else "N/A")

func update_dynamic_stats():
	if not is_instance_valid(selected_unit):
		visible = false
		return
	
	var current_hp = selected_unit.get("current_health")
	var max_hp = selected_unit.get("max_health")
	
	if current_hp != null and max_hp != null:
		health_label.text = "✙ Health (Current/Max): %d / %d" % [current_hp, max_hp]
	else:
		health_label.text = "✙ Health (Current/Max): N/A"
	
	var order_name = "Idle"
	if "combat_orders" in selected_unit and selected_unit.combat_orders != null:
		order_name = selected_unit.combat_orders.get_order_name()
	
	order_label.text = "⚑ Order (Command): " + order_name
	
	var target = selected_unit.get("attack_target")
	if is_instance_valid(target):
		target_label.text = "👁 Target (Active): " + target.name
	else:
		target_label.text = "👁 Target (Active): None"
