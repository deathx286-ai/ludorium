extends Resource
class_name UnitData

@export_group("Identity")
@export var unit_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var sprite_texture: Texture2D

@export_group("Core Stats")
@export var max_health: int = 100
@export var damage: int = 10
@export var attack_range_tiles: int = 1
@export var attack_cooldown: float = 1.0
@export var move_speed: float = 150.0
@export var vision_range_tiles: int = 6

@export_group("Tile Footprint")
@export var footprint_width: int = 1
@export var footprint_height: int = 1

@export_group("Classification")
@export var movement_type: UnitClassification.MovementType = UnitClassification.MovementType.GROUND
@export var unit_domain: UnitClassification.UnitDomain = UnitClassification.UnitDomain.INFANTRY
@export var unit_archetype: UnitClassification.UnitArchetype = UnitClassification.UnitArchetype.LIGHT_INFANTRY
@export var unit_role: UnitClassification.UnitRole = UnitClassification.UnitRole.SKIRMISHER

@export_group("Flags")
@export var can_move: bool = true
@export var can_attack: bool = true
@export var is_structure: bool = false

@export_group("Identity / Culture")
@export var culture_tag: String = ""
@export var origin_nation_id: String = ""
@export var divine_faction_id: String = ""
@export var unit_tags: Array[String] = []

@export_group("Rewards")
@export var xp_reward: int = 0
@export var gold_reward: int = 0
