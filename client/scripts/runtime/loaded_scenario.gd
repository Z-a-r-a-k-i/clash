class_name LoadedScenario
extends RefCounted

# What ScenarioLoader.load returns. Carries both:
# - the freshly-built MatchState (turn 0, all placements applied)
# - the effective EntityRegistry (registry_override or canonical
#   registry, with stat_overrides applied on a clone if any)
#
# Callers feed `registry` into Resolver.resolve every turn so the
# patched stats actually take effect at runtime.
#
# RefCounted (transient): never persisted; same lifetime as the match.

var state: MatchState
var registry: EntityRegistry
