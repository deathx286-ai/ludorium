extends Node
class_name ConstructionComponent

signal construction_started
signal construction_progress_updated(progress: float)
signal construction_finished

@export var construction_time: float = 10.0
@export var starting_health_percent: float = 0.1
@export var auto_start: bool = false

var is_under_construction: bool = false
var current_progress: float = 0.0
var parent_building: Node2D

func _ready():
	parent_building = get_parent() as Node2D
	if auto_start:
		start_construction()

func _process(delta: float):
	if not is_under_construction:
		return

	current_progress += delta
	var progress_ratio = clampf(current_progress / construction_time, 0.0, 1.0)
	
	_update_parent_health(progress_ratio)
	construction_progress_updated.emit(progress_ratio)

	if current_progress >= construction_time:
		finish_construction()

func start_construction(time_override: float = -1.0):
	if time_override > 0:
		construction_time = time_override
	
	is_under_construction = true
	current_progress = 0.0
	
	if parent_building != null:
		_update_parent_health(0.0)
		
	construction_started.emit()
	
	# Disable combat/production on parent if they exist
	_set_parent_active(false)

func finish_construction():
	is_under_construction = false
	current_progress = construction_time
	
	_update_parent_health(1.0)
	_set_parent_active(true)
	
	construction_finished.emit()

func get_progress() -> float:
	return clampf(current_progress / construction_time, 0.0, 1.0)

func _update_parent_health(progress_ratio: float):
	if parent_building == null:
		return
		
	var max_hp = int(parent_building.get("max_health"))
	if max_hp <= 0: return
	
	var min_hp = int(max_hp * starting_health_percent)
	var target_hp = lerp(min_hp, max_hp, progress_ratio)
	
	parent_building.set("current_health", int(target_hp))
	if parent_building.has_method("update_health_bar"):
		parent_building.call("update_health_bar")
	elif parent_building.get_node_or_null("HealthBar") != null:
		parent_building.get_node_or_null("HealthBar").value = int(target_hp)

func _set_parent_active(active: bool):
	if parent_building == null:
		return
		
	# Buildings shouldn't attack or produce while under construction
	if parent_building.has_method("update_process_mode"):
		# We might need to influence the process mode logic
		parent_building.set("can_attack_override", not active) 
	
	# If it's a spawner, disable auto-spawn
	if "auto_spawn_enabled" in parent_building:
		parent_building.set("auto_spawn_enabled", active if active else false)

	# Update road supply manager to realize this building is now (or not yet) active
	var road_supply_manager = get_tree().get_first_node_in_group("road_supply_manager")
	if road_supply_manager != null and road_supply_manager.has_method("rebuild_from_scene"):
		road_supply_manager.call("rebuild_from_scene")
