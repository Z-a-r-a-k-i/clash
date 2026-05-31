@tool
class_name ReplayTurnFrame
extends Resource

# One journaled resolver input frame. Events are deliberately not stored;
# same-version replay recomputes them from the saved state and submissions.

@export var turn_index: int = 0
@export var submit_a: SubmitTurn
@export var submit_b: SubmitTurn


func clone() -> ReplayTurnFrame:
	var c: ReplayTurnFrame = ReplayTurnFrame.new()
	c.turn_index = turn_index
	c.submit_a = submit_a.clone() if submit_a != null else SubmitTurn.new()
	c.submit_b = submit_b.clone() if submit_b != null else SubmitTurn.new()
	return c
