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


func find_nearest_food(from: Vector2i, max_range: int) -> Vector2i:
	if _food_dirty:
		_rebuild_food_index()
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

func _draw() -> void:
	var tile_size := GameConfig.TILE_SIZE
	for pos in tiles:
		var tile: GridTile = tiles[pos]
		var rect := Rect2(pos.x * tile_size, pos.y * tile_size, tile_size, tile_size)

		# Terrain color
		var color: Color
		match tile.terrain:
			GameConfig.Terrain.GRASS:
				color = Color(0.2, 0.5, 0.2)
			GameConfig.Terrain.FOREST:
				color = Color(0.1, 0.35, 0.1)
			GameConfig.Terrain.WATER:
				color = Color(0.15, 0.3, 0.6)
			GameConfig.Terrain.ROCK:
				color = Color(0.4, 0.4, 0.4)
			GameConfig.Terrain.SAND:
				color = Color(0.7, 0.65, 0.4)
			_:
				color = Color(0.3, 0.3, 0.3)

		draw_rect(rect, color)

		# Food indicator (yellow-green dot)
		if tile.food > 0.0:
			var food_alpha: float = clampf(tile.food / GameConfig.MAX_FOOD_PER_TILE, 0.2, 1.0)
			var center := Vector2(pos.x * tile_size + tile_size * 0.5, pos.y * tile_size + tile_size * 0.5)
			draw_circle(center, tile_size * 0.25, Color(0.8, 0.9, 0.2, food_alpha))

		# Corpse indicator (dark red dot)
		if tile.corpse_energy > 0.0:
			var center := Vector2(pos.x * tile_size + tile_size * 0.5, pos.y * tile_size + tile_size * 0.5)
			draw_circle(center, tile_size * 0.2, Color(0.6, 0.1, 0.1, 0.8))

		# Wall indicator
		if tile.wall:
			draw_rect(rect, Color(0.5, 0.4, 0.3, 0.9))

		# Pheromone overlay
		if tile.pheromone > 0.01:
			draw_rect(rect, Color(0.8, 0.2, 0.8, tile.pheromone * 0.4))

	# Grid lines (subtle)
	var total_w := width * tile_size
	var total_h := height * tile_size
	var line_color := Color(0.3, 0.3, 0.3, 0.15)
	for x in range(width + 1):
		draw_line(Vector2(x * tile_size, 0), Vector2(x * tile_size, total_h), line_color)
	for y in range(height + 1):
		draw_line(Vector2(0, y * tile_size), Vector2(total_w, y * tile_size), line_color)
