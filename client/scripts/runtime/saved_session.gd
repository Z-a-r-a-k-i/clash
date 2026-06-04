@tool
class_name SavedSession
extends Resource

# A serialized match snapshot: MatchState + the effective EntityRegistry
# the resolver was using. Saved/loaded together because a scenario with
# stat_overrides produces a CLONED registry; if we saved only the state
# and reloaded against a fresh canonical registry, the patched stats
# would silently revert and the resolver would see different numbers.
#
# Resource (so ResourceSaver / ResourceLoader handle it natively).

@export var state: MatchState
@export var registry: EntityRegistry
@export var input_snapshot: DevInputSnapshot


func clone() -> SavedSession:
	var c: SavedSession = SavedSession.new()
	c.state = state.clone() if state != null else null
	c.registry = registry
	c.input_snapshot = input_snapshot.clone() if input_snapshot != null else null
	return c
