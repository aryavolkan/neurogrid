class_name GenomeDiff
extends RefCounted
## Compares two DynamicGenomes and produces a structured diff report.

class DiffResult:
	var matching_connections: int = 0
	var disjoint_connections: int = 0
	var excess_connections: int = 0
	var avg_weight_diff: float = 0.0
	var shared_receptors: Array = []    # receptor names present in both
	var unique_receptors_a: Array = []  # only in genome A
	var unique_receptors_b: Array = []  # only in genome B
	var shared_skills: Array = []
	var unique_skills_a: Array = []
	var unique_skills_b: Array = []
	var node_count_a: int = 0
	var node_count_b: int = 0
	var connection_count_a: int = 0
	var connection_count_b: int = 0
	var compatibility_distance: float = 0.0


static func compare(a: DynamicGenome, b: DynamicGenome) -> DiffResult:
	var result := DiffResult.new()
	result.node_count_a = a.node_genes.size()
	result.node_count_b = b.node_genes.size()
	result.connection_count_a = a.connection_genes.size()
	result.connection_count_b = b.connection_genes.size()
	result.compatibility_distance = a.compatibility(b)

	# Connection gene alignment by innovation number
	var map_a: Dictionary = {}
	var max_a: int = 0
	for conn in a.connection_genes:
		map_a[conn.innovation] = conn
		max_a = maxi(max_a, conn.innovation)

	var map_b: Dictionary = {}
	var max_b: int = 0
	for conn in b.connection_genes:
		map_b[conn.innovation] = conn
		max_b = maxi(max_b, conn.innovation)

	var smaller_max: int = mini(max_a, max_b)
	var weight_diff_sum: float = 0.0
	var matching: int = 0

	var all_innovs: Dictionary = {}
	for k in map_a:
		all_innovs[k] = true
	for k in map_b:
		all_innovs[k] = true

	for innov in all_innovs:
		var in_a: bool = map_a.has(innov)
		var in_b: bool = map_b.has(innov)
		if in_a and in_b:
			matching += 1
			weight_diff_sum += absf(map_a[innov].weight - map_b[innov].weight)
		elif innov > smaller_max:
			result.excess_connections += 1
		else:
			result.disjoint_connections += 1

	result.matching_connections = matching
	result.avg_weight_diff = weight_diff_sum / matching if matching > 0 else 0.0

	# Receptor comparison
	var receptors_a := _get_receptor_names(a)
	var receptors_b := _get_receptor_names(b)
	for name in receptors_a:
		if name in receptors_b:
			result.shared_receptors.append(name)
		else:
			result.unique_receptors_a.append(name)
	for name in receptors_b:
		if name not in receptors_a:
			result.unique_receptors_b.append(name)

	# Skill comparison
	var skills_a := _get_skill_names(a)
	var skills_b := _get_skill_names(b)
	for name in skills_a:
		if name in skills_b:
			result.shared_skills.append(name)
		else:
			result.unique_skills_a.append(name)
	for name in skills_b:
		if name not in skills_a:
			result.unique_skills_b.append(name)

	return result


static func format_report(diff: DiffResult, label_a: String = "A", label_b: String = "B") -> String:
	var lines: Array = []
	lines.append("Genome Diff: %s vs %s" % [label_a, label_b])
	lines.append("  Compatibility distance: %.3f" % diff.compatibility_distance)
	lines.append("  Nodes: %s=%d, %s=%d" % [label_a, diff.node_count_a, label_b, diff.node_count_b])
	lines.append("  Connections: %s=%d, %s=%d" % [label_a, diff.connection_count_a, label_b, diff.connection_count_b])
	lines.append("  Matching: %d | Disjoint: %d | Excess: %d" % [
		diff.matching_connections, diff.disjoint_connections, diff.excess_connections])
	lines.append("  Avg weight diff (matching): %.4f" % diff.avg_weight_diff)

	if not diff.shared_receptors.is_empty():
		lines.append("  Shared receptors: %s" % ", ".join(diff.shared_receptors))
	if not diff.unique_receptors_a.is_empty():
		lines.append("  Only in %s receptors: %s" % [label_a, ", ".join(diff.unique_receptors_a)])
	if not diff.unique_receptors_b.is_empty():
		lines.append("  Only in %s receptors: %s" % [label_b, ", ".join(diff.unique_receptors_b)])
	if not diff.shared_skills.is_empty():
		lines.append("  Shared skills: %s" % ", ".join(diff.shared_skills))
	if not diff.unique_skills_a.is_empty():
		lines.append("  Only in %s skills: %s" % [label_a, ", ".join(diff.unique_skills_a)])
	if not diff.unique_skills_b.is_empty():
		lines.append("  Only in %s skills: %s" % [label_b, ", ".join(diff.unique_skills_b)])

	return "\n".join(lines)


static func _get_receptor_names(genome: DynamicGenome) -> Array:
	var names: Array = []
	for node in genome.get_receptor_nodes():
		var entry = Registries.receptor_registry.get_entry(node.registry_id)
		if entry:
			names.append(entry.name)
	return names


static func _get_skill_names(genome: DynamicGenome) -> Array:
	var names: Array = []
	for node in genome.get_skill_nodes():
		var entry = Registries.skill_registry.get_entry(node.registry_id)
		if entry:
			names.append(entry.name)
	return names
