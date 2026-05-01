class_name ResolveResult
extends RefCounted

# Bundle returned by Resolver.resolve(). Holds the new MatchState (a copy
# of the input with the turn applied) plus the ordered list of events
# that occurred. Callers MUST treat the input state as unchanged and use
# `new_state` going forward.

var new_state: MatchState
var events: Array[ResolverEvent] = []
