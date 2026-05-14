extends Node
class_name WorldGenerator

@export_group("Seeding")
@export var world_seed: int = 12345:
	set(value):
		world_seed = value
		if is_inside_tree():
			noise.seed = world_seed

@export_group("Region Settings")
@export var region_seed_count: int = 27
@export var noise_scale: float = 0.05
@export var noise_influence: float = 15.0
@export var regions: Array[RegionDefinition] = []

@export_group("Start Zone")
@export var inner_start_clear_radius: int = 18
@export var starter_resource_ring_radius: int = 35
@export var clear_center_on_generate: bool = true

@export_group("Resources")
@export var max_total_resource_nodes: int = 400
@export var minimum_resource_spacing_tiles: int = 6
@export var starter_resource_spacing_tiles: int = 12
@export var resource_node_scene: PackedScene = preload("res://scenes/resources/resource_node.tscn")

@export_group("Props")
@export var max_total_props: int = 2000
@export var minimum_prop_spacing_tiles: int = 3
@export var prop_placeholder_scene: PackedScene = preload("res://scenes/ui/placeholder_prop.tscn")

# Runtime state
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var noise: FastNoiseLite = FastNoiseLite.new()
var grid_manager: GridManager
var occupancy_manager: Node

var resource_parent: Node
var prop_parent: Node
var label_parent: Node

var total_resources_spawned: int = 0
var total_starter_resources_spawned: int = 0
var total_props_spawned: int = 0
var resource_cells := {} # cell -> true
var prop_cells := {} # cell -> true

class RegionSeed:
	var position: Vector2i
	var definition: RegionDefinition
	var weight: float

var active_seeds: Array[RegionSeed] = []

func _ready():
	add_to_group("world_generator")
	grid_manager = get_tree().get_first_node_in_group("grid_manager")
	occupancy_manager = get_tree().get_first_node_in_group("grid_occupancy_manager")
	
	_setup_containers()
	
	if regions.is_empty():
		_create_default_regions()
	
	call_deferred("generate_world")

func _setup_containers():
	if resource_parent == null:
		resource_parent = Node2D.new()
		resource_parent.name = "GeneratedResources"
		add_child(resource_parent)
	
	if prop_parent == null:
		prop_parent = Node2D.new()
		prop_parent.name = "GeneratedProps"
		add_child(prop_parent)

	if label_parent == null:
		label_parent = Node2D.new()
		label_parent.name = "GeneratedLabels"
		add_child(label_parent)

func generate_world():
	if grid_manager == null:
		grid_manager = get_tree().get_first_node_in_group("grid_manager")
	
	if grid_manager == null:
		print("ERROR: GridManager not found!")
		return
		
	print("Starting World Generation (Seed: ", world_seed, ")")
	print("Grid Dimensions: ", grid_manager.grid_width, "x", grid_manager.grid_height)
	
	# Reset state
	rng.seed = world_seed
	noise.seed = world_seed
	noise.frequency = noise_scale
	
	total_resources_spawned = 0
	total_starter_resources_spawned = 0
	total_props_spawned = 0
	resource_cells.clear()
	prop_cells.clear()
	
	_clear_old_generation()
	grid_manager.clear_all_tile_data()
	
	# Step 1: Regions
	_generate_region_seeds()
	print("Initial Region Count: ", regions.size())
	print("Active Seeds: ", active_seeds.size())
	
	if active_seeds.is_empty():
		print("WARNING: No region seeds generated! Forcing default regions...")
		_create_default_regions()
		_generate_region_seeds()
		print("Active Seeds after retry: ", active_seeds.size())

	_assign_tiles_to_regions()
	
	# Step 2: Start Zone Protection
	if clear_center_on_generate:
		_clear_start_zone()
		_place_starter_resources()
	
	# Step 3: Props and Resources
	_place_props_and_resources()
	
	# Step 4: Region labels
	_generate_region_labels()
	
	grid_manager.queue_redraw()
	print("World Generation Complete. Resources: ", total_resources_spawned, ", Starter: ", total_starter_resources_spawned, ", Props: ", total_props_spawned)

func _clear_old_generation():
	for child in resource_parent.get_children():
		child.queue_free()
	for child in prop_parent.get_children():
		child.queue_free()
	for child in label_parent.get_children():
		child.queue_free()

func _generate_region_seeds():
	active_seeds.clear()
	
	var counts = {
		RegionDefinition.RegionType.PLAINS: 6,
		RegionDefinition.RegionType.FOREST: 6,
		RegionDefinition.RegionType.ROCKY: 4,
		RegionDefinition.RegionType.SWAMP: 3,
		RegionDefinition.RegionType.MOUNTAIN: 4,
		RegionDefinition.RegionType.VOLCANIC: 2,
		RegionDefinition.RegionType.DEADLANDS: 2
	}
	
	for r_type in counts.keys():
		var def = _get_definition_for_type(r_type)
		if def == null:
			print("Could not find definition for region type: ", r_type)
			continue
		
		for i in range(counts[r_type]):
			var s = RegionSeed.new()
			s.position = Vector2i(
				rng.randi_range(0, grid_manager.grid_width - 1),
				rng.randi_range(0, grid_manager.grid_height - 1)
			)
			s.definition = def
			s.weight = rng.randf_range(0.8, 1.2)
			active_seeds.append(s)

func _assign_tiles_to_regions():
	var tiles_assigned = 0
	for y in range(grid_manager.grid_height):
		for x in range(grid_manager.grid_width):
			var cell = Vector2i(x, y)
			var best_seed = null
			var best_score = INF
			
			var noise_val = noise.get_noise_2d(x, y) * noise_influence
			
			for s in active_seeds:
				var dist = cell.distance_to(s.position)
				var score = (dist + noise_val) / s.weight
				
				if score < best_score:
					best_score = score
					best_seed = s
			
			if best_seed:
				tiles_assigned += 1
				var info = {
					"region_type": best_seed.definition.region_type,
					"debug_color": best_seed.definition.debug_color,
					"terrain_color": best_seed.definition.terrain_color if "terrain_color" in best_seed.definition else best_seed.definition.debug_color,
					"definition": best_seed.definition,
					"is_buildable": best_seed.definition.is_naturally_buildable,
					"is_walkable": best_seed.definition.is_naturally_walkable
				}
				grid_manager.set_tile_info(cell, info)
	print("Assigned ", tiles_assigned, " tiles to regions.")

func _clear_start_zone():
	var center = Vector2i(
		floori(float(grid_manager.grid_width) / 2.0),
		floori(float(grid_manager.grid_height) / 2.0)
	)
	var plains_def = _get_definition_for_type(RegionDefinition.RegionType.PLAINS)
	if plains_def == null:
		print("ERROR: Plains definition not found for start zone!")
		return
		
	# Clear inner build zone
	for y in range(center.y - inner_start_clear_radius, center.y + inner_start_clear_radius + 1):
		for x in range(center.x - inner_start_clear_radius, center.x + inner_start_clear_radius + 1):
			var cell = Vector2i(x, y)
			if grid_manager.is_cell_in_bounds(cell):
				var info = {
					"region_type": RegionDefinition.RegionType.PLAINS,
					"debug_color": plains_def.debug_color,
					"terrain_color": plains_def.terrain_color if "terrain_color" in plains_def else plains_def.debug_color,
					"definition": plains_def,
					"is_buildable": true,
					"is_walkable": true,
					"is_start_zone": true,
					"is_inner_start_zone": true
				}
				grid_manager.set_tile_info(cell, info)
				
	# Clear starter resource ring (prevent blocking terrain/props, but allow resources)
	for y in range(center.y - starter_resource_ring_radius, center.y + starter_resource_ring_radius + 1):
		for x in range(center.x - starter_resource_ring_radius, center.x + starter_resource_ring_radius + 1):
			var cell = Vector2i(x, y)
			if not grid_manager.is_cell_in_bounds(cell): continue
			
			var distance_squared = cell.distance_squared_to(center)
			if (
				distance_squared <= starter_resource_ring_radius * starter_resource_ring_radius
				and distance_squared > inner_start_clear_radius * inner_start_clear_radius
			):
				var info = grid_manager.get_tile_info(cell)
				var def = info.get("definition") as RegionDefinition
				
				# Ensure buildable/walkable for the starter ring
				info["is_buildable"] = true
				info["is_walkable"] = true
				info["is_start_zone"] = true
				
				# If it's a very harsh biome, normalize it slightly to plains or forest
				if def != null and (not def.is_naturally_buildable or not def.is_naturally_walkable):
					info["region_type"] = RegionDefinition.RegionType.PLAINS
					info["definition"] = plains_def
					info["debug_color"] = plains_def.debug_color
					info["terrain_color"] = plains_def.terrain_color if "terrain_color" in plains_def else plains_def.debug_color
				
				grid_manager.set_tile_info(cell, info)

func _place_starter_resources():
	var center = Vector2i(
		floori(float(grid_manager.grid_width) / 2.0),
		floori(float(grid_manager.grid_height) / 2.0)
	)
	var starter_types = [
		BuildingData.ResourceType.WOOD,
		BuildingData.ResourceType.FOOD,
		BuildingData.ResourceType.GOLD,
		BuildingData.ResourceType.STONE,
		BuildingData.ResourceType.METAL
	]
	
	# Try to place each starter resource a few times
	for res_type in starter_types:
		var placed = false
		var attempts = 0
		while not placed and attempts < 50:
			attempts += 1
			var angle = rng.randf() * TAU
			var dist = rng.randf_range(inner_start_clear_radius + 2, starter_resource_ring_radius - 2)
			var cell = center + Vector2i(roundi(cos(angle) * dist), roundi(sin(angle) * dist))
			
			if grid_manager.is_cell_in_bounds(cell):
				if not resource_cells.has(cell):
					if not _has_cell_within_spacing(cell, resource_cells, starter_resource_spacing_tiles):
						_spawn_specific_resource_at(cell, res_type)
						total_starter_resources_spawned += 1
						placed = true

func _spawn_specific_resource_at(cell: Vector2i, type: int):
	var node = resource_node_scene.instantiate()
	node.set("resource_type", type)
	node.global_position = grid_manager.cell_to_world(cell)
	resource_parent.add_child(node)
	
	resource_cells[cell] = true
	total_resources_spawned += 1

func _place_props_and_resources():
	# Use a list of cells and shuffle it for deterministic random distribution
	var cells: Array[Vector2i] = []
	for y in range(grid_manager.grid_height):
		for x in range(grid_manager.grid_width):
			cells.append(Vector2i(x, y))
	
	# Shuffle using our seeded RNG
	_shuffle_array(cells)
	
	for cell in cells:
		if total_resources_spawned >= max_total_resource_nodes and total_props_spawned >= max_total_props:
			break

		var info = grid_manager.get_tile_info(cell)
		var def = info.get("definition") as RegionDefinition
		if def == null: continue
		
		# Skip start zone (resources/props handled by starter logic or blocked)
		if info.get("is_start_zone", false):
			continue
			
		# Try Resources
		if total_resources_spawned < max_total_resource_nodes and not def.resource_weights.is_empty():
			if rng.randf() < def.resource_density:
				if _can_spawn_resource_at(cell, def):
					_spawn_resource_at(cell, def)
					continue # Cell occupied by resource
		
		# Try Props
		if total_props_spawned < max_total_props and not def.prop_weights.is_empty():
			if rng.randf() < def.prop_density:
				if _can_spawn_prop_at(cell, def):
					_spawn_prop_at(cell, def)

func _can_spawn_resource_at(cell: Vector2i, def: RegionDefinition) -> bool:
	if not def.is_naturally_walkable or not def.is_naturally_buildable:
		return false
	
	if _is_too_close_to_resource(cell):
		return false
		
	return true

func _can_spawn_prop_at(cell: Vector2i, def: RegionDefinition) -> bool:
	if not def.is_naturally_walkable:
		return false
		
	if _is_too_close_to_prop(cell):
		return false
		
	return true

func _is_too_close_to_resource(cell: Vector2i) -> bool:
	return _has_cell_within_spacing(cell, resource_cells, minimum_resource_spacing_tiles)

func _is_too_close_to_prop(cell: Vector2i) -> bool:
	return (
		_has_cell_within_spacing(cell, resource_cells, minimum_prop_spacing_tiles)
		or _has_cell_within_spacing(cell, prop_cells, minimum_prop_spacing_tiles)
	)

func _has_cell_within_spacing(cell: Vector2i, occupied_cells: Dictionary, spacing_tiles: int) -> bool:
	if occupied_cells.is_empty() or spacing_tiles <= 0:
		return false

	var search_radius = maxi(spacing_tiles - 1, 0)
	var spacing_squared = spacing_tiles * spacing_tiles

	for y in range(cell.y - search_radius, cell.y + search_radius + 1):
		for x in range(cell.x - search_radius, cell.x + search_radius + 1):
			var occupied_cell = Vector2i(x, y)
			if occupied_cells.has(occupied_cell) and cell.distance_squared_to(occupied_cell) < spacing_squared:
				return true

	return false

func _spawn_resource_at(cell: Vector2i, def: RegionDefinition):
	if def.resource_weights.is_empty(): return
	
	var type = _pick_weighted(def.resource_weights)
	if type != -1:
		_spawn_specific_resource_at(cell, type)

func _spawn_prop_at(cell: Vector2i, def: RegionDefinition):
	if def.prop_weights.is_empty(): return
	
	var type = _pick_weighted(def.prop_weights)
	if type != null:
		var node = prop_placeholder_scene.instantiate()
		node.global_position = grid_manager.cell_to_world(cell)
		prop_parent.add_child(node)
		if node.has_method("setup"):
			node.setup(type)
		
		prop_cells[cell] = true
		total_props_spawned += 1
		
		# If prop blocks, mark it in metadata
		if def.blocks_building or def.blocks_movement:
			var info = grid_manager.get_tile_info(cell)
			if def.blocks_building: info["is_buildable"] = false
			if def.blocks_movement: info["is_walkable"] = false
			grid_manager.set_tile_info(cell, info)

var total_region_blobs: int = 0
var total_labels_drawn: int = 0

func _generate_region_labels():
	# Strategic placement along region borders
	var min_label_spacing = 50.0 # tiles
	var sampling_step = 2 # Check every 2nd tile to speed up detection
	
	total_labels_drawn = 0
	var label_positions := [] # Array of Vector2
	
	# 1. Identify all potential border points
	var potential_points = []
	
	for y in range(0, grid_manager.grid_height, sampling_step):
		for x in range(0, grid_manager.grid_width, sampling_step):
			var cell = Vector2i(x, y)
			var info = grid_manager.get_tile_info(cell)
			var my_type = info.get("region_type")
			if my_type == null: continue
			
			# A border point is a cell that has a neighbor of a different type
			var is_border = false
			for neighbor in grid_manager.get_neighbor_cells(cell, false):
				var n_info = grid_manager.get_tile_info(neighbor)
				if n_info.is_empty(): continue
				if n_info.get("region_type") != my_type:
					is_border = true
					break
			
			if is_border:
				potential_points.append({
					"cell": cell,
					"def": info.get("definition")
				})

	# 2. To keep it deterministic but well-distributed, we iterate and check spacing
	# We use a fixed-seed shuffle or just step through if we want perfect spacing
	_shuffle_array(potential_points) # RNG is already seeded with world_seed
	
	var min_label_spacing_squared = min_label_spacing * min_label_spacing

	for pt in potential_points:
		var pos = Vector2(pt["cell"])
		var too_close = false
		for lp in label_positions:
			if pos.distance_squared_to(lp) < min_label_spacing_squared:
				too_close = true
				break
		
		if not too_close:
			_create_label_at_cell(pt["cell"], pt["def"])
			label_positions.append(pos)
			total_labels_drawn += 1
	
	print("Placed ", total_labels_drawn, " labels along borders.")

func _create_label_at_cell(cell: Vector2i, def: RegionDefinition):
	if def == null: return
	
	var label = Label.new()
	label.text = def.region_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	# Style
	label.modulate = Color(1, 1, 1, 0.6)
	label.add_theme_font_size_override("font_size", 28) # Slightly smaller for multi-labels
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	
	label_parent.add_child(label)
	# Center it
	label.global_position = grid_manager.cell_to_world(cell) - Vector2(100, 20) # Rough initial offset
	
	# Refine position once size is known
	label.resized.connect(func():
		label.global_position = grid_manager.cell_to_world(cell) - label.size / 2.0
	)

func _pick_weighted(weights: Dictionary):
	var total_weight = 0.0
	for w in weights.values():
		total_weight += w
	
	var roll = rng.randf() * total_weight
	var current_weight = 0.0
	
	for key in weights.keys():
		current_weight += weights[key]
		if roll <= current_weight:
			return key
	return null

func _shuffle_array(array: Array):
	for i in range(array.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var temp = array[i]
		array[i] = array[j]
		array[j] = temp

func _get_definition_for_type(type: RegionDefinition.RegionType) -> RegionDefinition:
	for d in regions:
		if d.region_type == type:
			return d
	return null

func _create_default_regions():
	print("Creating default regions...")
	regions.clear()
	var defaults = [
		{"type": RegionDefinition.RegionType.PLAINS, "name": "Plains", "color": Color(0.4, 0.7, 0.3, 0.4), "terrain": Color(0.5, 0.6, 0.3, 1.0), "res": {1: 1.0, 2: 2.0}, "r_dens": 0.02, "prop": {"bush": 1.0, "tree": 0.2}, "p_dens": 0.01},
		{"type": RegionDefinition.RegionType.FOREST, "name": "Forest", "color": Color(0.1, 0.5, 0.1, 0.4), "terrain": Color(0.1, 0.4, 0.1, 1.0), "res": {1: 5.0, 2: 1.0}, "r_dens": 0.04, "prop": {"tree": 5.0}, "p_dens": 0.1},
		{"type": RegionDefinition.RegionType.SWAMP, "name": "Swamp", "color": Color(0.3, 0.3, 0.1, 0.4), "terrain": Color(0.2, 0.25, 0.15, 1.0), "res": {1: 1.0, 2: 1.0}, "r_dens": 0.03, "prop": {"dead_tree": 1.0, "mushroom": 1.0, "reeds": 1.0}, "p_dens": 0.05},
		{"type": RegionDefinition.RegionType.ROCKY, "name": "Rocky", "color": Color(0.5, 0.5, 0.5, 0.4), "terrain": Color(0.4, 0.4, 0.4, 1.0), "res": {4: 3.0, 5: 2.0, 3: 1.0}, "r_dens": 0.04, "prop": {"rock": 2.0}, "p_dens": 0.08},
		{"type": RegionDefinition.RegionType.MOUNTAIN, "name": "Mountain", "color": Color(0.3, 0.3, 0.3, 0.4), "terrain": Color(0.2, 0.2, 0.2, 1.0), "res": {4: 5.0, 5: 5.0}, "r_dens": 0.05, "build": false, "walk": false, "prop": {"rock": 5.0}, "p_dens": 0.1},
		{"type": RegionDefinition.RegionType.VOLCANIC, "name": "Volcanic", "color": Color(0.7, 0.2, 0.1, 0.4), "terrain": Color(0.15, 0.1, 0.1, 1.0), "res": {5: 4.0, 4: 4.0, 3: 2.0}, "r_dens": 0.04, "build": false, "prop": {"lava_crack": 1.0, "rock": 1.0, "dead_tree": 0.5}, "p_dens": 0.06},
		{"type": RegionDefinition.RegionType.DEADLANDS, "name": "Deadlands", "color": Color(0.2, 0.2, 0.2, 0.4), "terrain": Color(0.1, 0.1, 0.1, 1.0), "res": {4: 2.0, 5: 2.0, 3: 2.0}, "r_dens": 0.02, "prop": {"dead_tree": 1.0, "bones": 1.0, "ruins": 1.0, "black_crystal": 0.5}, "p_dens": 0.04}
	]
	
	for d in defaults:
		var reg = RegionDefinition.new()
		reg.region_type = d["type"]
		reg.region_name = d["name"]
		reg.debug_color = d["color"]
		if d.has("terrain"): reg.terrain_color = d["terrain"]
		reg.resource_weights = d["res"]
		reg.resource_density = d["r_dens"]
		reg.prop_weights = d.get("prop", {})
		reg.prop_density = d.get("p_dens", 0.05)
		if d.has("build"): reg.is_naturally_buildable = d["build"]
		if d.has("walk"): reg.is_naturally_walkable = d["walk"]
		regions.append(reg)
