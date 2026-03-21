class_name GridWorld
extends Node2D
## Manages the 2D grid: tiles, spatial queries, rendering.

var tiles: Dictionary = {}  # Vector2i -> GridTile
var width: int
var height: int

# Spatial index: maps grid cell -> creature_id for fast neighbor queries
var _creature_positions: Dictionary = {}  # Vector2i -> int (creature_id)

# Spatial hash for fast neighbor queries (8x8 cells, each covering SPATIAL_CELL_SIZE tiles)
const SPATIAL_CELL_SIZE: int = 8
var _spatial_hash: Dictionary = {}  # Vector2i(cell) -> Dictionary{creature_id: Vector2i(pos)}

# Food positions for fast nearest-food queries
var _food_positions: Array = []  # Array[Vector2i]
var _food_dirty: bool = true


func _init() -> void:
	width = GameConfig.GRID_WIDTH
	height = GameConfig.GRID_HEIGHT


func setup() -> void:
	for y in height:
		for x in width:
			var pos := Vector2i(x, y)
			tiles[pos] = GridTile.new(pos)


func get_tile(pos: Vector2i) -> GridTile:
	return tiles.get(pos)


func is_valid(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height


func is_passable(pos: Vector2i) -> bool:
	if not is_valid(pos):
		return false
	var tile: GridTile = tiles.get(pos)
	return tile != null and tile.is_passable() and not tile.is_occupied()


# --- Spatial hash helpers ---

func _pos_to_cell(pos: Vector2i) -> Vector2i:
	return Vector2i(pos.x / SPATIAL_CELL_SIZE, pos.y / SPATIAL_CELL_SIZE)


func _spatial_add(creature_id: int, pos: Vector2i) -> void:
	var cell := _pos_to_cell(pos)
	if not _spatial_hash.has(cell):
		_spatial_hash[cell] = {}
	_spatial_hash[cell][creature_id] = pos


func _spatial_remove(creature_id: int, pos: Vector2i) -> void:
	var cell := _pos_to_cell(pos)
	if _spatial_hash.has(cell):
		_spatial_hash[cell].erase(creature_id)
		if _spatial_hash[cell].is_empty():
			_spatial_hash.erase(cell)


# --- Creature position tracking ---

func set_creature_position(creature_id: int, pos: Vector2i) -> void:
	_creature_positions[pos] = creature_id
	_spatial_add(creature_id, pos)


func clear_creature_position(pos: Vector2i) -> void:
	var cid: int = _creature_positions.get(pos, -1)
	_creature_positions.erase(pos)
	if cid >= 0:
		_spatial_remove(cid, pos)


func get_creature_at(pos: Vector2i) -> int:
	return _creature_positions.get(pos, -1)


func move_creature(creature_id: int, from: Vector2i, to: Vector2i) -> void:
	_creature_positions.erase(from)
	_creature_positions[to] = creature_id
	_spatial_remove(creature_id, from)
	_spatial_add(creature_id, to)
	var old_tile: GridTile = tiles.get(from)
	if old_tile:
		old_tile.occupant_id = -1
	var new_tile: GridTile = tiles.get(to)
	if new_tile:
		new_tile.occupant_id = creature_id


# --- Food queries ---

func mark_food_dirty() -> void:
	_food_dirty = true


func _rebuild_food_index() -> void:
	_food_positions.clear()
	for pos in tiles:
		var tile: GridTile = tiles[pos]
		if tile.food > 0.0 or tile.corpse_energy > 0.0:
			_food_positions.append(pos)
	_food_dirty = false


func rebuild_food_index_if_dirty() -> void:
	## Call once per tick before any food queries to batch the rebuild.
	if _food_dirty:
		_rebuild_food_index()


func find_nearest_food(from: Vector2i, max_range: int) -> Vector2i:
	var best_pos := Vector2i(-1, -1)
	var best_dist := max_range + 1
	for food_pos in _food_positions:
		var dist: int = abs(food_pos.x - from.x) + abs(food_pos.y - from.y)
		if dist <= max_range and dist < best_dist:
			best_dist = dist
			best_pos = food_pos
	return best_pos


# --- Spatial queries ---

func _get_nearby_cells(from: Vector2i, max_range: int) -> Array:
	## Returns array of spatial hash cell coordinates that could contain creatures within max_range.
	var center_cell := _pos_to_cell(from)
	var cell_range: int = ceili(float(max_range) / float(SPATIAL_CELL_SIZE)) + 1
	var cells: Array = []
	for cx in range(center_cell.x - cell_range, center_cell.x + cell_range + 1):
		for cy in range(center_cell.y - cell_range, center_cell.y + cell_range + 1):
			var cell := Vector2i(cx, cy)
			if _spatial_hash.has(cell):
				cells.append(cell)
	return cells


func find_creatures_in_range(from: Vector2i, max_range: int) -> Array:
	## Returns Array of {id: int, pos: Vector2i, dist: int}
	var results: Array = []
	for cell in _get_nearby_cells(from, max_range):
		var bucket: Dictionary = _spatial_hash[cell]
		for cid in bucket:
			var pos: Vector2i = bucket[cid]
			var dist: int = abs(pos.x - from.x) + abs(pos.y - from.y)
			if dist <= max_range and dist > 0:
				results.append({"id": cid, "pos": pos, "dist": dist})
	return results


func find_nearest_creature(from: Vector2i, max_range: int, exclude_id: int = -1) -> Dictionary:
	## Returns {id, pos, dist} or empty dict if none found.
	var best := {}
	var best_dist := max_range + 1
	for cell in _get_nearby_cells(from, max_range):
		var bucket: Dictionary = _spatial_hash[cell]
		for cid in bucket:
			var pos: Vector2i = bucket[cid]
			if pos == from:
				continue
			if cid == exclude_id:
				continue
			var dist: int = abs(pos.x - from.x) + abs(pos.y - from.y)
			if dist <= max_range and dist < best_dist:
				best_dist = dist
				best = {"id": cid, "pos": pos, "dist": dist}
	return best


func get_adjacent_positions(pos: Vector2i) -> Array:
	## Returns 4-connected neighbors that are valid.
	var neighbors: Array = []
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var np: Vector2i = pos + offset
		if is_valid(np):
			neighbors.append(np)
	return neighbors


func find_empty_adjacent(pos: Vector2i) -> Vector2i:
	## Find an adjacent passable + unoccupied tile. Returns (-1,-1) if none.
	var candidates := get_adjacent_positions(pos)
	candidates.shuffle()
	for np in candidates:
		if is_passable(np):
			return np
	return Vector2i(-1, -1)


# --- Rendering ---

# Pre-computed terrain colors (indexed by GameConfig.Terrain enum)
const TERRAIN_COLORS: Array = [
	Color(0.22, 0.52, 0.22),  # GRASS  — slightly brighter green
	Color(0.12, 0.38, 0.12),  # FOREST — deep green
	Color(0.18, 0.35, 0.62),  # WATER  — clear blue
	Color(0.38, 0.36, 0.34),  # ROCK   — warm gray
	Color(0.72, 0.66, 0.42),  # SAND   — warm tan
]
const DEFAULT_TERRAIN_COLOR: Color = Color(0.3, 0.3, 0.3)


func _draw() -> void:
	# Viewport culling: only draw visible tiles
	var tile_size := GameConfig.TILE_SIZE
	var viewport_rect := get_viewport_rect()
	var canvas_transform := get_canvas_transform()
	var inv_transform := canvas_transform.affine_inverse()

	# Calculate visible tile range from viewport
	var top_left := inv_transform * Vector2.ZERO
	var bottom_right := inv_transform * viewport_rect.size
	var min_x: int = maxi(int(top_left.x / tile_size) - 1, 0)
	var min_y: int = maxi(int(top_left.y / tile_size) - 1, 0)
	var max_x: int = mini(int(bottom_right.x / tile_size) + 1, width - 1)
	var max_y: int = mini(int(bottom_right.y / tile_size) + 1, height - 1)

	# Draw only visible tiles
	var half_tile: float = tile_size * 0.5
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var pos := Vector2i(x, y)
			var tile: GridTile = tiles[pos]
			var px: float = x * tile_size
			var py: float = y * tile_size
			var rect := Rect2(px, py, tile_size, tile_size)

			# Terrain color (array lookup instead of match)
			var color: Color = TERRAIN_COLORS[tile.terrain] if tile.terrain < TERRAIN_COLORS.size() else DEFAULT_TERRAIN_COLOR
			draw_rect(rect, color)

			# Food indicator (yellow-green dot)
			if tile.food > 0.0:
				var food_alpha: float = clampf(tile.food / GameConfig.MAX_FOOD_PER_TILE, 0.2, 1.0)
				draw_circle(Vector2(px + half_tile, py + half_tile), tile_size * 0.25, Color(0.8, 0.9, 0.2, food_alpha))

			# Corpse indicator (dark red dot)
			if tile.corpse_energy > 0.0:
				draw_circle(Vector2(px + half_tile, py + half_tile), tile_size * 0.2, Color(0.6, 0.1, 0.1, 0.8))

			# Wall indicator
			if tile.wall:
				draw_rect(rect, Color(0.5, 0.4, 0.3, 0.9))

			# Nesting site indicator (warm glow)
			if tile.is_nest:
				draw_rect(rect, Color(1.0, 0.85, 0.3, 0.15))
				draw_arc(Vector2(px + half_tile, py + half_tile), tile_size * 0.4, 0, TAU, 12, Color(1.0, 0.8, 0.2, 0.35), 1.0)

			# Mineral indicator (blue-gray sparkle)
			if tile.minerals > 0.0:
				draw_circle(Vector2(px + tile_size * 0.25, py + tile_size * 0.75), 1.5, Color(0.5, 0.6, 0.8, 0.6))

			# Medicinal plant indicator (green cross)
			if tile.medicinal > 0.0:
				draw_circle(Vector2(px + tile_size * 0.75, py + tile_size * 0.25), 1.5, Color(0.3, 0.9, 0.5, 0.6))

			# Pheromone overlay
			if tile.pheromone > 0.01:
				draw_rect(rect, Color(0.8, 0.2, 0.8, tile.pheromone * 0.4))

	# Grid lines (only visible range)
	var line_color := Color(0.3, 0.3, 0.3, 0.15)
	var grid_y_start: float = min_y * tile_size
	var grid_y_end: float = (max_y + 1) * tile_size
	for x in range(min_x, max_x + 2):
		var gx: float = x * tile_size
		draw_line(Vector2(gx, grid_y_start), Vector2(gx, grid_y_end), line_color)
	var grid_x_start: float = min_x * tile_size
	var grid_x_end: float = (max_x + 1) * tile_size
	for y in range(min_y, max_y + 2):
		var gy: float = y * tile_size
		draw_line(Vector2(grid_x_start, gy), Vector2(grid_x_end, gy), line_color)
