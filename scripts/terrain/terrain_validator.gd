class_name TerrainValidator
extends RefCounted

# Validates all Phase 3 Definition of Done criteria against a TerrainGenerator.
# Usage:
#   var v := TerrainValidator.new()
#   v.run(generator, seed_value)   # prints full pass/fail report

# Must match terrain_generator.gd constants.
const MAX_JUMP_HEIGHT: float = 75.0   # conservative; see PLATFORM_MAX_HEIGHT_DIFF
const SURFACE_SNAP_TOLERANCE: float = 2.0

# -----------------------------------------------------------------------
# Public entry-point
# -----------------------------------------------------------------------

## Runs all Phase 3 DoD checks for [param seed_value] using [param gen].
## Prints a formatted report and returns true if every check passed.
func run(gen: TerrainGenerator, seed_value: int) -> bool:
	gen.generate(seed_value)

	var results: Array[Dictionary] = []
	results.append(_check_ground(gen))
	results.append(_check_platforms(gen))
	results.append(_check_platform_reachability(gen))
	results.append(_check_cover_walls(gen))
	results.append(_check_death_zone(gen))
	results.append(_check_spawn_count(gen))
	results.append(_check_spawn_on_surfaces(gen))
	results.append(_check_weapon_spawns(gen))
	results.append(_check_determinism(gen, seed_value))

	_print_report(seed_value, results)

	for r in results:
		if not r.passed:
			return false
	return true


## Runs [param seeds] sequentially and returns the number of seeds that pass all checks.
func run_batch(gen: TerrainGenerator, seeds: Array[int]) -> int:
	var pass_count: int = 0
	print("\n========================================")
	print("TerrainValidator — batch of %d seeds" % seeds.size())
	print("========================================")
	for s in seeds:
		if run(gen, s):
			pass_count += 1
	print("\n[Validator] %d / %d seeds passed all Phase 3 DoD checks." % [pass_count, seeds.size()])
	return pass_count


# -----------------------------------------------------------------------
# Individual checks
# -----------------------------------------------------------------------

func _check_ground(gen: TerrainGenerator) -> Dictionary:
	var n: int = gen.ground_points.size()
	var ok: bool = n >= TerrainGenerator.GROUND_POINTS_MIN and n <= TerrainGenerator.GROUND_POINTS_MAX
	return _result(
		"Ground point count [10–14]",
		ok,
		"got %d points" % n
	)


func _check_platforms(gen: TerrainGenerator) -> Dictionary:
	var n: int = gen.platforms.size()
	var ok: bool = n >= TerrainGenerator.PLATFORM_COUNT_MIN and n <= TerrainGenerator.PLATFORM_COUNT_MAX
	return _result(
		"Platform count [4–8]",
		ok,
		"got %d platforms" % n
	)


func _check_platform_reachability(gen: TerrainGenerator) -> Dictionary:
	# Every platform must have a reachable surface (ground or lower platform) within
	# MAX_JUMP_HEIGHT below it. Mirrors the placement guard in terrain_generator.gd.
	var bad: Array[String] = []
	for plat in gen.platforms:
		var surface_below: float = _get_surface_y_below(gen, plat.x_center, plat.y)
		var diff: float = surface_below - plat.y
		if diff > MAX_JUMP_HEIGHT:
			bad.append("plat@(%.0f,%.0f) diff=%.1f" % [plat.x_center, plat.y, diff])
	var ok: bool = bad.is_empty()
	return _result(
		"All platforms reachable (height diff ≤ %.0f px)" % MAX_JUMP_HEIGHT,
		ok,
		"" if ok else "unreachable: " + ", ".join(bad)
	)


func _check_cover_walls(gen: TerrainGenerator) -> Dictionary:
	var n: int = gen.cover_walls.size()
	var ok: bool = n >= TerrainGenerator.COVER_WALL_COUNT_MIN and n <= TerrainGenerator.COVER_WALL_COUNT_MAX
	return _result(
		"Cover wall count [2–4]",
		ok,
		"got %d walls" % n
	)


func _check_death_zone(gen: TerrainGenerator) -> Dictionary:
	var found: bool = false
	for child in gen.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is Area2D and child.name == "DeathZone":
			found = true
			break
	return _result(
		"Death zone exists (Area2D 'DeathZone')",
		found,
		"" if found else "no DeathZone child found"
	)


func _check_spawn_count(gen: TerrainGenerator) -> Dictionary:
	var n: int = gen.spawn_points.size()
	var ok: bool = n == SpawnCalculator.SPAWN_ZONE_COUNT
	return _result(
		"Spawn point count == %d" % SpawnCalculator.SPAWN_ZONE_COUNT,
		ok,
		"got %d spawn points" % n
	)


func _check_spawn_on_surfaces(gen: TerrainGenerator) -> Dictionary:
	var bad: Array[String] = []
	for i in range(gen.spawn_points.size()):
		var sp: Vector2 = gen.spawn_points[i]
		var surf: float = _get_best_surface_y_at(gen, sp.x)
		var delta: float = absf(sp.y - surf)
		if delta > SURFACE_SNAP_TOLERANCE:
			bad.append("SP%d@(%.0f,%.0f) surf=%.0f Δ=%.1f" % [i, sp.x, sp.y, surf, delta])
	var ok: bool = bad.is_empty()
	return _result(
		"All spawn points on valid surfaces (±%.0f px)" % SURFACE_SNAP_TOLERANCE,
		ok,
		"" if ok else "off-surface: " + ", ".join(bad)
	)


func _check_weapon_spawns(gen: TerrainGenerator) -> Dictionary:
	var n: int = gen.weapon_spawns.size()
	var ok: bool = n >= 3 and n <= 5
	return _result(
		"Weapon spawn count [3–5]",
		ok,
		"got %d weapon spawns" % n
	)


func _check_determinism(gen: TerrainGenerator, seed_value: int) -> Dictionary:
	# Record state from first generate() (already called before this method).
	var spawns_a: Array[Vector2] = gen.spawn_points.duplicate()
	var ground_count_a: int = gen.ground_points.size()
	var platform_count_a: int = gen.platforms.size()

	# Regenerate with the same seed.
	gen.generate(seed_value)

	var mismatches: Array[String] = []
	if gen.ground_points.size() != ground_count_a:
		mismatches.append("ground_count %d vs %d" % [ground_count_a, gen.ground_points.size()])
	if gen.platforms.size() != platform_count_a:
		mismatches.append("platform_count %d vs %d" % [platform_count_a, gen.platforms.size()])
	for i in range(min(spawns_a.size(), gen.spawn_points.size())):
		if spawns_a[i] != gen.spawn_points[i]:
			mismatches.append("spawn[%d] %s vs %s" % [i, spawns_a[i], gen.spawn_points[i]])
	if spawns_a.size() != gen.spawn_points.size():
		mismatches.append("spawn_count %d vs %d" % [spawns_a.size(), gen.spawn_points.size()])

	var ok: bool = mismatches.is_empty()
	return _result(
		"Seed determinism (same seed = same map)",
		ok,
		"" if ok else "mismatches: " + ", ".join(mismatches)
	)


# -----------------------------------------------------------------------
# Geometry helpers (mirrors terrain_generator.gd internals)
# -----------------------------------------------------------------------

func _get_surface_y_below(gen: TerrainGenerator, x: float, above_y: float) -> float:
	var best: float = gen._get_ground_y_at(x)
	for plat in gen.platforms:
		if x >= plat.left and x <= plat.right and plat.y > above_y and plat.y < best:
			best = plat.y
	return best


func _get_best_surface_y_at(gen: TerrainGenerator, x: float) -> float:
	var ground_y: float = gen._get_ground_y_at(x)
	var best: float = ground_y
	for plat in gen.platforms:
		if x >= plat.left and x <= plat.right and plat.y < best:
			best = plat.y
	return best


# -----------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------

func _result(label: String, passed: bool, detail: String) -> Dictionary:
	return {"label": label, "passed": passed, "detail": detail}


func _print_report(seed_value: int, results: Array[Dictionary]) -> void:
	print("\n--- TerrainValidator  seed=%d ---" % seed_value)
	var all_pass: bool = true
	for r in results:
		var icon: String = "✓" if r.passed else "✗"
		var line: String = "  %s  %s" % [icon, r.label]
		if not r.detail.is_empty():
			line += "  (%s)" % r.detail
		print(line)
		if not r.passed:
			all_pass = false
	print("  %s" % ("ALL PASS" if all_pass else "SOME CHECKS FAILED"))
