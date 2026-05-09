extends Node
class_name UnitOwnershipComponent

enum Allegiance {
	PLAYER,
	ALLY,
	NEUTRAL,
	ENEMY
}

@export var owner_nation: Resource
@export var owner_id: String = ""
@export var allegiance: Allegiance = Allegiance.NEUTRAL

func set_ownership(new_owner_nation: Resource, new_allegiance: Allegiance, new_owner_id: String = ""):
	add_to_group("unit_ownership_component")
	owner_nation = new_owner_nation
	allegiance = new_allegiance
	owner_id = new_owner_id

	if owner_id.is_empty() and owner_nation != null:
		owner_id = str(owner_nation.get("nation_id"))

	_apply_owner_visuals()

func is_player_owned() -> bool:
	return allegiance == Allegiance.PLAYER

func is_enemy() -> bool:
	return allegiance == Allegiance.ENEMY

func is_ally() -> bool:
	return allegiance == Allegiance.ALLY

func is_neutral() -> bool:
	return allegiance == Allegiance.NEUTRAL

func _apply_owner_visuals():
	var owned_node = get_parent()
	if owned_node == null:
		return

	if owner_nation != null:
		NationVisuals.apply_to_node(owned_node, owner_nation)
		return

	if not owner_id.is_empty():
		NationVisuals.apply_to_node_by_id(owned_node, owner_id)
