extends Resource
class_name RegionDefinition

enum RegionType {
	PLAINS,
	FOREST,
	SWAMP,
	ROCKY,
	MOUNTAIN,
	VOLCANIC,
	DEADLANDS
}

@export var region_name: String = "Region"
@export var region_type: RegionType = RegionType.PLAINS
@export var debug_color: Color = Color.WHITE
@export var terrain_color: Color = Color.GREEN

@export_group("Weights")
# Dictionary of String (terrain_type) to float (weight)
@export var terrain_weights: Dictionary = {"grass": 1.0}
# Dictionary of String (prop_type) to float (weight)
@export var prop_weights: Dictionary = {}
# Dictionary of BuildingData.ResourceType to float (weight)
@export var resource_weights: Dictionary = {}

@export_group("Density")
@export var prop_density: float = 0.1
@export var resource_density: float = 0.02

@export_group("Behavior")
@export var is_naturally_buildable: bool = true
@export var is_naturally_walkable: bool = true
@export var blocks_movement: bool = false
@export var blocks_building: bool = false
