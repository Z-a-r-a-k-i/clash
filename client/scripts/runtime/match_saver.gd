@tool
class_name MatchSaver
extends RefCounted

# Round-trips a (MatchState, EntityRegistry) pair through disk via
# Godot's ResourceSaver / ResourceLoader. The pair is bundled as a
# SavedSession resource because saving the state alone would silently
# drop any stat_overrides applied to the registry (the resolver every
# turn must use the SAME registry the loader produced).
#
# Determinism is preserved: the round-trip is bit-for-bit equivalent to
# the original session because:
# - every persistent runtime field is @export
# - clone() semantics are unchanged (we kept custom clones)
# - ResourceLoader is invoked with CACHE_MODE_IGNORE so re-loading the
#   same path doesn't return a shared cached instance


# Save (state, registry) to `path`. Returns Godot's Error code (OK on
# success).
static func save(state: MatchState, registry: EntityRegistry, path: String) -> Error:
	if state == null:
		push_warning("MatchSaver.save: state is null; nothing written.")
		return ERR_INVALID_PARAMETER
	if registry == null:
		push_warning("MatchSaver.save: registry is null; nothing written.")
		return ERR_INVALID_PARAMETER
	if path == "":
		push_warning("MatchSaver.save: empty path; nothing written.")
		return ERR_INVALID_PARAMETER
	var session := SavedSession.new()
	session.state = state
	session.registry = registry
	return ResourceSaver.save(session, path)


# Load a SavedSession from `path`. Returns null if the resource isn't a
# SavedSession, has missing state/registry fields, or the path can't be
# read. CACHE_MODE_IGNORE makes each load return a fresh instance —
# important for tests that load the same file twice and for save/load/
# save flows that would otherwise alias the cached resource.
static func load_from(path: String) -> SavedSession:
	if path == "":
		push_warning("MatchSaver.load_from: empty path.")
		return null
	var resource: Resource = ResourceLoader.load(
		path, "SavedSession", ResourceLoader.CACHE_MODE_IGNORE
	)
	var session := resource as SavedSession
	if session == null:
		return null
	if session.state == null:
		push_warning("MatchSaver.load_from: loaded SavedSession has null state; rejecting.")
		return null
	if session.registry == null:
		push_warning("MatchSaver.load_from: loaded SavedSession has null registry; rejecting.")
		return null
	return session
