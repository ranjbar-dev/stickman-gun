class_name TerrainGenerator
extends Node2D

# Procedural terrain generator for StickFight LAN — Phase 3.
# Call generate(seed_value) to rebuild all terrain as child nodes.

const MAP_WIDTH: float = 6000.0
const MAP_TOP: float = -200.0
const MAP_BOTTOM: float = 1200.0

const GROUND_Y_MIN: float = 800.0
const GROUND_Y_MAX: float = 950.0
const GROUND_POINTS_MIN: int = 10
const GROUND_POINTS_MAX: int = 14

const PLATFORM_COUNT_MIN: int = 4
const PLATFORM_COUNT_MAX: int = 8
const PLATFORM_WIDTH_MIN: float = 100.0
const PLATFORM_WIDTH_MAX: float = 250.0
const PLATFORM_Y_MIN: float = 400.0
const PLATFORM_Y_MAX: float = 700.0
const PLATFORM_MIN_SPACING: float = 150.0
# Max height a platform may sit above its nearest reachable surface below.
# Must stay below the theoretical max jump height:
#   h_max = JUMP_VELOCITY² / (2 × GRAVITY) = 400² / (2 × 980) ≈ 81.6 px
# Using 75 px for a comfortable safety margin.
const PLATFORM_MAX_HEIGHT_DIFF: float = 75.0

const COVER_WALL_COUNT_MIN: int = 2
const COVER_WALL_COUNT_MAX: int = 4
const COVER_WALL_HEIGHT_MIN: float = 50.0
const COVER_WALL_HEIGHT_MAX: float = 100.0

const DEATH_ZONE_Y: float = 1100.0
const LINE_WIDTH: float = 3.0
const LINE_COLOR: Color = Color(0.9, 0.9, 0.9, 1.0)

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Terrain data exposed for external use (e.g. spawn calculator, test scene).
var ground_points: Array[Vector2] = []
var platforms: Array[Dictionary] = []   # {x_center, y, width, left, right}
var cover_walls: Array[Dictionary] = [] # {x, y_top, y_bottom}

# Outputs populated after generate().
var spawn_points: Array[Vector2] = []
var weapon_spawns: Array[Dictionary] = [] # {position: Vector2, weapon_type: String}


# ------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------

func generate(seed_value: int) -> void:
	rng.seed = seed_value

	# Remove all previously generated child nodes.
	for child in get_children():
		child.queue_free()

	ground_points.clear()
	platforms.clear()
	cover_walls.clear()
	spawn_points.clear()
	weapon_spawns.clear()

	_generate_ground()
	_generate_platforms()
	_generate_cover_walls()
	_generate_boundaries()
	_generate_death_zone()
	_calculate_spawn_points()
	_calculate_weapon_spawns()


# ------------------------------------------------------------------
# Ground
# ------------------------------------------------------------------

func _generate_ground() -> void:
	var num_points: int = rng.randi_range(GROUND_POINTS_MIN, GROUND_POINTS_MAX)
	var spacing: float = MAP_WIDTH / float(num_points - 1)

	for i in range(num_points):
		var x: float = i * spacing
		var y: float = rng.randf_range(GROUND_Y_MIN, GROUND_Y_MAX)
		ground_points.append(Vector2(x, y))

	var ground_body := StaticBody2D.new()
	ground_body.name = "Ground"
	add_child(ground_body)

	# Polygon: top edge = ground line, then extend down to MAP_BOTTOM to fill.
	var poly_pts := PackedVector2Array()
	for pt in ground_points:
		poly_pts.append(pt)
	poly_pts.append(Vector2(MAP_WIDTH, MAP_BOTTOM))
	poly_pts.append(Vector2(0.0, MAP_BOTTOM))

	var col_poly := CollisionPolygon2D.new()
	col_poly.polygon = poly_pts
	ground_body.add_child(col_poly)

	var line := Line2D.new()
	line.width = LINE_WIDTH
	line.default_color = LINE_COLOR
	for pt in ground_points:
		line.add_point(pt)
	ground_body.add_child(line)


# ------------------------------------------------------------------
# Platforms
# ------------------------------------------------------------------

func _generate_platforms() -> void:
	var count: int = rng.randi_range(PLATFORM_COUNT_MIN, PLATFORM_COUNT_MAX)
	var max_attempts: int = count * 10
	var attempts: int = 0

	while platforms.size() < count and attempts < max_attempts:
		attempts += 1
		var width: float = rng.randf_range(PLATFORM_WIDTH_MIN, PLATFORM_WIDTH_MAX)
		var half_w: float = width * 0.5
		var x_center: float = rng.randf_range(half_w + 100.0, MAP_WIDTH - half_w - 100.0)
		var y: float = rng.randf_range(PLATFORM_Y_MIN, PLATFORM_Y_MAX)

		# Enforce minimum spacing between platform centres.
		var too_close: bool = false
		for existing in platforms:
			var edge_gap: float = abs(x_center - existing.x_center) - half_w - existing.width * 0.5
			if edge_gap < PLATFORM_MIN_SPACING:
				too_close = true
				break

		if too_close:
			continue

		# Verify jumpability: nearest surface below must be within PLATFORM_MAX_HEIGHT_DIFF.
		var surface_below: float = _get_surface_y_below(x_center, y)
		if surface_below - y > PLATFORM_MAX_HEIGHT_DIFF:
			continue

		var plat := {
			"x_center": x_center,
			"y": y,
			"width": width,
			"left": x_center - half_w,
			"right": x_center + half_w
		}
		platforms.append(plat)
		_create_platform_node(plat)


func _create_platform_node(plat: Dictionary) -> void:
	var body := StaticBody2D.new()
	body.name = "Platform"
	add_child(body)

	var shape := BoxShape2D.new()
	shape.size = Vector2(plat.width, 8.0)
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(plat.x_center, plat.y)
	body.add_child(col)

	var line := Line2D.new()
	line.width = LINE_WIDTH
	line.default_color = LINE_COLOR
	line.add_point(Vector2(plat.left, plat.y))
	line.add_point(Vector2(plat.right, plat.y))
	body.add_child(line)


# ------------------------------------------------------------------
# Cover walls
# ------------------------------------------------------------------

func _generate_cover_walls() -> void:
	var count: int = rng.randi_range(COVER_WALL_COUNT_MIN, COVER_WALL_COUNT_MAX)

	# Build a list of candidate surfaces (x, y, usable_half_width).
	var surfaces: Array[Dictionary] = []
	for pt in ground_points:
		surfaces.append({"x": pt.x, "y": pt.y, "half_w": 200.0})
	for plat in platforms:
		surfaces.append({"x": plat.x_center, "y": plat.y, "half_w": plat.width * 0.4})

	if surfaces.is_empty():
		return

	for _i in range(count):
		var height: float = rng.randf_range(COVER_WALL_HEIGHT_MIN, COVER_WALL_HEIGHT_MAX)
		var surf: Dictionary = surfaces[rng.randi_range(0, surfaces.size() - 1)]
		var x: float = clamp(
			rng.randf_range(surf.x - surf.half_w, surf.x + surf.half_w),
			50.0, MAP_WIDTH - 50.0
		)
		var y_bottom: float = surf.y
		var y_top: float = surf.y - height
		cover_walls.append({"x": x, "y_top": y_top, "y_bottom": y_bottom})
		_create_cover_wall_node(x, y_top, y_bottom, height)


func _create_cover_wall_node(x: float, y_top: float, y_bottom: float, height: float) -> void:
	var body := StaticBody2D.new()
	body.name = "CoverWall"
	add_child(body)

	var shape := BoxShape2D.new()
	shape.size = Vector2(8.0, height)
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(x, (y_top + y_bottom) * 0.5)
	body.add_child(col)

	var line := Line2D.new()
	line.width = LINE_WIDTH
	line.default_color = LINE_COLOR
	line.add_point(Vector2(x, y_bottom))
	line.add_point(Vector2(x, y_top))
	body.add_child(line)


# ------------------------------------------------------------------
# Boundary walls
# ------------------------------------------------------------------

func _generate_boundaries() -> void:
	_create_boundary_wall(-10.0)
	_create_boundary_wall(MAP_WIDTH + 10.0)


func _create_boundary_wall(x: float) -> void:
	var body := StaticBody2D.new()
	body.name = "BoundaryWall"
	add_child(body)

	var shape := BoxShape2D.new()
	shape.size = Vector2(20.0, MAP_BOTTOM - MAP_TOP + 200.0)
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(x, (MAP_TOP + MAP_BOTTOM) * 0.5)
	body.add_child(col)


# ------------------------------------------------------------------
# Death zone
# ------------------------------------------------------------------

func _generate_death_zone() -> void:
	var area := Area2D.new()
	area.name = "DeathZone"
	add_child(area)

	var shape := BoxShape2D.new()
	shape.size = Vector2(MAP_WIDTH + 400.0, 40.0)
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(MAP_WIDTH * 0.5, DEATH_ZONE_Y)
	area.add_child(col)

	area.body_entered.connect(_on_death_zone_body_entered)


func _on_death_zone_body_entered(body: Node2D) -> void:
	if body.has_node("HitboxManager"):
		body.get_node("HitboxManager").take_body_hit(Vector2.ZERO, Vector2.DOWN, 999)


# ------------------------------------------------------------------
# Spawn points
# ------------------------------------------------------------------

func _calculate_spawn_points() -> void:
	var calculator := SpawnCalculator.new()
	spawn_points = calculator.calculate(ground_points, platforms, MAP_WIDTH)


# ------------------------------------------------------------------
# Weapon spawns
# ------------------------------------------------------------------

func _calculate_weapon_spawns() -> void:
	var count: int = rng.randi_range(3, 5)
	var weapon_types: Array[String] = ["sniper", "shotgun", "grenade"]
	var min_dist: float = 200.0
	var attempts: int = 0

	while weapon_spawns.size() < count and attempts < 60:
		attempts += 1
		var x: float = rng.randf_range(100.0, MAP_WIDTH - 100.0)
		# Place weapons on platform surfaces when available, otherwise ground.
		var surface_y: float = _get_best_surface_y(x)
		var pos := Vector2(x, surface_y - 10.0)

		# Keep away from spawn points.
		var too_close: bool = false
		for sp in spawn_points:
			if pos.distance_to(sp) < min_dist:
				too_close = true
				break

		if too_close:
			continue

		weapon_spawns.append({
			"position": pos,
			"weapon_type": weapon_types[rng.randi_range(0, weapon_types.size() - 1)]
		})

	# Fallback: guarantee the DoD minimum of 3 weapon spawns.
	# Distribute remaining slots evenly across ground points, ignoring proximity constraints.
	if weapon_spawns.size() < 3 and not ground_points.is_empty():
		var spacing: float = MAP_WIDTH / 4.0
		var fallback_idx: int = 0
		while weapon_spawns.size() < 3:
			var fx: float = spacing * float(fallback_idx + 1)
			fx = clamp(fx, 100.0, MAP_WIDTH - 100.0)
			var fy: float = _get_best_surface_y(fx) - 10.0
			weapon_spawns.append({
				"position": Vector2(fx, fy),
				"weapon_type": weapon_types[fallback_idx % weapon_types.size()]
			})
			fallback_idx += 1


# ------------------------------------------------------------------
# Geometry helpers
# ------------------------------------------------------------------

func _get_ground_y_at(x: float) -> float:
	if ground_points.is_empty():
		return GROUND_Y_MAX
	var clamped_x: float = clamp(x, 0.0, MAP_WIDTH)
	for i in range(ground_points.size() - 1):
		var a: Vector2 = ground_points[i]
		var b: Vector2 = ground_points[i + 1]
		if clamped_x >= a.x and clamped_x <= b.x:
			var t: float = (clamped_x - a.x) / (b.x - a.x)
			return lerp(a.y, b.y, t)
	return ground_points.back().y


func _get_surface_y_below(x: float, above_y: float) -> float:
	var best_y: float = _get_ground_y_at(x)
	for plat in platforms:
		if x >= plat.left and x <= plat.right and plat.y > above_y and plat.y < best_y:
			best_y = plat.y
	return best_y


# Returns the surface Y that a weapon pickup should sit on at the given X.
# Uses exact platform bounds so weapons always land on solid surfaces.
func _get_best_surface_y(x: float) -> float:
	var ground_y: float = _get_ground_y_at(x)
	var best_platform_y: float = ground_y
	for plat in platforms:
		if x >= plat.left and x <= plat.right:
			if plat.y < best_platform_y:
				best_platform_y = plat.y
	return best_platform_y
