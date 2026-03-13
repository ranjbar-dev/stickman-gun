class_name SpawnCalculator
extends RefCounted

# Divides the map into 8 horizontal zones and finds a valid spawn surface in each.
# Called by TerrainGenerator after ground and platforms are placed.

const SPAWN_ZONE_COUNT: int = 8
const MIN_HEADROOM: float = 100.0   # minimum height of platform above ground below it
const MIN_SPAWN_SPACING: float = 300.0


func calculate(
	ground_points: Array[Vector2],
	platforms: Array[Dictionary],
	map_width: float
) -> Array[Vector2]:
	var zone_width: float = map_width / float(SPAWN_ZONE_COUNT)
	var result: Array[Vector2] = []

	for i in range(SPAWN_ZONE_COUNT):
		var zone_x: float = (float(i) + 0.5) * zone_width
		var surface_y: float = _get_spawn_surface(zone_x, ground_points, platforms, map_width)
		# CharacterBody2D origin = feet (capsule bottom at local Y=0), so place directly on surface.
		var candidate := Vector2(zone_x, surface_y)

		# Enforce minimum spacing against ALL previously placed spawns.
		var too_close: bool = false
		for prev in result:
			if candidate.distance_to(prev) < MIN_SPAWN_SPACING:
				too_close = true
				break

		if too_close:
			# Try both zone edges; pick the one that maximises minimum distance to all prior spawns.
			var left_x: float = float(i) * zone_width + 80.0
			var right_x: float = float(i + 1) * zone_width - 80.0
			var left_sy: float = _get_spawn_surface(left_x, ground_points, platforms, map_width)
			var right_sy: float = _get_spawn_surface(right_x, ground_points, platforms, map_width)
			var left_cand := Vector2(left_x, left_sy)
			var right_cand := Vector2(right_x, right_sy)
			var left_min: float = _min_dist_to_all(left_cand, result)
			var right_min: float = _min_dist_to_all(right_cand, result)
			candidate = left_cand if left_min >= right_min else right_cand

		result.append(candidate)

	return result


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

func _get_spawn_surface(
	x: float,
	ground_points: Array[Vector2],
	platforms: Array[Dictionary],
	map_width: float
) -> float:
	var ground_y: float = _get_ground_y_at(x, ground_points, map_width)

	# Prefer a platform in this zone that has enough headroom above it.
	var best_platform_y: float = ground_y
	for plat in platforms:
		if x >= plat.left and x <= plat.right and plat.y < ground_y:
			var headroom: float = _get_ground_y_at(plat.x_center, ground_points, map_width) - plat.y
			if headroom >= MIN_HEADROOM and plat.y < best_platform_y:
				best_platform_y = plat.y

	return best_platform_y


func _min_dist_to_all(point: Vector2, others: Array[Vector2]) -> float:
	var min_d: float = INF
	for other in others:
		var d: float = point.distance_to(other)
		if d < min_d:
			min_d = d
	return min_d


func _get_ground_y_at(x: float, ground_points: Array[Vector2], map_width: float) -> float:
	if ground_points.is_empty():
		return 900.0
	var clamped_x: float = clamp(x, 0.0, map_width)
	for i in range(ground_points.size() - 1):
		var a: Vector2 = ground_points[i]
		var b: Vector2 = ground_points[i + 1]
		if clamped_x >= a.x and clamped_x <= b.x:
			var t: float = (clamped_x - a.x) / (b.x - a.x)
			return lerp(a.y, b.y, t)
	return ground_points.back().y
