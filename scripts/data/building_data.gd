extends Resource
class_name BuildingData

enum ResourceType {
	NONE,
	WOOD,
	FOOD,
	GOLD,
	STONE,
	METAL
}

@export_group("Identity")
@export var building_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var sprite_texture: Texture2D

@export_group("Base Stats")
@export var max_health: int = 200
@export var footprint_width: int = 2
@export var footprint_height: int = 2

@export_group("Classification")
@export var movement_type: UnitClassification.MovementType = UnitClassification.MovementType.STRUCTURE
@export var unit_domain: UnitClassification.UnitDomain = UnitClassification.UnitDomain.STRUCTURE
@export var unit_archetype: UnitClassification.UnitArchetype = UnitClassification.UnitArchetype.PRODUCTION_STRUCTURE
@export var unit_role: UnitClassification.UnitRole = UnitClassification.UnitRole.BARRACKS

@export_group("Resources")
@export var resource_type: ResourceType = ResourceType.NONE
@export var resource_amount_per_tick: int = 0
@export var resource_tick_seconds: float = 3.0

@export_group("Economy / Placement")
@export var building_kind: EconomyTypes.BuildingKind = EconomyTypes.BuildingKind.AUTO
@export var resource_cost: Dictionary = {}
@export var wood_cost: int = 0
@export var food_cost: int = 0
@export var gold_cost: int = 0
@export var stone_cost: int = 0
@export var metal_cost: int = 0
@export var supply_radius_tiles: int = 12
@export var outpost_network_range_tiles: int = 50
@export var minimum_anchor_distance_tiles: int = 25
@export var population_capacity_bonus: int = 0

@export_group("Flags")
@export var is_resource_building: bool = false
@export var is_production_building: bool = false
@export var is_defense_building: bool = false
@export var is_wall: bool = false
@export var is_gate: bool = false
@export var is_enemy_camp: bool = false
@export var can_attack: bool = false

@export_group("Combat")
@export var damage: int = 0
@export var attack_range_tiles: int = 0
@export var attack_cooldown: float = 1.0

@export_group("Identity / Culture")
@export var culture_tag: String = ""
@export var origin_nation_id: String = ""
@export var divine_faction_id: String = ""
@export var building_tags: Array[String] = []
