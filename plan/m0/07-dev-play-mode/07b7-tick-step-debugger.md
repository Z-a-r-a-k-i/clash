---
status: stub
depends_on:
  - ./07b6-playtest-loop.md
---

# Tick-step debugger

Deferred dev-tool node. Step the resolver one tick at a time and inspect
intermediate state only if gameplay/playtest work shows that turn-resolution
debugging is a bottleneck.

## Likely scope

- Single-tick advance button (advance one tick within a turn, not a full turn).
- Live entity inspector panel: select an entity, see its full state (HP,
  gather phase, persistent order, active buffs, cooldowns, moves_used_this_turn).
- Event-log scrubber: between any two ticks, see the full
  `Array[ResolverEvent]` produced by that tick.
- Pause / resume / step-forward semantics.
- Useful as both a dev tool and a foundation for replays (post-M0).

To be detailed after the gameplay command surface and playtest loop expose
whether this is actually the next bottleneck.
