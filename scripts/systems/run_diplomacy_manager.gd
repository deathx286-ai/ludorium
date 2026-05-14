extends Node
class_name RunDiplomacyManager

@export var known_nations: Array[Resource] = []
@export var enemy_nation_ids: Array[String] = ["grimburrow"]
@export var ally_nation_ids: Array[String] = ["veridion"]
@export var pairwise_relationships: Dictionary = {}

@export var selected_player_nation: Resource:
	set(value):
		selected_player_nation = value

func _ready():
	seed_default_relationships()

func seed_default_relationships():
	seed_default_pairwise_relationships()
	reapply_allegiances()

func seed_default_pairwise_relationships():
	for nation in known_nations:
		if nation == null:
			continue

		if is_player_nation(nation):
			continue

		var nation_id = _get_nation_key(nation)

		if enemy_nation_ids.has(nation_id):
			set_pairwise_relationship_if_empty(selected_player_nation, nation, UnitOwnershipComponent.Allegiance.ENEMY)
		elif ally_nation_ids.has(nation_id):
			set_pairwise_relationship_if_empty(selected_player_nation, nation, UnitOwnershipComponent.Allegiance.ALLY)
		else:
			set_pairwise_relationship_if_empty(selected_player_nation, nation, UnitOwnershipComponent.Allegiance.NEUTRAL)

	var emberhold = get_known_nation_by_id("emberhold")
	var veridion = get_known_nation_by_id("veridion")
	var grimburrow = get_known_nation_by_id("grimburrow")

	if emberhold != null and veridion != null and not is_player_pair(emberhold, veridion):
		set_pairwise_relationship_if_empty(emberhold, veridion, UnitOwnershipComponent.Allegiance.ALLY)

	if emberhold != null and grimburrow != null and not is_player_pair(emberhold, grimburrow):
		set_pairwise_relationship_if_empty(emberhold, grimburrow, UnitOwnershipComponent.Allegiance.ENEMY)

	if veridion != null and grimburrow != null and not is_player_pair(veridion, grimburrow):
		set_pairwise_relationship_if_empty(veridion, grimburrow, UnitOwnershipComponent.Allegiance.NEUTRAL)

func get_allegiance_for_nation(nation_data: Resource) -> UnitOwnershipComponent.Allegiance:
	if nation_data == null:
		return UnitOwnershipComponent.Allegiance.NEUTRAL

	if is_player_nation(nation_data):
		return UnitOwnershipComponent.Allegiance.PLAYER

	return get_pairwise_relationship(nation_data, selected_player_nation)

func get_combat_allegiance_for_nation(nation_data: Resource) -> UnitOwnershipComponent.Allegiance:
	return get_allegiance_for_nation(nation_data)

func set_nation_allegiance(nation_data: Resource, allegiance: UnitOwnershipComponent.Allegiance):
	if nation_data == null or is_player_nation(nation_data):
		return

	set_pairwise_relationship(nation_data, selected_player_nation, allegiance)

func set_pairwise_relationship(nation_a: Resource, nation_b: Resource, relationship: UnitOwnershipComponent.Allegiance):
	var key = get_pairwise_key(nation_a, nation_b)

	if key.is_empty():
		return

	pairwise_relationships[key] = relationship
	reapply_allegiances()

func set_pairwise_relationship_if_empty(nation_a: Resource, nation_b: Resource, relationship: UnitOwnershipComponent.Allegiance):
	var key = get_pairwise_key(nation_a, nation_b)

	if key.is_empty() or pairwise_relationships.has(key):
		return

	pairwise_relationships[key] = relationship

func get_pairwise_relationship(nation_a: Resource, nation_b: Resource) -> UnitOwnershipComponent.Allegiance:
	var key = get_pairwise_key(nation_a, nation_b)

	if key.is_empty():
		return UnitOwnershipComponent.Allegiance.NEUTRAL

	return int(pairwise_relationships.get(key, UnitOwnershipComponent.Allegiance.NEUTRAL)) as UnitOwnershipComponent.Allegiance

func has_pairwise_relationship(nation_a: Resource, nation_b: Resource) -> bool:
	var key = get_pairwise_key(nation_a, nation_b)
	return not key.is_empty() and pairwise_relationships.has(key)

func reapply_allegiances():
	if not is_inside_tree():
		return

	for ownership in get_tree().get_nodes_in_group("unit_ownership_component"):
		_reapply_ownership_node(ownership)

	_reapply_ownership_nodes_from_tree(get_tree().current_scene)

func _reapply_ownership_nodes_from_tree(root: Node):
	if root == null:
		return

	var ownership = root.get_node_or_null("UnitOwnershipComponent") as UnitOwnershipComponent
	if ownership != null:
		_reapply_ownership_node(ownership)

	for child in root.get_children():
		_reapply_ownership_nodes_from_tree(child)

func reapply_combat_allegiances():
	reapply_allegiances()

func _reapply_ownership_node(ownership: UnitOwnershipComponent):
	if ownership == null or ownership.owner_nation == null:
		return

	var owner_node = ownership.get_parent()

	if owner_node == null:
		return

	var new_allegiance = get_allegiance_for_nation(ownership.owner_nation)
	ownership.set_ownership(ownership.owner_nation, new_allegiance, ownership.owner_id)
	_apply_allegiance_groups(owner_node, ownership)

func _apply_allegiance_groups(node: Node, ownership: UnitOwnershipComponent):
	for group_name in ["player", "enemy", "enemy_unit", "ally", "neutral"]:
		if node.is_in_group(group_name):
			node.remove_from_group(group_name)

	if ownership.is_player_owned():
		node.add_to_group("player")
	elif ownership.is_enemy():
		node.add_to_group("enemy")
		if not _is_structure_node(node):
			node.add_to_group("enemy_unit")
	elif ownership.is_ally():
		node.add_to_group("ally")
	else:
		node.add_to_group("neutral")

func _is_structure_node(node: Node) -> bool:
	if node is BaseBuilding or node is UnitSpawnerBuilding:
		return true

	var building_data = node.get("building_data")
	if building_data != null:
		return true

	var unit_data = node.get("unit_data")
	return unit_data != null and bool(unit_data.get("is_structure"))

func is_player_nation(nation_data: Resource) -> bool:
	return selected_player_nation != null and nation_data != null and _get_nation_key(selected_player_nation) == _get_nation_key(nation_data)

func is_player_pair(nation_a: Resource, nation_b: Resource) -> bool:
	return is_player_nation(nation_a) or is_player_nation(nation_b)

func is_enemy_nation(nation_data: Resource) -> bool:
	return get_allegiance_for_nation(nation_data) == UnitOwnershipComponent.Allegiance.ENEMY

func is_ally_nation(nation_data: Resource) -> bool:
	return get_allegiance_for_nation(nation_data) == UnitOwnershipComponent.Allegiance.ALLY

func is_neutral_nation(nation_data: Resource) -> bool:
	return get_allegiance_for_nation(nation_data) == UnitOwnershipComponent.Allegiance.NEUTRAL

func get_relationship_summary() -> String:
	var lines: Array[String] = []

	for nation in known_nations:
		if nation == null:
			continue

		lines.append("%s: %s" % [
			str(nation.get("display_name")),
			get_allegiance_name(get_allegiance_for_nation(nation))
		])

	return "\n".join(lines)

func get_pairwise_relationship_summary() -> String:
	var lines: Array[String] = []

	for key in pairwise_relationships.keys():
		lines.append("%s: %s" % [
			key,
			get_allegiance_name(pairwise_relationships[key])
		])

	return "\n".join(lines)

func get_allegiance_name(allegiance: UnitOwnershipComponent.Allegiance) -> String:
	match allegiance:
		UnitOwnershipComponent.Allegiance.PLAYER:
			return "Player"
		UnitOwnershipComponent.Allegiance.ALLY:
			return "Ally"
		UnitOwnershipComponent.Allegiance.ENEMY:
			return "Enemy"
		_:
			return "Neutral"

func _get_nation_key(nation_data: Resource) -> String:
	if nation_data == null:
		return ""

	return str(nation_data.get("nation_id"))

func get_pairwise_key(nation_a: Resource, nation_b: Resource) -> String:
	var nation_a_id = _get_nation_key(nation_a)
	var nation_b_id = _get_nation_key(nation_b)

	if nation_a_id.is_empty() or nation_b_id.is_empty():
		return ""

	var ids = [nation_a_id, nation_b_id]
	ids.sort()
	return "%s|%s" % [ids[0], ids[1]]

func get_known_nation_by_id(nation_id: String) -> Resource:
	for nation in known_nations:
		if nation != null and _get_nation_key(nation) == nation_id:
			return nation

	return null
