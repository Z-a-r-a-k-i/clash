class_name ResolverProfiler
extends RefCounted

const _ENABLE_ENV_VAR := "RESOLVER_PROFILE"
const _MIN_REPORT_ENV_VAR := "RESOLVER_PROFILE_MIN_USEC"
const _ENABLE_FLAG_PATH := "res://resolver_profile_enabled"
const _LATEST_LOG_PATH := "user://resolver_profile_latest.log"
const _DEFAULT_MIN_REPORT_USEC := 5000

var _total_start_usec: int = 0
var _min_report_usec: int = _DEFAULT_MIN_REPORT_USEC
var _timings: Dictionary = {}
var _counts: Dictionary = {}


static func is_enabled() -> bool:
	var env_value: String = OS.get_environment(_ENABLE_ENV_VAR).strip_edges().to_lower()
	if env_value == "1" or env_value == "true" or env_value == "yes" or env_value == "on":
		return true
	return FileAccess.file_exists(_ENABLE_FLAG_PATH)


static func read_min_report_usec() -> int:
	var env_value: String = OS.get_environment(_MIN_REPORT_ENV_VAR).strip_edges()
	if env_value.is_valid_int():
		return max(0, env_value.to_int())
	return _DEFAULT_MIN_REPORT_USEC


func start() -> void:
	_total_start_usec = Time.get_ticks_usec()
	_min_report_usec = read_min_report_usec()


func mark() -> int:
	return Time.get_ticks_usec()


func add(label: String, start_usec: int) -> void:
	add_elapsed(label, Time.get_ticks_usec() - start_usec)


func add_elapsed(label: String, elapsed_usec: int) -> void:
	if elapsed_usec <= 0:
		return
	_timings[label] = int(_timings.get(label, 0)) + elapsed_usec


func count(label: String, amount: int = 1) -> void:
	_counts[label] = int(_counts.get(label, 0)) + amount


func finish() -> void:
	var total_usec: int = Time.get_ticks_usec() - _total_start_usec
	if total_usec < _min_report_usec:
		return
	var lines: Array[String] = [
		"[resolver_profile] captured_at=%s" % Time.get_datetime_string_from_system(),
		"[resolver_profile] total=%.3fms" % (float(total_usec) / 1000.0),
	]
	var count_keys: Array[String] = []
	for key in _counts.keys():
		count_keys.append(str(key))
	count_keys.sort()
	if not count_keys.is_empty():
		var count_parts: Array[String] = []
		for key in count_keys:
			count_parts.append("%s=%d" % [key, int(_counts[key])])
		lines.append("[resolver_profile] counts %s" % ", ".join(count_parts))

	var timing_keys: Array[String] = []
	for key in _timings.keys():
		timing_keys.append(str(key))
	timing_keys.sort_custom(
		func(a: String, b: String) -> bool: return int(_timings[a]) > int(_timings[b])
	)
	for key in timing_keys:
		lines.append("[resolver_profile]   %s=%.3fms" % [key, float(_timings[key]) / 1000.0])
	for line in lines:
		print(line)
	var file := FileAccess.open(_LATEST_LOG_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines) + "\n")
