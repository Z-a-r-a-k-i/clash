@tool
class_name MatchReplay
extends Resource

# Same-code-version replay journal. The initial session includes the state,
# effective registry, and dev input continuation snapshot for turn 0.

const CURRENT_FORMAT_VERSION := 1

@export var format_version: int = CURRENT_FORMAT_VERSION
@export var initial_session: SavedSession
@export var frames: Array[ReplayTurnFrame] = []


func clone() -> MatchReplay:
	var c := MatchReplay.new()
	c.format_version = format_version
	c.initial_session = initial_session.clone() if initial_session != null else null
	c.frames = []
	for frame in frames:
		c.frames.append(frame.clone() if frame != null else null)
	return c
