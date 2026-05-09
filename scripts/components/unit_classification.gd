@tool
extends Node
class_name UnitClassification

enum MovementType {
	GROUND,
	AIR,
	NAVAL,
	ETHEREAL,
	STRUCTURE
}

enum UnitDomain {
	INFANTRY,
	RANGED,
	CAVALRY,
	SIEGE,
	AIR,
	CHAMPION,
	STRUCTURE
}

enum UnitArchetype {
	LIGHT_INFANTRY,
	HEAVY_INFANTRY,
	SPECIALIST_INFANTRY,
	LIGHT_RANGED,
	HEAVY_RANGED,
	ARCANE_RANGED,
	LIGHT_CAVALRY,
	HEAVY_CAVALRY,
	WAR_BEAST,
	LIGHT_SIEGE,
	HEAVY_SIEGE,
	ARCANE_SIEGE,
	LIGHT_AIR,
	HEAVY_AIR,
	ARCANE_AIR,
	MARTIAL_CHAMPION,
	ARCANE_CHAMPION,
	DIVINE_FALLEN_CHAMPION,
	PRODUCTION_STRUCTURE,
	DEFENSE_STRUCTURE,
	ENEMY_CAMP_STRUCTURE
}

enum UnitRole {
	SKIRMISHER,
	SCOUT,
	RAIDER,
	VANGUARD,
	SHIELDBEARER,
	BRUISER,
	ENGINEER,
	CLERIC,
	SABOTEUR,
	ARCHER,
	JAVELINIER,
	SLINGER,
	MARKSMAN,
	CROSSBOWMAN,
	ARBALIST,
	BATTLEMAGE,
	HEXER,
	ELEMENTALIST,
	OUTRIDER,
	FLANKER,
	PURSUER,
	LANCER,
	KNIGHT,
	CATAPHRACT,
	MAULER,
	CRUSHER,
	TERROR_BEAST,
	BALLISTA,
	SCORPION,
	MANTLET,
	CATAPULT,
	TREBUCHET,
	BATTERING_RAM,
	RUNE_CANNON,
	SOUL_ENGINE,
	STORM_SPIRE,
	SCOUT_FLYER,
	HARRIER,
	INTERCEPTOR,
	WYVERN,
	DRAKE,
	SKYBREAKER,
	SPIRIT,
	TEMPEST,
	SERAPH,
	DUELIST,
	WARLORD,
	JUGGERNAUT,
	INVOKER,
	SEER,
	RITUALIST,
	SAINT,
	CHOSEN,
	FORSAKEN,
	BARRACKS,
	STABLE,
	WORKSHOP,
	TOWER,
	WALL,
	GATE,
	SPAWNER,
	BOSS_CAMP,
	RESOURCE_CAMP
}

@export var movement_type: MovementType = MovementType.GROUND
@export var unit_domain: UnitDomain = UnitDomain.INFANTRY
@export var unit_archetype: UnitArchetype = UnitArchetype.LIGHT_INFANTRY
@export var unit_role: UnitRole = UnitRole.SKIRMISHER

func apply_unit_data(unit_data):
	if unit_data == null:
		return

	movement_type = unit_data.movement_type
	unit_domain = unit_data.unit_domain
	unit_archetype = unit_data.unit_archetype
	unit_role = unit_data.unit_role

func apply_building_data(building_data):
	if building_data == null:
		return

	movement_type = building_data.movement_type
	unit_domain = building_data.unit_domain
	unit_archetype = building_data.unit_archetype
	unit_role = building_data.unit_role

func is_ground() -> bool:
	return movement_type == MovementType.GROUND

func is_air() -> bool:
	return movement_type == MovementType.AIR or unit_domain == UnitDomain.AIR

func is_naval() -> bool:
	return movement_type == MovementType.NAVAL

func is_ethereal() -> bool:
	return movement_type == MovementType.ETHEREAL

func is_structure() -> bool:
	return movement_type == MovementType.STRUCTURE or unit_domain == UnitDomain.STRUCTURE

func is_infantry() -> bool:
	return unit_domain == UnitDomain.INFANTRY

func is_ranged() -> bool:
	return unit_domain == UnitDomain.RANGED

func is_cavalry() -> bool:
	return unit_domain == UnitDomain.CAVALRY

func is_siege() -> bool:
	return unit_domain == UnitDomain.SIEGE

func is_champion() -> bool:
	return unit_domain == UnitDomain.CHAMPION

func has_role(role: UnitRole) -> bool:
	return unit_role == role

func has_archetype(archetype: UnitArchetype) -> bool:
	return unit_archetype == archetype

func get_full_classification_name() -> String:
	return "%s / %s / %s / %s" % [
		get_movement_type_name(movement_type),
		get_unit_domain_name(unit_domain),
		get_unit_archetype_name(unit_archetype),
		get_unit_role_name(unit_role)
	]

static func get_movement_type_name(value: MovementType) -> String:
	var names = {
		MovementType.GROUND: "Ground",
		MovementType.AIR: "Air",
		MovementType.NAVAL: "Naval",
		MovementType.ETHEREAL: "Ethereal",
		MovementType.STRUCTURE: "Structure"
	}
	return names.get(value, "Unknown")

static func get_unit_domain_name(value: UnitDomain) -> String:
	var names = {
		UnitDomain.INFANTRY: "Infantry",
		UnitDomain.RANGED: "Ranged",
		UnitDomain.CAVALRY: "Cavalry",
		UnitDomain.SIEGE: "Siege",
		UnitDomain.AIR: "Air",
		UnitDomain.CHAMPION: "Champion",
		UnitDomain.STRUCTURE: "Structure"
	}
	return names.get(value, "Unknown")

static func get_unit_archetype_name(value: UnitArchetype) -> String:
	var names = {
		UnitArchetype.LIGHT_INFANTRY: "Light Infantry",
		UnitArchetype.HEAVY_INFANTRY: "Heavy Infantry",
		UnitArchetype.SPECIALIST_INFANTRY: "Specialist Infantry",
		UnitArchetype.LIGHT_RANGED: "Light Ranged",
		UnitArchetype.HEAVY_RANGED: "Heavy Ranged",
		UnitArchetype.ARCANE_RANGED: "Arcane Ranged",
		UnitArchetype.LIGHT_CAVALRY: "Light Cavalry",
		UnitArchetype.HEAVY_CAVALRY: "Heavy Cavalry",
		UnitArchetype.WAR_BEAST: "War Beast",
		UnitArchetype.LIGHT_SIEGE: "Light Siege",
		UnitArchetype.HEAVY_SIEGE: "Heavy Siege",
		UnitArchetype.ARCANE_SIEGE: "Arcane Siege",
		UnitArchetype.LIGHT_AIR: "Light Air",
		UnitArchetype.HEAVY_AIR: "Heavy Air",
		UnitArchetype.ARCANE_AIR: "Arcane Air",
		UnitArchetype.MARTIAL_CHAMPION: "Martial Champion",
		UnitArchetype.ARCANE_CHAMPION: "Arcane Champion",
		UnitArchetype.DIVINE_FALLEN_CHAMPION: "Divine/Fallen Champion",
		UnitArchetype.PRODUCTION_STRUCTURE: "Production Structure",
		UnitArchetype.DEFENSE_STRUCTURE: "Defense Structure",
		UnitArchetype.ENEMY_CAMP_STRUCTURE: "Enemy Camp Structure"
	}
	return names.get(value, "Unknown")

static func get_unit_archetype_abbreviation(value: UnitArchetype) -> String:
	var abbreviations = {
		UnitArchetype.LIGHT_INFANTRY: "LI",
		UnitArchetype.HEAVY_INFANTRY: "HI",
		UnitArchetype.SPECIALIST_INFANTRY: "SI",
		UnitArchetype.LIGHT_RANGED: "LR",
		UnitArchetype.HEAVY_RANGED: "HR",
		UnitArchetype.ARCANE_RANGED: "AR",
		UnitArchetype.LIGHT_CAVALRY: "LC",
		UnitArchetype.HEAVY_CAVALRY: "HC",
		UnitArchetype.WAR_BEAST: "WB",
		UnitArchetype.LIGHT_SIEGE: "LS",
		UnitArchetype.HEAVY_SIEGE: "HS",
		UnitArchetype.ARCANE_SIEGE: "AS",
		UnitArchetype.LIGHT_AIR: "LA",
		UnitArchetype.HEAVY_AIR: "HA",
		UnitArchetype.ARCANE_AIR: "AA",
		UnitArchetype.MARTIAL_CHAMPION: "MC",
		UnitArchetype.ARCANE_CHAMPION: "AC",
		UnitArchetype.DIVINE_FALLEN_CHAMPION: "DFC",
		UnitArchetype.PRODUCTION_STRUCTURE: "PS",
		UnitArchetype.DEFENSE_STRUCTURE: "DS",
		UnitArchetype.ENEMY_CAMP_STRUCTURE: "ECS"
	}
	return abbreviations.get(value, "??")

static func get_unit_role_abbreviation(value: UnitRole) -> String:
	var role_name = get_unit_role_name(value)

	if role_name == "Unknown":
		return "?"

	var abbreviation = ""
	var words = role_name.split(" ", false)

	for word in words:
		if word.length() > 0:
			abbreviation += word.substr(0, 1).to_upper()

	return abbreviation

static func get_unit_role_name(value: UnitRole) -> String:
	var names = {
		UnitRole.SKIRMISHER: "Skirmisher",
		UnitRole.SCOUT: "Scout",
		UnitRole.RAIDER: "Raider",
		UnitRole.VANGUARD: "Vanguard",
		UnitRole.SHIELDBEARER: "Shieldbearer",
		UnitRole.BRUISER: "Bruiser",
		UnitRole.ENGINEER: "Engineer",
		UnitRole.CLERIC: "Cleric",
		UnitRole.SABOTEUR: "Saboteur",
		UnitRole.ARCHER: "Archer",
		UnitRole.JAVELINIER: "Javelinier",
		UnitRole.SLINGER: "Slinger",
		UnitRole.MARKSMAN: "Marksman",
		UnitRole.CROSSBOWMAN: "Crossbowman",
		UnitRole.ARBALIST: "Arbalist",
		UnitRole.BATTLEMAGE: "Battlemage",
		UnitRole.HEXER: "Hexer",
		UnitRole.ELEMENTALIST: "Elementalist",
		UnitRole.OUTRIDER: "Outrider",
		UnitRole.FLANKER: "Flanker",
		UnitRole.PURSUER: "Pursuer",
		UnitRole.LANCER: "Lancer",
		UnitRole.KNIGHT: "Knight",
		UnitRole.CATAPHRACT: "Cataphract",
		UnitRole.MAULER: "Mauler",
		UnitRole.CRUSHER: "Crusher",
		UnitRole.TERROR_BEAST: "Terror Beast",
		UnitRole.BALLISTA: "Ballista",
		UnitRole.SCORPION: "Scorpion",
		UnitRole.MANTLET: "Mantlet",
		UnitRole.CATAPULT: "Catapult",
		UnitRole.TREBUCHET: "Trebuchet",
		UnitRole.BATTERING_RAM: "Battering Ram",
		UnitRole.RUNE_CANNON: "Rune Cannon",
		UnitRole.SOUL_ENGINE: "Soul Engine",
		UnitRole.STORM_SPIRE: "Storm Spire",
		UnitRole.SCOUT_FLYER: "Scout Flyer",
		UnitRole.HARRIER: "Harrier",
		UnitRole.INTERCEPTOR: "Interceptor",
		UnitRole.WYVERN: "Wyvern",
		UnitRole.DRAKE: "Drake",
		UnitRole.SKYBREAKER: "Skybreaker",
		UnitRole.SPIRIT: "Spirit",
		UnitRole.TEMPEST: "Tempest",
		UnitRole.SERAPH: "Seraph",
		UnitRole.DUELIST: "Duelist",
		UnitRole.WARLORD: "Warlord",
		UnitRole.JUGGERNAUT: "Juggernaut",
		UnitRole.INVOKER: "Invoker",
		UnitRole.SEER: "Seer",
		UnitRole.RITUALIST: "Ritualist",
		UnitRole.SAINT: "Saint",
		UnitRole.CHOSEN: "Chosen",
		UnitRole.FORSAKEN: "Forsaken",
		UnitRole.BARRACKS: "Barracks",
		UnitRole.STABLE: "Stable",
		UnitRole.WORKSHOP: "Workshop",
		UnitRole.TOWER: "Tower",
		UnitRole.WALL: "Wall",
		UnitRole.GATE: "Gate",
		UnitRole.SPAWNER: "Spawner",
		UnitRole.BOSS_CAMP: "Boss Camp",
		UnitRole.RESOURCE_CAMP: "Resource Camp"
	}
	return names.get(value, "Unknown")
