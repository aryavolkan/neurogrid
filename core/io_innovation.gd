class_name IoInnovation
extends RefCounted
## Extension to NeatInnovation for receptor/skill node tracking.
## Ensures the same receptor/skill gets the same innovation number across agents.

var _receptor_innovations: Dictionary = {}  # registry_id -> innovation number
var _skill_innovations: Dictionary = {}     # registry_id -> innovation number
var _next_io_innovation: int = 0


func get_receptor_innovation(registry_id: int) -> int:
	if _receptor_innovations.has(registry_id):
		return _receptor_innovations[registry_id]
	var innov := _next_io_innovation
	_receptor_innovations[registry_id] = innov
	_next_io_innovation += 1
	return innov


func get_skill_innovation(registry_id: int) -> int:
	if _skill_innovations.has(registry_id):
		return _skill_innovations[registry_id]
	var innov := _next_io_innovation
	_skill_innovations[registry_id] = innov
	_next_io_innovation += 1
	return innov


func has_receptor(registry_id: int) -> bool:
	return _receptor_innovations.has(registry_id)


func has_skill(registry_id: int) -> bool:
	return _skill_innovations.has(registry_id)
