extends Node2D
class_name UnitSubtypeIndicator

enum Subtype {
	AUTO,
	INFANTRY,
	RANGED,
	CAVALRY,
	AIR,
	SIEGE,
	CHAMPION,
	BUILDING,
}

const FALLBACK_TILE_SIZE := 64.0

const SHAPE_COLORS := {
	Subtype.INFANTRY: Color(0.72, 0.88, 1.0, 0.9),
	Subtype.RANGED: Color(0.72, 1.0, 0.72, 0.9),
	Subtype.CAVALRY: Color(1.0, 0.86, 0.45, 0.9),
	Subtype.AIR: Color(0.75, 0.75, 1.0, 0.9),
	Subtype.SIEGE: Color(1.0, 0.55, 0.38, 0.9),
	Subtype.CHAMPION: Color(1.0, 0.95, 0.72, 0.95),
	Subtype.BUILDING: Color(0.8, 0.8, 0.8, 0.9),
}

const BORDER_COLOR := Color(0.05, 0.05, 0.05, 0.95)

var subtype: Subtype = Subtype.AUTO
var fallback_size := Vector2(FALLBACK_TILE_SIZE, FALLBACK_TILE_SIZE)


func setup(data_or_subtype: Variant, footprint_size: Vector2i = Vector2i.ONE) -> void:
	if data_or_subtype is Resource:
		subtype = _get_subtype_for_data(data_or_subtype)
	elif typeof(data_or_subtype) == TYPE_INT:
		subtype = _coerce_subtype(int(data_or_subtype))
	else:
		subtype = Subtype.AUTO

	fallback_size = Vector2(maxi(footprint_size.x, 1), maxi(footprint_size.y, 1)) * FALLBACK_TILE_SIZE
	visible = subtype != Subtype.AUTO
	queue_redraw()


func _draw() -> void:
	if subtype == Subtype.AUTO:
		return

	var draw_size := _get_draw_size()
	var shortest_side := minf(draw_size.x, draw_size.y)
	var scale_factor := clampf(shortest_side / FALLBACK_TILE_SIZE, 0.75, 1.75)

	var color: Color = SHAPE_COLORS.get(subtype, Color.WHITE)

	# Same top-right positioning style as your original subtype indicator.
	var top_right := Vector2(
		draw_size.x * 0.5 - 5.0 * scale_factor,
		-draw_size.y * 0.5 + 5.0 * scale_factor
	)

	var radius := 8.0 * scale_factor
	var center := top_right - Vector2(radius, -radius)
	var line_width := 2.0 * scale_factor

	match subtype:
		Subtype.INFANTRY:
			_draw_polygon(
				_regular_polygon(center, radius, 4, PI / 4.0),
				color,
				BORDER_COLOR,
				line_width
			)

		Subtype.RANGED:
			_draw_polygon(
				_regular_polygon(center, radius, 3, -PI / 2.0),
				color,
				BORDER_COLOR,
				line_width
			)

		Subtype.CAVALRY:
			_draw_polygon(
				_regular_polygon(center, radius, 4, 0.0),
				color,
				BORDER_COLOR,
				line_width
			)

		Subtype.AIR:
			draw_circle(center, radius, color)
			draw_arc(center, radius, 0.0, TAU, 48, BORDER_COLOR, line_width, true)

		Subtype.SIEGE:
			_draw_polygon(
				_regular_polygon(center, radius, 6, PI / 6.0),
				color,
				BORDER_COLOR,
				line_width
			)

		Subtype.CHAMPION:
			_draw_polygon(
				_star_points(center, radius, radius * 0.45, 5),
				color,
				BORDER_COLOR,
				line_width
			)

		Subtype.BUILDING:
			_draw_polygon(
				_house_points(center, radius),
				color,
				BORDER_COLOR,
				line_width
			)


func _get_draw_size() -> Vector2:
	var parent_node = get_parent()
	if parent_node == null:
		return fallback_size

	var hitbox_collision = parent_node.get_node_or_null("Hitbox/CollisionShape2D") as CollisionShape2D
	if hitbox_collision != null:
		if hitbox_collision.shape is RectangleShape2D:
			return (hitbox_collision.shape as RectangleShape2D).size
		if hitbox_collision.shape is CircleShape2D:
			var radius = (hitbox_collision.shape as CircleShape2D).radius
			return Vector2(radius * 2.0, radius * 2.0)

	var sprite = parent_node.get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null and sprite.texture != null:
		var sprite_scale = Vector2(absf(sprite.scale.x), absf(sprite.scale.y))
		return sprite.texture.get_size() * sprite_scale

	return fallback_size


func _coerce_subtype(value: int) -> Subtype:
	if value == Subtype.AUTO or SHAPE_COLORS.has(value):
		return value as Subtype

	return Subtype.AUTO


func _get_subtype_for_data(data: Resource) -> Subtype:
	if data == null:
		return Subtype.AUTO

	var domain := int(data.get("unit_domain")) as UnitClassification.UnitDomain

	match domain:
		UnitClassification.UnitDomain.INFANTRY:
			return Subtype.INFANTRY

		UnitClassification.UnitDomain.RANGED:
			return Subtype.RANGED

		UnitClassification.UnitDomain.CAVALRY:
			return Subtype.CAVALRY

		UnitClassification.UnitDomain.AIR:
			return Subtype.AIR

		UnitClassification.UnitDomain.SIEGE:
			return Subtype.SIEGE

		UnitClassification.UnitDomain.CHAMPION:
			return Subtype.CHAMPION

		UnitClassification.UnitDomain.STRUCTURE:
			return Subtype.BUILDING

		_:
			return Subtype.AUTO


func _draw_polygon(points: PackedVector2Array, fill_color: Color, border_color: Color, width: float) -> void:
	draw_colored_polygon(points, fill_color)

	for index in range(points.size()):
		var start := points[index]
		var end := points[(index + 1) % points.size()]
		draw_line(start, end, border_color, width, true)


func _regular_polygon(center: Vector2, radius: float, sides: int, angle_offset: float = 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()

	for index in range(sides):
		var angle := angle_offset + TAU * float(index) / float(sides)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	return points


func _star_points(center: Vector2, outer_radius: float, inner_radius: float, point_count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var total_points := point_count * 2

	for index in range(total_points):
		var point_radius := outer_radius if index % 2 == 0 else inner_radius
		var angle := -PI * 0.5 + float(index) * TAU / float(total_points)
		points.append(center + Vector2(cos(angle), sin(angle)) * point_radius)

	return points


func _house_points(center: Vector2, radius: float) -> PackedVector2Array:
	var w := radius * 0.9
	var h := radius * 0.9

	return PackedVector2Array([
		center + Vector2(-w, h * 0.45),
		center + Vector2(-w, -h * 0.15),
		center + Vector2(0.0, -h),
		center + Vector2(w, -h * 0.15),
		center + Vector2(w, h * 0.45),
	])
