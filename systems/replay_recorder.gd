class_name ReplayRecorder
extends RefCounted
## Records tick-by-tick creature snapshots for playback.
## Uses a ring buffer to cap memory. Each frame stores creature positions,
## vitals, and species id. Recording is done from main.gd via record(sim).

const MAX_FRAMES: int = 3000     # ~100 seconds at 30 ticks/sec
const RECORD_EVERY: int = 1      # Record every N ticks (1 = every tick)

var is_recording: bool = true

var _frames: Array = []          # Ring buffer of frame Dictionaries
var _write_pos: int = 0          # Next write index
var _total_recorded: int = 0     # Total frames ever written


func capture(sim: SimulationManager) -> void:
	## Build a frame from live sim state and store it.
	if not is_recording:
		return

	var tick: int = sim.get_tick_count()
	if tick % RECORD_EVERY != 0:
		return

	var creature_list: Array = []
	for cid in sim.creatures:
		var c: Creature = sim.creatures[cid]
		creature_list.append({
			"id": cid,
			"x": c.grid_pos.x,
			"y": c.grid_pos.y,
			"energy": c.body.energy,
			"health": c.body.health,
			"species_id": c.body.species_id,
		})

	record({
		"tick": tick,
		"creatures": creature_list,
		"pop": creature_list.size(),
		"food_total": sim.food_manager.get_total_food(),
	})


func record(frame_data: Dictionary) -> void:
	## Store an arbitrary frame dict (used directly in tests).
	if _frames.size() < MAX_FRAMES:
		_frames.append(frame_data)
	else:
		_frames[_write_pos] = frame_data
	_write_pos = (_write_pos + 1) % MAX_FRAMES
	_total_recorded += 1


func get_frame_count() -> int:
	return _frames.size()


func get_frame(index: int) -> Dictionary:
	## index 0 = oldest frame still in buffer.
	if _frames.is_empty() or index < 0 or index >= _frames.size():
		return {}
	# When buffer is full, oldest is at _write_pos
	if _total_recorded > MAX_FRAMES:
		var adjusted: int = (_write_pos + index) % MAX_FRAMES
		return _frames[adjusted]
	return _frames[index]


func get_latest_frame() -> Dictionary:
	if _frames.is_empty():
		return {}
	var last: int = (_write_pos - 1 + MAX_FRAMES) % MAX_FRAMES
	if _total_recorded <= MAX_FRAMES:
		last = _frames.size() - 1
	return _frames[last]


func clear() -> void:
	_frames.clear()
	_write_pos = 0
	_total_recorded = 0
