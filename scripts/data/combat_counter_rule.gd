extends Resource
class_name CombatCounterRule

@export_enum("Infantry", "Ranged", "Cavalry", "Air", "Siege", "Champion", "Building", "Unknown") var attacker_class: int = 0
@export_enum("Infantry", "Ranged", "Cavalry", "Air", "Siege", "Champion", "Building", "Unknown") var defender_class: int = 0
@export var multiplier: float = 1.0
