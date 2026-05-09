class_name HitboxMath
extends RefCounted

static func get_hitbox_rect(node: Node2D) -> Rect2:
	var hitbox = get_hitbox_area(node)

	if hitbox == null:
		return Rect2(node.global_position - Vector2(35.0, 35.0), Vector2(70.0, 70.0))

	var collision_shape = hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D

	if collision_shape == null or collision_shape.shape == null:
		return Rect2(hitbox.global_position - Vector2(35.0, 35.0), Vector2(70.0, 70.0))

	if collision_shape.shape is RectangleShape2D:
		var shape = collision_shape.shape as RectangleShape2D
		return Rect2(hitbox.global_position - shape.size / 2.0, shape.size)

	if collision_shape.shape is CircleShape2D:
		var shape = collision_shape.shape as CircleShape2D
		var diameter = shape.radius * 2.0
		return Rect2(
			hitbox.global_position - Vector2(shape.radius, shape.radius),
			Vector2(diameter, diameter)
		)

	return Rect2(hitbox.global_position - Vector2(35.0, 35.0), Vector2(70.0, 70.0))

static func contains_point(node: Node2D, point: Vector2) -> bool:
	var hitbox = get_hitbox_area(node)

	if hitbox == null:
		return node.global_position.distance_to(point) <= 35.0

	var collision_shape = hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D

	if collision_shape == null or collision_shape.shape == null:
		return hitbox.global_position.distance_to(point) <= 35.0

	if collision_shape.shape is RectangleShape2D:
		return get_hitbox_rect(node).has_point(point)

	if collision_shape.shape is CircleShape2D:
		var shape = collision_shape.shape as CircleShape2D
		return hitbox.global_position.distance_to(point) <= shape.radius

	return node.global_position.distance_to(point) <= 35.0

static func distance_from_point_to_hitbox(point: Vector2, node: Node2D) -> float:
	var hitbox = get_hitbox_area(node)

	if hitbox == null:
		return point.distance_to(node.global_position)

	var collision_shape = hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D

	if collision_shape == null or collision_shape.shape == null:
		return point.distance_to(hitbox.global_position)

	if collision_shape.shape is RectangleShape2D:
		var rect = get_hitbox_rect(node)
		var closest_point = point.clamp(rect.position, rect.position + rect.size)
		return point.distance_to(closest_point)

	if collision_shape.shape is CircleShape2D:
		var shape = collision_shape.shape as CircleShape2D
		var center_distance = point.distance_to(hitbox.global_position)
		return max(0.0, center_distance - shape.radius)

	return point.distance_to(node.global_position)

static func get_hitbox_area(node: Node2D) -> Area2D:
	if node.has_method("get_hitbox"):
		return node.get_hitbox() as Area2D

	return node.get_node_or_null("Hitbox") as Area2D
