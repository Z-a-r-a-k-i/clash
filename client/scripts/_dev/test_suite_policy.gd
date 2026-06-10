extends RefCounted

const INCLUDE_BROAD_ENV_VAR := "CLASH_INCLUDE_BROAD_TESTS"


static func include_broad_tests() -> bool:
	var raw: String = OS.get_environment(INCLUDE_BROAD_ENV_VAR).strip_edges().to_lower()
	return raw == "1" or raw == "true" or raw == "yes" or raw == "on"


static func filter_broad_tests(tests: Array, broad_names: Array[String]) -> Array:
	if include_broad_tests() or broad_names.is_empty():
		return tests
	var broad_lookup: Dictionary = {}
	for test_name: String in broad_names:
		broad_lookup[test_name] = true
	var filtered: Array = []
	for test_pair: Array in tests:
		if test_pair.is_empty():
			continue
		var test_name: String = str(test_pair[0])
		if not broad_lookup.has(test_name):
			filtered.append(test_pair)
	var skipped_count: int = tests.size() - filtered.size()
	if skipped_count > 0:
		print(
			(
				"[test_suite_policy] skipped %d broad tests; set %s=1 to include them"
				% [skipped_count, INCLUDE_BROAD_ENV_VAR]
			)
		)
	return filtered
